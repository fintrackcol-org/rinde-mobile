import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
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
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/tokens/rinde_colors.dart';
import 'package:rinde_mobile/design/widgets/rinde_line.dart';
import 'package:rinde_mobile/design/widgets/rinde_skeleton.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/home/presentation/home_screen.dart';
import 'package:rinde_mobile/features/home/presentation/tour/coach_tour.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/hero_card.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/home_empty.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/home_notice_card.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/home_tap.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/load_error_notice.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/month_totals.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/next_payments.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/presentation/money_invite.dart';
import 'package:rinde_mobile/features/rin/rin.dart';

import '../../support/fake_home_repository.dart';
import '../../support/home_fixtures.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

/// Pesos colombianos: «$ 412.300».
final _co = formatFor(const Region(country: 'CO', currency: 'COP', language: 'es'));
String _m(num value) => _co.money(value);

/// La preferencia de ocultar montos sin tocar el almacenamiento del teléfono.
class _NoStore extends HiddenAmountsStore {
  const _NoStore();
  @override
  Future<void> write(bool hidden) async {}
}

/// Lo que responde el servidor en cada prueba. Por defecto: plan listo y todo cargado.
class _Server {
  final repo = FakeHomeRepository();
  Future<WelcomeStatus> Function() status = () async => statusOf();
  int statusCalls = 0;

  /// Lo que responde «Ahora no» de la invitación.
  Future<void> Function() answer = () async {};
  DateTime now = DateTime(2026, 11, 12, 10);
}

/// De la bienvenida, el Inicio solo usa «Ahora no».
class _Answers implements OnboardingRepository {
  _Answers(this.server);
  final _Server server;

  @override
  bool get isDemo => false;

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) => server.answer();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Los textos de assets/l10n, los mismos que carga la app.
Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

/// Varios cuadros con tiempo: los esqueletos y Rin se mueven sin parar y `pumpAndSettle` no acaba.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// El Inicio con un router mínimo: cualquier destino es un marcador con su ruta.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool dark = false,
  bool hidden = false,
  String language = 'es',
  bool reduceMotion = false,
  Session session = _session,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget marker(BuildContext _, GoRouterState state) => Scaffold(body: Text('RUTA ${state.uri}'));
  final router = GoRouter(
    initialLocation: Routes.app,
    routes: [
      GoRoute(path: Routes.app, builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/app/:a', builder: marker),
      GoRoute(path: '/app/:a/:b', builder: marker),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(apiBaseUrl: '', environment: 'local', demoMode: session.demo),
        ),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
        homeRepositoryProvider.overrideWithValue(server.repo),
        onboardingRepositoryProvider.overrideWithValue(_Answers(server)),
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        welcomeStatusProvider.overrideWith((ref, _) {
          server.statusCalls++;
          return server.status();
        }),
        clockProvider.overrideWithValue(() => server.now),
        initialRegionProvider.overrideWithValue(Region(country: 'CO', currency: 'COP', language: language)),
        translationsProvider.overrideWithValue(_translations()),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        hiddenAmountsStoreProvider.overrideWithValue(const _NoStore()),
        tourSeenStoreProvider.overrideWithValue(MemoryTourSeenStore()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: dark ? RindeTheme.dark : RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
          child: child!,
        ),
      ),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
}

/// Todo lo que el Inicio escribe: textos en pantalla y etiquetas para el lector de pantalla.
List<String> _written(WidgetTester tester, [Finder? within]) => [
  for (final widget
      in within == null
          ? tester.allWidgets
          : tester.widgetList(find.descendant(of: within, matching: find.byWidgetPredicate((_) => true))))
    ...switch (widget) {
      Text(:final data, :final textSpan, :final semanticsLabel) => [
        data ?? textSpan!.toPlainText(),
        ?semanticsLabel,
      ],
      RichText(:final text) => [text.toPlainText()],
      Semantics(:final properties) => [?properties.label, ?properties.value],
      _ => const <String>[],
    },
];

Finder _inside(Finder of, Finder matching) => find.descendant(of: of, matching: matching);

/// Toca algo del Inicio (subiéndolo a la vista) y devuelve a dónde llevó.
Future<void> _tapAndExpectRoute(WidgetTester tester, Finder target, String route) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _settle(tester);
  expect(find.text('RUTA $route'), findsOneWidget, reason: route);
}

final _hero = find.byType(HeroCard);

