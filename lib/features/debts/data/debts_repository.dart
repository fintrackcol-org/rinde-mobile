import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import 'debt_models.dart';
import 'demo_debts_repository.dart';

/// Cuentas en el servidor (los mismos endpoints que debtService.js de Rinde Web).
/// - [ApiDebtsRepository]: la real.
/// - `DemoDebtsRepository`: MODO DEMOSTRACIÓN, guarda en el teléfono y nunca sale a la red.
///
/// POST /debts no es idempotente; POST /debts/:id/payments sí lo es con `Idempotency-Key`, en el
/// servidor que ya lo tiene. Las salvaguardas (un envío a la vez, la llave por borrador, foto previa,
/// confirmar leyendo) viven en `DebtsWriter`, no aquí.
abstract interface class DebtsRepository {
  bool get isDemo;

  /// GET /debts.
  Future<DebtsList> list();

  /// POST /debts. No toca Mi plata.
  Future<void> create(Map<String, dynamic> body);

  /// PUT /debts/:id. 409 `ALREADY_SETTLED` si ya está saldada.
  Future<void> update(String id, Map<String, dynamic> body);

  /// DELETE /debts/:id (borrado físico; sus movimientos quedan).
  Future<void> delete(String id);

  /// POST /debts/:id/settle con `{createTransaction}` y SIN `date`, como la web.
  Future<void> settle(String id, {required bool createTransaction});

  /// POST /debts/:id/payments. Con [createTransaction] crea el ingreso o gasto que cambia Mi plata.
  /// Con [idempotencyKey] el servidor lo aplica una sola vez (la repetición responde 201 con
  /// `Idempotent-Replayed: true`, que también es «hecho»); un servidor sin ese cambio la ignora.
  Future<void> pay(
    String id, {
    required num amount,
    required String date,
    required bool createTransaction,
    String? idempotencyKey,
  });

  /// DELETE /debts/:id/payments/:paymentId: la cuenta como queda. Borra también su movimiento.
  Future<Debt> deletePayment(String id, String paymentId);
}

class ApiDebtsRepository implements DebtsRepository {
  ApiDebtsRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id) => '/debts/${Uri.encodeComponent(id)}';

  @override
  Future<DebtsList> list() async => DebtsList.fromJson(await _api.get('/debts'));

  @override
  Future<void> create(Map<String, dynamic> body) => _api.post('/debts', body: body, auth: true);

  @override
  Future<void> update(String id, Map<String, dynamic> body) => _api.put(_path(id), body: body);

  @override
  Future<void> delete(String id) => _api.delete(_path(id));

  @override
  Future<void> settle(String id, {required bool createTransaction}) =>
      _api.post('${_path(id)}/settle', body: {'createTransaction': createTransaction}, auth: true);

  @override
  Future<void> pay(
    String id, {
    required num amount,
    required String date,
    required bool createTransaction,
    String? idempotencyKey,
  }) => _api.post(
    '${_path(id)}/payments',
    body: {'amount': amount, 'date': date, 'createTransaction': createTransaction},
    auth: true,
    headers: {'Idempotency-Key': ?idempotencyKey},
  );

  @override
  Future<Debt> deletePayment(String id, String paymentId) async =>
      Debt.fromJson(await _api.delete('${_path(id)}/payments/${Uri.encodeComponent(paymentId)}'));
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final debtsRepositoryProvider = Provider<DebtsRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) return ref.watch(demoDebtsRepositoryProvider(session.user.id));
  return ApiDebtsRepository(ref.watch(apiClientProvider));
});
