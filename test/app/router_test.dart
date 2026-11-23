import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart';
import 'package:rinde_mobile/app/pending_modules.dart';
import 'package:rinde_mobile/app/router.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/presentation/login_screen.dart';
import 'package:rinde_mobile/features/entry/presentation/entry_screen.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/shell/presentation/rinde_tab_scaffold.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co'),
  accessToken: 'a',
  refreshToken: 'r',
);

const _tabRoutes = {
  Routes.movements: RindeTab.movements,
  Routes.plan: RindeTab.plan,
  Routes.account: RindeTab.account,
};

/// Destinos que se abren encima de una pestaña, con el título que deben mostrar.
final _pushedRoutes = {
  Routes.notifications: 'Notificaciones',
  Routes.payments: 'Pagos del mes',
  Routes.fixBalance: 'Corregir saldo',
  Routes.income: 'Ingresos',
  Routes.expenses: 'Gastos',
  Routes.toConfirm: 'Por confirmar',
  Routes.budgets: 'Presupuestos',
  Routes.cards: 'Tarjetas',
  Routes.card('t1'): 'Tarjeta',
};

// Sin pumpAndSettle: la entrada deja un spinner girando mientras «espera» el perfil.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// La app con su router real. El Inicio no es de estas pruebas: el perfil nunca llega y la entrada
/// se queda cargando, sin salir a la red.
Future<GoRouter> _pumpApp(WidgetTester tester, {Session? session}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
        profileProvider.overrideWith((ref, _) => Completer<UserProfile>().future),
        // Mi plata se queda cargando: estas pruebas son de rutas, no de sus datos.
        incomeOverviewProvider.overrideWith((ref, _) => Completer<IncomeOverview>().future),
      ],
      child: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: const RindeApp()),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(RindeApp))).read(routerProvider);
}

String _location(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  test('todo destino pendiente vive bajo /app: sin sesión, al login', () {
    for (final module in pendingModules) {
      expect(module.path, startsWith('${Routes.app}/'));
      expect(
        sessionRedirect(session: const AsyncData(SessionState()), location: module.path),
        Routes.login,
        reason: module.path,
      );
    }
  });

  testWidgets('sin sesión, ninguna ruta de la app se abre: todas terminan en el login', (tester) async {
    final router = await _pumpApp(tester);
    for (final route in [
      Routes.app,
      ..._tabRoutes.keys,
      ..._pushedRoutes.keys,
      Routes.record,
      Routes.myMoney,
      Routes.movement('m1'),
    ]) {
      router.go(route);
      await _settle(tester);
      expect(_location(router), Routes.login, reason: route);
      expect(find.byType(LoginScreen), findsOneWidget, reason: route);
      expect(find.text('En desarrollo'), findsNothing, reason: route);
    }
  });

  testWidgets('con sesión, /app abre la entrada y cada pestaña abre con la suya marcada', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    expect(_location(router), Routes.app);
    expect(find.byType(EntryScreen), findsOneWidget);

    for (final MapEntry(key: route, value: tab) in _tabRoutes.entries) {
      router.go(route);
      await _settle(tester);
      expect(_location(router), route);
      expect(tester.widget<RindeTabScaffold>(find.byType(RindeTabScaffold)).current, tab, reason: route);
      // Movimientos ya es pantalla real (etapa 3); Planear y Yo siguen pendientes.
      expect(
        find.text('En desarrollo'),
        route == Routes.movements ? findsNothing : findsOneWidget,
        reason: route,
      );
      expect(find.byType(EntryScreen), findsNothing, reason: route);
    }
  });

  testWidgets('atrás en una pestaña que no es Inicio vuelve al Inicio; en el Inicio no se intercepta', (
    tester,
  ) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.app);
    expect(find.byType(EntryScreen), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('con sesión, los demás destinos abren «En desarrollo» sin barra y «Volver» regresa', (
    tester,
  ) async {
    final router = await _pumpApp(tester, session: _session);
    for (final MapEntry(key: route, value: title) in _pushedRoutes.entries) {
      router.go(Routes.plan);
      await _settle(tester);
      unawaited(router.push(route));
      await _settle(tester);
      expect(find.text(title), findsOneWidget, reason: route);
      expect(find.text('En desarrollo'), findsOneWidget, reason: route);
      expect(find.byType(RindeTabScaffold), findsNothing, reason: route);

      await tester.tap(find.byTooltip('Volver'));
      await _settle(tester);
      expect(_location(router), Routes.plan, reason: route);
      expect(tester.widget<RindeTabScaffold>(find.byType(RindeTabScaffold)).current, RindeTab.plan);
    }
  });

  testWidgets('«Anotar» de la barra abre el destino encima y atrás vuelve a la pestaña', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Anotar'));
    await _settle(tester);
    expect(find.text('Anotar un gasto'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.plan);
    expect(find.text('Planear'), findsWidgets);
  });

  testWidgets('Mi plata ya es pantalla real: se abre encima, sin barra, y «Volver» regresa', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    unawaited(router.push(Routes.myMoney));
    await _settle(tester);
    expect(find.byType(MyMoneyScreen), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);
    expect(find.byType(RindeTabScaffold), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await _settle(tester);
    expect(_location(router), Routes.plan);

    // Por enlace directo, atrás va al Inicio (backPath de la web).
    router.go(Routes.myMoney);
    await _settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.app);
  });

  testWidgets('un destino abierto por enlace directo no cierra la app con atrás: va al Inicio', (
    tester,
  ) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.notifications);
    await _settle(tester);
    expect(find.text('Notificaciones'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.app);
  });
}
