import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/money_models.dart';
import '../data/money_repository.dart';
import '../domain/income_rules.dart';
import 'money_providers.dart';

/// ¿Se puede escribir el saldo desde la app? Solo si el perfil trae `version` (el backend de hoy no
/// la manda: la propuesta §5 del plan la agrega) o en la demostración. No es una bandera manual: se
/// activa sola cuando el servidor la mande. La usa Corregir saldo (bloque 4B).
bool canWriteBalance(Session? session, MoneyProfile profile) =>
    (session?.demo ?? false) || profile.version != null;

/// «En duda»: la petición pudo llegar al servidor (se venció la espera o el servidor falló). A
/// diferencia de `ApiCodes.network`, que no salió del teléfono.
bool inDoubt(ApiException e) => e.code == ApiCodes.timeout || (e.status ?? 0) >= 500;

/// Escrituras de Mi plata. Sin reintentos solos:
/// - un solo envío a la vez por operación: un segundo toque espera el resultado del primero;
/// - si queda en duda, se vuelve a leer y, si lo guardado ya es lo enviado, cuenta como hecho;
/// - después se refrescan Mi plata y el Inicio.
class MoneyWriter {
  MoneyWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<void>>{};

  MoneyRepository get _repo => _ref.read(moneyRepositoryProvider);

  Future<void> _once(String operation, Future<void> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Con llaves: si el callback devolviera el Future quitado, whenComplete se esperaría a sí mismo.
    return _running[key] ??= send().whenComplete(() {
      _running.remove(key);
    });
  }

  /// Envía [write]; si queda en duda y [saved] confirma leyendo que ya quedó, no repite nada.
  Future<void> _send(Future<void> Function() write, Future<bool> Function() saved) async {
    // Al retomarse, la bienvenida a medias reenvía su borrador y pisaría lo que se guarde aquí.
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        // TEXTO NUEVO
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
    try {
      await write();
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      var confirmed = false;
      try {
        confirmed = await saved();
      } on Object {
        // Tampoco se pudo leer: sigue en duda y se muestra el error del envío.
      }
      if (!confirmed) {
        // Pudo aplicarse después: lo que se ve se vuelve a pedir igual.
        afterMoneyChange(_ref.container);
        Error.throwWithStackTrace(e, stack);
      }
    }
    afterMoneyChange(_ref.container);
  }

  /// PUT /money-profile/sources. Gana el último: dos envíos a la vez podrían dejar fuentes repetidas.
  Future<void> saveSources(List<Map<String, dynamic>> sources) => _once(
    'sources',
    () => _send(
      () => _repo.saveSources(sources),
      () async => sameSources(sources, (await _repo.income()).sources),
    ),
  );

  /// POST /money-profile/commitments. El nombre es único: si quedó en duda, se busca en el perfil.
  Future<void> createCommitment(Map<String, dynamic> body) => _once(
    // Un pago con otro nombre es otro envío: no espera al primero.
    'commitment ${body['name']}',
    () => _send(() => _repo.createCommitment(body), () async {
      final name = '${body['name']}'.trim().toLowerCase();
      final cents = ((body['amount'] as num) * 100).round();
      // El nombre solo no basta: uno que ya existía (otro día u otro monto) daría un falso «Listo».
      return (await _repo.profile()).commitments.any(
        (c) =>
            c.name.toLowerCase() == name &&
            c.dayOfMonth == body['dayOfMonth'] &&
            (c.amount * 100).round() == cents,
      );
    }),
  );
}

final moneyWriterProvider = Provider<MoneyWriter>(MoneyWriter.new);
