import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/home_models.dart' show readMoney;
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
    this.money,
    this.balanceSet = false,
    this.balance,
    this.incomeType,
    this.payDays = const [],
    this.commitmentNames = const [],
  });

  /// GET /money-profile → welcomeDone (la bienvenida se respondió u omitió).
  final bool welcomeDone;
  final bool tutorialDone;

  /// GET /transactions?page=1&pageSize=1 → total > 0.
  final bool hasTransactions;

  /// GET /money-profile → totals (todo el historial).
  final num income;
  final num expense;

  /// GET /money-profile → money: la plata actual según el servidor. null = el servidor no la sabe
  /// (nadie dijo un saldo y los movimientos no dan uno). Nunca se reemplaza por un cero.
  final num? money;

  /// GET /money-profile → balance es un número: la persona ya dijo cuánta plata tiene.
  final bool balanceSet;

  /// GET /money-profile → balance: lo que la persona dijo tener (no es la plata actual, [money]).
  final num? balance;

  /// GET /money-profile → incomeType y payDays. Un reenvío sin fuentes los devuelve tal cual: el
  /// servidor los pisa con lo que mande la bienvenida.
  final String? incomeType;
  final List<int> payDays;

  /// GET /money-profile → commitments[].name: los pagos que el servidor tiene guardados.
  final List<String> commitmentNames;

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
    final welcomeDone = profile['welcomeDone'];
    // Estricto: una respuesta mal formada no puede leerse como «cuenta nueva sin bienvenida»,
    // porque eso manda a la persona a la bienvenida.
    if (welcomeDone is! bool || total is! num) throw const ApiException(code: ApiCodes.unknown);
    return WelcomeStatus(
      welcomeDone: welcomeDone,
      tutorialDone: profile['tutorialDone'] == true,
      hasTransactions: total > 0,
      income: totals['income'] is num ? totals['income'] as num : 0,
      expense: totals['expense'] is num ? totals['expense'] as num : 0,
      money: readMoney(profile['money']),
      balanceSet: profile['balance'] is num,
      balance: readMoney(profile['balance']),
      incomeType: profile['incomeType'] is String ? profile['incomeType'] as String : null,
      payDays: [
        if (profile['payDays'] case final List<dynamic> days)
          for (final day in days)
            if (day is int) day,
      ],
      commitmentNames: [
        if (profile['commitments'] case final List<dynamic> saved)
          for (final c in saved)
            if (c case {'name': final String name}) name,
      ],
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
final welcomeStatusProvider = perAccount<WelcomeStatus>(
  (ref) => ref.watch(onboardingRepositoryProvider).status(),
);

/// En este dispositivo quedó una bienvenida a medias: el servidor confirmó la etapa 1 (saldo y
/// pagos) pero no las fuentes de ingreso. Al entrar se retoma para no perderlas.
final pendingSourcesProvider = perAccount<bool>((ref) async {
  final userId = ref.watch(accountProvider)?.user.id;
  if (userId == null) return false;
  final draft = OnboardingDraft.fromJson(
    await ref.read(draftStoreProvider).read(userId),
    suggestedCountry: 'CO',
  );
  // Todo éxito borra el borrador: si queda una marca, algo falta (el saldo, los pagos o las fuentes).
  return draft.sentWelcome != null;
});

/// En esta sesión la persona salió de «terminar la bienvenida» sin acabarla: la entrada no la
/// devuelve ahí otra vez (quedaría atrapada sin poder llegar al Inicio). Al reabrir la app se retoma.
class ResumeDeferred extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(sessionControllerProvider.select((s) => s.value?.session?.user.id));
    return false;
  }

  void defer() => state = true;
}

final resumeDeferredProvider = NotifierProvider<ResumeDeferred, bool>(ResumeDeferred.new);
