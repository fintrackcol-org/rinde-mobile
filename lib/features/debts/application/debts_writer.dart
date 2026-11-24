import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../money/application/money_writer.dart' show inDoubt;
import '../../movements/application/movement_saver.dart' show MovementSaver, afterMovementChange;
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/debt_models.dart';
import '../data/debts_repository.dart';
import 'debts_providers.dart';

/// Escrituras de Cuentas, con el patrón de CardsWriter (no se extrae a un módulo común para no tocar
/// MoneyWriter ni CardsWriter):
/// - un solo envío a la vez por operación y cuenta ([_once]);
/// - «en duda» (espera vencida o 5xx) se confirma VOLVIENDO A LEER GET /debts, nunca reintentando
///   solo. POST /debts no tiene llave de reintento y el abono la tiene (`Idempotency-Key`, ver
///   [pay]); para los dos, foto previa de los ids ANTES de enviar y «guardado» = apareció un id
///   NUEVO con lo enviado; si no, UNCONFIRMED;
/// - saldar: un 409 (ya saldada) tras una duda cuenta como hecho si quedó con la casilla que se pide;
///   borrar una cuenta: un 404; borrar un
///   abono: un 404 se comprueba leyendo (el servidor también lo da si la cuenta ya está saldada);
/// - `_sameAccount` antes de cada envío y bienvenida pendiente bloquea toda escritura.
///
/// Después de escribir, la lista SIEMPRE se recarga mostrando la carga (no la cifra vieja: «Registrar
/// abono» volvería a sugerir lo ya abonado). Crear, editar o borrar una cuenta no toca Mi plata; el
/// abono o el saldo con la casilla crean un movimiento, y borrar un abono borra el suyo: entonces
/// también Movimientos, Mi plata y el Inicio ([afterMovementChange]).
class DebtsWriter {
  DebtsWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<Object?>>{};

  /// Llave de los abonos que quedaron en duda, por borrador (cuenta, cuenta personal, monto y fecha):
  /// un reintento a mano del MISMO abono la reusa y el servidor no lo aplica dos veces; uno
  /// nuevo (o uno ya confirmado o rechazado) saca otra. Vive mientras la app está abierta.
  final _payKeys = <String, String>{};

  DebtsRepository get _repo => _ref.read(debtsRepositoryProvider);

  Future<T> _once<T>(String operation, Future<T> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Un segundo toque espera el resultado del primero, sin un segundo envío.
    return (_running[key] ??= send().whenComplete(() {
          _running.remove(key);
        }))
        as Future<T>;
  }

  /// Al retomarse, la bienvenida a medias reenvía su borrador y pisaría la plata que un abono acaba de
  /// mover (`saldo_at`).
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

  void _refresh({bool movement = false}) {
    _ref.container.invalidate(debtsProvider, asReload: true);
    if (movement) afterMovementChange(_ref.container);
  }

  /// Una lectura fresca de GET /debts, o null si no se pudo (y entonces nada se da por hecho).
  Future<DebtsList?> _read() async {
    try {
      return await _repo.list();
    } on Object {
      return null;
    }
  }

  static const unconfirmedText = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

