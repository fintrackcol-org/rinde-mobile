import 'dart:ui' show SemanticsRole;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/presentation/tour_anchors.dart';
import 'package:rinde_mobile/features/onboarding/presentation/widgets/onboarding_shell.dart';
import 'package:rinde_mobile/features/shell/presentation/rinde_tab_scaffold.dart';

const _routes = {
  RindeTab.home: Routes.app,
  RindeTab.movements: Routes.movements,
  RindeTab.plan: Routes.plan,
  RindeTab.account: Routes.account,
};
const _labels = {
  RindeTab.home: 'Inicio',
  RindeTab.movements: 'Movimientos',
  RindeTab.plan: 'Planear',
  RindeTab.account: 'Yo',
};

/// Las 4 pestañas con un contenido marcador y «Anotar» como pantalla aparte, con un router mínimo.
Future<void> _pump(
  WidgetTester tester, {
  String initial = Routes.app,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  Session? session,
  Widget? overlay,
  TourAnchors? anchors,
  Tr tr = const Tr('es', {}),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final tab in RindeTab.values)
        GoRoute(
          path: _routes[tab]!,
          pageBuilder: (_, state) => NoTransitionPage(
            key: state.pageKey,
            child: RindeTabScaffold(
              current: tab,
              overlay: overlay,
              anchors: tab == RindeTab.home ? anchors : null,
              child: Text('CONTENIDO ${tab.name}'),
            ),
          ),
        ),
      GoRoute(
        path: Routes.record,
        builder: (_, _) => const Scaffold(body: Text('ANOTAR')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // Llave por montaje: cada llamada arranca con proveedores nuevos (otra sesión).
      key: UniqueKey(),
      overrides: [
        trProvider.overrideWithValue(tr),
        appConfigProvider.overrideWithValue(
          AppConfig(apiBaseUrl: '', environment: 'local', demoMode: session?.demo ?? false),
        ),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('cada pestaña lleva a su ruta y queda marcada', (tester) async {
    await _pump(tester);
    for (final tab in [RindeTab.movements, RindeTab.plan, RindeTab.account, RindeTab.home]) {
      await tester.tap(_tab(_labels[tab]!));
      await tester.pumpAndSettle();
      expect(find.text('CONTENIDO ${tab.name}'), findsOneWidget);
      for (final other in RindeTab.values) {
        expect(
          tester.getSemantics(_tab(_labels[other]!)),
          isSemantics(isButton: true, hasSelectedState: true, isSelected: other == tab, hasTapAction: true),
          reason: 'en ${tab.name}, pestaña ${other.name}',
        );
      }
    }
  });

  testWidgets('la barra es una región de navegación con nombre y Anotar es un botón', (tester) async {
    await _pump(tester);
    final nav = tester.getSemantics(_tab('Secciones'));
    expect(nav.role, SemanticsRole.navigation);
    expect(tester.getSemantics(_tab('Anotar')), isSemantics(isButton: true, hasTapAction: true));
    // Los cuatro nombres y Anotar, una sola vez cada uno (sin duplicar texto e ícono).
    for (final label in [..._labels.values, 'Anotar']) {
      expect(_tab(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Anotar se abre encima y atrás vuelve a la pestaña donde estaba', (tester) async {
    await _pump(tester, initial: Routes.plan);
    await tester.tap(_tab('Anotar'));
    await tester.pumpAndSettle();
    expect(find.text('ANOTAR'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('CONTENIDO plan'), findsOneWidget);
  });

  testWidgets('atrás en una pestaña que no es Inicio va al Inicio; en Inicio no se intercepta', (
    tester,
  ) async {
    await _pump(tester, initial: Routes.account);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('CONTENIDO home'), findsOneWidget);

    // En el Inicio nadie lo maneja: el sistema cierra la app.
    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('CONTENIDO home'), findsOneWidget);
  });

  testWidgets('con algo encima (el tutorial), atrás no es del marco', (tester) async {
    await _pump(
      tester,
      initial: Routes.movements,
      overlay: const ColoredBox(color: Color(0x80000000)),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('CONTENIDO movements'), findsOneWidget);

    // Aunque lo de encima frene el atrás (el tutorial se cierra a sí mismo), el marco no navega.
    var asked = 0;
    await _pump(
      tester,
      initial: Routes.movements,
      overlay: PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => asked++,
        child: const ColoredBox(color: Color(0x80000000)),
      ),
    );
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('CONTENIDO movements'), findsOneWidget);
  });

  testWidgets('lo de encima cubre toda la pantalla, barra incluida', (tester) async {
    const key = Key('encima');
    await _pump(
      tester,
      overlay: const ColoredBox(key: key, color: Color(0x80000000)),
    );
    expect(tester.getSize(find.byKey(key)), const Size(390, 844));
    // Lo de encima recibe los toques: la barra de abajo no navega.
    await tester.tap(_tab('Movimientos'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('CONTENIDO home'), findsOneWidget);
  });

  testWidgets('el Inicio reparte las anclas del tutorial a Anotar, Planear y Yo', (tester) async {
    final anchors = TourAnchors();
    await _pump(tester, anchors: anchors);
    final bar = tester.getRect(_tab('Secciones'));
    for (final target in [TourTarget.anotar, TourTarget.planear, TourTarget.cuenta]) {
      final rect = anchors.rectOf(target);
      expect(rect, isNotNull, reason: target.name);
      expect(bar.expandToInclude(rect!), bar, reason: '${target.name} dentro de la barra');
    }
    expect(anchors.rectOf(TourTarget.anotar)!.center.dx, closeTo(195, 0.5));
    expect(anchors.rectOf(TourTarget.planear), tester.getRect(_tab('Planear')));
    // Las que no son de la barra no se dibujaron aquí.
    expect(anchors.rectOf(TourTarget.saldo), isNull);
  });

  testWidgets('medidas: 12 a los lados, 64 de alto, Anotar sobresale 12 y áreas táctiles de 48', (
    tester,
  ) async {
    await _pump(tester);
    final bar = tester.getRect(_tab('Secciones'));
    expect(bar.left, 12);
    expect(bar.right, 390 - 12);
    expect(bar.bottom, 844 - 12);
    expect(bar.height, 64 + 12);
    final context = tester.element(find.text('CONTENIDO home'));
    expect(RindeTabScaffold.bottomInset(context), 104);
    for (final label in [..._labels.values, 'Anotar']) {
      final size = tester.getSize(_tab(label));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
  });

  testWidgets('con zona segura abajo la barra sube y el contenido deja más espacio', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34, top: 47);
    tester.view.padding = const FakeViewPadding(bottom: 34, top: 47);
    await _pump(tester);
    expect(tester.getRect(_tab('Secciones')).bottom, 844 - 34);
    expect(RindeTabScaffold.bottomInset(tester.element(find.text('CONTENIDO home'))), 34 + 64 + 12 + 16);
    // El contenido empieza debajo de la barra de estado.
    expect(tester.getTopLeft(find.text('CONTENIDO home')).dy, 47);
  });

  for (final session in [null, Session.demo('nuevo')]) {
    testWidgets('acostado, barra y contenido fuera de las zonas de los lados (demo: ${session != null})', (
      tester,
    ) async {
      tester.view.viewPadding = const FakeViewPadding(left: 32, right: 48);
      tester.view.padding = const FakeViewPadding(left: 32, right: 48);
      await _pump(tester, size: const Size(800, 360), session: session);

      final bar = tester.getRect(_tab('Secciones'));
      expect((bar.left, bar.right), (32, 800 - 48));
      expect(tester.getRect(_tab('Yo')).right, lessThanOrEqualTo(800 - 48));
      // El contenido va centrado en lo que queda entre las dos zonas.
      expect(tester.getCenter(find.text('CONTENIDO home')).dx, (32 + 800 - 48) / 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Movimientos: nombre corto a la vista donde lo hay, completo para el lector', (tester) async {
    await _pump(
      tester,
      tr: const Tr('pt', {'Movimientos': 'Movimentações', 'Movimientos (pestaña)': 'Extrato'}),
    );
    expect(find.text('Extrato'), findsOneWidget);
    expect(_tab('Movimentações'), findsOneWidget);

    // Sin nombre corto (español) se ve el completo, nunca la clave.
    await _pump(tester);
    expect(find.text('Movimientos'), findsOneWidget);
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda ni se corta', (tester) async {
      for (final tab in RindeTab.values) {
        await _pump(tester, initial: _routes[tab]!, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(tester.takeException(), isNull, reason: tab.name);
        // El tope de 1,3 mantiene el alto de la barra.
        final bar = tester.getRect(_tab('Secciones'));
        expect(bar.height, 64 + 12);
        for (final label in [..._labels.values, 'Anotar']) {
          final cell = tester.getRect(_tab(label));
          final text = tester.getRect(find.text(label));
          expect(cell.expandToInclude(text), cell, reason: '$label cabe en su celda (${tab.name})');
          expect(text.width, greaterThan(0));
        }
      }
    });
  }

  testWidgets('la franja DEMO solo aparece en una sesión de demostración', (tester) async {
    await _pump(tester);
    expect(find.byType(DemoStrip), findsNothing);

    await _pump(tester, session: Session.demo('nuevo'));
    expect(find.byType(DemoStrip), findsOneWidget);
    // El contenido queda debajo de la franja, no detrás.
    expect(
      tester.getTopLeft(find.text('CONTENIDO home')).dy,
      tester.getBottomLeft(find.byType(DemoStrip)).dy,
    );
  });

  testWidgets('con sesión normal no hay franja', (tester) async {
    await _pump(
      tester,
      session: const Session(
        user: AuthUser(id: 'u1', email: 'ana@rinde.co'),
        accessToken: 'a',
        refreshToken: 'r',
      ),
    );
    expect(find.byType(DemoStrip), findsNothing);
    // La sesión sí se leyó.
    final container = ProviderScope.containerOf(tester.element(find.byType(RindeTabScaffold)));
    expect(container.read(sessionControllerProvider).value?.signedIn, isTrue);
  });
}
