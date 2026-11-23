import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
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
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
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
          theme: theme ?? RindeTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Lo que se le anuncia al lector de pantalla (SemanticsService), en orden.
List<String> _announcements(WidgetTester tester) {
  final log = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
    final data = message is Map && message['type'] == 'announce' ? message['data'] : null;
    if (data is Map) log.add('${data['message']}');
    return null;
  });
  addTearDown(() => messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return log;
}

Tr _tr(String language, [Map<String, String> messages = const {}]) => Tr(language, messages);

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
      await tester.enterText(find.byType(TextField), '500');
      await tester.pump();
      // Con los separadores con que se ve el resto de la plata, no un «$1.000» fijo.
      final thousand = formatFor(regionForCountry('CO')).money(1000);
      expect(thousand, contains('1.000'));
      expect(find.text('Son menos de $thousand. ¿Faltan ceros?'), findsOneWidget);
      await _end(tester);
    });

    test('palabras del monto por idioma: plural, singular del portugués y separador de escritura', () {
      String words(num v, String language, [String decimal = ',']) => bigAmountWords(v, language, decimal);
      expect(words(1500000, 'es'), '1,5 millones');
      expect(words(1500000, 'en', '.'), '1.5 million');
      expect(words(1500000, 'pt'), '1,5 milhão');
      expect(words(1000000, 'es'), '1 millón');
      expect(words(1000000, 'en'), '1 million');
      expect(words(1000000, 'pt'), '1 milhão');
      expect(words(2000000, 'pt'), '2 milhões');
      expect(words(1040000, 'es'), '1 millón', reason: 'el plural se decide después de redondear');
      expect(words(2500000000, 'es'), '2,5 mil millones');
      expect(words(2500000000, 'en', '.'), '2.5 billion');
      expect(words(2500000000, 'pt'), '2,5 bilhões');
      expect(words(1000000000, 'pt'), '1 bilhão');
      // 999,96 millones redondea a 1000: se dice en miles de millones, no «1000 millones».
      expect(words(999960000, 'es'), '1 mil millones');
      expect(words(999960000, 'en'), '1 billion');
      expect(words(999940000, 'es'), '999,9 millones');
    });

    test('describeAmount: frase completa en es, en y pt, con el decimal de escritura del país', () {
      final co = formatFor(regionForCountry('CO'));
      const en = {
        ' de pesos': ' pesos',
        'Monto muy grande ({value}{unit}). Revisa que no sobren ceros.':
            'Very large amount ({value}{unit}). Check there are no extra zeros.',
      };
      String? say(String raw, Tr t, {MoneyFormat? format, bool inPesos = true}) =>
          describeAmount(raw, format: format ?? co, inPesos: inPesos, t: t)?.message;

      expect(say('1500000', _tr('es')), '≈ 1,5 millones de pesos');
      expect(say('1500000', _tr('en', en)), '≈ 1,5 million pesos');
      expect(say('1500000', _tr('pt', const {' de pesos': ' de pesos'})), '≈ 1,5 milhão de pesos');
      expect(
        say('250000000', _tr('es')),
        'Monto muy grande (250 millones de pesos). Revisa que no sobren ceros.',
      );
      expect(
        say('2500000000', _tr('en', en)),
        'Very large amount (2,5 billion pesos). Check there are no extra zeros.',
      );
      // Otra moneda: sin «de pesos», sin «¿faltan ceros?» y con el decimal con que se escribe allá.
      final us = formatFor(regionForCountry('US'));
      expect(
        say('1500000', _tr('en'), format: us, inPesos: false),
        '≈ ${bigAmountWords(1500000, 'en', us.inputDecimal)}',
      );
      expect(us.inputDecimal, '.');
      expect(say('500', _tr('en'), format: us, inPesos: false), isNull);

      expect(say('500', _tr('es')), 'Son menos de ${co.money(1000)}. ¿Faltan ceros?');
      expect(say('99999999999', _tr('es')), 'Supera el máximo permitido (${co.money(9999999999.99)}).');
      expect(
        describeAmount('99999999999', format: co, inPesos: true, t: _tr('es'))?.tone,
        RindeMoneyMessageTone.error,
      );
      for (final none in ['', '0', '250000']) {
        expect(say(none, _tr('es')), isNull, reason: none);
      }
    });

    testWidgets('con el teclado, el margen que sube el aviso y la ayuda crece con el tamaño de texto', (
      tester,
    ) async {
      await _pump(tester, position: OnboardingSteps.balance);
      expect(tester.widget<TextField>(find.byType(TextField)).scrollPadding.bottom, 120);
      await _end(tester);
      await _pump(tester, position: OnboardingSteps.balance, textScale: 2);
      expect(tester.widget<TextField>(find.byType(TextField)).scrollPadding.bottom, 240);
      await _end(tester);
    });

    testWidgets('al cambiar de paso se anuncia el título y «Paso n de m» al lector de pantalla', (
      tester,
    ) async {
      final said = _announcements(tester);
      await _pump(tester, position: OnboardingSteps.balance);
      expect(said, ['¿Cuánta plata tienes hoy, más o menos?\nPaso 8 de 9']);

      await tester.tap(find.text('Seguir'));
      await tester.pumpAndSettle();
      expect(said.last, '¿Qué pagas cada mes?\nPaso 9 de 9');
      // Volver a dibujar el mismo paso no lo repite.
      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();
      expect(said, hasLength(2));
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

  group('Monto y Día de un pago', () {
    Future<(Rect, Rect)> fields(WidgetTester tester, {required Size size, double textScale = 1}) async {
      await _pump(tester, size: size, textScale: textScale);
      await tester.ensureVisible(_pill('Arriendo'));
      await tester.tap(_pill('Arriendo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return (tester.getRect(_cardFields().at(0)), tester.getRect(_cardFields().at(1)));
    }

    testWidgets('con espacio van lado a lado: el día a la derecha del monto', (tester) async {
      for (final (size, scale) in [(const Size(390, 844), 1.0), (const Size(320, 568), 1.3)]) {
        final (amount, day) = await fields(tester, size: size, textScale: scale);
        expect(day.left, greaterThan(amount.right), reason: '$size ×$scale');
        expect(day.top, amount.top, reason: '$size ×$scale');
        await _end(tester);
      }
    });

    testWidgets('con texto grande o pantalla angosta van uno debajo del otro', (tester) async {
      for (final (size, scale) in [
        (const Size(390, 844), 2.0),
        (const Size(320, 568), 2.0),
        (const Size(260, 568), 1.0),
      ]) {
        final (amount, day) = await fields(tester, size: size, textScale: scale);
        expect(day.top, greaterThan(amount.bottom), reason: '$size ×$scale');
        expect(day.left, amount.left, reason: '$size ×$scale');
        // El monto ocupa todo el ancho de la tarjeta; el día conserva su ancho corto.
        expect(amount.width, greaterThan(day.width), reason: '$size ×$scale');
        await _end(tester);
      }
    });
  });

  testWidgets('mientras guarda no se edita: el campo suelta el foco y los toques no llegan', (tester) async {
    final repo = _PendingRepo();
    final c = await _pump(tester, repo: repo);
    await tester.tap(_pill('Arriendo'));
    await tester.pumpAndSettle();
    await tester.enterText(_cardFields().at(0), '800000');
    await tester.enterText(_cardFields().at(1), '5');
    await tester.pump();
    bool focused(int i) => tester
        .widget<EditableText>(find.descendant(of: _cardFields().at(i), matching: find.byType(EditableText)))
        .focusNode
        .hasFocus;
    expect(focused(1), isTrue);

    await tester.tap(find.text('Ver mi plata'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_state(c).busy, OnboardingBusy.finishing);
    expect(repo.bodies, hasLength(1));
    // Lo que se escribiera ahora no viajaría: el campo pierde el foco y no lo recupera al tocarlo.
    expect(focused(1), isFalse);
    await tester.tap(_cardFields().at(0), warnIfMissed: false);
    await tester.tap(find.byTooltip('Quitar Arriendo'), warnIfMissed: false);
    await tester.tap(_pill('Internet'), warnIfMissed: false);
    await tester.pump();
    expect(focused(0), isFalse);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    expect(_state(c).draft.items.map((i) => (i.name, i.amount, i.dayOfMonth)), [('Arriendo', '800000', '5')]);

    // Falló: se puede corregir y reintentar.
    repo.reply.completeError(const ApiException(code: ApiCodes.network));
    await tester.pumpAndSettle();
    expect(_state(c).busy, isNull);
    await tester.enterText(_cardFields().at(0), '900000');
    await tester.pump();
    expect(_state(c).draft.items.single.amount, '900000');
    await _end(tester);
  });

  testWidgets('salir de «solo las preguntas» sin terminar: va al Inicio y la entrada ya no devuelve aquí', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      position: OnboardingSteps.income,
      home: const OnboardingScreen(mode: OnboardingMode.questions),
    );
    expect(c.read(resumeDeferredProvider), isFalse);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('inicio falso'), findsOneWidget);
    expect(c.read(resumeDeferredProvider), isTrue);
    await _end(tester);
  });

  for (final (scale, theme, name) in [(2.0, RindeTheme.dark, 'oscuro'), (1.3, RindeTheme.light, 'claro')]) {
    testWidgets('texto ×$scale en tema $name: saldo, pagos e invitación sin desbordes', (tester) async {
      await _pump(tester, position: OnboardingSteps.balance, textScale: scale, theme: theme);
      await tester.enterText(find.byType(TextField), '150000000');
      await tester.pump();
      expect(find.textContaining('Monto muy grande'), findsOneWidget);
      await _end(tester);

      await _pump(tester, textScale: scale, theme: theme);
      for (final name in ['Universidad', 'Otro']) {
        await tester.ensureVisible(_pill(name));
        await tester.pumpAndSettle();
        await tester.tap(_pill(name));
        await tester.pumpAndSettle();
      }
      expect(find.byType(PaymentCard), findsNWidgets(2));
      await _end(tester);

      await _pump(
        tester,
        home: const Scaffold(body: SingleChildScrollView(child: MoneyInviteCard())),
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
        home: const Scaffold(body: SingleChildScrollView(child: MoneyInviteCard())),
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

    testWidgets('«Ahora no» borra un borrador a medias, pero no uno que ya salió', (tester) async {
      for (final sent in [null, '{"balance":900000}']) {
        final repo = _PendingRepo()..reply = (Completer<void>()..complete());
        final c = await _pump(
          tester,
          home: const Scaffold(body: SingleChildScrollView(child: MoneyInviteCard())),
          repo: repo,
        );
        final user = c.read(accountProvider)!.user.id;
        final drafts = c.read(draftStoreProvider);
        await drafts.write(
          user,
          OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: sent).toJson(),
        );
        await tester.tap(find.text('Ahora no'));
        await tester.pumpAndSettle();
        expect(await drafts.read(user) != null, sent != null, reason: '$sent');
        await _end(tester);
      }
    });

    testWidgets('«Responder» abre las tres preguntas', (tester) async {
      await _pump(
        tester,
        home: const Scaffold(body: SingleChildScrollView(child: MoneyInviteCard())),
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
