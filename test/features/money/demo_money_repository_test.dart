// MODO DEMOSTRACIÓN de Mi plata: cifras fijas de cada escenario (calculadas a mano con la regla del
// servidor), coherencia con el plan del Inicio, escrituras bloqueadas en los escenarios fijos y
// guardadas en los recorridos. Todo corre con los proveedores reales y nada sale a la red.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/application/money_writer.dart';
import 'package:rinde_mobile/features/money/data/demo_money_repository.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/domain/commitment_rules.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';

import '../../support/fake_http.dart';

const _demo = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa', demoMode: true);
const _us = Region(country: 'US', currency: 'USD', language: 'en');
final _now = DateTime(2026, 11, 22, 10);

int _cents(num value) => (value * 100).round();

/// income.logic.js: `roundTo`.
num _roundTo(num value, num step) => (value / step).round() * step;

/// Lo que cada escenario fijo debe decir, en pesos. `pace` es el del plan fijo del Inicio.
typedef _Income = ({
  List<IncomeKind> kinds,
  num normal,
  num lean,
  bool estimated,
  bool variable,
  num? ownSalary,
  num cushion,
  num? pila,
  num pace,
});

const Map<DemoScenario, _Income> _expected = {
  // Proyectos: mediana 700.000 y mínimo 650.000. Sueldo propio = 650.000 × 0,9 = 585.000 → 600.000.
  // Colchón = (338.000 de pagos + 13.700 × 30) × 3 = 2.247.000 → 2.250.000. PILA sobre 1 SMMLV.
  DemoScenario.planListo: (
    kinds: [IncomeKind.proyectos],
    normal: 700000,
    lean: 650000,
    estimated: false,
    variable: true,
    ownSalary: 600000,
    cushion: 2250000,
    pila: 499008,
    pace: 13700,
  ),
  // Un solo mes: el flaco es el 80 % y va «estimado». 320.000 × 0,9 = 288.000 → 300.000.
  // Colchón = (273.000 + 24.800 × 30) × 3 = 3.051.000 → 3.050.000.
  DemoScenario.teFaltan: (
    kinds: [IncomeKind.proyectos],
    normal: 400000,
    lean: 320000,
    estimated: true,
    variable: true,
    ownSalary: 300000,
    cushion: 3050000,
    pila: 499008,
    pace: 24800,
  ),
  // Sueldo fijo: sin sueldo propio ni PILA. Colchón = (45.000 + 30.200 × 30) × 1 = 951.000 → 950.000.
  DemoScenario.negativo: (
    kinds: [IncomeKind.sueldo],
    normal: 600000,
    lean: 600000,
    estimated: false,
    variable: false,
    ownSalary: null,
    cushion: 950000,
    pila: null,
    pace: 30200,
  ),
  // Omitió la bienvenida: sin fuentes ni plan.
  DemoScenario.sinPlan: (
    kinds: [],
    normal: 0,
    lean: 0,
    estimated: false,
    variable: false,
    ownSalary: null,
    cushion: 0,
    pila: null,
    pace: 0,
  ),
};

