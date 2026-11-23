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
/// activa sola cuando el servidor la mande.
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
  /// [check] va antes del envío y sus errores llegan tal cual: no se mandó nada.
  /// [money]: cambió la plata misma (ver [afterMoneyChange]).
  Future<void> _send(
    Future<void> Function() write,
    Future<bool> Function() saved, {
    Future<void> Function()? check,
    bool money = false,
  }) async {
    // Al retomarse, la bienvenida a medias reenvía su borrador y pisaría lo que se guarde aquí.
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        // TEXTO NUEVO
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
    await check?.call();
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
        afterMoneyChange(_ref.container, money: money);
        Error.throwWithStackTrace(e, stack);
      }
    }
    afterMoneyChange(_ref.container, money: money);
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

  /// PUT /money-profile con `resetBalance` (Corregir saldo). No es idempotente y gana el último:
  /// - solo si [canWriteBalance] con [opened], el perfil que la pantalla tiene a la vista;
  /// - antes se vuelve a leer: si la plata, su fecha, el tipo de ingreso o los días cambiaron desde
  ///   [opened], no se envía nada (otro dispositivo la cambió);
  /// - va con lo recién leído (es reemplazo total) y con `expectedVersion` solo si llegó `version`;
  /// - en duda, cuenta como guardado si cambió `balanceAt` y el saldo es el enviado;
  /// - un 409 PROFILE_CHANGED (cuando el backend tenga versión) vuelve a leer y se muestra.
  Future<void> saveBalance(MoneyProfile opened, num balance) => _once('balance', () async {
    final account = _ref.read(accountProvider);
    if (!canWriteBalance(account, opened)) {
      throw StateError('El saldo no se escribe sin la versión del perfil');
    }
    late MoneyProfile fresh;
    // Solo un PUT puede quedar en duda: un GET previo que falla no mandó nada.
    var sent = false;
    try {
      await _send(
        check: () async {
          fresh = await _repo.profile();
          if (_changed(opened, fresh)) {
            throw const ApiException(
              code: ApiCodes.profileChanged,
              status: 409,
              // TEXTO NUEVO
              serverMessage: 'Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.',
            );
          }
        },
        () {
          // Otra cuenta entró mientras se leía: el token ya es el suyo y este saldo no es de ella.
          if (_ref.read(accountProvider)?.user.id != account?.user.id) {
            throw StateError('Cambió la cuenta antes de guardar el saldo');
          }
          sent = true;
          return _repo.saveProfile({
            'incomeType': fresh.incomeType,
            'payDays': fresh.incomeType == 'fecha_fija' ? fresh.payDays : const <int>[],
            'balance': balance,
            'resetBalance': true,
            'expectedVersion': ?fresh.version,
          });
        },
        () async {
          final now = await _repo.profile();
          return now.balanceAt != fresh.balanceAt && _cents(now.balance) == _cents(balance);
        },
        money: true,
      );
    } on ApiException catch (e, stack) {
      // Lo de la pantalla ya no es lo vigente: se vuelve a pedir para revisarlo.
      if (e.code == ApiCodes.profileChanged) afterMoneyChange(_ref.container, money: true);
      if (sent && inDoubt(e)) {
        Error.throwWithStackTrace(
          ApiException(
            code: ApiCodes.unconfirmed,
            status: e.status,
            // TEXTO NUEVO
            serverMessage: 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.',
          ),
          stack,
        );
      }
      rethrow;
    }
  });
}

int? _cents(num? value) => value == null ? null : (value * 100).round();

/// ¿Cambió algo de lo que el PUT reemplaza (o la versión) desde que se abrió la pantalla?
bool _changed(MoneyProfile a, MoneyProfile b) =>
    _cents(a.balance) != _cents(b.balance) ||
    a.balanceAt != b.balanceAt ||
    a.incomeType != b.incomeType ||
    a.payDays.join(',') != b.payDays.join(',') ||
    a.version != b.version;

final moneyWriterProvider = Provider<MoneyWriter>(MoneyWriter.new);
