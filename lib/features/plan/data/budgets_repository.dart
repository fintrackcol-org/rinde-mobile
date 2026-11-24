import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import 'demo_budgets_repository.dart';

/// Escrituras de presupuestos (budgetService.js de la web). La lista del mes la lee el Inicio
/// (`HomeRepository.budgets`): una sola lectura de GET /budgets para todos.
/// - [ApiBudgetsRepository]: la real.
/// - `DemoBudgetsRepository`: MODO DEMOSTRACIÓN, nunca sale a la red.
abstract interface class BudgetsRepository {
  bool get isDemo;

  /// POST /budgets. 409 `BUDGET_EXISTS` si esa categoría ya tiene uno ese mes.
  Future<void> create({required String category, required String month, required num amount});

  /// PUT /budgets/:id `{amount}`: solo el límite (la API no cambia la categoría ni el mes).
  Future<void> update(String id, num amount);

  /// DELETE /budgets/:id (204). 404 si ya no existe.
  Future<void> delete(String id);
}

class ApiBudgetsRepository implements BudgetsRepository {
  ApiBudgetsRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id) => '/budgets/${Uri.encodeComponent(id)}';

  @override
  Future<void> create({required String category, required String month, required num amount}) =>
      _api.post('/budgets', body: {'category': category, 'month': month, 'amount': amount}, auth: true);

  @override
  Future<void> update(String id, num amount) => _api.put(_path(id), body: {'amount': amount});

  @override
  Future<void> delete(String id) => _api.delete(_path(id));
}

/// Una sesión demo nunca usa la API.
final budgetsRepositoryProvider = Provider<BudgetsRepository>((ref) {
  final session = ref.watch(sessionControllerProvider.select((s) => s.value?.session));
  if (session != null && session.demo) return ref.watch(demoBudgetsRepositoryProvider(session.user.id));
  return ApiBudgetsRepository(ref.watch(apiClientProvider));
});
