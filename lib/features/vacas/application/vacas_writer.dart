import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../money/application/money_writer.dart' show inDoubt;
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/vaca_models.dart';
import '../data/vacas_repository.dart';
import 'vacas_providers.dart';

/// Escrituras de Metas y Vacas, con el patrón de CardsWriter:
/// - un solo envío a la vez por operación y cuenta ([_once]): un segundo toque espera al primero;
/// - `_sameAccount` antes de cada envío; la bienvenida pendiente bloquea lo que mueve plata;
/// - «en duda» (espera vencida o 5xx) se confirma VOLVIENDO A LEER, nunca reintentando solo;
/// - el aporte SÍ es idempotente en el servidor (`localId`): la hoja lo genera y lo reusa en cada
///   reintento del mismo borrador, así una duda o dos toques no lo duplican;
/// - un 404 al borrar o al sacar a alguien cuenta como hecho.
/// Permisos (quién edita, borra o saca miembros) los decide el servidor: aquí no se adivinan.
class VacasWriter {
  VacasWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<Object?>>{};

  static const unconfirmedText = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

  VacasRepository get _repo => _ref.read(vacasRepositoryProvider);

  Future<T> _once<T>(String operation, Future<T> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    return (_running[key] ??= send().whenComplete(() {
          _running.remove(key);
        }))
        as Future<T>;
  }

  /// Al retomarse, la bienvenida a medias reenvía su borrador y pisaría la plata que mueve un aporte.
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

  void _refresh({bool movement = false}) => afterVacaChange(_ref.container, movement: movement);

  /// Envía con la cuenta de ahora y refresca. Un 404 también refresca (la vaca ya no está).
  Future<T> _send<T>(Future<T> Function() send, {bool movement = false}) async {
    final account = _ref.read(accountProvider);
    if (movement) await _welcomeDone();
    _sameAccount(account);
    try {
      final result = await send();
      _refresh(movement: movement);
      return result;
    } on ApiException catch (e) {
      if (e.status == 404 || inDoubt(e)) _refresh(movement: movement);
      rethrow;
    }
  }

  static int _cents(num value) => (value * 100).round();

  /// Una relectura para salir de la duda: si también falla, sigue en duda (false).
  static Future<bool> _check(Future<bool> Function() read) async {
    try {
      return await read();
    } on Object {
      return false;
    }
  }

  /// ¿La vaca leída ya tiene lo que mandó el PATCH? Solo los campos enviados.
  static bool _matches(Vaca vaca, Map<String, dynamic> body) => body.entries.every(
    (e) => switch (e.key) {
      'name' => vaca.name == e.value,
      'goal' => e.value is num && _cents(vaca.goal) == _cents(e.value as num),
      'deadline' => vaca.deadline == e.value,
      'description' => vaca.description == e.value,
      'split' => vaca.personal || vaca.split == e.value,
      _ => true,
    },
  );