void main() {
  group('la tarjeta grande', () {
    testWidgets('mientras carga: un solo esqueleto violeta que dice «Cargando…», sin cifras', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server()..status = () => Completer<WelcomeStatus>().future;
      await _pump(tester, server);

      expect(_hero, findsOneWidget);
      expect(_inside(_hero, find.bySemanticsLabel('Cargando…')), findsOneWidget);
      expect(_inside(_hero, find.byType(RindeSkeleton)), findsWidgets);
      expect(_inside(_hero, find.byType(Text)), findsNothing);
      expect(_written(tester, _hero).where((text) => text.contains(RegExp(r'\d'))), isEmpty);
      // Aún no se sabe si hay con qué corregir ni qué avisar.
      expect(find.textContaining('Corrígela'), findsNothing);
      expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
      // No se toca: no hay a dónde ir todavía.
      await tester.tap(_hero);
      await _settle(tester);
      expect(find.textContaining('RUTA'), findsNothing);
      handle.dispose();
    });

    testWidgets('libre para gastar: la cifra del servidor, por día, el detalle y lleva a Mi plata', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Server());

      expect(find.text('LIBRE PARA GASTAR · ESTIMADO'), findsOneWidget);
      expect(_inside(_hero, find.text(_m(139300))), findsOneWidget);
      expect(find.text('Más o menos ${_m(13900)} al día hasta el 30 de noviembre'), findsOneWidget);
      expect(
        find.text('De ${_m(412300)} que tienes, ${_m(273000)} ya están apartados para pagos.'),
        findsOneWidget,
      );
      expect(find.text('¿De dónde sale?'), findsOneWidget);
      // Con plan no hay «Mi plata · mes» ni la línea de hasta cuándo alcanza.
      expect(find.byType(RindeLine), findsNothing);

      final card = tester.getSemantics(_inside(_hero, find.byType(HomeTap)));
      expect(card, isSemantics(isButton: true, hasTapAction: true));
      expect(card.label, startsWith('Libre para gastar · estimado: ${_m(139300)}.'));
      expect(card.label, endsWith(', ver Mi plata'));

      await _tapAndExpectRoute(tester, _hero, Routes.myMoney);
      handle.dispose();
    });

    testWidgets('sin modo diario, o sin la cifra o la fecha, no hay línea «al día»', (tester) async {
      for (final plan in [
        const MoneyPlan(
          money: 412300,
          pendingTotal: 273000,
          free: 139300,
          shortfall: 0,
          mode: 'goal',
          perDay: 13900,
          nextPay: '2026-11-30',
        ),
        const MoneyPlan(money: 412300, pendingTotal: 273000, free: 139300, shortfall: 0, mode: 'daily'),
      ]) {
        final server = _Server()..repo.onPlan = () async => plan;
        await _pump(tester, server);
        expect(_inside(_hero, find.text(_m(139300))), findsOneWidget);
        expect(find.textContaining('al día'), findsNothing, reason: plan.mode);
        // Un dato que no llegó no se pinta como cero.
        expect(_written(tester, _hero).where((text) => text.contains(_m(0))), isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('no alcanza: dice cuánto falta, en positivo; ningún número bajo cero', (tester) async {
      final server = _Server()
        ..status = (() async => statusOf(money: 223000))
        ..repo.onPlan = () async =>
            planOf(money: 223000, pendingTotal: 273000, free: -50000, shortfall: 50000, pending: const []);
      await _pump(tester, server);

      expect(find.text('TE FALTAN · ESTIMADO'), findsOneWidget);
      final amount = tester.widget<Text>(_inside(_hero, find.text(_m(50000))));
      expect(amount.style!.color, RindePalette.light.negative);
      expect(find.text('para tus pagos. Tienes ${_m(223000)} y vencen ${_m(273000)}.'), findsOneWidget);
      expect(find.textContaining('al día'), findsNothing);
      // «Libre» en negativo nunca se pinta como plata para gastar.
      expect(_written(tester).where((text) => text.contains('-')), isEmpty);
      expect(find.text('Revisa tus gastos'), findsNothing);
    });

    testWidgets('en negativo: la plata con su signo y la salida a revisar los gastos, sin repetir la nota', (
      tester,
    ) async {
      final server = _Server()
        ..status = (() async => statusOf(money: -20000))
        ..repo.onPlan = () async =>
            planOf(money: -20000, pendingTotal: 273000, free: -293000, shortfall: 293000, pending: const []);
      await _pump(tester, server);

      expect(find.text('ESTÁS EN NEGATIVO · ESTIMADO'), findsOneWidget);
      expect(_m(-20000), contains('-'));
      expect(_inside(_hero, find.text(_m(-20000))), findsOneWidget);
      // La tarjeta ya lo dice: la nota de saldo negativo no sale otra vez.
      expect(find.text('Tus gastos superan lo que tienes. ¿Anotaste algo mal?'), findsOneWidget);
      expect(find.text(_m(293000)), findsNothing);

      await _tapAndExpectRoute(tester, find.text('Revisa tus gastos'), Routes.expenses);
    });

    testWidgets('sin plan: Mi plata con hasta cuándo alcanza y el acceso para configurarla', (tester) async {
      final server = _Server()..repo.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester, server);

      expect(find.text('MI PLATA · NOVIEMBRE'), findsOneWidget);
      expect(_inside(_hero, find.text(_m(412300))), findsOneWidget);
      // 412.300 × 12 ÷ 287.700 = 17 días; quedan 18 del mes.
      expect(find.text('Te alcanza 17 días más'), findsOneWidget);
      expect(find.text('hasta el 29 nov'), findsOneWidget);
      final line = tester.widget<RindeLine>(find.byType(RindeLine));
      expect(line.tone, RindeLineTone.brand);
      expect(line.height, 4);
      expect(line.value, closeTo(17 / 18, 1e-9));
      expect(find.text('Lo próximo'), findsNothing);
      expect(find.text('¿No es tu plata real? Corrígela'), findsOneWidget);

      await _tapAndExpectRoute(tester, find.text('¿Cuánta plata tienes hoy?'), Routes.myMoney);
    });

    testWidgets(
      'sin plan: alcanza para todo el mes, un solo día, calculando, sin datos y sin gastos del mes',
      (tester) async {
        Future<void> check(
          _Server server, {
          List<String> shows = const [],
          List<String> hides = const [],
        }) async {
          server.repo.onPlan = () async => const MoneyPlan.notReady();
          await _pump(tester, server);
          expect(_inside(_hero, find.text(_m(412300))), findsOneWidget);
          for (final text in shows) {
            expect(find.text(text), findsOneWidget, reason: text);
          }
          for (final text in hides) {
            expect(find.textContaining(text), findsNothing, reason: text);
          }
          await tester.pumpWidget(const SizedBox());
        }

        await check(
          _Server()..repo.onTotals = (_) async => totalsOf(expense: 1000),
          shows: ['Te alcanza para todo el mes', 'pasa el fin de mes'],
        );
        // 412.300 × 12 ÷ 4.000.000 = 1,2.
        await check(
          _Server()..repo.onTotals = (_) async => totalsOf(expense: 4000000),
          shows: ['Te alcanza 1 día más', 'hasta el 13 nov'],
        );
        await check(
          _Server()..repo.onTotals = (_) => Completer<MonthTotals>().future,
          shows: ['Calculando hasta cuándo te alcanza…'],
          hides: ['Anota tu primer ingreso'],
        );
        await check(
          _Server()..repo.onTotals = (_) async => totalsOf(expense: 0),
          shows: ['Anota tu primer ingreso para saber hasta cuándo te alcanza.'],
        );
        // Los gastos del mes no llegaron: no se dice nada sobre hasta cuándo alcanza.
        await check(
          _Server()..repo.onTotals = (_) async => throw serverError,
          hides: ['Te alcanza', 'Calculando', 'Anota tu primer ingreso'],
        );
      },
    );

    testWidgets('saldo bajo cero sin plan: la nota lleva a revisar los gastos', (tester) async {
      final server = _Server()
        ..status = (() async => statusOf(money: -5000))
        ..repo.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester, server);

      expect(_inside(_hero, find.text(_m(-5000))), findsOneWidget);
      await _tapAndExpectRoute(
        tester,
        find.textContaining('¿Anotaste algo mal? Revisa tus gastos'),
        Routes.expenses,
      );
    });

    testWidgets('el servidor no sabe cuánta plata hay: raya y el porqué, nunca un cero', (tester) async {
      final server = _Server()
        ..status = (() async => statusOf(money: null, balanceSet: false))
        ..repo.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester, server);

      expect(_inside(_hero, find.text('—')), findsOneWidget);
      expect(find.text('Todavía no sabemos cuánta plata tienes.'), findsOneWidget);
      expect(_written(tester, _hero).where((text) => text.contains(RegExp(r'\d'))), isEmpty);
      expect(_written(tester).where((text) => text.contains(_m(0))), isEmpty);

      await _tapAndExpectRoute(
        tester,
        find.text('¿Ya tenías plata cuando empezaste? Dinos cuánta tienes hoy'),
        Routes.fixBalance,
      );
    });

    testWidgets('sin conexión: raya, nota de sin conexión y «Reintentar» trae los datos', (tester) async {
      final handle = tester.ensureSemantics();
      var online = false;
      final server = _Server();
      server
        ..status = (() async => online ? statusOf() : throw offlineError)
        ..repo.onPlan = (() async => online ? planOf() : throw offlineError)
        ..repo.onTotals = ((_) async => online ? totalsOf() : throw offlineError);
      await _pump(tester, server);

      expect(_inside(_hero, find.text('—')), findsOneWidget);
      expect(find.text('No pudimos traer tu plata porque no hay conexión.'), findsOneWidget);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.textContaining('al volver internet'), findsNothing, reason: 'no promete actualizarse solo');
      expect(tester.getSemantics(find.text('Sin conexión')), isSemantics(isLiveRegion: true));
      expect(find.text('Reintentar'), findsOneWidget, reason: 'sin cifra lo trae la tarjeta, y solo ella');
      // Sin conexión no es un error del servidor: no sale el aviso flotante.
      expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
      expect(_written(tester).where((text) => text.contains(RegExp(r'\d'))), isEmpty);
      // La tarjeta sin cifra no lleva a ninguna parte.
      await tester.tap(_inside(_hero, find.text('—')));
      await _settle(tester);
      expect(find.textContaining('RUTA'), findsNothing);

      online = true;
      await tester.tap(find.text('Reintentar'));
      await _settle(tester);
      expect(_inside(_hero, find.text(_m(139300))), findsOneWidget);
      expect(find.text('Sin conexión'), findsNothing);
      handle.dispose();
    });

    testWidgets('sin conexión con cifras ya traídas: la nota trae su propio «Reintentar»', (tester) async {
      var online = true;
      final server = _Server();
      server
        ..status = (() async => online ? statusOf() : throw offlineError)
        ..repo.onTotals = ((_) async => online ? totalsOf() : throw offlineError);
      final container = await _pump(tester, server);

      online = false;
      container.invalidate(welcomeStatusProvider);
      await _settle(tester);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(_inside(_hero, find.text('Reintentar')), findsNothing);
      expect(tester.getSize(find.widgetWithText(HomeLink, 'Reintentar')).height, greaterThanOrEqualTo(48));

      online = true;
      await tester.tap(find.text('Reintentar'));
      await _settle(tester);
      expect(find.text('Sin conexión'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('sin los totales del mes, lo que oye el lector no queda con «. ,»', (tester) async {
      final server = _Server()
        ..status = (() async => statusOf(money: 650000))
        ..repo.onPlan = (() async => const MoneyPlan.notReady())
        ..repo.onTotals = (_) async => throw serverError;
      await _pump(tester, server);
      expect(_written(tester, _hero), contains('Mi plata · noviembre: ${_m(650000)}, ver Mi plata'));
    });

    testWidgets('el rótulo llega a 4,5:1 también donde lo cruza el aro', (tester) async {
      for (final ready in [true, false]) {
        final server = _Server();
        if (!ready) server.repo.onPlan = () async => const MoneyPlan.notReady();
        await _pump(tester, server);
        final ring = tester
            .widgetList<DecoratedBox>(_inside(_hero, find.byType(DecoratedBox)))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .singleWhere((decoration) => decoration.shape == BoxShape.circle && decoration.border != null)
            .border!
            .top
            .color;
        final under = Color.alphaBlend(ring, RindeBrand.violet);
        final title = ready ? 'LIBRE PARA GASTAR · ESTIMADO' : 'MI PLATA · NOVIEMBRE';
        final text = Color.alphaBlend(tester.widget<Text>(find.text(title)).style!.color!, under);
        final contrast = (text.computeLuminance() + 0.05) / (under.computeLuminance() + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: title);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('con el teclado, el foco se ve por fuera de la tarjeta violeta', (tester) async {
      await _pump(tester, _Server());
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      BorderSide? ring() => tester
          .widgetList<DecoratedBox>(_inside(_hero, find.byType(DecoratedBox)))
          .where((box) => box.position == DecorationPosition.foreground)
          .map((box) => (box.decoration as BoxDecoration).border?.top)
          .first;
      for (var i = 0; i < 10 && ring() == null; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final side = ring();
      expect(side, isNotNull, reason: 'el tabulador llega a la tarjeta');
      expect(side!.color, RindePalette.light.brand);
      // El borde de adentro del anillo queda 2 px por fuera de la tarjeta.
      expect(side.strokeInset, -2);
    });

    testWidgets('falla del servidor: raya, aviso flotante y «Reintentar» vuelve a pedir todo', (
      tester,
    ) async {
      var broken = true;
      final server = _Server();
      server.status = () async => broken ? throw serverError : statusOf();
      // Sin plan tampoco: un plan que llega se muestra aunque falle el perfil.
      server.repo.onPlan = () async => broken ? throw serverError : planOf();
      await _pump(tester, server);

      expect(_inside(_hero, find.text('—')), findsOneWidget);
      expect(find.text('No pudimos traer tu plata.'), findsOneWidget);
      expect(find.text('No pudimos traer todos tus datos.'), findsOneWidget);
      expect(find.textContaining('solos'), findsNothing, reason: 'no promete reintentos automáticos');
      expect(_written(tester, _hero).where((text) => text.contains(RegExp(r'\d'))), isEmpty);

      broken = false;
      final before = (server.statusCalls, server.repo.count('plan'), server.repo.count('unread'));
      // El del aviso flotante es el último «Reintentar».
      await tester.tap(find.text('Reintentar').last);
      await _settle(tester);
      expect(server.statusCalls, before.$1 + 1);
      expect(server.repo.count('plan'), before.$2 + 1);
      expect(server.repo.count('unread'), before.$3 + 1);
      expect(_inside(_hero, find.text(_m(139300))), findsOneWidget);
      expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('la sesión venció: no sale el aviso de error (el router ya lleva al login)', (tester) async {
      final server = _Server()
        ..repo.onTotals = (_) async => throw const ApiException(code: ApiCodes.tokenExpired, status: 401);
      await _pump(tester, server);
      expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
    });
  });

  group('este mes', () {
    testWidgets('ingresos con «+» y en verde, gastos sin signo; cada uno lleva a su detalle', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Server());

      expect(tester.getSemantics(find.text('Este mes')), isSemantics(isHeader: true));
      final income = tester.widget<Text>(find.text('+ ${_m(700000)}'));
      expect(income.style!.color, RindePalette.light.positive);
      expect(income.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.text(_m(287700)), findsOneWidget);
      expect(find.bySemanticsLabel('Ingresos: + ${_m(700000)}, ver ingresos de noviembre'), findsOneWidget);
      expect(find.bySemanticsLabel('Gastos: ${_m(287700)}, ver gastos de noviembre'), findsOneWidget);

      await _tapAndExpectRoute(tester, find.text('INGRESOS'), Routes.income);
      handle.dispose();
    });

    testWidgets('gastos lleva a Gastos', (tester) async {
      await _pump(tester, _Server());
      await _tapAndExpectRoute(tester, find.text('GASTOS'), Routes.expenses);
    });

    testWidgets('cargando: esqueletos, sin cifra ni cero', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server()..repo.onTotals = (_) => Completer<MonthTotals>().future;
      await _pump(tester, server);

      final section = find.byType(MonthSection);
      expect(_inside(section, find.byType(RindeSkeleton)), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('^Ingresos: Cargando…')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Gastos: Cargando…')), findsOneWidget);
      expect(_written(tester, section).where((text) => text.contains(RegExp(r'\d'))), isEmpty);
      handle.dispose();
    });

    testWidgets('falló: raya en vez de cifra, y se dice', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server()..repo.onTotals = (_) async => throw serverError;
      await _pump(tester, server);

      final section = find.byType(MonthSection);
      expect(_inside(section, find.text('—')), findsNWidgets(2));
      expect(_inside(section, find.byType(RindeSkeleton)), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Ingresos: No se pudo cargar')), findsOneWidget);
      expect(_written(tester, section).where((text) => text.contains(RegExp(r'\d'))), isEmpty);
      handle.dispose();
    });

    testWidgets('la cifra se achica con el largo y nunca se corta', (tester) async {
      final server = _Server()
        ..repo.onTotals = (_) async => totalsOf(income: 9999999999.99, expense: 12345678);
      await _pump(tester, server);

      final income = tester.widget<Text>(find.text('+ ${_m(9999999999.99)}'));
      expect(income.style!.fontSize, 15);
      expect(income.overflow, isNull);
      expect(income.maxLines, 1);
      // «$ 12.345.678» tiene 12 caracteres: tamaño medio.
      expect(tester.widget<Text>(find.text(_m(12345678))).style!.fontSize, 18);
    });

    testWidgets('por confirmar: singular, plural, lleva a la lista y no sale en cero ni si falla', (
      tester,
    ) async {
      await _pump(tester, _Server()..repo.onToConfirm = () async => 1);
      expect(find.text('1 pago que llegó solo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _Server()..repo.onToConfirm = () async => throw serverError);
      expect(find.text('Por confirmar'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _Server());
      expect(find.text('Por confirmar'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _Server()..repo.onToConfirm = () async => 3);
      expect(find.text('3 pagos que llegaron solos'), findsOneWidget);
      await _tapAndExpectRoute(tester, find.text('Por confirmar'), Routes.toConfirm);
    });
  });

  group('lo próximo', () {
    testWidgets('como mucho dos pagos, con fecha y monto, y «Ver pagos»', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Server());

      expect(tester.getSemantics(find.text('Lo próximo')), isSemantics(isHeader: true));
      final section = find.byType(NextPayments);
      expect(_inside(section, find.text('PILA')), findsOneWidget);
      expect(_inside(section, find.text('13 de noviembre')), findsOneWidget);
      expect(_inside(section, find.text(_m(228000))), findsOneWidget);
      expect(_inside(section, find.text('Plan celular')), findsOneWidget);
      expect(_inside(section, find.text(_m(45000))), findsOneWidget);
      // El tercero queda para «Ver pagos».
      expect(_inside(section, find.text(_m(180000))), findsNothing);
      expect(find.textContaining('Venció'), findsNothing);

      await _tapAndExpectRoute(tester, find.text('Ver pagos'), Routes.payments);
      handle.dispose();
    });

    testWidgets('un pago con la fecha pasada dice que venció, en rojo; el de hoy no', (tester) async {
      final server = _Server()..now = DateTime(2026, 11, 15, 8);
      await _pump(tester, server);

      final overdue = tester.widget<Text>(find.text('Venció el 13 de noviembre'));
      expect(overdue.style!.color, RindePalette.light.negative);
      final today = tester.widget<Text>(find.text('15 de noviembre'));
      expect(today.style!.color, RindePalette.light.inkMuted);
    });

    for (final language in ['es', 'en', 'pt']) {
      testWidgets('320 con letra al doble en $language: en una columna y sin partir palabras', (
        tester,
      ) async {
        await _pump(tester, _Server(), size: const Size(320, 568), textScale: 2, language: language);
        final block = find.byType(NextPayments);
        for (final element in _inside(block, find.byType(RichText)).evaluate()) {
          final text = element.renderObject! as RenderParagraph;
          expect(
            text.getMinIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(text.constraints.maxWidth + 0.01),
            reason: text.text.toPlainText(),
          );
        }
        final name = _inside(block, find.text('PILA'));
        final amount = _inside(block, find.text(_m(228000)));
        expect(tester.getTopLeft(amount).dy, greaterThan(tester.getBottomLeft(name).dy));
        final header = _inside(block, find.byType(HomeSectionTitle));
        final link = _inside(block, find.byType(HomeLink));
        expect(tester.getTopLeft(link).dy, greaterThanOrEqualTo(tester.getBottomLeft(header).dy));
      });
    }

    testWidgets('sin pagos pendientes no sale el bloque', (tester) async {
      await _pump(tester, _Server()..repo.onPlan = () async => planOf(pending: const []));
      expect(find.text('Lo próximo'), findsNothing);
      expect(find.text('Ver pagos'), findsNothing);
    });
  });

  group('el aviso', () {
    Future<void> expectNotice(
      WidgetTester tester,
      _Server server, {
      required String title,
      required String detail,
      required String route,
    }) async {
      await _pump(tester, server);
      final notice = find.byType(HomeNoticeCard);
      expect(notice, findsOneWidget);
      expect(_inside(notice, find.text(title)), findsOneWidget, reason: title);
      expect(_inside(notice, find.text(detail)), findsOneWidget, reason: detail);
      await _tapAndExpectRoute(tester, notice, route);
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('tarjeta: atrasada, hoy, mañana, en N días, y la red «otra» usa el nombre de la tarjeta', (
      tester,
    ) async {
      _Server cards(CardSummary card) => _Server()..repo.onCards = () async => [card];
      await expectNotice(
        tester,
        cards(cardOf(-2)),
        title: 'Tu Visa ••4242 tiene el pago atrasado',
        detail: 'Debes ${_m(320000)}',
        route: Routes.card('7'),
      );
      await expectNotice(
        tester,
        cards(cardOf(0)),
        title: 'Tu Visa ••4242 se paga hoy',
        detail: 'Debes ${_m(320000)}',
        route: Routes.card('7'),
      );
      await expectNotice(
        tester,
        cards(cardOf(1)),
        title: 'Tu Visa ••4242 se paga mañana',
        detail: 'Debes ${_m(320000)}',
        route: Routes.card('7'),
      );
      await expectNotice(
        tester,
        cards(cardOf(10, id: '9')),
        title: 'Tu Visa ••4242 se paga en 10 días',
        detail: 'Debes ${_m(320000)}',
        route: Routes.card('9'),
      );
      await expectNotice(
        tester,
        cards(
          const CardSummary(
            id: '3',
            name: 'La del banco',
            network: 'otra',
            last4: '1234',
            used: 90000,
            daysToPayment: 2,
            paidThisCycle: false,
          ),
        ),
        title: 'Tu La del banco ••1234 se paga en 2 días',
        detail: 'Debes ${_m(90000)}',
        route: Routes.card('3'),
      );
    });

    testWidgets('presupuesto: pasado y cerca del límite, con el nombre traducido de la categoría', (
      tester,
    ) async {
      await expectNotice(
        tester,
        _Server()..repo.onBudgets = () async => [budgetOf(BudgetLevel.exceeded, consumed: 540000)],
        title: 'Te pasaste en Vivienda',
        detail: 'Llevas ${_m(540000)} de ${_m(450000)}',
        route: Routes.budgets,
      );
      await expectNotice(
        tester,
        _Server()..repo.onBudgets = () async => [budgetOf(BudgetLevel.warning)],
        title: 'Vivienda ya casi llega al límite',
        detail: 'Quedan ${_m(50000)}',
        route: Routes.budgets,
      );
      // Sin el nombre traducido se usa la clave, como la web.
      await expectNotice(
        tester,
        _Server()
          ..repo.onBudgets = (() async => [budgetOf(BudgetLevel.warning, category: 'mascotas')])
          ..repo.onCategoryNames = () async => throw serverError,
        title: 'mascotas ya casi llega al límite',
        detail: 'Quedan ${_m(50000)}',
        route: Routes.budgets,
      );
    });

    testWidgets('sin tarjetas ni presupuestos que avisar no hay aviso', (tester) async {
      await _pump(tester, _Server());
      expect(find.byType(HomeNoticeCard), findsNothing);
    });
  });

  group('el pie', () {
    testWidgets('bienvenida sin responder: la invitación', (tester) async {
      final server = _Server()
        ..status = (() async => statusOf(welcomeDone: false))
        ..repo.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester, server);
      expect(find.byType(MoneyInviteCard), findsOneWidget);
      expect(find.byType(MoneySetupLink), findsNothing);
    });

    testWidgets('«Ahora no» guardado se quita aunque falle volver a cargar, sin quedarse girando', (
      tester,
    ) async {
      var saved = false;
      final server = _Server()
        ..status = (() async => saved ? throw offlineError : statusOf(welcomeDone: false))
        ..repo.onPlan = (() async => const MoneyPlan.notReady())
        ..answer = () async => saved = true;
      await _pump(tester, server);
      await tester.ensureVisible(find.text('Ahora no'));
      await tester.pump();
      await tester.tap(find.text('Ahora no'));
      await _settle(tester);

      expect(saved, isTrue);
      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('Responder'), findsNothing);
      expect(find.text('Sin conexión'), findsOneWidget, reason: 'el fallo de la recarga sí se dice');
    });

    testWidgets('bienvenida hecha y plan sin armar: el acceso a Mi plata', (tester) async {
      await _pump(tester, _Server()..repo.onPlan = () async => const MoneyPlan.notReady());
      expect(find.byType(MoneySetupLink), findsOneWidget);
      expect(find.byType(MoneyInviteCard), findsNothing);
    });

    testWidgets('con plan listo no hay pie; y un aviso le gana a la invitación', (tester) async {
      await _pump(tester, _Server());
      expect(find.byType(MoneySetupLink), findsNothing);
      expect(find.byType(MoneyInviteCard), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final server = _Server()
        ..status = (() async => statusOf(welcomeDone: false))
        ..repo.onPlan = (() async => const MoneyPlan.notReady())
        ..repo.onCards = () async => [cardOf(1)];
      await _pump(tester, server);
      expect(find.byType(HomeNoticeCard), findsOneWidget);
      expect(find.byType(MoneyInviteCard), findsNothing);
    });
  });

  group('sin movimientos', () {
    Future<void> pumpEmpty(WidgetTester tester) =>
        _pump(tester, _Server()..status = () async => statusOf(hasTransactions: false));

    testWidgets('saluda Rin (decorativo, una vez) con una acción clara', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpEmpty(tester);

      final rin = tester.widget<Rin>(find.byType(Rin));
      expect(rin.emotion, RinEmotion.tranquilo);
      expect(rin.gesture, RinGesture.saludar);
      expect(rin.semanticLabel, isNull);
      expect(tester.getSize(find.byType(Rin)).height, 96);
      expect(
        tester.getSemantics(find.text('Todavía no has anotado nada este mes')),
        isSemantics(isHeader: true),
      );
      await _tapAndExpectRoute(tester, find.text('Anotar mi primer gasto'), Routes.recordExpense);
      handle.dispose();
    });

    testWidgets('Rin saluda una vez por sesión de la app y después queda quieto', (tester) async {
      final server = _Server()..status = () async => statusOf(hasTransactions: false);
      final container = await _pump(tester, server);
      bool moving() => tester.widget<Rin>(find.byType(Rin)).animate;
      expect(moving(), isTrue);
      expect(
        tester.element(find.byType(Rin)).findAncestorWidgetOfExactType<RepaintBoundary>()?.child,
        isA<SizedBox>().having((box) => box.height, 'alto', 96),
        reason: 'mientras se mueve no repinta el Inicio',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(moving(), isFalse);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      // La tarjeta se va y vuelve (como al recargar o al cambiar de pestaña): no saluda otra vez.
      server.status = () async => statusOf();
      container.invalidate(welcomeStatusProvider);
      await _settle(tester);
      expect(find.byType(Rin), findsNothing);
      server.status = () async => statusOf(hasTransactions: false);
      container.invalidate(welcomeStatusProvider);
      await _settle(tester);
      expect(moving(), isFalse);
    });

    testWidgets('411 × 914: sin hueco encima de Rin', (tester) async {
      await _pump(
        tester,
        _Server()..status = () async => statusOf(hasTransactions: false),
        size: const Size(411, 914),
      );
      final rin = find.byType(Rin);
      // El lienzo con pila deja arriba una tercera parte vacía; aquí no hay billetes que mostrar.
      expect(tester.widget<Rin>(rin).compact, isTrue);
      expect(tester.getTopLeft(rin).dy - tester.getTopLeft(find.byType(HomeEmpty)).dy, lessThanOrEqualTo(24));
    });

    testWidgets('las otras dos salidas: anotar un ingreso y conectar WhatsApp', (tester) async {
      await pumpEmpty(tester);
      await _tapAndExpectRoute(tester, find.text('O anota lo que te entró'), Routes.recordIncome);
      await tester.pumpWidget(const SizedBox());
      await pumpEmpty(tester);
      await _tapAndExpectRoute(tester, find.text('O conecta WhatsApp y anota desde el chat'), Routes.account);
    });

    testWidgets('con movimientos Rin no aparece en el Inicio', (tester) async {
      await _pump(tester, _Server());
      expect(find.byType(Rin), findsNothing);
      expect(find.text('Anotar mi primer gasto'), findsNothing);
    });
  });

  group('encabezado', () {
    testWidgets('la campana lleva a los avisos y la insignia se queda en «9+»', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Server()..repo.onUnread = () async => 12);

      expect(find.text('9+'), findsOneWidget);
      expect(find.bySemanticsLabel('Rinde'), findsOneWidget);
      final bell = find.bySemanticsLabel('Notificaciones, 12 sin leer');
      expect(tester.getSemantics(bell), isSemantics(isButton: true, hasTapAction: true));
      await _tapAndExpectRoute(tester, bell, Routes.notifications);
      handle.dispose();
    });

    testWidgets('sin avisos, o si no llegan, no hay insignia', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Server());
      expect(find.bySemanticsLabel('Notificaciones'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _Server()..repo.onUnread = () async => throw serverError);
      expect(find.bySemanticsLabel('Notificaciones'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      handle.dispose();
    });
  });

  group('montos ocultos', () {
    _Server rich() => _Server()
      ..repo.onBudgets = (() async => [budgetOf(BudgetLevel.exceeded, consumed: 540000)])
      ..repo.onToConfirm = (() async => 2)
      ..repo.onUnread = () async => 3;

    /// Tres cifras seguidas: todo monto del ejemplo las tiene; las fechas y los conteos no.
    final digits = RegExp(r'\d{3}');

    testWidgets('no queda ni un dígito de ningún monto, ni en pantalla ni para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, rich(), hidden: true);

      expect(_written(tester).where(digits.hasMatch), isEmpty);
      expect(find.bySemanticsLabel(digits), findsNothing);
      // El lector dice «Monto oculto», no la moneda con seis viñetas.
      expect(find.bySemanticsLabel(RegExp('•')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Monto oculto')), findsWidgets);
      final card = tester.getSemantics(_inside(_hero, find.byType(HomeTap)));
      expect(card.label, startsWith('Libre para gastar · estimado: Monto oculto.'));
      expect(find.bySemanticsLabel('Ingresos: + Monto oculto, ver ingresos de noviembre'), findsOneWidget);
      // En pantalla, la máscara con la moneda del país.
      expect(_inside(_hero, find.text('${_co.prefix}••••••${_co.suffix}')), findsOneWidget);
      expect(
        find.text('Llevas ${_co.prefix}••••••${_co.suffix} de ${_co.prefix}••••••${_co.suffix}'),
        findsOneWidget,
      );
      // Lo que no es un monto sigue a la vista.
      expect(find.text('13 de noviembre'), findsOneWidget);
      expect(find.text('2 pagos que llegaron solos'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('también sin plan: Mi plata y la nota de saldo negativo', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server()
        ..status = (() async => statusOf(money: -412300))
        ..repo.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester, server, hidden: true);

      expect(_written(tester).where(digits.hasMatch), isEmpty);
      expect(find.bySemanticsLabel(digits), findsNothing);
      // Oculto tampoco se ve el signo.
      expect(_written(tester).where((text) => text.contains('-')), isEmpty);
      handle.dispose();
    });

    testWidgets('el botón cambia de una vez (sin animar cifras) y dice su estado', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await _pump(tester, rich());

      expect(find.byType(AnimatedSwitcher), findsNothing);
      final hide = find.bySemanticsLabel('Ocultar montos');
      expect(tester.getSemantics(hide), isSemantics(isButton: true, hasToggledState: true, isToggled: false));
      await tester.tap(hide);
      // Un solo cuadro: ya no queda ninguna cifra, ni saliendo.
      await tester.pump();
      expect(container.read(hiddenAmountsProvider), isTrue);
      expect(_written(tester).where(digits.hasMatch), isEmpty);
      expect(find.bySemanticsLabel(digits), findsNothing);

      final show = find.bySemanticsLabel('Mostrar montos');
      expect(tester.getSemantics(show), isSemantics(hasToggledState: true, isToggled: true));
      await tester.tap(show);
      await tester.pump();
      expect(_inside(_hero, find.text(_m(139300))), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ningún monto va en una región viva', (tester) async {
      final handle = tester.ensureSemantics();
      final server = rich()..repo.onTotals = (_) async => throw serverError;
      await _pump(tester, server);

      // El aviso de error sí se anuncia solo; las cifras nunca.
      final live = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.liveRegion == true);
      expect(live, isNotEmpty);
      for (final region in live) {
        expect(
          _written(tester, find.byWidget(region)).where((text) => text.contains(RegExp(r'\d'))),
          isEmpty,
        );
      }
      handle.dispose();
    });
  });

  group('idiomas', () {
    testWidgets('en inglés', (tester) async {
      await _pump(tester, _Server(), language: 'en');
      expect(find.text('FREE TO SPEND · ESTIMATE'), findsOneWidget);
      expect(find.text('About ${_m(13900)} a day until November 30'), findsOneWidget);
      expect(
        find.text('Of the ${_m(412300)} you have, ${_m(273000)} is already set aside for payments.'),
        findsOneWidget,
      );
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('November 13'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('INCOME'), findsOneWidget);
      expect(find.text('LIBRE PARA GASTAR · ESTIMADO'), findsNothing);
    });

    testWidgets('en portugués', (tester) async {
      await _pump(tester, _Server(), language: 'pt');
      expect(find.text('LIVRE PARA GASTAR · ESTIMATIVA'), findsOneWidget);
      expect(find.text('Mais ou menos ${_m(13900)} por dia até 30 de novembro'), findsOneWidget);
      expect(find.text('O próximo'), findsOneWidget);
      expect(find.text('13 de novembro'), findsOneWidget);
      expect(find.text('Este mês'), findsOneWidget);
      expect(find.text('RECEITAS'), findsOneWidget);
    });

    testWidgets('sin plan en inglés: el mes y hasta cuándo alcanza', (tester) async {
      await _pump(tester, _Server()..repo.onPlan = () async => const MoneyPlan.notReady(), language: 'en');
      expect(find.text('MY MONEY · NOVEMBER'), findsOneWidget);
      expect(find.text('It lasts 17 days more'), findsOneWidget);
      expect(find.text('until Nov 29'), findsOneWidget);
    });
  });

  group('pantalla pequeña, letra grande y tema oscuro', () {
    const big = 9999999999.99;
    final longPlan = MoneyPlan(
      money: big,
      pendingTotal: big,
      free: big,
      shortfall: 0,
      mode: 'daily',
      perDay: big,
      nextPay: '2026-11-30',
      pending: const [
        PendingPayment(
          id: 'a',
          name: 'Arriendo del apartamento de Chapinero con administración',
          amount: big,
          date: '2026-11-01',
        ),
        PendingPayment(id: 'b', name: 'PILA', amount: big, date: '2026-11-20'),
      ],
    );

    final states = <String, _Server Function()>{
      'plan con montos enormes, aviso y por confirmar': () => _Server()
        ..status = (() async => statusOf(money: big))
        ..repo.onPlan = (() async => longPlan)
        ..repo.onTotals = ((_) async => totalsOf(income: big, expense: big))
        ..repo.onBudgets = (() async => [
          budgetOf(BudgetLevel.exceeded, amount: big, consumed: big, percentage: 120),
        ])
        ..repo.onToConfirm = (() async => 12)
        ..repo.onUnread = () async => 40,
      'no alcanza': () =>
          _Server()
            ..repo.onPlan = () async => planOf(money: big, pendingTotal: big, free: -big, shortfall: big),
      'en negativo': () => _Server()
        ..status = (() async => statusOf(money: -big))
        ..repo.onPlan = () async => planOf(money: -big, pendingTotal: big, free: -big, shortfall: big),
      'Mi plata con invitación y tarjeta': () => _Server()
        ..status = (() async => statusOf(money: big, welcomeDone: false, balanceSet: false))
        ..repo.onPlan = (() async => const MoneyPlan.notReady())
        ..repo.onTotals = (_) async => totalsOf(income: big, expense: 4000000),
      'Mi plata en negativo con acceso a configurarla': () => _Server()
        ..status = (() async => statusOf(money: -big))
        ..repo.onPlan = () async => const MoneyPlan.notReady(),
      'sin movimientos y sin saldo': () => _Server()
        ..status = (() async => statusOf(money: null, hasTransactions: false, balanceSet: false))
        ..repo.onPlan = () async => const MoneyPlan.notReady(),
      'cargando': () => _Server()..status = () => Completer<WelcomeStatus>().future,
      'falla del servidor': () => _Server()
        ..status = (() async => throw serverError)
        ..repo.onTotals = (_) async => throw serverError,
      'sin conexión': () => _Server()
        ..status = (() async => throw offlineError)
        ..repo.onPlan = (() async => throw offlineError)
        ..repo.onTotals = (_) async => throw offlineError,
    };

    for (final MapEntry(key: name, value: build) in states.entries) {
      for (final dark in [false, true]) {
        testWidgets('$name, 320 × 568 con letra al doble${dark ? ', oscuro' : ''}: nada se desborda', (
          tester,
        ) async {
          // Un desborde hace fallar la prueba por sí solo.
          final container = await _pump(
            tester,
            build(),
            size: const Size(320, 568),
            textScale: 2,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
          // Y con los montos ocultos.
          container.read(hiddenAmountsProvider.notifier).toggle();
          await tester.pump();
          expect(tester.takeException(), isNull);
          // Todo lo que se toca mide al menos 48 de alto.
          for (final element in find.byType(HomeTap).evaluate()) {
            expect(element.size!.height, greaterThanOrEqualTo(48), reason: '${element.widget}');
          }
        });
      }
    }

    for (final language in ['es', 'pt']) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final size in [const Size(320, 568), const Size(568, 320)]) {
          testWidgets('$size, ×$scale, $language: el aviso de error no tapa lo último del Inicio', (
            tester,
          ) async {
            final server = _Server()..repo.onTotals = (_) async => throw serverError;
            await _pump(tester, server, size: size, textScale: scale, language: language);
            final scroll = tester.state<ScrollableState>(
              _inside(find.byType(SingleChildScrollView), find.byType(Scrollable)).first,
            );
            scroll.position.jumpTo(scroll.position.maxScrollExtent);
            await tester.pump();
            expect(tester.takeException(), isNull);
            final notice = find.byType(LoadErrorNotice);
            final last = tester.getBottomLeft(find.byType(MonthSection)).dy;
            if (size.height < 480) {
              // Bajita: el aviso va en la lista, arriba, y lo último sube por encima de la barra.
              expect(_inside(find.byType(SingleChildScrollView), notice), findsOneWidget);
              expect(tester.getBottomLeft(notice).dy, lessThan(tester.getTopLeft(_hero).dy));
              expect(last, lessThanOrEqualTo(size.height - 103.9));
            } else {
              expect(last, lessThanOrEqualTo(tester.getTopLeft(notice).dy - 15.9));
            }
          });
        }
      }
    }

    testWidgets('pantalla normal con montos enormes: la cifra grande se achica, no se corta', (tester) async {
      await _pump(tester, states.values.first());
      final amount = tester.widget<Text>(_inside(_hero, find.text(_m(big))).first);
      expect(amount.overflow, isNull);
      expect(_inside(_hero, find.byType(FittedBox)), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('oscuro: los fondos violeta usan el violeta sólido y el texto blanco', (tester) async {
      await _pump(tester, _Server()..repo.onUnread = () async => 2, dark: true);
      final fills = tester
          .widgetList<DecoratedBox>(_inside(_hero, find.byType(DecoratedBox)))
          .map((box) => (box.decoration as BoxDecoration).color);
      expect(fills, contains(RindePalette.dark.brandSolid));
      expect(tester.widget<Text>(_inside(_hero, find.text(_m(139300)))).style!.color, RindeBrand.white);
      expect(tester.widget<Text>(find.text('LIBRE PARA GASTAR · ESTIMADO')).style!.color, RindeBrand.white);
    });
  });

  group('movimiento', () {
    testWidgets('al presionar la tarjeta se encoge un poco; con movimiento reducido, no', (tester) async {
      for (final reduce in [false, true]) {
        await _pump(tester, _Server(), reduceMotion: reduce);
        final gesture = await tester.startGesture(tester.getCenter(_hero));
        // El toque compite con el arrastre de la lista: se confirma pasados 100 ms.
        await tester.pump(const Duration(milliseconds: 150));
        final scale = tester.widget<AnimatedScale>(_inside(_hero, find.byType(AnimatedScale))).scale;
        expect(scale, reduce ? 1 : 0.99, reason: 'reducido: $reduce');
        await gesture.cancel();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('con movimiento reducido nada queda animándose: ni esqueletos ni Rin', (tester) async {
      final loading = _Server()
        ..status = (() async => statusOf(hasTransactions: false))
        ..repo.onPlan = (() => Completer<MoneyPlan>().future)
        ..repo.onTotals = (_) => Completer<MonthTotals>().future;
      await _pump(tester, loading, reduceMotion: true);
      expect(find.byType(RindeSkeleton), findsWidgets);
      expect(find.byType(Rin), findsOneWidget);
      // Si algo siguiera moviéndose, esto no terminaría.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('sin movimiento reducido el esqueleto late', (tester) async {
      await _pump(tester, _Server()..status = () => Completer<WelcomeStatus>().future);
      expect(tester.binding.hasScheduledFrame, isTrue);
    });
  });

  group('recargar', () {
    testWidgets('halar hacia abajo vuelve a pedir todo el Inicio', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      final repo = server.repo;
      // Los nombres de categoría solo se piden si un aviso los muestra.
      const blocks = ['plan', 'monthTotals', 'budgets', 'cards', 'toConfirm', 'unread'];
      final before = {for (final block in blocks) block: repo.count(block)};
      final statusBefore = server.statusCalls;

      repo.onPlan = () async => planOf(free: 99000);
      await tester.fling(find.byType(SingleChildScrollView), const Offset(0, 320), 1200);
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(server.statusCalls, statusBefore + 1);
      for (final block in blocks) {
        expect(repo.count(block), before[block]! + 1, reason: block);
      }
      expect(_inside(_hero, find.text(_m(99000))), findsOneWidget);
      final indicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      expect(indicator.color, RindePalette.light.brandSolid);
    });

    testWidgets('mientras recarga, las cifras que ya estaban no parpadean', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      final next = Completer<MonthTotals>();
      server.repo.onTotals = (_) => next.future;
      await tester.fling(find.byType(SingleChildScrollView), const Offset(0, 320), 1200);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_m(287700)), findsOneWidget);
      expect(_inside(find.byType(MonthSection), find.byType(RindeSkeleton)), findsNothing);
      next.complete(totalsOf(expense: 300000));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.text(_m(300000)), findsOneWidget);
    });

    testWidgets('al volver a la app: recarga si pasaron más de 5 minutos; si no, no', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      final before = server.repo.count('plan');

      server.now = server.now.add(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(server.repo.count('plan'), before);

      server.now = server.now.add(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(server.repo.count('plan'), before + 1);
    });

    testWidgets('al volver otro día, lo del mes se pide con la fecha nueva', (tester) async {
      final server = _Server()..now = DateTime(2026, 11, 30, 23, 50);
      await _pump(tester, server);
      expect(server.repo.calls, contains('monthTotals 2026-11-30'));

      server.now = DateTime(2026, 12, 1, 0, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(server.repo.calls, contains('monthTotals 2026-12-01'));
      expect(server.repo.calls, contains('budgets 2026-12'));
    });
  });

  group('tutorial de primera vez', () {
    const demo = Session(
      user: AuthUser(id: 'demo', email: 'ana@rinde.co', name: 'Ana'),
      accessToken: 'a',
      refreshToken: 'r',
      demo: true,
    );

    testWidgets('se abre solo cuando el Inicio ya cargó y falta verlo', (tester) async {
      final status = Completer<WelcomeStatus>();
      final server = _Server()..status = () => status.future;
      final container = await _pump(tester, server, session: demo);
      expect(find.byType(CoachTour), findsNothing);

      status.complete(statusOf(tutorialDone: false));
      await _settle(tester);
      expect(container.read(tourControllerProvider), isTrue);
      expect(find.byType(CoachTour), findsOneWidget);
    });

    testWidgets('ya visto no se abre; pedido desde «Yo» sí, y la petición se apaga', (tester) async {
      final container = await _pump(tester, _Server());
      expect(find.byType(CoachTour), findsNothing);

      container.read(tourRequestedProvider.notifier).request();
      await _settle(tester);
      expect(find.byType(CoachTour), findsOneWidget);
      expect(container.read(tourRequestedProvider), isFalse);

      unawaited(container.read(tourControllerProvider.notifier).close());
      await _settle(tester);
      expect(find.byType(CoachTour), findsNothing);
    });

    testWidgets('pedido mientras carga: espera a que haya algo que explicar', (tester) async {
      final status = Completer<WelcomeStatus>();
      final server = _Server()..status = () => status.future;
      final container = await _pump(tester, server);
      container.read(tourRequestedProvider.notifier).request();
      await _settle(tester);
      expect(find.byType(CoachTour), findsNothing);

      status.complete(statusOf());
      await _settle(tester);
      expect(find.byType(CoachTour), findsOneWidget);
    });
  });
}
