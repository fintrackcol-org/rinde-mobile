import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/data/onboarding_repository.dart';
import 'demo_money_repository.dart';
import 'money_models.dart';

/// Lo que Mi plata le pide al servidor (los mismos endpoints de Rinde Web). Dos implementaciones:
/// - [ApiMoneyRepository]: la real.
/// - `DemoMoneyRepository`: MODO DEMOSTRACIÓN / SIN BACKEND, respuestas sintéticas del mismo contrato.
abstract interface class MoneyRepository {
  /// true = nada de esto viene de un servidor.
  bool get isDemo;

  /// GET /money-profile.
  Future<MoneyProfile> profile();

  /// GET /money-profile/income.
  Future<IncomeOverview> income();

  /// PUT /money-profile/sources {sources}: reemplaza todas las fuentes.
  Future<void> saveSources(List<Map<String, dynamic>> sources);

  /// POST /money-profile/commitments. 409 COMMITMENT_EXISTS si el nombre ya está.
  Future<void> createCommitment(Map<String, dynamic> body);

  /// PUT /money-profile {incomeType, payDays, balance, resetBalance?, expectedVersion?}. Reemplazo
  /// total y no idempotente con `resetBalance`: solo lo llama `MoneyWriter.saveBalance`.
  Future<void> saveProfile(Map<String, dynamic> body);

  /// GET /money-profile/adjustments?from=&to= (AAAA-MM-DD): las correcciones de saldo del periodo.
  Future<List<BalanceAdjustment>> adjustments({required String from, required String to});
}

class ApiMoneyRepository implements MoneyRepository {
  ApiMoneyRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<MoneyProfile> profile() async => MoneyProfile.fromJson(await _api.get('/money-profile'));

  @override
  Future<IncomeOverview> income() async => IncomeOverview.fromJson(await _api.get('/money-profile/income'));

  // El mismo envío de la bienvenida: un solo lugar arma la petición.
  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) =>
      ApiOnboardingRepository(_api).saveSources(sources);

  @override
  Future<void> createCommitment(Map<String, dynamic> body) =>
      _api.post('/money-profile/commitments', body: body, auth: true);

  @override
  Future<void> saveProfile(Map<String, dynamic> body) => _api.put('/money-profile', body: body);

  @override
  Future<List<BalanceAdjustment>> adjustments({required String from, required String to}) async =>
      BalanceAdjustment.listFromJson(
        await _api.get('/money-profile/adjustments', query: {'from': from, 'to': to}),
      );
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final moneyRepositoryProvider = Provider<MoneyRepository>((ref) {
  final session = ref.watch(sessionControllerProvider.select((s) => s.value?.session));
  if (session != null && session.demo) return ref.watch(demoMoneyRepositoryProvider(session.user.id));
  return ApiMoneyRepository(ref.watch(apiClientProvider));
});
