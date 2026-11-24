import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../money/application/money_writer.dart' show inDoubt;
import '../../movements/application/movement_saver.dart' show afterMovementChange;
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/card_models.dart';
import '../data/cards_repository.dart';
import '../domain/card_rules.dart';
import 'cards_providers.dart';

/// Escrituras de Tarjetas. Ningún endpoint de tarjetas es idempotente, así que se aplica el patrón
/// de MoneyWriter (no se extrae a un módulo común para no tocar MoneyWriter ni sus pruebas; se
/// reusa `inDoubt`, que ya es público):
/// - un solo envío a la vez por operación y cuenta ([_once]);
/// - «en duda» (espera vencida o 5xx) se confirma VOLVIENDO A LEER, nunca reintentando solo;
/// - para los POST sin llave de reintento, foto previa de los ids ANTES de enviar (P5 del plan):
///   «guardado» = apareció un id nuevo con lo enviado;
/// - un 404 al borrar cuenta como hecho (el de un pago, solo si la tarjeta sigue en pie);
/// - `_sameAccount` antes de cada envío y bienvenida pendiente bloquea toda escritura.
class CardsWriter {
  CardsWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<Object?>>{};

  CardsRepository get _repo => _ref.read(cardsRepositoryProvider);

  Future<T> _once<T>(String operation, Future<T> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Un segundo toque espera el resultado del primero, sin un segundo envío.
    return (_running[key] ??= send().whenComplete(() {
          _running.remove(key);
        }))
        as Future<T>;
  }

  /// Al retomarse, la bienvenida a medias reenvía su borrador y pisaría la plata que un pago de
  /// tarjeta acaba de mover (`saldo_at`).
  Future<void> _welcomeDone() async {
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
  }

  /// Otra cuenta entró mientras se leía: lo que se iba a mandar no es de ella.
  void _sameAccount(Session? account) {
    if (_ref.read(accountProvider)?.user.id != account?.user.id) {
      throw StateError('Cambió la cuenta antes de enviar');
    }
  }

  void _refresh({bool money = false, bool movement = false}) {
    afterCardChange(_ref.container, money: money);
    // El ajuste con el banco crea el gasto «Cargos del banco»; editar o borrar la tarjeta cambia la
    // que muestra cada compra (nombre, últimos 4, «Tarjeta eliminada»): Movimientos también cambia.
    if (movement) afterMovementChange(_ref.container);
  }

  static const unconfirmedText = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

  static int _cents(num value) => (value * 100).round();

