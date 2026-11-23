// Continuidad bienvenida → Mi plata → Inicio (bloque 4D):
// - la bienvenida a medias avisa de entrada en Mi plata, Pagos del mes y Corregir saldo, con «Terminar»
//   que la retoma; al terminarla el aviso se va;
// - dos cuentas no se mezclan (pagos, avisos cerrados ni bienvenida pendiente);
// - en la demostración, de la bienvenida al Inicio pasando por Mi plata, cada pago sale una sola vez.
import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart';
import 'package:rinde_mobile/app/router.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_feedback.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_text_field.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/presentation/fix_balance_screen.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/money/presentation/payments_screen.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';
import 'package:rinde_mobile/features/onboarding/presentation/income/pay_days_field.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';
import '../../support/fake_movements_repository.dart';

const _pending = 'Primero terminemos de guardar tu bienvenida.';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co'),
  accessToken: 'b',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _ana));

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

/// El borrador que deja una bienvenida a medias: la etapa 1 salió y faltan las fuentes.
Map<String, dynamic> get _halfDone =>
    const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson();

MoneyProfile _profile(String payment) => MoneyProfile(
  welcomeDone: true,
  incomeType: 'fecha_fija',
  payDays: const [30],
  balance: 500000,
  balanceAt: '2026-11-01T05:00:00.000Z',
  money: 500000,
  commitments: [Commitment(id: 'c-$payment', name: payment, amount: 100000, dayOfMonth: 28)],
);

FakeMoneyRepository _repoOf(String payment) => FakeMoneyRepository()
  ..onProfile = (() async => _profile(payment))
  ..onCalendar = (_) async => [
    CalendarPayment(id: 'c-$payment', name: payment, amount: 100000, date: '2026-11-28', status: 'pendiente'),
  ];

Finder get _banner => find.widgetWithText(RindeBanner, _pending);

