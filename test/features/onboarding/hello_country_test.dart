import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_segmented.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';
import 'package:rinde_mobile/features/onboarding/presentation/onboarding_screen.dart';
import 'package:rinde_mobile/features/onboarding/presentation/widgets/onboarding_shell.dart';
import 'package:rinde_mobile/features/welcome/presentation/welcome_screen.dart';

const _mode = OnboardingMode.full;
const _title = 'Hagamos que Rinde hable tu idioma.';

/// MODO DEMOSTRACIÓN con todo en memoria: sesión demo 'nuevo' (Ana), sin latencia, idioma es-CO.
ProviderContainer _container({bool demoMode = true, bool signedIn = true, MemoryDraftStore? drafts}) {
  // Cualquier error al liberar el contenedor (p. ej. usar ref en onDispose) hace fallar la prueba.
  final c = runZoned(
    () => ProviderContainer.test(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(apiBaseUrl: '', environment: 'local', demoMode: demoMode),
        ),
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage(signedIn ? Session.demo('nuevo') : null),
        ),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
      ],
    ),
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) {
        parent.handleUncaughtError(zone, error, stack);
      },
    ),
  );
  c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
  c.listen(sessionControllerProvider, (_, _) {});
  return c;
}

/// Borrador que ya está en País (posición 1).
MemoryDraftStore _atCountry() =>
    MemoryDraftStore()
      ..data['demo-nuevo'] = jsonEncode({'v': 1, 'position': 1, 'country': 'CO', 'language': 'es'});

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(ProviderContainer c, Widget home, {double textScale = 1, ThemeData? theme}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: theme ?? RindeTheme.light,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
          child: child!,
        ),
      ),
    );

