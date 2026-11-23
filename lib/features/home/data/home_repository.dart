import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import 'demo_home_repository.dart';
import 'home_models.dart';

/// Lo que el Inicio le pide al servidor (los mismos endpoints que usa Rinde Web). El saldo, la
/// bienvenida y si hay movimientos llegan por `welcomeStatusProvider` (GET /money-profile).
/// Dos implementaciones:
/// - [ApiHomeRepository]: la real.
/// - `DemoHomeRepository`: MODO DEMOSTRACIÓN / SIN BACKEND, respuestas sintéticas del mismo contrato.
abstract interface class HomeRepository {
  /// true = nada de esto viene de un servidor.
  bool get isDemo;

  /// GET /money-profile/plan.
  Future<MoneyPlan> plan();

  /// GET /transactions/summary?period=month&date=AAAA-MM-DD (día local del dispositivo, como la web).
  Future<MonthTotals> monthTotals(String date);

  /// GET /budgets?month=AAAA-MM.
  Future<List<BudgetStatus>> budgets(String month);

  /// GET /cards.
  Future<List<CardSummary>> cards();

  /// GET /pending-payments → cuántos pagos esperan confirmación.
  Future<int> toConfirm();

  /// GET /notifications → `unread`.
  Future<int> unread();

  /// GET /categories → clave → nombre (ya traducido por el servidor según Accept-Language).
  Future<Map<String, String>> categoryNames();

  /// POST /money-profile/tutorial: el tutorial de primera vez ya se vio.
  Future<void> finishTutorial();
}

class ApiHomeRepository implements HomeRepository {
  ApiHomeRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<MoneyPlan> plan() async => MoneyPlan.fromJson(await _api.get('/money-profile/plan'));

  @override
  Future<MonthTotals> monthTotals(String date) async =>
      MonthTotals.fromJson(await _api.get('/transactions/summary', query: {'period': 'month', 'date': date}));

  @override
  Future<List<BudgetStatus>> budgets(String month) async => [
    for (final item in readList(await _api.get('/budgets', query: {'month': month})))
      ?BudgetStatus.tryParse(item),
  ];

  @override
  Future<List<CardSummary>> cards() async => [
    for (final item in readList(await _api.get('/cards'))) ?CardSummary.tryParse(item),
  ];

  @override
  Future<int> toConfirm() async => readList(readMap(await _api.get('/pending-payments'))['items']).length;

  @override
  Future<int> unread() async {
    final unread = readMap(await _api.get('/notifications'))['unread'];
    return unread is int && unread > 0 ? unread : 0;
  }

  @override
  Future<Map<String, String>> categoryNames() async {
    final json = readMap(await _api.get('/categories'));
    return {
      for (final list in [json['expense'], json['income']])
        if (list is List)
          for (final c in list)
            if (c is Map && c['key'] is String && c['name'] is String)
              c['key'] as String: c['name'] as String,
    };
  }

  @override
  Future<void> finishTutorial() => _api.post('/money-profile/tutorial', auth: true);
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final session = ref.watch(sessionControllerProvider.select((s) => s.value?.session));
  if (session != null && session.demo) return ref.watch(demoHomeRepositoryProvider(session.user.id));
  return ApiHomeRepository(ref.watch(apiClientProvider));
});