void main() {
  group('bienvenida a medias en este teléfono', () {
    late MemoryDraftStore drafts;
    late FakeMoneyRepository ana;
    late FakeMoneyRepository beto;
    late MemoryJsonListStore dismissed;

    setUp(() async {
      drafts = MemoryDraftStore();
      await drafts.write('a', _halfDone);
      ana = _repoOf('Arriendo');
      beto = _repoOf('Gimnasio');
      dismissed = MemoryJsonListStore();
    });

    Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester, String route) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: Routes.app,
        routes: [
          GoRoute(
            path: Routes.app,
            builder: (_, _) => const Scaffold(body: Text('INICIO')),
          ),
          GoRoute(path: Routes.myMoney, builder: (_, _) => const MyMoneyScreen()),
          GoRoute(path: Routes.payments, builder: (_, _) => const MoneyPaymentsScreen()),
          GoRoute(path: Routes.fixBalance, builder: (_, _) => const FixBalanceScreen()),
          GoRoute(
            path: Routes.onboardingQuestions,
            builder: (_, _) => const Scaffold(body: Text('RETOMAR')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sessionControllerProvider.overrideWith(_Sessions.new),
            moneyRepositoryProvider.overrideWith((ref) => ref.watch(accountProvider) == _beto ? beto : ana),
            homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
            movementsRepositoryProvider.overrideWithValue(FakeMovementsRepository()),
            pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
            dismissedStoreProvider.overrideWithValue(dismissed),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
            draftStoreProvider.overrideWithValue(drafts),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: RindeTheme.light,
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(route));
      await tester.pumpAndSettle();
      return (ProviderScope.containerOf(tester.element(find.text('INICIO', skipOffstage: false))), router);
    }

    for (final (route, screen) in [
      (Routes.myMoney, MyMoneyScreen),
      (Routes.payments, MoneyPaymentsScreen),
      (Routes.fixBalance, FixBalanceScreen),
    ]) {
      testWidgets('$screen: el aviso sale de entrada y «Terminar» lleva a retomarla', (tester) async {
        final (_, router) = await pump(tester, route);
        expect(_banner, findsOneWidget);
        expect(tester.widget<RindeBanner>(_banner).tone, RindeBannerTone.info);
        expect(find.descendant(of: _banner, matching: find.text('Terminar')), findsOneWidget);

        await tester.tap(find.text('Terminar'));
        await tester.pumpAndSettle();
        // La misma ruta con que la entrada retoma la bienvenida (entry_screen.dart).
        expect(router.routerDelegate.currentConfiguration.uri.path, Routes.onboardingQuestions);
        expect(find.text('RETOMAR'), findsOneWidget);
      });
    }

    testWidgets('al terminar la bienvenida el aviso se va; sin bienvenida pendiente no sale', (tester) async {
      final (c, _) = await pump(tester, Routes.payments);
      expect(_banner, findsOneWidget);
      // Lo que hace la bienvenida al terminar: borra el borrador e invalida el proveedor.
      await drafts.clear('a');
      c.invalidate(pendingSourcesProvider);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(find.text('Terminar'), findsNothing);
      expect(find.text('Arriendo'), findsOneWidget);
    });

    testWidgets(
      'Mi plata con dos cuentas: ni los pagos, ni los avisos cerrados, ni la bienvenida de A en B',
      (tester) async {
        final (c, _) = await pump(tester, Routes.myMoney);
        final sessions = c.read(sessionControllerProvider.notifier) as _Sessions;
        expect(_banner, findsOneWidget);
        expect(find.textContaining('Arriendo'), findsOneWidget);
        // A cierra el aviso de la PILA (el plan de ejemplo trae PILA, Plan celular y Visa).
        await tester.tap(find.byTooltip('Cerrar el aviso de PILA'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Cerrar el aviso de PILA'), findsNothing);

        sessions.enter(_beto);
        await tester.pumpAndSettle();
        expect(_banner, findsNothing);
        expect(find.textContaining('Arriendo'), findsNothing);
        expect(find.textContaining('Gimnasio'), findsOneWidget);
        // B no cerró nada: ve el aviso de la PILA.
        expect(find.byTooltip('Cerrar el aviso de PILA'), findsOneWidget);
        expect(await dismissed.read('b'), isEmpty);

        // A vuelve: su bienvenida sigue pendiente y su aviso sigue cerrado.
        sessions.enter(_ana);
        await tester.pumpAndSettle();
        expect(_banner, findsOneWidget);
        expect(find.byTooltip('Cerrar el aviso de PILA'), findsNothing);
        expect(find.textContaining('Arriendo'), findsOneWidget);
      },
    );

    testWidgets('Pagos del mes con dos cuentas: al cambiar no queda nada de A', (tester) async {
      final (c, _) = await pump(tester, Routes.payments);
      expect(find.text('Arriendo'), findsOneWidget);
      expect(_banner, findsOneWidget);
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      await tester.pumpAndSettle();
      expect(find.text('Arriendo'), findsNothing);
      expect(find.text('Gimnasio'), findsOneWidget);
      expect(_banner, findsNothing);
      expect((ana.count('calendar'), beto.count('calendar')), (1, 1));
    });
  });

  group('demostración en la app real', () {
    late MemoryDemoStateStore store;
    late MemoryDraftStore drafts;
    late FakeHttpAdapter network;

    setUp(() {
      store = MemoryDemoStateStore();
      drafts = MemoryDraftStore();
      network = FakeHttpAdapter((_) => jsonBody(500, {}));
    });

    tearDown(() => expect(network.requests, isEmpty, reason: 'la demostración no sale a la red'));

    Future<void> settle(WidgetTester tester) async {
      // Sin pumpAndSettle: Rin y los indicadores de carga no dejan de animarse.
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<ProviderContainer> openApp(WidgetTester tester, String scenario) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const config = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa', demoMode: true);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            appConfigProvider.overrideWithValue(config),
            sessionStorageProvider.overrideWithValue(MemorySessionStorage(Session.demo(scenario))),
            demoStateStoreProvider.overrideWithValue(store),
            demoControlsProvider.overrideWith(_FastControls.new),
            draftStoreProvider.overrideWithValue(drafts),
            // El tutorial ya se vio: no tapa nada.
            tourSeenStoreProvider.overrideWithValue(MemoryTourSeenStore()..seen.add('demo-$scenario')),
            demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
            pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
            dismissedStoreProvider.overrideWithValue(MemoryJsonListStore()),
            regionStoreProvider.overrideWithValue(_Regions()),
            systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
            apiClientProvider.overrideWith(
              (ref) => ApiClient(config: config, session: ref.watch(sessionHolderProvider), adapter: network),
            ),
          ],
          child: const MediaQuery(data: MediaQueryData(disableAnimations: true), child: RindeApp()),
        ),
      );
      await settle(tester);
      return ProviderScope.containerOf(tester.element(find.byType(RindeApp)));
    }

    // La pantalla de arriba, también si se abrió con push.
    String path(ProviderContainer c) =>
        c.read(routerProvider).routerDelegate.currentConfiguration.last.matchedLocation;

    Future<void> tap(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await settle(tester);
    }

    /// El campo de la hoja del pago con esa etiqueta.
    Finder field(String label) => find.descendant(
      of: find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is RindeTextField || w is RindeMoneyField),
          )
          .first,
      matching: find.byType(EditableText),
    );

    Future<void> type(WidgetTester tester, String label, String text) async {
      await tester.ensureVisible(field(label));
      await tester.enterText(field(label), text);
      await tester.pump();
    }

    testWidgets('«nuevo»: bienvenida → Inicio → Mi plata → editar y agregar pagos → Atrás: una sola vez', (
      tester,
    ) async {
      final c = await openApp(tester, 'nuevo');
      expect(path(c), Routes.onboarding);

      // La bienvenida con su controlador real: sueldo, saldo y un pago.
      final welcome = c.read(onboardingControllerProvider(OnboardingMode.full).notifier);
      welcome.toggleSource(IncomeKind.sueldo);
      welcome.updateSource(
        c
            .read(onboardingControllerProvider(OnboardingMode.full))
            .draft
            .sources[IncomeKind.sueldo]!
            .copyWith(payDays: [30]),
      );
      welcome.setBalance('1500000');
      welcome.updateItem(welcome.addCustom()!, name: 'Internet', amount: '65000', dayOfMonth: '25');
      // Sin esperarla sola: en la prueba el tiempo solo corre al bombear.
      final finishing = welcome.finish();
      await settle(tester);
      await finishing;
      await tap(tester, find.text('Ir al inicio'));
      expect(path(c), Routes.app);
      expect(c.read(homeViewProvider).hero, isA<HeroPlan>());
      expect(find.text('Lo próximo'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);

      // Mi plata desde la tarjeta grande: el pago de la bienvenida, una vez.
      await tap(tester, find.text('¿De dónde sale?'));
      expect(path(c), Routes.myMoney);
      expect(find.text('25 nov · Internet'), findsOneWidget);
      expect(_banner, findsNothing);

      // La promesa de la bienvenida: se edita en Pagos del mes, con el mismo id.
      await tap(tester, find.text('Editar pagos fijos'));
      expect(path(c), Routes.payments);
      expect(find.text('Internet'), findsOneWidget);
      await tap(tester, find.byTooltip('Editar Internet'));
      await type(tester, 'Monto', '70000');
      await tap(tester, find.text('Guardar pago'));
      expect(find.text('Guardar pago'), findsNothing, reason: 'la hoja se cerró');
      expect(find.text('Internet'), findsOneWidget);

      // Y uno nuevo.
      await tap(tester, find.text('Agregar pago'));
      await type(tester, 'Nombre', 'Arriendo');
      await type(tester, 'Monto', '800000');
      await type(tester, 'Día', '28');
      await tap(tester, find.text('Guardar pago'));
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('Arriendo'), findsOneWidget);

      final saved = (await store.read('demo-nuevo')).commitmentsWithIds;
      expect(saved.map((p) => (p['id'], p['name'], p['amount'])), [
        ('demo-c1', 'Internet', 70000),
        ('demo-c2', 'Arriendo', 800000),
      ]);

      // Atrás dos veces: Mi plata y el Inicio, ya con los dos pagos y una sola vez cada uno.
      await tap(tester, find.byTooltip('Volver'));
      expect(path(c), Routes.myMoney);
      expect(find.text('25 nov · Internet'), findsOneWidget);
      expect(find.text('28 nov · Arriendo'), findsOneWidget);
      await tap(tester, find.byTooltip('Volver'));
      expect(path(c), Routes.app);
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('Arriendo'), findsOneWidget);
      final plan = (c.read(homeViewProvider).hero as HeroPlan).plan;
      expect(plan.pending.map((p) => (p.id, p.amount)), [('demo-c1', 70000), ('demo-c2', 800000)]);
      expect(c.read(homeViewProvider).nextPayments.map((p) => p.id), ['demo-c1', 'demo-c2']);

      // Y se elimina el de la bienvenida desde «Ver pagos»: al volver, el Inicio ya no lo tiene.
      await tap(tester, find.text('Ver pagos'));
      expect(path(c), Routes.payments);
      await tap(tester, find.byTooltip('Editar Internet'));
      await tap(tester, find.text('Eliminar pago'));
      await tap(tester, find.text('Eliminar pago').last);
      expect(find.text('Internet'), findsNothing);
      await tap(tester, find.byTooltip('Volver'));
      expect(path(c), Routes.app);
      expect(find.text('Internet'), findsNothing);
      expect(find.text('Arriendo'), findsOneWidget);
      expect(c.read(homeViewProvider).nextPayments.map((p) => p.id), ['demo-c2']);
      expect((await store.read('demo-nuevo')).commitmentsWithIds.map((p) => p['id']), ['demo-c2']);
    });

    testWidgets('«Sin plan»: Inicio → Mi plata → «Configurar» el sueldo → Atrás: «Libre para gastar»', (
      tester,
    ) async {
      final c = await openApp(tester, 'sinPlan');
      expect(path(c), Routes.app);
      expect(c.read(homeViewProvider).hero, isA<HeroMoney>());
      await tap(tester, find.text('¿Cuánta plata tienes hoy?'));
      expect(path(c), Routes.myMoney);

      // La hoja de fuentes de Mi plata, como en la web: sueldo de 700.000 el 30.
      await tap(tester, find.text('Configurar'));
      await tap(tester, find.text('Sueldo fijo'));
      final amount = find.descendant(
        of: find.byKey(const ValueKey('income-sueldo-amount')),
        matching: find.byType(EditableText),
      );
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '700000');
      await tester.pump();
      await tap(tester, find.descendant(of: find.byType(PayDaysField), matching: find.text('30')));
      await tap(tester, find.text('Guardar'));
      expect((await store.read('demo-sinPlan')).incomeType, 'fecha_fija');

      // Atrás cierra la hoja y luego Mi plata.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(path(c), Routes.myMoney);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(path(c), Routes.app);
      // La plata sale de los movimientos (700.000 − 287.700) y sin pagos todo queda libre.
      final hero = c.read(homeViewProvider).hero as HeroPlan;
      expect((hero.tone, hero.plan.free), (PlanTone.free, 412300));
      expect(find.text('¿Cuánta plata tienes hoy?'), findsNothing);
    });

    testWidgets('bienvenida a medias: el aviso de Mi plata la retoma y, al terminarla, se va', (
      tester,
    ) async {
      // La etapa 1 (el saldo) llegó al servidor y faltan las fuentes.
      await store.update('demo-nuevo', (state) => state.withWelcome(const {'balance': 100000}));
      await drafts.write('demo-nuevo', {
        'v': 1,
        'position': OnboardingSteps.payments,
        'country': 'CO',
        'language': 'es',
        'balance': '100000',
        'sources': [
          {
            'kind': 'sueldo',
            'payDays': [15],
          },
        ],
        'sentWelcome': '{"balance":100000}',
      });
      final c = await openApp(tester, 'nuevo');
      expect(path(c), Routes.onboardingQuestions, reason: 'la entrada la retoma');

      // Sale sin terminar (Atrás hasta el Inicio): en esta sesión la entrada ya no la devuelve.
      for (var i = 0; i < 4 && path(c) != Routes.app; i++) {
        await tester.binding.handlePopRoute();
        await settle(tester);
      }
      expect(path(c), Routes.app);
      await tap(tester, find.text('¿Cuánta plata tienes hoy?'));
      expect(path(c), Routes.myMoney);
      expect(_banner, findsOneWidget);

      await tap(tester, find.text('Terminar'));
      expect(path(c), Routes.onboardingQuestions);
      final finishing = c.read(onboardingControllerProvider(OnboardingMode.questions).notifier).finish();
      await settle(tester);
      await finishing;
      await tap(tester, find.text('Ir al inicio'));
      expect(path(c), Routes.app);
      expect(await drafts.read('demo-nuevo'), isNull);
      expect((await store.read('demo-nuevo')).incomeType, 'fecha_fija');

      unawaited(c.read(routerProvider).push(Routes.myMoney));
      await settle(tester);
      expect(path(c), Routes.myMoney);
      expect(_banner, findsNothing);
      expect(find.text('Terminar'), findsNothing);
    });
  });
}

class _FastControls extends DemoControlsNotifier {
  @override
  DemoControls build() => const DemoControls(latency: Duration.zero);
}

class _Regions extends RegionStore {
  @override
  Future<Region?> read() async => null;

  @override
  Future<void> write(Region region) async {}
}
