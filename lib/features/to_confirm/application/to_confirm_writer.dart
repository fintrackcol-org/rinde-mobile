import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../cards/data/card_models.dart' show CreditCard;
import '../../home/application/home_providers.dart' show homeToConfirmProvider;
import '../../money/application/money_writer.dart' show inDoubt;
import '../../movements/application/movement_saver.dart' show afterMovementChange;
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/to_confirm_repository.dart';

/// GET /pending-payments de una cuenta. Se pide al abrir Por confirmar y se suelta al salir.
final toConfirmListProvider = FutureProvider.autoDispose.family<List<IncomingPayment>, Session?>((
  ref,
  account,
) {
  if (ref.watch(accountProvider) != account) return Completer<List<IncomingPayment>>().future;
  return ref.watch(toConfirmRepositoryProvider).list();
});

/// La tarjeta propia que corresponde a la de Wallet ([IncomingPayment.card], solo texto), o null
/// («Efectivo o débito»). Solo si es inequívoco: el texto trae UN solo grupo de 4 cifras y UNA sola
/// tarjeta termina en él. Un nombre sin números («Mi Visa») no adivina nada.
String? walletCardMatch(String? wallet, List<CreditCard> cards) {
  final groups = {for (final m in RegExp(r'(?<!\d)\d{4}(?!\d)').allMatches(wallet ?? '')) m[0]};
  if (groups.length != 1) return null;
  final matches = cards.where((c) => c.last4 == groups.single).toList();
  return matches.length == 1 ? matches.single.id : null;
}

/// Confirmar y descartar, con el patrón de los demás writers:
/// - un solo envío a la vez por pago y cuenta ([_once]): un segundo toque espera al primero;
/// - «en duda» (espera vencida o 5xx) se resuelve RELEYENDO la lista, nunca reintentando solo: si el
///   pago ya no está pendiente, cuenta como hecho; si sigue, se informa el fallo y se puede reintentar
///   (el servidor no duplica: un pago ya resuelto responde 409 `ALREADY_RESOLVED`);
/// - `_sameAccount` antes de enviar y la bienvenida pendiente bloquea toda escritura.
///
/// Confirmar crea un gasto: después cambian Movimientos, Mi plata, el Inicio y Planear
/// ([afterMovementChange], que también recarga Tarjetas: un gasto con tarjeta cambia lo usado).
/// Descartar no anota nada: solo la lista y el aviso del Inicio.
class ToConfirmWriter {
  ToConfirmWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<void>>{};

  ToConfirmRepository get _repo => _ref.read(toConfirmRepositoryProvider);

  Future<void> _once(String operation, Future<void> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Sin devolver el Future quitado: whenComplete lo esperaría y nunca terminaría.
    return _running[key] ??= send().whenComplete(() {
      _running.remove(key);
    });
  }

  Future<void> _welcomeDone() async {
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
  }

  void _sameAccount(Session? account) {
    if (_ref.read(accountProvider)?.user.id != account?.user.id) {
      throw StateError('Cambió la cuenta antes de enviar');
    }
  }

  static const unconfirmedText = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

  void _refresh({required bool movement}) {
    _ref.container.invalidate(toConfirmListProvider);
    if (movement) {
      afterMovementChange(_ref.container);
    } else {
      // El aviso «Por confirmar» del Inicio y de Mi plata.
      _ref.container.invalidate(homeToConfirmProvider);
    }
  }

  Future<void> _send(String id, {required bool movement, required Future<void> Function() send}) =>
      _once('${movement ? 'confirm' : 'discard'} $id', () async {
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        _sameAccount(account);
        try {
          await send();
        } on ApiException catch (e, stack) {
          if (!inDoubt(e)) {
            // Ya resuelto en otro lado o ya no existe: la lista se pone al día y se dice por qué.
            if (e.status == 409 || e.status == 404) _refresh(movement: movement);
            rethrow;
          }
          List<IncomingPayment>? after;
          try {
            after = await _repo.list();
          } on Object {
            after = null;
          }
          _refresh(movement: movement);
          if (after == null) {
            Error.throwWithStackTrace(
              ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText),
              stack,
            );
          }
          if (after.any((p) => p.id == id)) Error.throwWithStackTrace(e, stack);
          return;
        }
        _refresh(movement: movement);
      });

  /// POST /pending-payments/:id/confirm. [category] null: la elige la IA. [card] null: efectivo o
  /// débito (resta de Mi plata); con una tarjeta, resta cuando se pague la tarjeta.
  Future<void> confirm(
    IncomingPayment payment, {
    required String description,
    String? category,
    String? card,
  }) => _send(
    payment.id,
    movement: true,
    send: () => _repo.confirm(payment.id, description: description, category: category, card: card),
  );

  /// POST /pending-payments/:id/discard.
  Future<void> discard(IncomingPayment payment) =>
      _send(payment.id, movement: false, send: () => _repo.discard(payment.id));
}

final toConfirmWriterProvider = Provider<ToConfirmWriter>(ToConfirmWriter.new);