Future<ProviderContainer> _pumpOnboarding(
  WidgetTester tester, {
  MemoryDraftStore? drafts,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  _phone(tester, size);
  final c = _container(drafts: drafts);
  await tester.runAsync(() => c.read(sessionControllerProvider.future));
  await tester.pumpWidget(_app(c, const OnboardingScreen(mode: _mode), textScale: textScale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  return c;
}

/// Deja correr los temporizadores (saludo de Rin, escritura del borrador) y desmonta.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

OnboardingState _state(ProviderContainer c) => c.read(onboardingControllerProvider(_mode));

void main() {
  group('Saludo', () {
    testWidgets('muestra el nombre, los textos, a Rin y los dos botones', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpOnboarding(tester);

      expect(find.text('Hola, Ana'), findsOneWidget);
      expect(find.text('Tu plata tiene una historia. Entendámosla juntos.'), findsOneWidget);
      expect(find.text('Descubre cómo organizar tu dinero y tomar mejores decisiones.'), findsOneWidget);
      expect(find.bySemanticsLabel('Rin, la mascota de Rinde, te saluda'), findsOneWidget);
      expect(find.bySemanticsLabel('Rinde'), findsOneWidget);
      for (final label in ['Empezar', 'Ahora no']) {
        expect(tester.getSize(find.widgetWithText(InkWell, label)).height, greaterThanOrEqualTo(48));
      }
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('«Empezar» avanza a País', (tester) async {
      final c = await _pumpOnboarding(tester);
      await tester.tap(find.text('Empezar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_state(c).position, OnboardingSteps.country);
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Elige tu país y ajustamos la moneda por ti.'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('«Ahora no» manda finishWelcome({}) a la demo y termina en demoSkipped', (tester) async {
      final c = await _pumpOnboarding(tester);
      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      final repo = c.read(onboardingRepositoryProvider) as DemoOnboardingRepository;
      final bodies = repo.calls
          .where((call) => call.operation == DemoOperation.welcome)
          .map((call) => call.body);
      expect(bodies, [<String, dynamic>{}]);
      expect(_state(c).outcome, OnboardingOutcome.demoSkipped);
      await _finish(tester);
    });

    testWidgets('a 320x568 con texto 1,3x no se desborda y deja llegar a «Ahora no»', (tester) async {
      await _pumpOnboarding(tester, size: const Size(320, 568), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Ahora no'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Ahora no')).bottom, lessThanOrEqualTo(568));
      await _finish(tester);
    });

    testWidgets('en tema oscuro se dibuja sin errores', (tester) async {
      _phone(tester, const Size(390, 844));
      final c = _container();
      await tester.runAsync(() => c.read(sessionControllerProvider.future));
      await tester.pumpWidget(_app(c, const OnboardingScreen(mode: _mode), theme: RindeTheme.dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.takeException(), isNull);
      expect(find.text('Empezar'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('País e idioma', () {
    testWidgets('cambiar de país actualiza la muestra, el chip y (sin idioma elegido) el idioma', (
      tester,
    ) async {
      final c = await _pumpOnboarding(tester, drafts: _atCountry());
      expect(find.text(findCountry('CO')!.sample), findsOneWidget);
      expect(find.text('Peso colombiano · COP'), findsOneWidget);

      await tester.tap(find.text('Colombia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brasil'));
      await tester.pumpAndSettle();

      expect(_state(c).draft.country, 'BR');
      expect(find.text(findCountry('BR')!.sample), findsOneWidget);
      // BR sugiere portugués: el chip sale con el nombre de la moneda en pt.
      expect(_state(c).draft.language, 'pt');
      expect(_state(c).draft.languagePicked, isFalse);
      expect(c.read(displayLanguageProvider), 'pt');
      expect(find.text('Real brasileiro · BRL'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('elegir English cambia el idioma del borrador y ya no lo mueve el país', (tester) async {
      final c = await _pumpOnboarding(tester, drafts: _atCountry());
      await tester.tap(find.text('English'));
      await tester.pump();

      expect(_state(c).draft.language, 'en');
      expect(_state(c).draft.languagePicked, isTrue);
      expect(c.read(trProvider).language, 'en');
      expect(find.text('Colombian Peso · COP'), findsOneWidget);
      // Sin traducciones cargadas en la prueba, el título cae al español.
      expect(find.text(_title), findsOneWidget);

      c.read(onboardingControllerProvider(_mode).notifier).pickCountry('BR');
      await tester.pump();
      expect(_state(c).draft.language, 'en');
      expect(find.text('Brazilian Real · BRL'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('la hoja de países busca sin tildes: «peru» → Perú', (tester) async {
      await _pumpOnboarding(tester, drafts: _atCountry());
      await tester.tap(find.text('Colombia'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'peru');
      await tester.pump();
      final list = find.byType(ListView);
      expect(find.descendant(of: list, matching: find.text('Perú')), findsOneWidget);
      expect(find.descendant(of: list, matching: find.text('Colombia')), findsNothing);
      expect(find.descendant(of: list, matching: find.text('Brasil')), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No encontramos ese país.'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('a 320x568 con texto 2x no se desborda', (tester) async {
      await _pumpOnboarding(tester, drafts: _atCountry(), size: const Size(320, 568), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Los dos se cambian cuando quieras en Cuenta.'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });

    testWidgets('los idiomas van en fila si caben', (tester) async {
      // La letra de las pruebas es cuadrada (más ancha que Inter Tight): se achica para que quepan.
      await _pumpOnboarding(tester, drafts: _atCountry(), textScale: 0.7);
      final tops = [for (final l in kLanguages) tester.getRect(find.text(l.name)).top];
      expect(tops.toSet(), hasLength(1));
      expect(
        tester.getRect(find.text(kLanguages[1].name)).left,
        greaterThan(tester.getRect(find.text(kLanguages[0].name)).right),
      );
      await _finish(tester);
    });

    testWidgets('si una etiqueta no cabe a su tamaño, los idiomas van uno debajo del otro sin achicarse', (
      tester,
    ) async {
      final c = await _pumpOnboarding(tester, drafts: _atCountry(), size: const Size(320, 568), textScale: 2);
      final segmented = find.byType(RindeSegmented<String>);
      await tester.ensureVisible(segmented);
      await tester.pump();
      final rects = [for (final l in kLanguages) tester.getRect(find.text(l.name))];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom));
      }
      // Letra de 15 con interlínea de 20, al doble: nada de encogerla para que entre.
      expect(rects.first.height, greaterThanOrEqualTo(40));
      final box = tester.getRect(segmented);
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(box.left));
        expect(r.right, lessThanOrEqualTo(box.right));
      }
      // Cada opción sigue siendo un botón de 48 o más y elige su idioma.
      final english = find.widgetWithText(InkWell, 'English');
      expect(tester.getSize(english).height, greaterThanOrEqualTo(48));
      await tester.tap(english);
      await tester.pump();
      expect(_state(c).draft.language, 'en');
      expect(tester.takeException(), isNull);
      await _finish(tester);
    });
  });

  group('Modo demostración', () {
    testWidgets('el panel programa una falla y reinicia la demostración', (tester) async {
      final c = await _pumpOnboarding(tester, drafts: _atCountry());
      await tester.tap(find.byType(DemoStrip));
      await tester.pumpAndSettle();
      expect(find.text('MODO DEMOSTRACIÓN · SIN BACKEND: nada se envía a ningún servidor.'), findsOneWidget);

      // La primera fila es «Guardar país e idioma».
      await tester.tap(find.text('Sin conexión').first);
      await tester.pump();
      expect(c.read(demoControlsProvider).failures[DemoOperation.region], DemoFailure.network);

      Navigator.of(tester.element(find.text('Panel de demostración'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seguir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.textContaining('Estás sin conexión.'), findsOneWidget);

      await tester.tap(find.byType(DemoStrip));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reiniciar demostración'));
      await tester.pump();
      await tester.tap(find.text('Reiniciar demostración'));
      await tester.pumpAndSettle();
      expect(_state(c).position, OnboardingSteps.hello);
      expect(find.text('Empezar'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('sin DEMO_MODE la pantalla de entrada no muestra la demo', (tester) async {
      _phone(tester, const Size(390, 844));
      final c = _container(demoMode: false, signedIn: false);
      await tester.pumpWidget(_app(c, const WelcomeScreen(), theme: RindeTheme.public));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ya tengo cuenta'), findsOneWidget);
      expect(find.text('Probar sin servidor (demo)'), findsNothing);
    });

    testWidgets('con DEMO_MODE entra con el escenario elegido', (tester) async {
      _phone(tester, const Size(390, 844));
      final c = _container(signedIn: false);
      await tester.runAsync(() => c.read(sessionControllerProvider.future));
      await tester.pumpWidget(_app(c, const WelcomeScreen(), theme: RindeTheme.public));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.ensureVisible(find.text('Probar sin servidor (demo)'));
      await tester.pump();
      await tester.tap(find.text('Probar sin servidor (demo)'));
      await tester.pumpAndSettle();
      expect(find.text('MODO DEMOSTRACIÓN · SIN BACKEND: nada se envía a ningún servidor.'), findsOneWidget);
      expect(find.text(DemoScenario.nuevo.label), findsOneWidget);

      await tester.tap(find.text(DemoScenario.movimientos.label));
      await tester.pumpAndSettle();
      final session = c.read(sessionControllerProvider).value?.session;
      expect(session?.demo, isTrue);
      expect(session?.user.id, 'demo-movimientos');
    });
  });
}
