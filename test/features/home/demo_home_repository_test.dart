// MODO DEMOSTRACIÓN del Inicio: cifras de cada escenario, continuidad con la bienvenida, persistencia,
// fallas y que nada salga a la red. Todo corre con los proveedores reales y los almacenes en memoria.
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/data/demo_home_repository.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/home/domain/home_notice.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';

import '../../support/fake_http.dart';

// Un servidor bien configurado: si algo intentara salir, se vería en el adaptador.
const _demo = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa', demoMode: true);
const _noDemo = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');

const _us = Region(country: 'US', currency: 'USD', language: 'en');
const _br = Region(country: 'BR', currency: 'BRL', language: 'pt');

/// 28 de noviembre: lo que viene cae en otro mes.
final _now = DateTime(2026, 11, 28, 10);

int _cents(num value) => (value * 100).round();

class _Regions extends RegionStore {
  Region? saved;
  int writes = 0;

  @override
  Future<Region?> read() async => saved;

  @override
  Future<void> write(Region region) async {
    writes++;
    saved = region;
  }
}

/// Lo que cada escenario debe mostrar, en pesos.
typedef _Figures = ({num? money, List<num> pending, num free, num perDay, num income, num expense});

const _expected = <DemoScenario, _Figures>{
  DemoScenario.nuevo: (money: null, pending: [], free: 0, perDay: 0, income: 0, expense: 0),
  DemoScenario.movimientos: (
    money: 650000,
    pending: [],
    free: 0,
    perDay: 0,
    income: 2500000,
    expense: 1850000,
  ),
  DemoScenario.planListo: (
    money: 412300,
    pending: [45000, 228000, 65000],
    free: 74300,
    perDay: 6500,
    income: 700000,
    expense: 287700,
  ),
  DemoScenario.teFaltan: (
    money: 180000,
    pending: [45000, 228000],
    free: -93000,
    perDay: 0,
    income: 400000,
    expense: 520000,
  ),
  DemoScenario.negativo: (
    money: -35000,
    pending: [45000],
    free: -80000,
    perDay: 0,
    income: 600000,
    expense: 635000,
  ),
  DemoScenario.sinPlan: (money: 412300, pending: [], free: 0, perDay: 0, income: 700000, expense: 287700),
};

