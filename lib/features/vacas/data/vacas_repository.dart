import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/home_models.dart' show readList, readMap;
import 'demo_vacas_repository.dart';
import 'vaca_models.dart';

/// Metas y Vacas en el servidor (los mismos endpoints que vacaService.js de Rinde Web).
/// - [ApiVacasRepository]: la real.
/// - `DemoVacasRepository`: MODO DEMOSTRACIÓN, sin red.
///
/// Solo el aporte es idempotente (por `localId`); las salvaguardas de las demás escrituras (un envío
/// a la vez, foto previa, confirmar leyendo) viven en `VacasWriter`.
abstract interface class VacasRepository {
  bool get isDemo;

  /// GET /vacas: metas y vacas juntas, la de último cambio primero (como la web, que filtra aquí).
  Future<List<Vaca>> list();

  /// GET /vacas/:id. 404 si no existe o ya no se es miembro.
  Future<Vaca> get(String id);

  /// POST /vacas. Quien la crea queda de administrador.
  Future<Vaca> create(Map<String, dynamic> body);

  /// PATCH /vacas/:id (administradores).
  Future<Vaca> update(String id, Map<String, dynamic> body);

  /// DELETE /vacas/:id (administradores). Los gastos de los aportes quedan en Movimientos.
  Future<void> delete(String id);

  /// GET /vacas/invitations/:code.
  Future<InvitationPreview> preview(String code);

  /// POST /vacas/join. Si ya se era miembro, solo devuelve el detalle.
  Future<Vaca> join(String code);

  /// POST /vacas/:id/code: el código anterior deja de servir (administradores).
  Future<void> regenerateCode(String id);

  /// POST /vacas/:id/invitations. false: ya se le había enviado hace un momento.
  Future<bool> invite(String id, String email);

  /// DELETE /vacas/:id/invitations?email= (administradores).
  Future<void> cancelInvitation(String id, String email);

  /// PATCH /vacas/:id/members/:userId con `role` o `quota` (administradores).
  Future<void> updateMember(String id, String userId, Map<String, dynamic> body);

  /// DELETE /vacas/:id/members/:userId: sacar a alguien (administradores) o salirse (el id propio).
  Future<void> removeMember(String id, String userId);

  /// POST /vacas/:id/contributions. Crea también el GASTO en Movimientos. Con el mismo [localId] el
  /// servidor no duplica ni el aporte ni el gasto. Devuelve el monto que quedó registrado.
  Future<num> contribute(String id, Map<String, dynamic> body, {required String localId});

  /// DELETE /vacas/:id/contributions/:contributionId: borra también su gasto (solo el propio).
  Future<void> deleteContribution(String id, String contributionId);

  /// GET /vacas/:id/advice.
  Future<VacaAdvice> advice(String id);

  /// POST /vacas/:id/reminders (administradores, uno cada 12 horas).
  Future<({int reminded, int delivered})> remind(String id);

  /// POST /vacas/:id/personal: pasar a Metas una vaca de un solo integrante.
  Future<Vaca> makePersonal(String id);
}

class ApiVacasRepository implements VacasRepository {
  ApiVacasRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id) => '/vacas/${Uri.encodeComponent(id)}';

  @override
  Future<List<Vaca>> list() async => [
    for (final item in readList(await _api.get('/vacas'))) Vaca.fromJson(item),
  ];

  @override
  Future<Vaca> get(String id) async => Vaca.fromJson(await _api.get(_path(id)));

  @override
  Future<Vaca> create(Map<String, dynamic> body) async =>
      Vaca.fromJson(await _api.post('/vacas', body: body, auth: true));

  @override
  Future<Vaca> update(String id, Map<String, dynamic> body) async =>
      Vaca.fromJson(await _api.patch(_path(id), body: body));

  @override
  Future<void> delete(String id) => _api.delete(_path(id));

  @override
  Future<InvitationPreview> preview(String code) async =>
      InvitationPreview.fromJson(await _api.get('/vacas/invitations/${Uri.encodeComponent(code)}'));

  @override
  Future<Vaca> join(String code) async =>
      Vaca.fromJson(await _api.post('/vacas/join', body: {'code': code}, auth: true));

  @override
  Future<void> regenerateCode(String id) => _api.post('${_path(id)}/code', auth: true);

  @override
  Future<bool> invite(String id, String email) async =>
      readMap(await _api.post('${_path(id)}/invitations', body: {'email': email}, auth: true))['sent'] !=
      false;

  @override
  Future<void> cancelInvitation(String id, String email) =>
      _api.delete('${_path(id)}/invitations?email=${Uri.encodeQueryComponent(email)}');

  @override
  Future<void> updateMember(String id, String userId, Map<String, dynamic> body) =>
      _api.patch('${_path(id)}/members/${Uri.encodeComponent(userId)}', body: body);

  @override
  Future<void> removeMember(String id, String userId) =>
      _api.delete('${_path(id)}/members/${Uri.encodeComponent(userId)}');

  @override
  Future<num> contribute(String id, Map<String, dynamic> body, {required String localId}) async {
    final result = readMap(
      await _api.post('${_path(id)}/contributions', body: {...body, 'localId': localId}, auth: true),
    );
    return VacaContribution.fromJson(result['contribution']).amount;
  }

  @override
  Future<void> deleteContribution(String id, String contributionId) =>
      _api.delete('${_path(id)}/contributions/${Uri.encodeComponent(contributionId)}');

  @override
  Future<VacaAdvice> advice(String id) async => VacaAdvice.fromJson(await _api.get('${_path(id)}/advice'));

  @override
  Future<({int reminded, int delivered})> remind(String id) async {
    final json = readMap(await _api.post('${_path(id)}/reminders', auth: true));
    int count(Object? raw) => raw is int ? raw : 0;
    return (reminded: count(json['reminded']), delivered: count(json['delivered']));
  }

  @override
  Future<Vaca> makePersonal(String id) async =>
      Vaca.fromJson(await _api.post('${_path(id)}/personal', auth: true));
}

/// Una sesión demo nunca usa la API.
final vacasRepositoryProvider = Provider<VacasRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) return ref.watch(demoVacasRepositoryProvider(session.user.id));
  return ApiVacasRepository(ref.watch(apiClientProvider));
});
