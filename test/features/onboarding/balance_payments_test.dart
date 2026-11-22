import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';
import 'package:rinde_mobile/features/onboarding/presentation/finish_views.dart';
import 'package:rinde_mobile/features/onboarding/presentation/money_invite.dart';
import 'package:rinde_mobile/features/onboarding/presentation/onboarding_screen.dart';
import 'package:rinde_mobile/features/onboarding/presentation/payments/payment_widgets.dart';

/// La demostración sin espera, para no depender de los 700 ms por defecto.
class _FastDemoControls extends DemoControlsNotifier {
  @override
  DemoControls build() => const DemoControls(latency: Duration.zero);
}

/// Doble de «Ahora no»: cuenta las llamadas y responde cuando la prueba lo diga.
class _PendingRepo implements OnboardingRepository {
  final bodies = <Map<String, dynamic>>[];
  var reply = Completer<void>();

  @override
  bool get isDemo => false;

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) {
    bodies.add(body);
    return reply.future;
  }

  @override
  Future<WelcomeStatus> status() async =>
      const WelcomeStatus(welcomeDone: false, tutorialDone: false, hasTransactions: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// La sesión se lee antes de montar la pantalla (como lo garantiza el router de la app).
class _AfterSession extends ConsumerWidget {
  const _AfterSession(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(sessionControllerProvider).hasValue ? child : const SizedBox();
}

/// Monta la bienvenida (o [home]) con una sesión de demostración y el borrador en [position].
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  int position = OnboardingSteps.payments,
  String scenario = 'nuevo',
  Widget? home,
  OnboardingRepository? repo,
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final session = Session.demo(scenario);
  final drafts = MemoryDraftStore();
  drafts.data[session.user.id] = jsonEncode(
    OnboardingDraft(position: position, country: 'CO', language: 'es').toJson(),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => home ?? const OnboardingScreen(mode: OnboardingMode.full),
      ),
      GoRoute(path: Routes.app, builder: (_, _) => const Text('inicio falso')),
      GoRoute(path: Routes.onboardingQuestions, builder: (_, _) => const Text('preguntas falsas')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
        ),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
        draftStoreProvider.overrideWithValue(drafts),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        demoControlsProvider.overrideWith(_FastDemoControls.new),
        systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
        if (repo != null) onboardingRepositoryProvider.overrideWithValue(repo),
      ],
      child: _AfterSession(
        MaterialApp.router(
          theme: RindeTheme.light,
          routerConfig: router,
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

OnboardingState _state(ProviderContainer c) => c.read(onboardingControllerProvider(OnboardingMode.full));

Finder _pill(String label) => find.widgetWithText(PaymentPill, label);
Finder _cardFields() => find.descendant(of: find.byType(PaymentCard), matching: find.byType(TextField));

Future<void> _end(WidgetTester tester) async {
  // Desmonta para que el controlador cancele su temporizador del borrador.
  await tester.pumpWidget(const SizedBox());
  // Cerrar la bienvenida no debe lanzar nada (antes, el onDispose usaba ref).
  expect(tester.takeException(), isNull);
}

void main() {
  group('Saldo', () {
    testWidgets('lo escrito llega crudo al borrador y vacío queda vacío', (tester) async {
      final c = await _pump(tester, position: OnboardingSteps.balance);
      expect(find.text('¿Cuánta plata tienes hoy, más o menos?'), findsOneWidget);
      expect(find.text('Total aproximado'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '250000');
      await tester.pump();
      expect(_state(c).draft.balance, '250000');
      expect(find.text('250.000'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(_state(c).draft.balance, '');
      // Sin número no se inventa un cero: la bienvenida enviaría null.
      expect(welcomeBody(balance: _state(c).draft.balance)['balance'], isNull);
      expect(find.text('Dato de demostración'), findsNothing);
      await _end(tester);
    });

    testWidgets('desde un millón avisa el monto en palabras', (tester) async {
      await _pump(tester, position: OnboardingSteps.balance);
      await tester.enterText(find.byType(TextField), '1500000');
      await tester.pump();
      expect(find.text('≈ 1,5 millones de pesos'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('en demostración marca el saldo propuesto hasta que la persona lo cambia', (tester) async {
      final c = await _pump(tester, position: OnboardingSteps.balance, scenario: 'movimientos');
      // Totales sintéticos de la demo: 2.500.000 − 1.850.000.
      expect(_state(c).draft.balance, '650000');
      expect(find.text('Dato de demostración'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '700000');
      await tester.pump();
      expect(find.text('Dato de demostración'), findsNothing);
      await _end(tester);
    });
  });

  group('Pagos', () {
    testWidgets('tocar Arriendo agrega su tarjeta y volver a tocarlo la quita', (tester) async {
      final c = await _pump(tester);
      expect(find.byType(PaymentCard), findsNothing);

      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsOneWidget);
      expect(_state(c).draft.items.single.name, 'Arriendo');
      expect(tester.getSemantics(_pill('Arriendo')), isSemantics(isButton: true, isSelected: true));

      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNothing);
      expect(_state(c).draft.items, isEmpty);
      await _end(tester);
    });

    testWidgets('Otro agrega una tarjeta con el nombre editable y enfocado', (tester) async {
      final c = await _pump(tester);
      await tester.tap(_pill('Otro'));
      await tester.pumpAndSettle();

      final name = find.widgetWithText(TextField, 'Nombre del pago');
      expect(name, findsOneWidget);
      expect(tester.widget<TextField>(name).focusNode!.hasFocus, isTrue);
      await tester.enterText(name, 'Gimnasio');
      await tester.pump();
      expect(_state(c).draft.items.single.name, 'Gimnasio');
      expect(_state(c).draft.items.single.custom, isTrue);
      await _end(tester);
    });

    testWidgets('quitar elimina el pago', (tester) async {
      final c = await _pump(tester);
      await tester.tap(_pill('Internet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quitar Internet'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNothing);
      expect(_state(c).draft.items, isEmpty);
      await _end(tester);
    });

    testWidgets('sin monto no envía y lleva el foco al monto que falta', (tester) async {
      final c = await _pump(tester);
      final repo = c.read(onboardingRepositoryProvider) as DemoOnboardingRepository;
      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver mi plata'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe cuánto pagas por Arriendo.'), findsOneWidget);
      expect(repo.calls.where((call) => call.operation == DemoOperation.welcome), isEmpty);
      expect(_state(c).errorItemKey, _state(c).draft.items.single.key);
      final amount = find.descendant(of: _cardFields().first, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(amount).focusNode.hasFocus, isTrue);
      await _end(tester);
    });

    testWidgets('con todo lleno termina la demostración y muestra lo que se habría enviado', (tester) async {
      final c = await _pump(tester);
      final repo = c.read(onboardingRepositoryProvider) as DemoOnboardingRepository;
      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();
      await tester.enterText(_cardFields().at(0), '800000');
      await tester.enterText(_cardFields().at(1), '5');
      await tester.pump();

      await tester.tap(find.text('Ver mi plata'));
      await tester.pumpAndSettle();

      expect(_state(c).outcome, OnboardingOutcome.demoSaved);
      final welcome = repo.calls.singleWhere((call) => call.operation == DemoOperation.welcome);
      final body = welcome.body! as Map<String, dynamic>;
      expect(body['balance'], isNull);
      expect(body['commitments'], [
        {
          'name': 'Arriendo',
          'amount': 800000,
          'dayOfMonth': 5,
          'kind': 'fixed',
          'frequency': 'monthly',
          'month': null,
        },
      ]);
      expect(find.text('Demostración terminada'), findsOneWidget);
      expect(
        find.text('No se envió nada a ningún servidor. Esto es lo que se habría enviado:'),
        findsOneWidget,
      );
      expect(find.text('POST /money-profile/welcome'), findsOneWidget);
      await _end(tester);
    });
  });

  for (final (scale, theme, name) in [(2.0, RindeTheme.dark, 'oscuro'), (1.3, RindeTheme.light, 'claro')]) {
    testWidgets('texto ×$scale en tema $name: saldo, pagos e invitación sin desbordes', (tester) async {
      await _pump(tester, position: OnboardingSteps.balance, textScale: scale, theme: theme);
      await tester.enterText(find.byType(TextField), '150000000');
      await tester.pump();
      expect(find.textContaining('Monto muy grande'), findsOneWidget);
      await _end(tester);

      await _pump(tester, textScale: scale, theme: theme);
      await tester.tap(_pill('Universidad'));
      await tester.pumpAndSettle();
      await tester.tap(_pill('Otro'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNWidgets(2));
      await _end(tester);

      await _pump(
        tester,
        home: const Scaffold(body: Center(child: MoneyInviteCard())),
        repo: _PendingRepo(),
        textScale: scale,
        theme: theme,
      );
      expect(find.text('Responder'), findsOneWidget);
      await _end(tester);
    });
  }

  group('Invitación del inicio', () {
    testWidgets('«Ahora no» envía {} una sola vez aunque se toque dos veces y muestra el error', (
      tester,
    ) async {
      final repo = _PendingRepo();
      await _pump(
        tester,
        home: const Scaffold(body: Center(child: MoneyInviteCard())),
        repo: repo,
      );

      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      expect(repo.bodies, [<String, dynamic>{}]);

      repo.reply.completeError(const ApiException(code: ApiCodes.network));
      await tester.pumpAndSettle();
      expect(find.text(ApiMessages.network), findsOneWidget);

      // Después del error se puede reintentar.
      repo.reply = Completer<void>()..complete();
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(repo.bodies, hasLength(2));
      await _end(tester);
    });

    testWidgets('«Responder» abre las tres preguntas', (tester) async {
      await _pump(
        tester,
        home: const Scaffold(body: Center(child: MoneyInviteCard())),
        repo: _PendingRepo(),
      );
      expect(find.text('¿Ya tenías plata cuando empezaste?'), findsOneWidget);
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      expect(find.text('preguntas falsas'), findsOneWidget);
      await _end(tester);
    });
  });

  testWidgets('la celebración sigue sola; con movimiento reducido, a los 700 ms', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: RindeTheme.light,
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: CelebrationView(onDone: () => done++),
        ),
      ),
    );
    expect(find.text('¡Listo!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 650));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, 1);
    await _end(tester);
  });
}