  /// POST /vacas (meta con `personal: true`). No es idempotente: foto previa de los ids y, en duda,
  /// «guardada» = una vaca NUEVA con el mismo nombre y meta. Si no se confirma, UNCONFIRMED.
  Future<Vaca> create(Map<String, dynamic> body) => _once('vaca-create', () async {
    Set<String>? before;
    try {
      before = {for (final v in await _repo.list()) v.id};
    } on Object {
      // Sin foto previa igual se envía; en duda no se podrá confirmar.
    }
    try {
      return await _send(() => _repo.create(body));
    } on ApiException catch (e, stack) {
      if (!inDoubt(e)) rethrow;
      Vaca? found;
      try {
        final snapshot = before;
        if (snapshot != null) {
          found = (await _repo.list())
              .where(
                (v) =>
                    !snapshot.contains(v.id) &&
                    v.name == body['name'] &&
                    _cents(v.goal) == _cents(body['goal'] as num),
              )
              .firstOrNull;
        }
      } on Object {
        // Tampoco se pudo leer.
      }
      if (found != null) return found;
      Error.throwWithStackTrace(
        ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText),
        stack,
      );
    }
  });

  /// PATCH /vacas/:id. Gana el último; en duda se confirma leyendo lo enviado.
  Future<void> update(String id, Map<String, dynamic> body) => _once('vaca-edit $id', () async {
    try {
      await _send(() => _repo.update(id, body));
    } on ApiException catch (e) {
      if (!inDoubt(e) || !await _check(() async => _matches(await _repo.get(id), body))) rethrow;
    }
  });

  /// DELETE /vacas/:id. Un 404 cuenta como borrada; en duda, borrada = ya no está en la lista.
  Future<void> delete(String id) => _once('vaca-delete $id', () async {
    try {
      await _send(() => _repo.delete(id));
    } on ApiException catch (e) {
      if (e.status == 404) return;
      if (!inDoubt(e) || !await _check(() async => !(await _repo.list()).any((v) => v.id == id))) rethrow;
    }
  });

  /// POST /vacas/join: idempotente en el servidor (si ya era miembro, devuelve el detalle).
  Future<Vaca> join(String code) => _once('vaca-join $code', () => _send(() => _repo.join(code)));

  /// DELETE /vacas/:id/members/:userId: salirse (el id propio) o sacar a alguien. 404 = hecho.
  Future<void> removeMember(String id, String userId) => _once('vaca-member-remove $id $userId', () async {
    try {
      await _send(() => _repo.removeMember(id, userId));
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  });

  /// Salirse de la vaca: el servidor solo deja quitarse a uno mismo o, si se administra, a otros.
  Future<void> leave(String id) => removeMember(id, _ref.read(accountProvider)?.user.id ?? '');

  /// PATCH de un miembro: `role` o `quota` (null = la calculada). Poner lo mismo dos veces no cambia.
  Future<void> updateMember(String id, String userId, Map<String, dynamic> body) =>
      _once('vaca-member-edit $id $userId', () => _send(() => _repo.updateMember(id, userId, body)));

  /// POST de una invitación por correo: el servidor no reenvía la de hace un momento (false).
  Future<bool> invite(String id, String email) =>
      _once('vaca-invite $id $email', () => _send(() => _repo.invite(id, email)));

  Future<void> cancelInvitation(String id, String email) => _once('vaca-invite-cancel $id $email', () async {
    try {
      await _send(() => _repo.cancelInvitation(id, email));
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
  });

  Future<void> regenerateCode(String id) =>
      _once('vaca-code $id', () => _send(() => _repo.regenerateCode(id)));

  /// POST /vacas/:id/reminders: el servidor deja uno cada 12 horas (429 con su mensaje).
  Future<({int reminded, int delivered})> remind(String id) =>
      _once('vaca-remind $id', () => _send(() => _repo.remind(id)));

  /// POST /vacas/:id/contributions: crea también el GASTO en Movimientos (Mi plata baja). [localId] es
  /// del borrador de la hoja (como MovementSaver): un reintento tras una duda devuelve el aporte que ya
  /// llegó en vez de crear otro; otra hoja u otro borrador es un aporte nuevo, aunque sea idéntico (el
  /// servidor devuelve el que tenga ese localId, también si se borró). Devuelve el monto registrado.
  Future<num> contribute(String id, Map<String, dynamic> body, {required String localId}) => _once(
    'vaca-contribute $id',
    () => _send(() => _repo.contribute(id, body, localId: localId), movement: true),
  );

  /// DELETE de un aporte propio (y su gasto). Un 404 cuenta como borrado solo si la vaca sigue a la
  /// vista: el servidor también responde 404 cuando ya no se es miembro, y entonces el gasto sigue.
  /// En duda, borrado = ya no está en el detalle.
  Future<void> deleteContribution(String id, String contributionId) =>
      _once('vaca-contribution-delete $contributionId', () async {
        try {
          await _send(() => _repo.deleteContribution(id, contributionId), movement: true);
        } on ApiException catch (e) {
          if (e.status != 404 && !inDoubt(e)) rethrow;
          final gone = await _check(() async {
            final vaca = await _repo.get(id);
            return e.status == 404 || !vaca.contributions.any((c) => c.id == contributionId);
          });
          if (!gone) rethrow;
        }
      });

  /// POST /vacas/:id/personal. Un 409 «ya es personal» (el reintento tras perder la respuesta) o una
  /// duda que al releer ya es meta cuentan como hechos.
  Future<Vaca> makePersonal(String id) => _once('vaca-personal $id', () async {
    try {
      return await _send(() => _repo.makePersonal(id));
    } on ApiException catch (e) {
      if (e.code != 'ALREADY_PERSONAL' && !inDoubt(e)) rethrow;
      final vaca = await _repo.get(id).then<Vaca?>((v) => v, onError: (_) => null);
      if (vaca == null || !vaca.personal) rethrow;
      _refresh();
      return vaca;
    }
  });
}

final vacasWriterProvider = Provider<VacasWriter>(VacasWriter.new);
