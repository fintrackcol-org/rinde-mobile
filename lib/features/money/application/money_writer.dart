import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show homePlanProvider, todayProvider;
import '../../home/domain/home_dates.dart';
import '../../movements/application/movement_saver.dart';
import '../../movements/domain/movement.dart';
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

  /// Al retomarse, la bienvenida a medias reenvía su borrador y pisaría lo que se guarde aquí.
  Future<void> _welcomeDone() async {
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        // TEXTO NUEVO
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
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
    await _welcomeDone();
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

  /// PUT /money-profile con `resetBalance` (Corregir saldo). No es idempotente y gana el último (ver
  /// [_replaceProfile]). En duda, cuenta como guardado si cambió `balanceAt` y el saldo es el enviado.
  Future<void> saveBalance(MoneyProfile opened, num balance) => _replaceProfile(
    'balance',
    opened,
    (fresh) => {
      'incomeType': fresh.incomeType,
      'payDays': fresh.incomeType == 'fecha_fija' ? fresh.payDays : const <int>[],
      'balance': balance,
      'resetBalance': true,
    },
    (fresh, now) => now.balanceAt != fresh.balanceAt && _cents(now.balance) == _cents(balance),
    conflict: _changed,
  );

  /// PUT /money-profile sin `resetBalance` («Tu sueldo»). Lleva el saldo RECIÉN LEÍDO, no el de al
  /// abrir: con uno viejo revertiría una corrección más nueva (lo que hace hoy la web); el mismo saldo
  /// no reinicia `saldo_at`. Por eso solo choca si cambió lo que se edita aquí (tipo, días o versión).
  /// En duda, cuenta como guardado si el tipo y los días leídos son los enviados.
  Future<void> saveIncomeType(MoneyProfile opened, String? incomeType, List<int> payDays) {
    final days = incomeType == 'fecha_fija' ? payDays : const <int>[];
    return _replaceProfile(
      'income-type',
      opened,
      (fresh) => {'incomeType': incomeType, 'payDays': days, 'balance': fresh.balance},
      (_, now) => now.incomeType == incomeType && now.payDays.join(',') == days.join(','),
      conflict: (a, b) =>
          a.incomeType != b.incomeType ||
          a.payDays.join(',') != b.payDays.join(',') ||
          a.version != b.version,
    );
  }

  /// PUT /money-profile, que reemplaza el tipo de ingreso, los días y el saldo:
  /// - solo si [canWriteBalance] con [opened], el perfil que la pantalla tiene a la vista;
  /// - antes se vuelve a leer: si [conflict] ve un cambio desde [opened], no se envía nada (otro
  ///   dispositivo lo cambió);
  /// - va con [body] armado sobre lo recién leído y con `expectedVersion` solo si llegó `version`;
  /// - en duda, [saved] decide leyendo; si no lo confirma: «No pudimos confirmar si se guardó…»;
  /// - un 409 PROFILE_CHANGED (cuando el backend tenga versión) vuelve a leer y se muestra.
  Future<void> _replaceProfile(
    String operation,
    MoneyProfile opened,
    Map<String, dynamic> Function(MoneyProfile fresh) body,
    bool Function(MoneyProfile fresh, MoneyProfile now) saved, {
    required bool Function(MoneyProfile opened, MoneyProfile fresh) conflict,
  }) => _once(operation, () async {
    final account = _ref.read(accountProvider);
    if (!canWriteBalance(account, opened)) {
      throw StateError('El perfil no se escribe sin su versión');
    }
    late MoneyProfile fresh;
    // Solo un PUT puede quedar en duda: un GET previo que falla no mandó nada.
    var sent = false;
    try {
      await _send(
        check: () async {
          fresh = await _repo.profile();
          if (conflict(opened, fresh)) throw _profileChanged;
        },
        () {
          _sameAccount(account);
          sent = true;
          return _repo.saveProfile({...body(fresh), 'expectedVersion': ?fresh.version});
        },
        () async => saved(fresh, await _repo.profile()),
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

  /// Otra cuenta entró mientras se leía: el token ya es el suyo y lo que se iba a mandar no es de ella.
  void _sameAccount(Session? account) {
    if (_ref.read(accountProvider)?.user.id != account?.user.id) {
      throw StateError('Cambió la cuenta antes de enviar');
    }
  }

  /// PUT /money-profile/commitments/:id con el pago completo (sin `reminder`: el aviso guardado no se
  /// toca). Gana el último y la tabla no tiene versión, así que:
  /// - antes se vuelve a leer: si el pago ya no está, 404; si cambió desde [opened], no se envía;
  /// - en duda, cuenta como guardado si lo leído es lo enviado (repetirlo daría lo mismo);
  /// - con 404 o con el cambio, se vuelve a pedir lo que se ve.
  Future<void> updateCommitment(Commitment opened, Map<String, dynamic> body) =>
      _once('commitment-edit ${opened.id}', () async {
        final account = _ref.read(accountProvider);
        try {
          await _send(
            check: () async {
              final now = _commitment(await _repo.profile(), opened.id);
              if (now == null) throw _notFound;
              // Ya es lo que se manda (un envío en duda sí llegó): repetirlo no cambia nada.
              if (!sameCommitment(now, commitmentBody(opened)) && !sameCommitment(now, body)) {
                throw _profileChanged;
              }
            },
            () {
              _sameAccount(account);
              return _repo.updateCommitment(opened.id, body);
            },
            () async => sameCommitment(_commitment(await _repo.profile(), opened.id), body),
          );
        } on ApiException catch (e) {
          if (e.code == ApiCodes.profileChanged || e.status == 404) afterMoneyChange(_ref.container);
          rethrow;
        }
      });

  /// DELETE /money-profile/commitments/:id. Un 404 cuenta como borrado: el de un reintento, tras
  /// perder la respuesta del primero, llega aunque sí se borró. En duda, se confirma leyendo.
  Future<void> deleteCommitment(String id) => _once(
    'commitment-delete $id',
    () => _send(() async {
      try {
        await _repo.deleteCommitment(id);
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
      }
    }, () async => _commitment(await _repo.profile(), id) == null),
  );

  /// localId de cada «Ya lo pagué» que no terminó, por cuenta y pago. Un reintento tras un error usa
  /// el mismo (si el primero sí llegó, el servidor no lo duplica). Al guardarse o quedar en la cola se
  /// suelta: repetir el de un gasto que después se borró devolvería el borrado sin crear nada.
  final _paidIds = <String, String>{};

  /// «Ya lo pagué» anotados (o en la cola) cuyo «Pagado» aún no llegó, por cuenta y pago: mientras
  /// tanto lo viejo sigue «Por pagar» con el botón, y un toque ahí no anota otro gasto, solo recarga.
  /// shortcut: vive mientras la app siga abierta, y si el servidor lo vuelve a dar por pagar (se borró
  /// el gasto), el primer toque solo recarga; si molesta, soltarlo cuando llegue un calendario nuevo.
  final _unseen = <String>{};

  /// «Ya lo pagué» (MoneyPayments.jsx y PendingPayments.jsx): un gasto con el nombre exacto del pago
  /// (así el servidor lo da por pagado), su monto, la fecha de hoy del teléfono (como la web; ver la
  /// pregunta 3 del plan) y sin categoría (la pone el servidor). [key] es `{id}-{date}`.
  /// - Sin conexión queda en la cola de movimientos; si ya hay en la cola un gasto igual de este mes,
  ///   no se anota otro.
  /// - Termina cuando llegan el calendario y el plan nuevos: hasta entonces el botón sigue ocupado.
  /// - En la demostración no se anota: el plan no lo daría por pagado y la plata bajaría dos veces.
  Future<void> markPaid({required String key, required String name, required num amount}) =>
      _once('paid $key', () async {
        if (_repo.isDemo) {
          throw const ApiException(
            code: ApiCodes.demoNoBackend,
            // TEXTO NUEVO
            serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
          );
        }
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        final date = isoDay(_ref.read(todayProvider));
        final queue = await _ref.read(pendingMovementsProvider.future);
        if (queuedPayment(queue, name: name, amount: amount, date: date)) return;
        final id = '${account?.user.id} $key';
        if (_unseen.contains(id)) {
          afterMoneyChange(_ref.container);
        } else {
          final localId = _paidIds[id] ??= MovementSaver.newLocalId();
          _sameAccount(account);
          final created = await _ref
              .read(movementSaverProvider)
              .create(
                MovementInput(type: MovementType.expense, amount: amount, description: name, date: date),
                localId: localId,
              );
          _paidIds.remove(id);
          _unseen.add(id);
          // En la cola ya dice «Pendiente de sincronizar».
          if (created.pending) return;
        }
        if (await _reloaded(account)) _unseen.remove(id);
      });

  /// Espera el calendario y el plan que ya se estén viendo, pedidos otra vez. false si alguno falló.
  Future<bool> _reloaded(Session? account) async {
    if (_ref.read(accountProvider) != account) return false;
    final calendar = paymentCalendarProvider(account);
    final plan = homePlanProvider(account);
    try {
      await Future.wait([
        if (_ref.read(calendar.exists)) _ref.read(calendar.future),
        if (_ref.read(plan.exists)) _ref.read(plan.future),
        // Si otra cuenta entra a mitad, lo de esta nunca llega: no se queda esperando.
      ]).timeout(const Duration(minutes: 1));
      return true;
    } on Object {
      return false;
    }
  }
}

const _profileChanged = ApiException(
  code: ApiCodes.profileChanged,
  status: 409,
  // TEXTO NUEVO
  serverMessage: 'Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.',
);

const _notFound = ApiException(code: 'NOT_FOUND', status: 404, serverMessage: 'Compromiso no encontrado');

Commitment? _commitment(MoneyProfile profile, String id) =>
    profile.commitments.where((c) => c.id == id).firstOrNull;

/// El cuerpo de PUT de un pago guardado: lo que se compara antes de editarlo.
Map<String, dynamic> commitmentBody(Commitment c) => {
  'name': c.name,
  'amount': c.amount,
  'dayOfMonth': c.dayOfMonth,
  'kind': c.kind,
  'frequency': c.frequency,
  'month': c.frequency == 'yearly' ? c.month : null,
};

/// ¿El pago [c] es [body]? Nombre exacto, centavos, día, tipo, frecuencia y mes.
bool sameCommitment(Commitment? c, Map<String, dynamic> body) =>
    c != null &&
    c.name == body['name'] &&
    _cents(c.amount) == _cents(body['amount'] as num?) &&
    c.dayOfMonth == body['dayOfMonth'] &&
    c.kind == (body['kind'] ?? 'fixed') &&
    c.frequency == (body['frequency'] ?? 'monthly') &&
    (c.frequency == 'yearly' ? c.month : null) == body['month'];

/// ¿Ya hay en la cola un gasto de «Ya lo pagué» para este pago? Misma descripción y monto, del mes de
/// [date]: el servidor lo da por pagado con cualquier gasto del mes con su nombre (no solo el de hoy).
bool queuedPayment(PendingState queue, {required String name, required num amount, required String date}) =>
    queue.items.any(
      (p) =>
          p.input.type == MovementType.expense &&
          p.input.description == name &&
          _cents(p.input.amount) == _cents(amount) &&
          p.input.date.startsWith(date.substring(0, 7)),
    );

int? _cents(num? value) => value == null ? null : (value * 100).round();

/// ¿Cambió algo de lo que el PUT reemplaza (o la versión) desde que se abrió la pantalla?
bool _changed(MoneyProfile a, MoneyProfile b) =>
    _cents(a.balance) != _cents(b.balance) ||
    a.balanceAt != b.balanceAt ||
    a.incomeType != b.incomeType ||
    a.payDays.join(',') != b.payDays.join(',') ||
    a.version != b.version;

final moneyWriterProvider = Provider<MoneyWriter>(MoneyWriter.new);
