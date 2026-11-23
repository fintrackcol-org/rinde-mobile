// El panel de demostración dentro de la app real (router, entrada, Inicio y bienvenida), sin red.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/app/app.dart';
import 'package:rinde_mobile/app/router.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';
import 'package:rinde_mobile/features/onboarding/presentation/widgets/onboarding_shell.dart';
import 'package:rinde_mobile/features/welcome/presentation/welcome_screen.dart';

import '../../support/fake_http.dart';

class _FastControls extends DemoControlsNotifier {
  @override
  DemoControls build() => const DemoControls(latency: Duration.zero);
}

class _Regions extends RegionStore {
  int writes = 0;

  @override
  Future<Region?> read() async => null;

  @override
  Future<void> write(Region region) async => writes++;
}

const _restart = 'Reiniciar demostración';

const _salary = {
  'kind': 'sueldo',
  'payDays': [15],
};

Map<String, dynamic> _draft({
  int position = OnboardingSteps.balance,
  String balance = '',
  String? sentWelcome,
}) => {
  'v': 1,
  'position': position,
  'country': 'CO',
  'language': 'es',
  'balance': balance,
  'sources': [_salary],
  'sentWelcome': ?sentWelcome,
};

void main() {
  late MemoryDemoStateStore store;
  late MemoryDraftStore drafts;
  late MemoryTourSeenStore seen;
  late _Regions regions;
  late FakeHttpAdapter network;

  setUp(() {
    store = MemoryDemoStateStore();
    drafts = MemoryDraftStore();
    // El tutorial ya se vio: no tapa la franja de demostración.
    seen = MemoryTourSeenStore()..seen.addAll([for (final s in DemoScenario.values) 'demo-${s.name}']);
    regions = _Regions();
    network = FakeHttpAdapter((_) => jsonBody(500, {}));
  });

  tearDown(() => expect(network.requests, isEmpty, reason: 'la demostración no sale a la red'));

  Future<void> settle(WidgetTester tester) async {
    // Sin pumpAndSettle: Rin y los indicadores de carga no dejan de animarse.
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> openApp(
    WidgetTester tester,
    String scenario, {
    bool demoMode = true,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = AppConfig(
      apiBaseUrl: 'https://api-qa.ejemplo.test',
      environment: 'qa',
      demoMode: demoMode,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(config),
          sessionStorageProvider.overrideWithValue(MemorySessionStorage(Session.demo(scenario))),
          demoStateStoreProvider.overrideWithValue(store),
          demoControlsProvider.overrideWith(_FastControls.new),
          draftStoreProvider.overrideWithValue(drafts),
          tourSeenStoreProvider.overrideWithValue(seen),
          demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
          pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
          regionStoreProvider.overrideWithValue(regions),
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

  /// Desmonta y deja correr lo que quedó programado.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byType(DemoStrip));
    await settle(tester);
    expect(find.text('Panel de demostración'), findsOneWidget);
  }

  Future<void> tapInPanel(WidgetTester tester, Finder target, {bool wait = true}) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    if (wait) await settle(tester);
  }

  String path(ProviderContainer c) => c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  group('región', () {
    testWidgets('mientras llega la otra moneda no muestra las cifras en pesos', (tester) async {
      final c = await openApp(tester, 'planListo');
      expect((c.read(homeViewProvider).hero as HeroPlan).plan.money, 412300);
      await openPanel(tester);
      c.read(demoControlsProvider.notifier).setLatency(const Duration(seconds: 1));

      await tapInPanel(tester, find.text('US'), wait: false);
      expect(c.read(appRegionProvider).currency, 'USD');
      var view = c.read(homeViewProvider);
      expect(view.hero, isA<HeroLoading>());
      expect(view.totals.value, isNull);

      await settle(tester);
      view = c.read(homeViewProvider);
      expect((view.hero as HeroPlan).plan.money, 412.3);
      expect(view.totals.value!.income, 700);
      expect(regions.writes, 0);
      await close(tester);
    });

    testWidgets('sin conexión y con una falla puesta: las quita y vuelve a pedir los montos', (tester) async {
      final c = await openApp(tester, 'planListo');
      await openPanel(tester);
      await tapInPanel(tester, find.text('Apagada'));
      expect(c.read(demoControlsProvider).offline, isTrue);
      expect((c.read(homeViewProvider).hero as HeroMoney).money, 412300, reason: 'el último dato, sin red');
      c.read(demoControlsProvider.notifier).failNext(DemoHomeOperation.summary, DemoFailure.server);

      await tapInPanel(tester, find.text('US'));

      expect(c.read(demoControlsProvider).offline, isFalse);
      expect(c.read(demoControlsProvider).failures, isEmpty);
      final view = c.read(homeViewProvider);
      expect((view.hero as HeroPlan).plan.money, 412.3);
      expect(view.totals.value!.income, 700);
      expect(view.offline || view.loadError, isFalse);
      await close(tester);
    });

    for (final (name, from, to, balance, sent, expected) in [
      ('la propuesta de COP se quita al pasar a USD', 'CO', 'US', '650000', null, ''),
      ('la propuesta de USD se quita al volver a COP', 'US', 'CO', '650', null, ''),
      ('lo que escribió la persona se queda', 'CO', 'US', '800000', null, '800000'),
      ('lo que ya se envió se queda', 'CO', 'US', '650000', '{}', '650000'),
      ('la misma moneda no toca la propuesta', 'CO', 'CO', '650000', null, '650000'),
    ]) {
      testWidgets('saldo del borrador: $name', (tester) async {
        await store.update('demo-movimientos', (state) => state.withRegion(regionForCountry(from)));
        await drafts.write('demo-movimientos', _draft(balance: balance, sentWelcome: sent));
        await openApp(tester, 'movimientos');
        await openPanel(tester);

        await tapInPanel(tester, find.text(to));

        final draft = await drafts.read('demo-movimientos') as Map<String, dynamic>;
        expect(
          draft,
          _draft(balance: expected, sentWelcome: sent),
          reason: 'lo demás no se toca',
        );
        await close(tester);
      });
    }

    testWidgets('las preguntas proponen el saldo en la moneda nueva', (tester) async {
      await drafts.write('demo-movimientos', _draft(balance: '650000'));
      final c = await openApp(tester, 'movimientos');
      await openPanel(tester);
      await tapInPanel(tester, find.text('US'));
      Navigator.of(tester.element(find.text('Panel de demostración'))).pop();
      await settle(tester);

      c.read(routerProvider).go(Routes.onboardingQuestions);
      await settle(tester);

      expect(c.read(onboardingControllerProvider(OnboardingMode.questions)).draft.balance, '650');
      await close(tester);
    });
  });

  group('reiniciar', () {
    testWidgets('al terminar las preguntas, reiniciar vuelve a la entrada', (tester) async {
      final c = await openApp(tester, 'movimientos');
      c.read(routerProvider).go(Routes.onboardingQuestions);
      await settle(tester);
      final skipped = c.read(onboardingControllerProvider(OnboardingMode.questions).notifier).later();
      await settle(tester);
      await skipped;
      await tapInPanel(tester, find.text(_restart));
      expect(path(c), Routes.app);
      await close(tester);
    });

    testWidgets('sin conexión: borra la plata de la pantalla y vuelve a la bienvenida', (tester) async {
      await store.update(
        'demo-nuevo',
        (state) => state.withWelcome(const {'incomeType': 'sin_fecha', 'balance': 800000}),
      );
      final c = await openApp(tester, 'nuevo');
      expect((c.read(homeViewProvider).hero as HeroPlan).plan.money, 800000);
      await openPanel(tester);
      await tapInPanel(tester, find.text('Apagada'));
      expect((c.read(homeViewProvider).hero as HeroMoney).money, 800000);

      await tapInPanel(tester, find.text(_restart));

      expect(path(c), Routes.onboarding);
      expect(c.read(onboardingControllerProvider(OnboardingMode.full)).position, OnboardingSteps.hello);
      expect(c.read(demoControlsProvider).offline, isFalse);
      expect((await store.read('demo-nuevo')).balance, isNull);
      expect(seen.seen, isNot(contains('demo-nuevo')));
      await close(tester);
    });

    testWidgets('en un escenario con bienvenida hecha el tutorial se vuelve a abrir solo', (tester) async {
      final c = await openApp(tester, 'planListo');
      expect(c.read(tourControllerProvider), isFalse);
      await openPanel(tester);

      await tapInPanel(tester, find.text(_restart));

      expect(path(c), Routes.app);
      expect(c.read(tourControllerProvider), isTrue);
      await close(tester);
    });

    testWidgets('desde «solo las preguntas» una cuenta nueva vuelve al saludo', (tester) async {
      await store.update('demo-nuevo', (state) => state.withWelcome(const {'balance': 100000}));
      await drafts.write(
        'demo-nuevo',
        _draft(position: OnboardingSteps.payments, sentWelcome: '{"balance":100000}'),
      );
      final c = await openApp(tester, 'nuevo');
      expect(path(c), Routes.onboardingQuestions, reason: 'retoma las fuentes pendientes');
      await openPanel(tester);

      await tapInPanel(tester, find.text(_restart));

      expect(path(c), Routes.onboarding);
      expect(c.read(onboardingControllerProvider(OnboardingMode.full)).position, OnboardingSteps.hello);
      expect(await store.welcomeDone('demo-nuevo'), isFalse);
      await close(tester);
    });

    testWidgets('desde «solo las preguntas» una cuenta con movimientos vuelve al Inicio', (tester) async {
      final c = await openApp(tester, 'movimientos');
      c.read(routerProvider).go(Routes.onboardingQuestions);
      await settle(tester);
      await openPanel(tester);

      await tapInPanel(tester, find.text(_restart));

      expect(path(c), Routes.app);
      expect(c.read(homeViewProvider).hero, isA<HeroMoney>());
      await close(tester);
    });

    testWidgets('mientras guarda no se puede reiniciar; al terminar sí', (tester) async {
      final c = await openApp(tester, 'nuevo');
      expect(path(c), Routes.onboarding);
      await store.update('demo-nuevo', (state) => state.withTutorial());
      c.read(demoControlsProvider.notifier).setLatency(const Duration(seconds: 6));
      final saving = c.read(onboardingControllerProvider(OnboardingMode.full).notifier).later();
      await tester.pump();
      await openPanel(tester);
      // .last: al terminar, la pantalla final de detrás tiene un botón con el mismo texto.
      RindeButton button() => tester.widget<RindeButton>(find.widgetWithText(RindeButton, _restart).last);
      expect(button().onPressed, isNull);

      await tapInPanel(tester, find.text(_restart));
      expect((await store.read('demo-nuevo')).tutorialDone, isTrue, reason: 'no se borró nada');

      await tester.pump(const Duration(seconds: 6));
      await saving;
      await tester.pump();
      expect(await store.welcomeDone('demo-nuevo'), isTrue);
      expect(button().onPressed, isNotNull);
      await close(tester);
    });
  });

  group('perillas del Inicio', () {
    testWidgets('latencia, falla programada y quitarla', (tester) async {
      final c = await openApp(tester, 'teFaltan');
      await openPanel(tester);
      expect(find.text('GET /money-profile/plan'), findsOneWidget);
      expect(find.text('PATCH /users/me'), findsNothing, reason: 'esa perilla es de la bienvenida');

      await tapInPanel(tester, find.text('2 s'));
      expect(c.read(demoControlsProvider).latency, const Duration(seconds: 2));
      await tapInPanel(tester, find.text('Error del servidor').first);
      expect(c.read(demoControlsProvider).failures, {DemoHomeOperation.plan: DemoFailure.server});
      await tapInPanel(tester, find.text('Ninguna').first);
      expect(c.read(demoControlsProvider).failures, isEmpty);
      await close(tester);
    });

    testWidgets('la conexión hace caer el Inicio y lo devuelve', (tester) async {
      final c = await openApp(tester, 'teFaltan');
      await openPanel(tester);
      await tapInPanel(tester, find.text('Apagada'));
      expect(c.read(homeViewProvider).offline, isTrue);
      await tapInPanel(tester, find.text('Encendida'));
      expect(c.read(homeViewProvider).offline, isFalse);
      expect((c.read(homeViewProvider).hero as HeroPlan).plan.shortfall, 93000);
      await close(tester);
    });

    testWidgets('cambia el tema', (tester) async {
      final c = await openApp(tester, 'planListo');
      await openPanel(tester);
      await tapInPanel(tester, find.text('Oscuro'));
      expect(c.read(themeModeProvider), ThemeMode.dark);
      await close(tester);
    });

    testWidgets('«Ver el tutorial» lo abre aunque ya se vio', (tester) async {
      final c = await openApp(tester, 'planListo');
      await openPanel(tester);
      await tapInPanel(tester, find.text('Ver el tutorial'));
      expect(c.read(tourControllerProvider), isTrue);
      await close(tester);
    });

    testWidgets('salir cierra la sesión y no deja la región de la demostración', (tester) async {
      await store.update('demo-planListo', (state) => state.withRegion(regionForCountry('BR')));
      final c = await openApp(tester, 'planListo');
      expect(c.read(appRegionProvider).currency, 'BRL');
      await openPanel(tester);

      await tapInPanel(tester, find.text('Salir de la demostración'));

      expect(c.read(sessionControllerProvider).value?.signedIn, isFalse);
      expect(path(c), Routes.login);
      expect(c.read(appRegionProvider), kDefaultRegion);
      expect(regions.writes, 0);
      await close(tester);
    });

    testWidgets('cabe en 320 de ancho con el texto al doble', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openApp(tester, 'planListo', size: const Size(320, 640));
      await openPanel(tester);
      await tester.ensureVisible(find.text('Salir de la demostración'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  });

  testWidgets('sin DEMO_MODE una sesión demo guardada no llega al Inicio ni al panel', (tester) async {
    await openApp(tester, 'planListo', demoMode: false);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(DemoStrip), findsNothing);
    expect(find.text('Probar sin servidor (demo)'), findsNothing);
    await close(tester);
  });
}