  static ApiException _unconfirmed(ApiException e) =>
      ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText);

  static int _cents(num value) => (value * 100).round();

  /// POST /debts. En duda, una cuenta NUEVA (id que no estaba en la foto previa) con el mismo lado,
  /// la misma persona (sin espacios a los lados) y el mismo monto cuenta como guardada.
  Future<void> create(Map<String, dynamic> body) => _once('debt-create', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    final before = await _read();
    _sameAccount(account);
    try {
      await _repo.create(body);
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      final ids = before == null ? null : {for (final d in before.items) d.id};
      final after = ids == null ? null : await _read();
      final confirmed =
          after != null &&
          after.items.any(
            (d) =>
                !ids!.contains(d.id) &&
                d.kind.wire == body['kind'] &&
                d.person.trim() == '${body['person']}'.trim() &&
                _cents(d.amount) == _cents(body['amount'] as num),
          );
      if (!confirmed) {
        _refresh();
        Error.throwWithStackTrace(_unconfirmed(e), stack);
      }
    }
    _refresh();
  });

  /// PUT /debts/:id con todos los campos menos `kind` y `reminder`. Gana el último; en duda se
  /// confirma leyendo y comparando lo enviado. Un 409 (ya saldada) o un 404 recargan: la hoja se
  /// cierra y muestra el mensaje del servidor.
  Future<void> update(String id, Map<String, dynamic> body) => _once('debt-edit $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    try {
      await _repo.update(id, body);
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) {
        if (e.status == 404 || e.status == 409) _refresh();
        rethrow;
      }
      final debt = (await _read())?.items.where((d) => d.id == id).firstOrNull;
      if (debt == null || !_matches(debt, body)) {
        _refresh();
        Error.throwWithStackTrace(e, stack);
      }
    }
    _refresh();
  });

  /// DELETE /debts/:id. Un 404 cuenta como borrada (el de un reintento tras perder la respuesta).
  Future<void> delete(String id) => _once('debt-delete $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    try {
      await _repo.delete(id);
    } on ApiException catch (e, stack) {
      if (e.status != 404) {
        if (!inDoubt(e)) rethrow;
        final after = await _read();
        if (after == null || after.items.any((d) => d.id == id)) {
          _refresh();
          Error.throwWithStackTrace(e, stack);
        }
      }
    }
    _refresh();
  });

  /// POST /debts/:id/payments: con la casilla crea un movimiento que cambia Mi plata (riesgo ALTO). Va
  /// con `Idempotency-Key`, una por borrador ([_payKeys]): reintentar a mano el mismo abono tras una
  /// duda no abona dos veces (aunque la cuenta ya haya quedado saldada), y una repetición
  /// (`Idempotent-Replayed`) es una respuesta 2xx más: hecho. Igual se conserva la foto previa de los
  /// abonos de ESA cuenta para un servidor sin la llave; en duda, «guardado» = un abono NUEVO con el
  /// mismo monto y fecha (sigue en la lista aunque la cuenta haya quedado saldada). Si no,
  /// UNCONFIRMED y nada se reintenta solo: los abonos quedan a la vista (hoja de editar) para borrar
  /// uno doble.
  Future<void> pay(String id, {required num amount, required String date, required bool createTransaction}) =>
      _once('debt-pay $id', () async {
        final account = _ref.read(accountProvider);
        // Sin la casilla: si cambia entre intentos, la misma llave da 409 en vez de un segundo abono.
        final draft = '${account?.user.id} $id ${_cents(amount)} $date';
        // El localId de Anotar sirve de llave: 128 bits al azar con el formato que acepta el servidor.
        final key = _payKeys[draft] ?? MovementSaver.newLocalId();
        await _welcomeDone();
        final before = (await _read())?.items.where((d) => d.id == id).firstOrNull;
        _sameAccount(account);
        try {
          await _repo.pay(
            id,
            amount: amount,
            date: date,
            createTransaction: createTransaction,
            idempotencyKey: key,
          );
        } on ApiException catch (e, stack) {
          if (!inDoubt(e)) {
            _payKeys.remove(draft); // Rechazado: no se aplicó; el próximo intento es otro abono.
            if (e.status == 404 || e.status == 409) _refresh();
            rethrow;
          }
          final ids = before == null ? null : {for (final p in before.payments) p.id};
          final after = ids == null ? null : await _read();
          final confirmed =
              after?.items
                  .where((d) => d.id == id)
                  .firstOrNull
                  ?.payments
                  .any((p) => !ids!.contains(p.id) && _cents(p.amount) == _cents(amount) && p.date == date) ??
              false;
          if (!confirmed) {
            // Sigue en duda: el próximo intento del mismo abono va con esta misma llave.
            _payKeys[draft] = key;
            _refresh(movement: createTransaction);
            Error.throwWithStackTrace(_unconfirmed(e), stack);
          }
        }
        _payKeys.remove(draft);
        _refresh(movement: createTransaction);
      });

  /// Los saldos que quedaron en duda sin confirmar, con la casilla de cada envío: solo para ellos un
  /// 409 después puede contar como hecho.
  final _settleDoubt = <String, Set<bool>>{};

  /// POST /debts/:id/settle con `{createTransaction}` y sin fecha. Repetir es seguro: un 409 (ya
  /// saldada) en el reintento de una duda cuenta como hecho, sin otro movimiento, si quedó saldada
  /// como se pide ahora (la casilla puede cambiar entre intentos); sin duda antes o con otra casilla
  /// llega a la hoja. En duda se relee; si no se confirma, el error queda en la hoja y se puede
  /// repetir sin riesgo.
  Future<void> settle(String id, {required bool createTransaction}) => _once('debt-settle $id', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    bool asAsked(Debt? debt) =>
        debt != null && debt.settled && (debt.transactionId != null) == createTransaction;
    try {
      await _repo.settle(id, createTransaction: createTransaction);
    } on ApiException catch (e, stack) {
      if (e.status == 409) {
        final sent = _settleDoubt.remove(id);
        // Sin una duda antes, la saldaron en otro lado: la casilla no anotó nada y la hoja lo dice.
        if (sent == null) {
          _refresh();
          rethrow;
        }
        // Tras la duda se relee: otro dispositivo pudo saldarla distinto. Sin poder leer, vale si
        // toda duda mandó la misma casilla. Si no, la hoja lo dice y la lista muestra la verdad.
        final debt = (await _read())?.items.where((d) => d.id == id).firstOrNull;
        if (!(debt == null ? sent.every((v) => v == createTransaction) : asAsked(debt))) {
          _refresh(movement: true);
          rethrow;
        }
      } else {
        if (!inDoubt(e)) {
          if (e.status == 404) _refresh();
          rethrow;
        }
        final debt = (await _read())?.items.where((d) => d.id == id).firstOrNull;
        if (!asAsked(debt)) {
          (_settleDoubt[id] ??= {}).add(createTransaction);
          _refresh(movement: createTransaction);
          Error.throwWithStackTrace(e, stack);
        }
      }
    }
    _settleDoubt.remove(id);
    _refresh(movement: createTransaction);
  });

  /// DELETE de un abono: también borra su movimiento. Devuelve la cuenta como queda. Un 404 NO se da
  /// por hecho sin releer: el servidor también lo da cuando la cuenta ya está saldada, y entonces el
  /// abono sigue; solo es hecho si la cuenta sigue pendiente y el abono ya no está. Si no, el error
  /// llega a la hoja (con 404, la cierra y muestra el mensaje del servidor).
  Future<Debt> deletePayment(Debt debt, DebtPayment payment) =>
      _once('debt-payment-delete ${payment.id}', () async {
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        _sameAccount(account);
        final movement = payment.transactionId != null;
        try {
          final updated = await _repo.deletePayment(debt.id, payment.id);
          _refresh(movement: movement);
          return updated;
        } on ApiException catch (e, stack) {
          if (e.status != 404 && !inDoubt(e)) rethrow;
          final current = (await _read())?.items.where((d) => d.id == debt.id).firstOrNull;
          _refresh(movement: movement);
          if (current != null && !current.settled && !current.payments.any((p) => p.id == payment.id)) {
            return current;
          }
          Error.throwWithStackTrace(e, stack);
        }
      });

  /// ¿La cuenta leída ya es lo que mandó el PUT?
  static bool _matches(Debt debt, Map<String, dynamic> body) {
    final installments = body['installments'] as int?;
    final amount = body['amount'];
    return debt.person.trim() == '${body['person']}'.trim() &&
        amount is num &&
        _cents(debt.amount) == _cents(amount) &&
        debt.loanDate == body['loanDate'] &&
        debt.installments == installments &&
        debt.frequency?.wire == body['frequency'] &&
        debt.note == body['note'] &&
        // Con cuotas, lo enviado es la PRIMERA cuota; al leer va en firstDueDate.
        (installments == null ? debt.dueDate : debt.firstDueDate) == body['dueDate'];
  }
}

final debtsWriterProvider = Provider<DebtsWriter>(DebtsWriter.new);
