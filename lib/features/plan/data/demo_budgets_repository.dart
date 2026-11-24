import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/home_models.dart' show readMoney;
import '../../movements/data/demo_movements_repository.dart' show demoCategoryExpenseCents;
import '../../movements/data/json_list_store.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import 'budgets_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Presupuestos de los recorridos (nuevo, movimientos, sinPlan) en un almacén propio
//  (`rinde.demo.presupuestos.<userId>`), como las cuentas y tarjetas de la demo. Los escenarios fijos
//  tienen su presupuesto sembrado en el Inicio demo y no escriben (demoNoBackend). «Reiniciar
//  demostración» los borra. En cuentas reales no se guarda nada de esto en el teléfono.
// ─────────────────────────────────────────────────────────────────────────────

final demoBudgetsStoreProvider = Provider<JsonListStore>(
  (ref) => const SecureJsonListStore('rinde.demo.presupuestos.'),
);

const _journeys = {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan};

const _noBackend = ApiException(
  code: ApiCodes.demoNoBackend,
  serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
);

const _notFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Presupuesto no encontrado', status: 404);

const _exists = ApiException(
  code: 'BUDGET_EXISTS',
  serverMessage: 'Ya existe un presupuesto para esa categoría en ese mes',
  status: 409,
);

ApiException _invalid(Map<String, String> fields) =>
    ApiException(code: ApiCodes.validation, serverMessage: 'Datos inválidos', status: 422, fields: fields);

int _cents(Object? value) => ((readMoney(value) ?? 0) * 100).round();

/// GET /budgets?month= de un recorrido: lo guardado de ese mes con lo gastado y la alerta, como
/// budgets.service.js (redondeo a 2 decimales, advertencia desde el 80 %, excedido desde el 100 %).
/// [spentCents]: lo que el escenario ya trae gastado por categoría ese mes (lo anotado se suma).
Future<List<Map<String, dynamic>>> demoJourneyBudgets({
  required JsonListStore store,
  required JsonListStore movements,
  required String userId,
  required String month,
  required Map<String, int> spentCents,
}) async {
  final result = <Map<String, dynamic>>[];
  for (final raw in await store.read(userId) ?? const <Object?>[]) {
    if (raw is! Map || raw['month'] != month) continue;
    final category = '${raw['category']}';
    final consumed =
        (spentCents[category] ?? 0) + await demoCategoryExpenseCents(movements, userId, month, category);
    final amount = _cents(raw['amount']);
    final percentage = (consumed * 10000 / amount).round() / 100;
    result.add({
      'id': raw['id'],
      'category': category,
      'month': month,
      'amount': readMoney(amount / 100),
      'consumed': readMoney(consumed / 100),
      'percentage': percentage,
      'alert': {
        'level': percentage >= 100 ? 'exceeded_100' : (percentage >= 80 ? 'warning_80' : 'none'),
        'percentage': percentage,
      },
    });
  }
  return result;
}

class DemoBudgetsRepository implements BudgetsRepository {
  DemoBudgetsRepository({
    required this.userId,
    required this.store,
    required this.controls,
    required this.clock,
  });

  final String userId;
  final JsonListStore store;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  @override
  bool get isDemo => true;

  Future<T> _write<T>(Future<T> Function(List<Map<String, dynamic>> all) change) async {
    await controls.simulate();
    if (!_journeys.contains(scenario)) throw _noBackend;
    // Sin poder leer no se escribe: se pisaría lo guardado.
    final raw =
        await store.read(userId) ?? (throw StateError('No se pudieron leer los presupuestos de la demo'));
    return change([
      for (final b in raw)
        if (b is Map) Map<String, dynamic>.from(b),
    ]);
  }

  @override
  Future<void> create({required String category, required String month, required num amount}) =>
      _write((all) async {
        if (amount <= 0) throw _invalid({'amount': 'Debe ser un número mayor que 0'});
        if (all.any((b) => b['category'] == category && b['month'] == month)) throw _exists;
        await store.write(userId, [
          ...all,
          {
            'id': 'demo-presupuesto-${clock().microsecondsSinceEpoch}',
            'category': category,
            'month': month,
            'amount': readMoney(amount),
          },
        ]);
      });

  @override
  Future<void> update(String id, num amount) => _write((all) async {
    if (amount <= 0) throw _invalid({'amount': 'Debe ser un número mayor que 0'});
    final index = all.indexWhere((b) => b['id'] == id);
    if (index < 0) throw _notFound;
    all[index] = {...all[index], 'amount': readMoney(amount)};
    await store.write(userId, all);
  });

  @override
  Future<void> delete(String id) => _write((all) async {
    final before = all.length;
    all.removeWhere((b) => b['id'] == id);
    if (all.length == before) throw _notFound;
    await store.write(userId, all);
  });
}

final demoBudgetsRepositoryProvider = Provider.family<DemoBudgetsRepository, String>(
  (ref, userId) => DemoBudgetsRepository(
    userId: userId,
    store: ref.watch(demoBudgetsStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
  ),
);