final _sueldo = const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15]).toApi();
const _pila = {'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 10};
const _arriendo = {
  'name': 'Arriendo',
  'amount': 900000,
  'dayOfMonth': 5,
  'kind': 'fixed',
  'frequency': 'monthly',
  'month': null,
};

void main() {
  late MemoryDemoStateStore store;
  late MemorySessionStorage sessions;
  late FakeHttpAdapter network;

  setUp(() {
    store = MemoryDemoStateStore();
    sessions = MemorySessionStorage();
    network = FakeHttpAdapter((_) => jsonBody(500, {}));
  });

  // La demostración nunca sale a la red.
  tearDown(() => expect(network.requests, isEmpty));

  Future<ProviderContainer> open(String scenario, {Region region = kDefaultRegion, DateTime? now}) async {
    await sessions.write(Session.demo(scenario));
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(_demo),
        sessionStorageProvider.overrideWithValue(sessions),
        demoStateStoreProvider.overrideWithValue(store),
        demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
        initialRegionProvider.overrideWithValue(region),
        clockProvider.overrideWithValue(() => now ?? _now),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(config: _demo, session: ref.watch(sessionHolderProvider), adapter: network),
        ),
      ],
    );
    c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
    c.listen(sessionControllerProvider, (_, _) {});
    await c.read(sessionControllerProvider.future);
    return c;
  }

  group('escenarios fijos: las cifras cuadran con la regla del servidor y con el plan', () {
    for (final (region, scale) in [(kDefaultRegion, 1), (_us, 1000)]) {
      for (final MapEntry(key: scenario, value: want) in _expected.entries) {
        test('${scenario.name} en ${region.currency}', () async {
          await store.update('demo-${scenario.name}', (state) => state.withRegion(region));
          final c = await open(scenario.name, region: region);
          final repo = c.read(moneyRepositoryProvider);
          expect(repo, isA<DemoMoneyRepository>());
          final income = await repo.income();
          final plan = await c.read(homeRepositoryProvider).plan();
          int scaled(num pesos) => (pesos * 100 / scale).round();

          expect(income.sources.map((s) => s.kind), want.kinds);
          expect(_cents(income.normal!), scaled(want.normal));
          expect(_cents(income.lean!), scaled(want.lean));
          expect(income.basis, want.kinds.isEmpty ? 'none' : 'declared');
          expect(income.estimated, want.estimated);
          final (salary, pila) = (want.ownSalary, want.pila);
          expect(
            income.ownSalary == null ? null : _cents(income.ownSalary!),
            salary == null ? null : scaled(salary),
          );
          expect(_cents(income.cushion!.suggestedGoal!), scaled(want.cushion));
          expect(
            income.socialSecurity == null ? null : _cents(income.socialSecurity!.total),
            pila == null ? null : scaled(pila),
          );
          expect(income.workDay, isNull);

          // La regla, en pesos: sueldo propio, colchón (con los pagos y el ritmo del plan fijo) y PILA.
          if (salary != null) expect(_roundTo(want.lean * 0.9, 50000), salary);
          final pending = plan.ready ? plan.pendingTotal * scale : 0;
          expect(
            _roundTo((pending + want.pace * 30) * (want.variable ? 3 : 1), 10000),
            closeTo(want.cushion, 0.5),
          );
          if (pila != null) {
            const smmlv = 1750905;
            final ibc = want.normal * 0.4 < smmlv ? smmlv : want.normal * 0.4;
            expect((ibc * 0.125).round() + (ibc * 0.16).round(), pila);
          }

          // Los pagos del perfil son los mismos que faltan en el plan del Inicio.
          final profile = await repo.profile();
          expect(profile.commitments.map((p) => (p.id, p.name, _cents(p.amount))), [
            for (final p in plan.pending) (p.id, p.name, _cents(p.amount)),
          ]);
          expect(profile.commitments.map((p) => p.dayOfMonth), [
            for (final p in plan.pending) int.parse(p.date.substring(8)),
          ]);
          // El mismo GET /money-profile que lee la bienvenida.
          final status = await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
          expect((profile.money, profile.welcomeDone, profile.incomeType), (status.money, true, null));
          expect(profile.version, isNull);
        });
      }
    }

    test('guardar fuentes o la PILA: «Modo demostración…» y nada cambia', () async {
      for (final scenario in _expected.keys) {
        final c = await open(scenario.name);
        final writer = c.read(moneyWriterProvider);
        final demo = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend));
        await expectLater(writer.saveSources([_sueldo]), demo, reason: scenario.name);
        await expectLater(writer.createCommitment(_pila), demo, reason: scenario.name);
        final state = await store.read('demo-${scenario.name}');
        expect(state.sources, isEmpty);
        expect(state.commitments, isEmpty);
        expect(state.incomeType, isNull);
        expect(
          (await c.read(moneyRepositoryProvider).income()).sources.map((s) => s.kind),
          _expected[scenario]!.kinds,
        );
      }
    });
  });

  group('recorrido «nuevo»: lo guardado persiste y el Inicio lo refleja', () {
    test('el mes normal y el flaco salen con la regla del servidor (declaredMonth)', () async {
      await store.write('demo-nuevo', const DemoState(welcomeDone: true, balance: 500000));
      final c = await open('nuevo');
      final repo = c.read(moneyRepositoryProvider);
      Map<String, dynamic> projects(List<String> months) =>
          IncomeSourceForm(kind: IncomeKind.proyectos, lastMonths: months).toApi();

      // Las mismas cifras que el escenario fijo «Plan listo» (calculadas a mano con income.logic.js).
      await repo.saveSources([
        projects(['700000', '650000', '800000']),
      ]);
      var income = await repo.income();
      expect(
        (income.basis, income.normal, income.lean, income.ownSalary),
        ('declared', 700000, 650000, 600000),
      );

      // Un solo mes: el flaco es el 80 % y queda «estimado», como «Te faltan».
      await repo.saveSources([
        projects(['400000', '', '']),
      ]);
      income = await repo.income();
      expect(
        (income.normal, income.lean, income.estimated, income.ownSalary),
        (400000, 320000, true, 300000),
      );

      // Con sueldo no se sugiere otro sueldo; sin montos no hay mes normal.
      await repo.saveSources([
        _sueldo,
        projects(['100000', '', '']),
      ]);
      income = await repo.income();
      expect((income.normal, income.lean, income.ownSalary), (2600000, 2580000, null));
      await repo.saveSources([
        projects(['', '', '']),
      ]);
      expect((await repo.income()).basis, 'none');
    });

    test('las fuentes llegan a Mi plata (con su mes normal) y el plan queda listo', () async {
      // Ya dijo su saldo en la bienvenida, pero no cómo le entra la plata.
      await store.write('demo-nuevo', const DemoState(welcomeDone: true, balance: 500000));
      final c = await open('nuevo');
      final account = c.read(accountProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      c.listen(incomeOverviewProvider(account), (_, _) {});
      expect((await c.read(homePlanProvider(account).future)).ready, isFalse);

      await c.read(moneyWriterProvider).saveSources([_sueldo]);
      final income = await c.read(incomeOverviewProvider(account).future);
      expect(income.sources.single.kind, IncomeKind.sueldo);
      expect((income.sources.single.amount, income.basis, income.normal), (2500000, 'declared', 2500000));
      final plan = await c.read(homePlanProvider(account).future);
      expect((plan.ready, plan.money), (true, 500000));
      expect((await c.read(moneyRepositoryProvider).profile()).incomeType, 'fecha_fija');

      // Sigue ahí al reabrir la app.
      final again = await open('nuevo');
      expect((await again.read(moneyRepositoryProvider).income()).sources, hasLength(1));
    });

    test('«Recordármelo cada mes»: queda en los pagos y en el plan; repetirlo da 409', () async {
      await store.write(
        'demo-nuevo',
        const DemoState(welcomeDone: true, balance: 500000, incomeType: 'sin_fecha'),
      );
      final c = await open('nuevo');
      final writer = c.read(moneyWriterProvider);
      await writer.createCommitment(_pila);
      final profile = await c.read(moneyRepositoryProvider).profile();
      expect(profile.commitments.single.name, 'Seguridad social (PILA)');
      expect(profile.commitments.single.dayOfMonth, 10);
      final plan = await c.read(homeRepositoryProvider).plan();
      expect(plan.pending.single.name, 'Seguridad social (PILA)');
      expect(plan.free, 500000 - 499008);

      await expectLater(
        writer.createCommitment({..._pila, 'name': 'seguridad social (pila)'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'COMMITMENT_EXISTS')
              .having((e) => e.serverMessage, 'mensaje', 'Ya tienes un compromiso con ese nombre'),
        ),
      );
      expect((await store.read('demo-nuevo')).commitments, hasLength(1));
    });

    test('las fallas del panel también llegan a Mi plata', () async {
      final c = await open('nuevo');
      c.read(demoControlsProvider.notifier).failNext(DemoMoneyOperation.income, DemoFailure.network);
      final repo = c.read(moneyRepositoryProvider);
      await expectLater(
        repo.income(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'red', isTrue)),
      );
      expect((await repo.income()).sources, isEmpty);
    });
  });

  group('Corregir saldo en la demostración (bloque 4B)', () {
    test('escenarios fijos: «Modo demostración…», el saldo no cambia y no hay ajustes', () async {
      for (final scenario in _expected.keys) {
        final c = await open(scenario.name);
        final repo = c.read(moneyRepositoryProvider);
        final opened = await repo.profile();
        await expectLater(
          c.read(moneyWriterProvider).saveBalance(opened, 1),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
          reason: scenario.name,
        );
        expect((await repo.profile()).money, opened.money, reason: scenario.name);
        expect(await repo.adjustments(from: '2026-11-01', to: '2026-11-30'), isEmpty);
      }
    });

    test('recorrido: el saldo queda, deja su ajuste en Movimientos y el plan del Inicio cambia', () async {
      // Con movimientos (2.500.000 − 1.850.000 = 650.000) y ya con fecha de pago.
      await store.write(
        'demo-movimientos',
        const DemoState(welcomeDone: true, incomeType: 'fecha_fija', payDays: [30]),
      );
      final c = await open('movimientos');
      final account = c.read(accountProvider);
      final repo = c.read(moneyRepositoryProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      expect((await c.read(homePlanProvider(account).future)).money, 650000);
      final opened = await repo.profile();
      expect((opened.money, opened.balance, opened.version), (650000, null, null));

      await c.read(moneyWriterProvider).saveBalance(opened, 500000.5);
      final profile = await repo.profile();
      expect((profile.money, profile.balance), (500000.5, 500000.5));
      expect(profile.balanceAt, _now.toUtc().toIso8601String());
      expect((await c.read(homePlanProvider(account).future)).money, 500000.5);
      final adjustments = await repo.adjustments(from: '2026-11-01', to: '2026-11-30');
      expect([for (final a in adjustments) (a.before, a.after, a.date)], [(650000, 500000.5, '2026-11-22')]);
      expect(await repo.adjustments(from: '2026-12-01', to: '2026-12-31'), isEmpty);

      // El mismo saldo otra vez: sin ajuste nuevo (como el servidor, en pesos enteros).
      await c.read(moneyWriterProvider).saveBalance(profile, 500000.5);
      expect(await repo.adjustments(from: '2026-11-01', to: '2026-11-30'), hasLength(1));
    });

    test('las fallas del panel llegan a los ajustes', () async {
      final c = await open('nuevo');
      c.read(demoControlsProvider.notifier).failNext(DemoMoneyOperation.adjustments, DemoFailure.server);
      await expectLater(
        c.read(moneyRepositoryProvider).adjustments(from: '2026-11-01', to: '2026-11-30'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
    });
  });

  group('pagos del mes (bloque 4C)', () {
    // «Falta por pagar» de Pagos del mes = `pendingTotal` del plan fijo del Inicio.
    for (final (scenario, region, total) in [
      ('planListo', kDefaultRegion, 338000),
      ('planListo', _us, 338),
      ('teFaltan', kDefaultRegion, 273000),
      ('negativo', kDefaultRegion, 45000),
    ]) {
      test('$scenario en ${region.currency}: «Falta por pagar» = pendingTotal = $total', () async {
        await store.update('demo-$scenario', (state) => state.withRegion(region));
        final c = await open(scenario, region: region);
        final payments = await c.read(moneyRepositoryProvider).calendar('2026-11');
        final plan = await c.read(homeRepositoryProvider).plan();
        final totals = paymentTotals(payments);
        expect(_cents(totals.pending), _cents(total));
        expect(_cents(totals.pending), _cents(plan.pendingTotal));
        expect(totals.paid, 0);
        // Las mismas ocurrencias (id, fecha y monto) que «Lo próximo» y el aviso de Mi plata.
        expect(payments.map((p) => (p.id, p.date, _cents(p.amount))), [
          for (final p in plan.pending) (p.id, p.date, _cents(p.amount)),
        ]);
        expect(payments.every((p) => p.status == 'pendiente'), isTrue);
      });
    }

    // A fin de mes, lo de «hoy + N días» caería en diciembre; el calendario del mes no trae otro mes.
    for (final scenario in ['planListo', 'teFaltan', 'negativo']) {
      test(
        '$scenario el 28 de noviembre: todo dentro del mes y lo mismo en el perfil, el plan y el calendario',
        () async {
          final c = await open(scenario, now: DateTime(2026, 11, 28, 10));
          final payments = await c.read(moneyRepositoryProvider).calendar('2026-11');
          final plan = await c.read(homeRepositoryProvider).plan();
          final profile = await c.read(moneyRepositoryProvider).profile();
          expect(payments, isNotEmpty);
          expect(
            payments.every((p) => p.date.startsWith('2026-11-')),
            isTrue,
            reason: '${payments.map((p) => p.date)}',
          );
          expect(plan.pending.map((p) => p.date), [for (final p in payments) p.date]);
          // «Pagos fijos del mes» pinta el día del perfil: el mismo de la fecha del calendario.
          expect(profile.commitments.map((c) => c.dayOfMonth), [
            for (final p in payments) int.parse(p.date.substring(8)),
          ]);
          expect(_cents(paymentTotals(payments).pending), _cents(plan.pendingTotal));
        },
      );
    }

    test('escenarios fijos: crear, editar y borrar pagos dan «Modo demostración…» y nada cambia', () async {
      for (final scenario in _expected.keys) {
        final c = await open(scenario.name);
        final writer = c.read(moneyWriterProvider);
        final demo = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend));
        final profile = await c.read(moneyRepositoryProvider).profile();
        await expectLater(writer.createCommitment(_arriendo), demo, reason: scenario.name);
        if (profile.commitments.isNotEmpty) {
          final first = profile.commitments.first;
          await expectLater(writer.updateCommitment(first, _arriendo), demo, reason: scenario.name);
          await expectLater(writer.deleteCommitment(first.id), demo, reason: scenario.name);
        }
        expect((await store.read('demo-${scenario.name}')).commitments, isEmpty);
      }
    });

    test('«Ya lo pagué» en la demostración: «Modo demostración…» en todos los escenarios', () async {
      for (final scenario in [..._expected.keys.map((s) => s.name), 'nuevo', 'movimientos']) {
        final c = await open(scenario);
        await expectLater(
          c.read(moneyWriterProvider).markPaid(key: 'demo-celular-x', name: 'Plan celular', amount: 45000),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
          reason: scenario,
        );
      }
    });

    test('recorrido: crear, renombrar y borrar persisten con su id fijo y el Inicio cambia', () async {
      await store.write(
        'demo-nuevo',
        const DemoState(welcomeDone: true, balance: 1000000, incomeType: 'sin_fecha'),
      );
      final c = await open('nuevo');
      final account = c.read(accountProvider);
      final writer = c.read(moneyWriterProvider);
      final repo = c.read(moneyRepositoryProvider);
      for (final p in [moneyProfileProvider, paymentCalendarProvider, homePlanProvider]) {
        c.listen(p(account), (_, _) {});
      }

      await writer.createCommitment(_arriendo);
      await writer.createCommitment({..._arriendo, 'name': 'Seguro', 'frequency': 'yearly', 'month': 3});
      var profile = await c.read(moneyProfileProvider(account).future);
      // Como el servidor: la suscripción anual cuenta su doceava parte (1.200.000 / 12).
      await writer.createCommitment({
        ..._arriendo,
        'name': 'Antivirus',
        'amount': 1200000,
        'kind': 'subscription',
        'frequency': 'yearly',
        'month': 1,
      });
      expect(
        ((await repo.profile()).subscriptionCount, (await repo.profile()).subscriptionsMonthly),
        (1, 100000),
      );
      await writer.deleteCommitment('demo-c3');
      profile = await c.read(moneyProfileProvider(account).future);
      expect(profile.commitments.map((p) => (p.id, p.name, p.frequency, p.month)), [
        ('demo-c1', 'Arriendo', 'monthly', null),
        ('demo-c2', 'Seguro', 'yearly', 3),
      ]);
      // El anual de marzo no toca noviembre: ni en el calendario ni en el plan.
      var plan = await c.read(homePlanProvider(account).future);
      final payments = await c.read(paymentCalendarProvider(account).future);
      expect(payments.map((p) => (p.id, p.date, p.status)), [('demo-c1', '2026-11-05', 'atrasado')]);
      expect(plan.pending.map((p) => (p.id, p.name)), [('demo-c1', 'Arriendo')]);
      expect((plan.pendingTotal, plan.free), (900000, 100000));
      expect(_cents(paymentTotals(payments).pending), _cents(plan.pendingTotal));

      await writer.updateCommitment(profile.commitments.first, {
        ..._arriendo,
        'name': 'Arriendo casa',
        'amount': 950000,
      });
      profile = await c.read(moneyProfileProvider(account).future);
      expect(profile.commitments.first.id, 'demo-c1');
      plan = await c.read(homePlanProvider(account).future);
      expect((plan.pending.single.name, plan.pendingTotal), ('Arriendo casa', 950000));

      // Un nombre que ya tiene otro pago: 409, como el servidor.
      await expectLater(
        writer.updateCommitment(profile.commitments.first, {..._arriendo, 'name': 'seguro'}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'COMMITMENT_EXISTS')),
      );

      await writer.deleteCommitment('demo-c1');
      plan = await c.read(homePlanProvider(account).future);
      expect(plan.pending, isEmpty);
      expect((await repo.profile()).commitments.map((p) => p.id), ['demo-c2']);
      // Borrar otra vez: el 404 cuenta como borrado.
      await writer.deleteCommitment('demo-c1');

      // El siguiente id sale después del mayor que quede.
      await writer.createCommitment(_arriendo);
      expect((await repo.profile()).commitments.map((p) => p.id), ['demo-c2', 'demo-c3']);
    });

    test('los pagos de la bienvenida reciben su id al leerlos y Mi plata y el plan dicen el mismo', () async {
      await store.write(
        'demo-nuevo',
        const DemoState(
          welcomeDone: true,
          balance: 1000000,
          incomeType: 'sin_fecha',
          commitments: [
            {'name': 'Internet', 'amount': 65000, 'dayOfMonth': 25},
          ],
        ),
      );
      final c = await open('nuevo');
      final profile = await c.read(moneyRepositoryProvider).profile();
      final plan = await c.read(homeRepositoryProvider).plan();
      expect(profile.commitments.single.id, 'demo-c1');
      expect(plan.pending.single.id, 'demo-c1');
      // Lo guardado no cambia hasta que se escriba.
      expect((await store.read('demo-nuevo')).commitments.single.containsKey('id'), isFalse);
    });

    test(
      'recorrido: «Tu sueldo» guarda el tipo y los días, sin tocar el saldo, y el plan queda listo',
      () async {
        await store.write('demo-nuevo', const DemoState(welcomeDone: true, balance: 500000));
        final c = await open('nuevo');
        final account = c.read(accountProvider);
        c.listen(homePlanProvider(account), (_, _) {});
        c.listen(moneyProfileProvider(account), (_, _) {});
        expect((await c.read(homePlanProvider(account).future)).ready, isFalse);
        final opened = await c.read(moneyProfileProvider(account).future);
        await c.read(moneyWriterProvider).saveIncomeType(opened, 'fecha_fija', const [15, 30]);
        final profile = await c.read(moneyProfileProvider(account).future);
        expect(
          (profile.incomeType, profile.payDays.join(','), profile.balance),
          ('fecha_fija', '15,30', 500000),
        );
        expect((await c.read(homePlanProvider(account).future)).ready, isTrue);
        expect((await store.read('demo-nuevo')).adjustments, isEmpty);
      },
    );

    test('la demo es por usuario: lo de «nuevo» no aparece en «movimientos»', () async {
      await store.write(
        'demo-nuevo',
        const DemoState(welcomeDone: true, balance: 1000000, incomeType: 'sin_fecha'),
      );
      await (await open('nuevo')).read(moneyWriterProvider).createCommitment(_arriendo);
      final other = await open('movimientos');
      expect((await other.read(moneyRepositoryProvider).profile()).commitments, isEmpty);
      expect(await other.read(moneyRepositoryProvider).calendar('2026-11'), isEmpty);
    });
  });
}
