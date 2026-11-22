import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../auth/application/session_controller.dart';
import '../domain/onboarding_draft.dart';
import 'demo_onboarding_repository.dart';
import 'draft_store.dart';

/// Lo que la app necesita saber para decidir si muestra la bienvenida.
class WelcomeStatus {
  const WelcomeStatus({
    required this.welcomeDone,
    required this.tutorialDone,
    required this.hasTransactions,
    this.income = 0,
    this.expense = 0,
  });

  /// GET /money-profile → welcomeDone (la bienvenida se respondió u omitió).
  final bool welcomeDone;
  final bool tutorialDone;

  /// GET /transactions?page=1&pageSize=1 → total > 0.
  final bool hasTransactions;

  /// GET /money-profile → totals (todo el historial).
  final num income;
  final num expense;

  /// Propuesta de saldo de la web (balanceProposal): ingresos − gastos, solo si es positiva.
  num? get balanceProposal {
    final value = (income - expense).round();
    return value > 0 ? value : null;
  }
}

/// Contrato de la bienvenida con el servidor. Dos implementaciones:
/// - [ApiOnboardingRepository]: la real, con los endpoints que ya usa Rinde Web.
/// - [DemoOnboardingRepository]: MODO DEMOSTRACIÓN / SIN BACKEND, solo para desarrollo y pruebas.
abstract interface class OnboardingRepository {
  /// true = nada de esto llega a un servidor.
  bool get isDemo;

  Future<WelcomeStatus> status();

  /// PATCH /users/me {country, language, currency}. Si la moneda ya no se puede cambiar
  /// (409 CURRENCY_LOCKED), repite sin moneda. Devuelve la región que quedó guardada.
  Future<Region> saveRegion({required String country, required String language});

  /// POST /money-profile/welcome.
  Future<void> finishWelcome(Map<String, dynamic> body);

  /// PUT /money-profile/sources {sources}. Reemplaza las fuentes anteriores.
  Future<void> saveSources(List<Map<String, dynamic>> sources);
}

class ApiOnboardingRepository implements OnboardingRepository {
  ApiOnboardingRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<WelcomeStatus> status() async {
    final results = await Future.wait([
      _api.get('/money-profile'),
      _api.get('/transactions', query: {'page': 1, 'pageSize': 1}),
    ]);
    final profile = _map(results[0]);
    final list = _map(results[1]);
    final totals = profile['totals'] is Map ? profile['totals'] as Map : const {};
    final total = list['total'];
    return WelcomeStatus(
      welcomeDone: profile['welcomeDone'] == true,
      tutorialDone: profile['tutorialDone'] == true,
      hasTransactions: total is num && total > 0,
      income: totals['income'] is num ? totals['income'] as num : 0,
      expense: totals['expense'] is num ? totals['expense'] as num : 0,
    );
  }

  @override
  Future<Region> saveRegion({required String country, required String language}) async {
    final currency = regionForCountry(country).currency;
    Map<String, dynamic> profile;
    try {
      profile = _map(
        await _api.patch('/users/me', body: {'country': country, 'language': language, 'currency': currency}),
      );
    } on ApiException catch (e) {
      if (e.code != 'CURRENCY_LOCKED') rethrow;
      // Ya hay movimientos en otra moneda: se guarda el país y el idioma, la moneda queda.
      profile = _map(await _api.patch('/users/me', body: {'country': country, 'language': language}));
    }
    return Region.fromJson(profile);
  }

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) =>
      _api.post('/money-profile/welcome', body: body, auth: true);

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) =>
      _api.put('/money-profile/sources', body: {'sources': sources});

  Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException(code: ApiCodes.unknown);
  }
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  final session = ref.watch(sessionControllerProvider.select((s) => s.value?.session));
  if (session != null && session.demo) return ref.watch(demoOnboardingRepositoryProvider(session.user.id));
  return ApiOnboardingRepository(ref.watch(apiClientProvider));
});

/// Estado de la bienvenida de quien está dentro (se vuelve a pedir al cambiar de cuenta).
final welcomeStatusProvider = FutureProvider<WelcomeStatus>((ref) {
  ref.watch(sessionControllerProvider.select((s) => s.value?.session?.user.id));
  return ref.watch(onboardingRepositoryProvider).status();
});

/// En este dispositivo quedó una bienvenida a medias: el servidor confirmó la etapa 1 (saldo y
/// pagos) pero no las fuentes de ingreso. Al entrar se retoma para no perderlas.
final pendingSourcesProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.user.id));
  if (userId == null) return false;
  final draft = OnboardingDraft.fromJson(
    await ref.read(draftStoreProvider).read(userId),
    suggestedCountry: 'CO',
  );
  return draft.sentWelcome != null && draft.sources.isNotEmpty;
});
