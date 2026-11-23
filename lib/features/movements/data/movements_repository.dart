import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/home_models.dart' show readMap;
import '../domain/movement.dart';
import 'demo_movements_repository.dart';

/// Movimientos en el servidor (los mismos endpoints que transactionService.js de la web).
/// - [ApiMovementsRepository]: la real.
/// - `DemoMovementsRepository`: MODO DEMOSTRACIÓN, guarda en el teléfono y nunca sale a la red.
///
/// No hay `parse(texto)`: la barra rápida de la web interpreta el texto en el navegador
/// (lib/voiceEntry.js); el backend no tiene un endpoint para eso.
abstract interface class MovementsRepository {
  bool get isDemo;

  /// GET /transactions con filtros, del más reciente al más antiguo.
  Future<MovementPage> list(MovementQuery q);

  /// GET /transactions/:id. 404 `NOT_FOUND` si no existe, se borró o es de otro usuario.
  Future<Movement> get(String id);

  /// POST /transactions con `localId`: el servidor devuelve el mismo movimiento si ya lo recibió.
  Future<Movement> create(MovementInput input, {required String localId});

  /// PUT /transactions/:id con el estado completo del formulario.
  /// Con [from], solo lo que cambió (lo que no se tocó no se vuelve a decidir en el servidor).
  Future<Movement> update(String id, MovementInput input, {Movement? from});

  /// DELETE /transactions/:id (borrado lógico).
  Future<void> delete(String id);

  /// GET /categories.
  Future<CategoryLists> categories();
}

class ApiMovementsRepository implements MovementsRepository {
  ApiMovementsRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id) => '/transactions/${Uri.encodeComponent(id)}';

  @override
  Future<MovementPage> list(MovementQuery q) async =>
      MovementPage.fromJson(await _api.get('/transactions', query: q.toParams()));

  @override
  Future<Movement> get(String id) async => Movement.fromJson(await _api.get(_path(id)));

  // POST y PUT responden `{ transaction, alert }`; la alerta de presupuesto no se lee todavía.
  @override
  Future<Movement> create(MovementInput input, {required String localId}) async => Movement.fromJson(
    readMap(
      await _api.post('/transactions', body: {...input.toJson(), 'localId': localId}, auth: true),
    )['transaction'],
  );

  @override
  Future<Movement> update(String id, MovementInput input, {Movement? from}) async => Movement.fromJson(
    readMap(
      await _api.put(_path(id), body: from == null ? input.toJson(update: true) : input.changesFrom(from)),
    )['transaction'],
  );

  @override
  Future<void> delete(String id) async {
    // ApiClient no trae delete: mismo manejo de errores que sus otros verbos.
    try {
      await _api.authed.delete<dynamic>(_path(id));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  @override
  Future<CategoryLists> categories() async => CategoryLists.fromJson(await _api.get('/categories'));
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final movementsRepositoryProvider = Provider<MovementsRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) return ref.watch(demoMovementsRepositoryProvider(session.user.id));
  return ApiMovementsRepository(ref.watch(apiClientProvider));
});