void main() {
  late MemoryDemoStateStore store;
  late MemoryDraftStore drafts;
  late MemoryTourSeenStore seen;
  late MemorySessionStorage sessions;
  late _Regions regions;
  late FakeHttpAdapter network;

  setUp(() {
    store = MemoryDemoStateStore();
    drafts = MemoryDraftStore();
    seen = MemoryTourSeenStore();
    sessions = MemorySessionStorage();
    regions = _Regions();
    network = FakeHttpAdapter((_) => jsonBody(500, {}));
  });

  // Vale para todas las pruebas del archivo: la demostración nunca sale a la red.
  tearDown(() => expect(network.requests, isEmpty));

  /// Una apertura de la app. Llamarla otra vez es reabrirla con lo que quedó guardado.
  Future<ProviderContainer> open({
    String? scenario,
    AppConfig config = _demo,
    Region initial = kDefaultRegion,
    DateTime? now,
  }) async {
    if (scenario != null) await sessions.write(Session.demo(scenario));
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sessionStorageProvider.overrideWithValue(sessions),
        demoStateStoreProvider.overrideWithValue(store),
        draftStoreProvider.overrideWithValue(drafts),
        tourSeenStoreProvider.overrideWithValue(seen),
        demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
        regionStoreProvider.overrideWithValue(regions),
        initialRegionProvider.overrideWithValue(initial),
        systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
        clockProvider.overrideWithValue(() => now ?? _now),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(config: config, session: ref.watch(sessionHolderProvider), adapter: network),
        ),
      ],
    );
    c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
    c.listen(sessionControllerProvider, (_, _) {});
    await c.read(sessionControllerProvider.future);
    return c;
  }

  /// El Inicio como lo arma la app, con todos los bloques ya respondidos (bien o mal).
  Future<HomeView> home(ProviderContainer c) async {
    final account = c.read(accountProvider);
    c.listen(homeViewProvider, (_, _) {});
    c.listen(profileProvider(account), (_, _) {});
    await Future.wait([
      for (final load in <Future<Object?>>[
        c.read(profileProvider(account).future),
        c.read(welcomeStatusProvider(account).future),
        c.read(homePlanProvider(account).future),
        c.read(homeTotalsProvider(account).future),
        c.read(homeBudgetsProvider(account).future),
        c.read(homeCardsProvider(account).future),
        c.read(homeToConfirmProvider(account).future),
      ])
        load.then<void>((_) {}, onError: (_) {}),
    ]);
    await pumpEventQueue();
    return c.read(homeViewProvider);
  }

  MoneyPlan planOf(HomeView view) => (view.hero as HeroPlan).plan;

  /// La bienvenida contestada con su controlador real, hasta «Ver mi plata».
  Future<void> answer(
    ProviderContainer c, {
    required OnboardingMode mode,
    required String balance,
    required List<(String, String, String)> payments,
    String? country,
  }) async {
    final provider = onboardingControllerProvider(mode);
    final screen = c.listen(provider, (_, _) {});
    final controller = c.read(provider.notifier);
    await pumpEventQueue();
    if (country != null) {
      controller.pickCountry(country);
      await controller.saveRegion();
    }
    controller.toggleSource(IncomeKind.sueldo);
    controller.updateSource(c.read(provider).draft.sources[IncomeKind.sueldo]!.copyWith(payDays: [15]));
    controller.setBalance(balance);
    for (final (name, amount, day) in payments) {
      controller.updateItem(controller.addCustom()!, name: name, amount: amount, dayOfMonth: day);
    }
    await controller.finish();
    expect(c.read(provider).outcome, OnboardingOutcome.demoSaved);
    screen.close();
    await pumpEventQueue();
  }

  group('cada escenario cuadra', () {
    for (final (region, scale) in [(kDefaultRegion, 1), (_us, 1000)]) {
      for (final MapEntry(key: scenario, value: cop) in _expected.entries) {
        test('${scenario.name} en ${region.currency}', () async {
          await store.update('demo-${scenario.name}', (state) => state.withRegion(region));
          final c = await open(scenario: scenario.name);
          final view = await home(c);
          final repo = c.read(homeRepositoryProvider);
          final status = await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
          final plan = await repo.plan();
          final totals = await repo.monthTotals('2026-11-28');
          int scaled(num pesos) => (pesos * 100 / scale).round();

          expect(c.read(appRegionProvider), region);
          if (cop.money case final money?) {
            expect(_cents(status.money!), scaled(money));
            expect(_cents(status.income) - _cents(status.expense), scaled(money));
          } else {
            expect(status.money, isNull);
          }
          expect(totals.month, '2026-11');
          expect(_cents(totals.income), scaled(cop.income));
          expect(_cents(totals.expense), scaled(cop.expense));
          // El mes nunca pasa del historial.
          expect(totals.income, lessThanOrEqualTo(status.income));
          expect(totals.expense, lessThanOrEqualTo(status.expense));

          expect(plan.ready, cop.pending.isNotEmpty);
          if (plan.ready) {
            expect(plan.money, status.money, reason: 'un solo saldo');
            expect(plan.pending.map((p) => _cents(p.amount)), cop.pending.map(scaled));
            expect(_cents(plan.pendingTotal), plan.pending.fold<int>(0, (sum, p) => sum + _cents(p.amount)));
            expect(_cents(plan.free), _cents(plan.money) - _cents(plan.pendingTotal));
            expect(_cents(plan.free), scaled(cop.free));
            expect(_cents(plan.shortfall), plan.free < 0 ? -_cents(plan.free) : 0);
            expect(_cents(plan.perDay!), scaled(cop.perDay));
            for (final payment in plan.pending) {
              expect(payment.date.compareTo('2026-11-28'), greaterThan(0));
              expect(payment.date.compareTo(plan.nextPay!), lessThanOrEqualTo(0));
            }
          }

          for (final budget in await repo.budgets('2026-11')) {
            expect(budget.consumed, lessThanOrEqualTo(totals.expense));
            expect(budget.percentage, closeTo(budget.consumed * 100 / budget.amount, 0.01));
          }

          expect(view.hero, switch (scenario) {
            DemoScenario.nuevo => isA<HeroUnknown>().having(
              (h) => h.reason,
              'motivo',
              UnknownReason.noBalance,
            ),
            DemoScenario.movimientos ||
            DemoScenario.sinPlan => isA<HeroMoney>().having((h) => h.money, 'saldo', status.money),
            DemoScenario.planListo => isA<HeroPlan>().having((h) => h.tone, 'tono', PlanTone.free),
            DemoScenario.teFaltan => isA<HeroPlan>().having((h) => h.tone, 'tono', PlanTone.short),
            DemoScenario.negativo => isA<HeroPlan>().having((h) => h.tone, 'tono', PlanTone.negative),
          });
          expect(view.footer, switch (scenario) {
            DemoScenario.nuevo || DemoScenario.movimientos => HomeFooter.invite,
            DemoScenario.sinPlan => HomeFooter.setup,
            _ => HomeFooter.none,
          });
          expect(view.notice?.kind, switch (scenario) {
            DemoScenario.planListo => HomeNoticeKind.cardSoon,
            DemoScenario.teFaltan => HomeNoticeKind.budgetExceeded,
            _ => null,
          });
          expect(view.toConfirm, scenario == DemoScenario.planListo ? 2 : 0);
          expect(await repo.unread(), switch (scenario) {
            DemoScenario.planListo => 3,
            DemoScenario.teFaltan => 1,
            _ => 0,
          });
          expect(view.empty, scenario == DemoScenario.nuevo);
          expect(view.offline || view.loadError, isFalse);
        });
      }
    }

    test('las fechas siguen en el futuro al cruzar el año', () async {
      final c = await open(scenario: 'planListo', now: DateTime(2026, 12, 31, 23, 50));
      final repo = c.read(homeRepositoryProvider);
      final plan = await repo.plan();
      expect(plan.pending.map((p) => p.date), ['2027-01-03', '2027-01-06', '2027-01-10']);
      expect(plan.nextPay, '2027-01-12');
      expect((await repo.cards()).single.daysToPayment, 2);
    });

    test('las categorías son las 15 y salen en el idioma que se ve', () async {
      for (final (language, food) in [('es', 'Alimentación'), ('en', 'Food'), ('pt', 'Alimentação')]) {
        final c = await open(scenario: 'planListo', initial: kDefaultRegion.copyLanguage(language));
        final names = await c.read(homeRepositoryProvider).categoryNames();
        expect(names, hasLength(15));
        expect(names['alimentacion'], food);
      }
    });
  });

  group('de la bienvenida al Inicio', () {
    test('cuenta nueva en USD: un solo saldo, sus pagos y ningún movimiento inventado', () async {
      final c = await open(scenario: 'nuevo');
      // El Inicio ya se había cargado sin respuestas: no puede quedarse con ese plan.
      expect((await home(c)).hero, isA<HeroUnknown>());

      await answer(
        c,
        mode: OnboardingMode.full,
        country: 'US',
        balance: '1250.50',
        payments: [('Rent', '500.25', '31'), ('Gym', '100.10', '15')],
      );
      final view = await home(c);
      final plan = planOf(view);
      final status = await c.read(welcomeStatusProvider(c.read(accountProvider)).future);

      expect(c.read(appRegionProvider).currency, 'USD');
      // Lo que escribió la persona no se escala.
      expect(status.money, 1250.5);
      expect(plan.money, 1250.5);
      expect(status.balanceSet, isTrue);
      expect(status.commitmentNames, ['Rent', 'Gym']);
      expect(plan.pending.map((p) => (p.name, p.amount, p.date)), [
        ('Gym', 100.1, '2026-11-15'),
        ('Rent', 500.25, '2026-11-30'),
      ]);
      expect(plan.pendingTotal, 600.35);
      expect(plan.free, 650.15);
      expect(plan.shortfall, 0);
      expect(plan.mode, 'runway');
      expect(plan.nextPay, isNull);

      expect(status.hasTransactions, isFalse);
      expect([status.income, status.expense], [0, 0]);
      expect([view.totals.value!.income, view.totals.value!.expense], [0, 0]);
      expect(view.empty, isTrue);
      expect(view.toConfirm, 0);
      expect(view.notice, isNull);
      expect(drafts.data, isEmpty);
    });

    test('cuenta nueva en COP: si no alcanza, «te faltan» por la resta exacta', () async {
      final c = await open(scenario: 'nuevo');
      await answer(
        c,
        mode: OnboardingMode.full,
        country: 'CO',
        balance: '300000',
        payments: [('Arriendo', '800000', '5')],
      );
      final view = await home(c);
      expect((view.hero as HeroPlan).tone, PlanTone.short);
      expect(planOf(view).money, 300000);
      expect(planOf(view).free, -500000);
      expect(planOf(view).shortfall, 500000);
      expect([view.totals.value!.income, view.totals.value!.expense], [0, 0]);
    });

    test('con movimientos: manda el saldo que dijo y los movimientos no cambian', () async {
      final c = await open(scenario: 'movimientos');
      expect(((await home(c)).hero as HeroMoney).money, 650000);
      await answer(
        c,
        mode: OnboardingMode.questions,
        balance: '1200000',
        payments: [('Internet', '65000', '10')],
      );
      final view = await home(c);
      expect(planOf(view).money, 1200000);
      expect(planOf(view).free, 1135000);
      expect([view.totals.value!.income, view.totals.value!.expense], [2500000, 1850000]);
      expect(view.footer, HomeFooter.none);
    });

    test('«Ahora no»: ni plan ni saldo', () async {
      final c = await open(scenario: 'nuevo');
      await c.read(onboardingRepositoryProvider).finishWelcome(const {});
      final view = await home(c);
      expect(view.hero, isA<HeroUnknown>().having((h) => h.reason, 'motivo', UnknownReason.noBalance));
      expect(view.footer, HomeFooter.setup);
    });

    test('el estado expone los nombres de los pagos guardados, no los del escenario', () async {
      final c = await open(scenario: 'planListo');
      final repo = c.read(onboardingRepositoryProvider);
      expect((await repo.status()).commitmentNames, isEmpty);
      await repo.finishWelcome(const {
        'commitments': [
          {'name': 'Arriendo', 'amount': 500000, 'dayOfMonth': 5},
          {'name': 'arriendo', 'amount': 1, 'dayOfMonth': 1},
        ],
      });
      expect((await repo.status()).commitmentNames, ['Arriendo']);
    });
  });

  group('persistencia', () {
    test('al salir vuelve la región guardada, no la del arranque', () async {
      final c = await open(scenario: 'planListo');
      await home(c);
      regions.saved = _us;
      await c.read(sessionControllerProvider.notifier).signOut();
      await pumpEventQueue();
      expect(c.read(appRegionProvider), _us);
    });

    test('al reabrir siguen la plata, los pagos, la región y el tutorial', () async {
      var c = await open(scenario: 'nuevo');
      await answer(
        c,
        mode: OnboardingMode.full,
        country: 'US',
        balance: '900',
        payments: [('Rent', '400', '5')],
      );
      await c.read(homeRepositoryProvider).finishTutorial();
      c.dispose();

      c = await open();
      final view = await home(c);
      expect(c.read(accountProvider)?.user.id, 'demo-nuevo');
      expect(planOf(view).money, 900);
      expect(planOf(view).free, 500);
      expect(c.read(appRegionProvider), _us);
      expect(view.tourEligible, isFalse);
      // La región de la demostración no se guarda en el dispositivo.
      expect(regions.writes, 0);
    });

    for (final expires in [false, true]) {
      test('al ${expires ? 'vencer la sesión' : 'salir'} vuelve la región del dispositivo', () async {
        regions.saved = _us;
        await store.update('demo-planListo', (state) => state.withRegion(_br));
        final c = await open(scenario: 'planListo', initial: _us);
        await home(c);
        expect(c.read(appRegionProvider), _br);

        if (expires) {
          await c.read(sessionHolderProvider).expire();
        } else {
          await c.read(sessionControllerProvider.notifier).signOut();
        }
        await pumpEventQueue();
        expect(c.read(appRegionProvider), _us);
        expect(regions.writes, 0);
      });
    }
  });

  group('fallas', () {
    final reads = <DemoHomeOperation, List<Future<Object?> Function(HomeRepository)>>{
      DemoHomeOperation.plan: [(r) => r.plan()],
      DemoHomeOperation.summary: [(r) => r.monthTotals('2026-11-28')],
      DemoHomeOperation.secondary: [
        (r) => r.budgets('2026-11'),
        (r) => r.cards(),
        (r) => r.toConfirm(),
        (r) => r.unread(),
        (r) => r.categoryNames(),
      ],
    };

    for (final op in DemoHomeOperation.values) {
      for (final failure in DemoFailure.values) {
        test('${op.name} falla una vez (${failure.name}): las que salen juntas y solo esa vez', () async {
          final c = await open(scenario: 'planListo');
          final repo = c.read(homeRepositoryProvider);
          c.read(demoControlsProvider.notifier).failNext(op, failure);

          final code = failure == DemoFailure.network ? ApiCodes.network : 'INTERNAL_ERROR';
          await Future.wait([
            for (final read in reads[op]!)
              expectLater(read(repo), throwsA(isA<ApiException>().having((e) => e.code, 'código', code))),
          ]);
          expect(c.read(demoControlsProvider).failures, isEmpty);
          for (final read in reads[op]!) {
            await read(repo);
          }
        });
      }
    }

    test('sin conexión: falla todo, el Inicio no inventa cifras y vuelve al encenderla', () async {
      final c = await open(scenario: 'planListo');
      final controls = c.read(demoControlsProvider.notifier)..setOffline(true);
      final repo = c.read(homeRepositoryProvider);
      for (final read in [
        for (final list in reads.values) ...list,
        (HomeRepository r) => r.finishTutorial(),
      ]) {
        await expectLater(read(repo), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'red', isTrue)));
      }
      expect((await store.read('demo-planListo')).tutorialDone, isFalse);

      var view = await home(c);
      expect(view.hero, isA<HeroUnknown>().having((h) => h.reason, 'motivo', UnknownReason.offline));
      expect(view.offline, isTrue);
      expect(view.totals.value, isNull);

      controls.setOffline(false);
      invalidateHome(c.invalidate);
      view = await home(c);
      expect(planOf(view).free, 74300);
    });
  });

  group('reiniciar', () {
    test('reset borra la cuenta, la conexión apagada, las fallas, la región y el tutorial visto', () async {
      final c = await open(scenario: 'planListo');
      final repo = c.read(onboardingRepositoryProvider) as DemoOnboardingRepository;
      await repo.saveRegion(country: 'BR', language: 'pt');
      await c.read(appRegionProvider.notifier).set(_br, persist: false);
      await c.read(homeRepositoryProvider).finishTutorial();
      await seen.write('demo-planListo');
      await seen.write('demo-nuevo');
      c.read(demoControlsProvider.notifier)
        ..setLatency(const Duration(milliseconds: 5))
        ..setOffline(true)
        ..failNext(DemoHomeOperation.plan, DemoFailure.server);

      await repo.reset();

      expect((await store.read('demo-planListo')).toJson(), const DemoState().toJson());
      final controls = c.read(demoControlsProvider);
      expect(controls.offline, isFalse);
      expect(controls.failures, isEmpty);
      expect(controls.latency, const Duration(milliseconds: 5));
      expect(c.read(appRegionProvider), kDefaultRegion);
      expect(seen.seen, {'demo-nuevo'}, reason: 'solo la marca de la cuenta reiniciada');
    });

    test('después de reiniciar el tutorial se abre solo', () async {
      await seen.write('demo-planListo');
      final c = await open(scenario: 'planListo');
      await home(c);
      c.listen(tourControllerProvider, (_, _) {});
      await c.read(tourControllerProvider.notifier).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);

      await (c.read(onboardingRepositoryProvider) as DemoOnboardingRepository).reset();
      invalidateHome(c.invalidate);
      await home(c);
      await c.read(tourControllerProvider.notifier).maybeStart();
      expect(c.read(tourControllerProvider), isTrue);
    });
  });

  group('sin red y sin DEMO_MODE', () {
    test('con una sesión demo el repositorio real del Inicio tampoco sale a la red', () async {
      final c = await open(scenario: 'planListo');
      final api = ApiHomeRepository(c.read(apiClientProvider));
      for (final call in <Future<Object?> Function()>[
        api.plan,
        () => api.monthTotals('2026-11-28'),
        () => api.budgets('2026-11'),
        api.cards,
        api.toConfirm,
        api.unread,
        api.categoryNames,
        api.finishTutorial,
      ]) {
        await expectLater(
          call(),
          throwsA(isA<ApiException>().having((e) => e.code, 'código', ApiCodes.demoNoBackend)),
        );
      }
    });

    test('con una sesión demo el Inicio, la bienvenida y salir usan solo la demostración', () async {
      final c = await open(scenario: 'teFaltan');
      expect(c.read(homeRepositoryProvider), isA<DemoHomeRepository>());
      expect(c.read(onboardingRepositoryProvider), isA<DemoOnboardingRepository>());
      await home(c);
      await c.read(sessionControllerProvider.notifier).signOut();
    });

    test('sin DEMO_MODE no se puede entrar a la demostración', () async {
      final c = await open(config: _noDemo);
      await expectLater(c.read(sessionControllerProvider.notifier).signInDemo('nuevo'), throwsStateError);
      expect(c.read(accountProvider), isNull);
      expect(await sessions.read(), isNull);
      expect(c.read(homeRepositoryProvider).isDemo, isFalse);
    });

    test('sin DEMO_MODE una sesión demo guardada se descarta al abrir', () async {
      final c = await open(scenario: 'planListo', config: _noDemo);
      expect(c.read(accountProvider), isNull);
      expect(await sessions.read(), isNull);
      expect(c.read(homeRepositoryProvider).isDemo, isFalse);
      expect(c.read(onboardingRepositoryProvider).isDemo, isFalse);
    });
  });
}