  /// POST /cards. En duda, una tarjeta NUEVA (id que no estaba en la foto previa) con los mismos
  /// últimos 4 cuenta como guardada. Un reintento manual daría 409, que la hoja marca en su campo.
  Future<void> createCard(Map<String, dynamic> body) => _once('card-create ${body['last4']}', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    Set<String>? before;
    try {
      before = {for (final c in await _repo.list()) c.id};
    } on Object {
      // Sin foto previa igual se envía (riesgo BAJO); en duda no se podrá confirmar.
    }
    _sameAccount(account);
    try {
      await _repo.create(body);
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      var confirmed = false;
      try {
        final snapshot = before;
        confirmed =
            snapshot != null &&
            (await _repo.list()).any((c) => !snapshot.contains(c.id) && c.last4 == body['last4']);
      } on Object {
        // Tampoco se pudo leer: se muestra el error del envío.
      }
      if (!confirmed) {
        _refresh();
        Error.throwWithStackTrace(e, stack);
      }
    }
    _refresh();
  });

  /// PUT /cards/:id con SOLO lo que cambió (la hoja arma el cuerpo). Gana el último; en duda se
  /// confirma leyendo y comparando lo enviado. Un 404 recarga: la tarjeta ya no existe.
  Future<void> updateCard(String id, Map<String, dynamic> body) => _once('card-edit $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    try {
      await _repo.update(id, body);
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) {
        if (e.status == 404) _refresh();
        rethrow;
      }
      var confirmed = false;
      try {
        confirmed = _matchesCard(await _repo.get(id), body);
      } on Object {
        // Sigue en duda.
      }
      if (!confirmed) {
        _refresh(movement: true);
        Error.throwWithStackTrace(e, stack);
      }
    }
    _refresh(movement: true);
  });

  /// DELETE /cards/:id. Un 404 cuenta como borrado (el de un reintento tras perder la respuesta).
  Future<void> deleteCard(String id) => _once('card-delete $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    try {
      await _del(() => _repo.delete(id));
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      var confirmed = false;
      try {
        confirmed = !(await _repo.list()).any((c) => c.id == id);
      } on Object {
        // Sigue en duda.
      }
      if (!confirmed) {
        _refresh(movement: true);
        Error.throwWithStackTrace(e, stack);
      }
    }
    _refresh(movement: true);
  });

  /// POST /cards/:id/payments: RESTA de Mi plata y el servidor no tiene llave de reintento
  /// (riesgo ALTO). Foto previa de los pagos; en duda, «guardado» = un pago NUEVO con el mismo
  /// monto y fecha. Si no se puede confirmar, UNCONFIRMED y nada se reintenta: el historial queda a
  /// la vista para borrar un pago doble.
  Future<void> pay(String id, {required num amount, required String date}) => _once('card-pay $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    Set<String>? before;
    try {
      before = {
        for (final m in await _repo.movements(id))
          if (m.kind == CardMovementKind.payment) m.id,
      };
    } on Object {
      // Sin foto previa, una duda no se podrá confirmar: mejor eso que reintentar solo.
    }
    _sameAccount(account);
    try {
      await _repo.pay(id, amount: amount, date: date);
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      var confirmed = false;
      try {
        final snapshot = before;
        confirmed =
            snapshot != null &&
            (await _repo.movements(id)).any(
              (m) =>
                  m.kind == CardMovementKind.payment &&
                  !snapshot.contains(m.id) &&
                  _cents(m.amount) == _cents(amount) &&
                  m.date == date,
            );
      } on Object {
        // Tampoco se pudo leer.
      }
      if (!confirmed) {
        _refresh(money: true);
        Error.throwWithStackTrace(
          ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText),
          stack,
        );
      }
    }
    _refresh(money: true);
  });

  /// DELETE del pago: Mi plata vuelve a subir. Un 404 cuenta como borrado solo si la tarjeta sigue
  /// en pie: el servidor también responde 404 cuando la TARJETA ya no existe (`owned`), y entonces el
  /// pago sigue restando de Mi plata; ese 404 de la tarjeta llega a la pantalla.
  Future<void> deletePayment(String id, String paymentId) =>
      _once('card-payment-delete $paymentId', () async {
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        _sameAccount(account);
        try {
          await _repo.deletePayment(id, paymentId);
        } on ApiException catch (e, stack) {
          if (e.status == 404) {
            try {
              await _repo.get(id);
            } on Object {
              _refresh();
              rethrow;
            }
          } else {
            if (!inDoubt(e)) rethrow;
            var confirmed = false;
            try {
              confirmed = !(await _repo.movements(id)).any((m) => m.id == paymentId);
            } on Object {
              // Sigue en duda.
            }
            if (!confirmed) {
              // Sin esqueleto: el error de la duda está en la fila del pago y se perdería al recargar.
              _refresh();
              Error.throwWithStackTrace(e, stack);
            }
          }
        }
        _refresh(money: true);
      });

  /// POST /cards/:id/sync-with-bank. Con dos envíos a la vez el servidor duplicaría el cargo (B5):
  /// [_once] lo evita en la app. En duda, «hecho» = el disponible leído es el enviado; el monto del
  /// cargo se rehace entonces con la fórmula de la vista previa (cardFormat.js:27-34), porque la
  /// respuesta se perdió. Con diferencia 0 el disponible ya era ese: entonces el extracto enviado
  /// también tiene que estar (si el servidor lo descarta por vencido, queda UNCONFIRMED, que es lo
  /// seguro: repetirlo no crea cargos). Devuelve el monto del gasto «Cargos del banco», o null.
  /// La diferencia sale de una foto previa del servidor, no de [opened]: el detalle puede estar viejo
  /// (falló su recarga). Sin foto previa, una duda queda UNCONFIRMED.
  Future<num?> syncWithBank(CreditCard opened, Map<String, dynamic> body) =>
      _once('card-sync ${opened.id}', () async {
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        CreditCard? before;
        try {
          before = await _repo.get(opened.id);
        } on Object {
          // Sin foto previa igual se envía; en duda no se podrá confirmar.
        }
        _sameAccount(account);
        num? charge;
        try {
          charge = await _repo.syncWithBank(opened.id, body);
        } on ApiException catch (e, stack) {
          if (!inDoubt(e)) rethrow;
          final difference = before == null ? null : syncDifference(before, body['available'] as num);
          var confirmed = false;
          try {
            final card = await _repo.get(opened.id);
            confirmed =
                difference != null &&
                _cents(card.available) == _cents(body['available'] as num) &&
                (difference != 0 || _matchesStatement(card, body));
          } on Object {
            // Tampoco se pudo leer.
          }
          if (!confirmed) {
            _refresh(movement: true);
            Error.throwWithStackTrace(
              ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText),
              stack,
            );
          }
          charge = difference! > 0 ? difference : null;
        }
        _refresh(movement: true);
        return charge;
      });

  /// Corre [delete] tratando un 404 como hecho.
  Future<void> _del(Future<void> Function() delete) async {
    try {
      await delete();
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  /// ¿El extracto leído es el que mandó el ajuste con el banco? Solo los campos enviados.
  static bool _matchesStatement(CreditCard card, Map<String, dynamic> body) =>
      (!body.containsKey('statementTotal') ||
          (card.statementTotal != null &&
              _cents(card.statementTotal!) == _cents(body['statementTotal'] as num))) &&
      (!body.containsKey('statementDueDate') || card.statementDueDate == body['statementDueDate']);

  /// ¿La tarjeta leída ya es lo que mandó el PUT? Solo compara los campos enviados.
  static bool _matchesCard(CreditCard card, Map<String, dynamic> body) {
    for (final MapEntry(:key, :value) in body.entries) {
      final matches = switch (key) {
        'network' => card.network == value,
        'tier' => card.tier == value,
        'last4' => card.last4 == value,
        'name' => card.name == value,
        'limit' => value is num && _cents(card.limit) == _cents(value),
        'paymentDay' => card.paymentDay == value,
        'cutoffDay' => card.cutoffDay == value,
        'expiryMonth' => card.expiryMonth == value,
        'expiryYear' => card.expiryYear == value,
        _ => true,
      };
      if (!matches) return false;
    }
    return true;
  }
}

final cardsWriterProvider = Provider<CardsWriter>(CardsWriter.new);
