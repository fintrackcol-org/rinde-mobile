import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/pending_modules.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/shell/presentation/pending_module_screen.dart';
import 'package:rinde_mobile/features/shell/presentation/rinde_tab_scaffold.dart';

const _honest = 'Esta parte todavía no está en la app. Ya funciona en la web de Rinde, con tu misma cuenta.';

/// Título esperado de cada destino (los de Rinde Web), por la ruta con que se abre.
final _titles = {
  Routes.notifications: 'Notificaciones',
  // De Planear y del Calendario.
  Routes.goals: 'Metas',
  Routes.vacas: 'Vacas',
  // Accesos de «Más de tu plata».
  Routes.insights: 'Consejos',
  Routes.export: 'Exportar movimientos',
  Routes.renta: 'Renta y DIAN',
};
// Planear (etapa 7) ya es pantalla real: ninguna pestaña queda pendiente.
const _tabs = <String, RindeTab>{};

/// Los destinos pendientes con un router mínimo; el Inicio es un marcador.
Future<GoRouter> _pump(
  WidgetTester tester, {
  String initial = Routes.app,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  Session? session,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: Routes.app,
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
      for (final module in pendingModules)
        GoRoute(
          path: module.path,
          builder: (_, state) => PendingModuleScreen(module, query: state.uri.queryParameters),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // Llave por montaje: cada llamada arranca con proveedores nuevos.
      key: UniqueKey(),
      overrides: [
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
  return router;
}

void main() {
  test('la lista cubre todos los destinos del Inicio y de la barra, sin repetir rutas', () {
    final paths = pendingModules.map((m) => m.path).toList();
    expect(paths.toSet().length, paths.length);
    expect(paths.toSet(), {
      Routes.notifications,
      Routes.goals,
      Routes.vacas,
      Routes.insights,
      Routes.export,
      Routes.renta,
    });
    expect({for (final m in pendingModules) ?m.tab}, isEmpty);
  });

  testWidgets('cada destino dice «En desarrollo» con su título y sin datos ni acciones de mentira', (
    tester,
  ) async {
    for (final MapEntry(key: route, value: title) in _titles.entries) {
      await _pump(tester, initial: route);
      expect(find.text('En desarrollo'), findsOneWidget, reason: route);
      expect(find.text(_honest), findsOneWidget, reason: route);
      // En el contenido: «Movimientos» y «Planear» también son nombres de pestaña en la barra.
      final heading = find.descendant(of: find.byType(SingleChildScrollView), matching: find.text(title));
      expect(tester.getSemantics(heading), isSemantics(isHeader: true, label: title), reason: route);

      final tab = _tabs[route];
      final scaffold = find.byType(RindeTabScaffold);
      if (tab == null) {
        // Se abre encima: «Volver» y nada de barra.
        expect(scaffold, findsNothing, reason: route);
        expect(find.byTooltip('Volver'), findsOneWidget, reason: route);
      } else {
        expect(tester.widget<RindeTabScaffold>(scaffold).current, tab, reason: route);
        expect(find.byTooltip('Volver'), findsNothing, reason: route);
      }
      // Ninguno ofrece acciones: «Yo» ya tiene su pantalla (account_screen_test.dart).
      expect(find.byType(RindeButton), findsNothing, reason: route);
    }
  });

  testWidgets('un destino abierto encima vuelve a donde estaba, con «Volver» o con atrás', (tester) async {
    final router = await _pump(tester);
    unawaited(router.push(Routes.notifications));
    await tester.pumpAndSettle();
    expect(find.text('Notificaciones'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);

    unawaited(router.push(Routes.goals));
    await tester.pumpAndSettle();
    expect(find.text('Metas'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets('abierto sin pantalla anterior, «Volver» y atrás llevan al Inicio en vez de cerrar la app', (
    tester,
  ) async {
    await _pump(tester, initial: Routes.notifications);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);

    await _pump(tester, initial: Routes.goals);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
      for (final route in [Routes.goals, Routes.renta, Routes.vacas]) {
        await _pump(tester, initial: route, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(tester.takeException(), isNull, reason: route);
        expect(find.text('En desarrollo'), findsOneWidget, reason: route);
      }
    });
  }
}
