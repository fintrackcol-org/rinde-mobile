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
import 'package:rinde_mobile/features/account/application/account_providers.dart';
import 'package:rinde_mobile/features/account/data/account_models.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/presentation/login_screen.dart';
import 'package:rinde_mobile/features/cards/application/cards_providers.dart';
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/presentation/card_detail_screen.dart';
import 'package:rinde_mobile/features/cards/presentation/cards_screen.dart';
import 'package:rinde_mobile/features/debts/application/debts_providers.dart';
import 'package:rinde_mobile/features/debts/data/debt_models.dart';
import 'package:rinde_mobile/features/debts/presentation/debts_screen.dart';
import 'package:rinde_mobile/features/entry/presentation/entry_screen.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/presentation/fix_balance_screen.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/money/presentation/payments_screen.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/money_shortcuts.dart';
import 'package:rinde_mobile/features/shell/presentation/pending_module_screen.dart';
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
  Routes.income: 'Ingresos',
  Routes.expenses: 'Gastos',
  Routes.toConfirm: 'Por confirmar',
  Routes.budgets: 'Presupuestos',
  Routes.calendar: 'Calendario',
  Routes.insights: 'Consejos',
  // Antes que /app/transacciones/:id: no es el movimiento «exportar».
  Routes.export: 'Exportar movimientos',
  Routes.renta: 'Renta y DIAN',
  Routes.liquidity: 'Tu plata en los próximos días',
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
        moneyProfileProvider.overrideWith((ref, _) => Completer<MoneyProfile>().future),
        cardsProvider.overrideWith((ref, _) => Completer<List<CreditCard>>().future),
        cardDetailProvider.overrideWith((ref, _) => Completer<CardDetailData>().future),
        debtsProvider.overrideWith((ref, _) => Completer<DebtsList>().future),
        whatsappLinkProvider.overrideWith((ref, _) => Completer<WhatsappLink>().future),
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

  test('estas pruebas recorren exactamente los pendientes; Mi plata, Pagos, Corregir saldo, Tarjetas, Cuentas y Yo ya no lo son', () {
    expect(
      {for (final m in pendingModules) m.path},
      {
        for (final route in [..._tabRoutes.keys, ..._pushedRoutes.keys])
          if (route != Routes.movements && route != Routes.account) route,
      },
    );
    for (final route in [
      Routes.myMoney,
      Routes.payments,
      Routes.fixBalance,
      Routes.cards,
      Routes.card(':id'),
      Routes.debts,
      Routes.account,
    ]) {
      expect(pendingModules.map((m) => m.path), isNot(contains(route)), reason: route);
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
      Routes.fixBalance,
      Routes.payments,
      Routes.cards,
      Routes.card('t1'),
      Routes.debts,
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
      // Movimientos (etapa 3) y Yo (etapa 6) ya son pantallas reales; Planear sigue pendiente.
      expect(find.text('En desarrollo'), route == Routes.plan ? findsOneWidget : findsNothing, reason: route);
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

  testWidgets('Corregir saldo ya es pantalla real; por enlace directo, atrás va a Mi plata', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    unawaited(router.push(Routes.fixBalance));
    await _settle(tester);
    expect(find.byType(FixBalanceScreen), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);
    expect(find.byType(RindeTabScaffold), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await _settle(tester);
    expect(_location(router), Routes.plan);

    // Sin pantalla anterior, atrás va a Mi plata (backPath de la web).
    router.go(Routes.fixBalance);
    await _settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.myMoney);
  });

  testWidgets('Pagos del mes ya es pantalla real; por enlace directo, atrás va a Planear', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.myMoney);
    await _settle(tester);
    unawaited(router.push(Routes.payments));
    await _settle(tester);
    expect(find.byType(MoneyPaymentsScreen), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);
    expect(find.byType(RindeTabScaffold), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await _settle(tester);
    expect(_location(router), Routes.myMoney);

    // Sin pantalla anterior, atrás va a Planear (backPath de la web).
    router.go(Routes.payments);
    await _settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.plan);
  });

  testWidgets(
    'Tarjetas ya es pantalla real; por enlace directo, atrás va a Planear y el detalle a Tarjetas',
    (tester) async {
      final router = await _pumpApp(tester, session: _session);
      router.go(Routes.myMoney);
      await _settle(tester);
      unawaited(router.push(Routes.cards));
      await _settle(tester);
      expect(find.byType(CardsScreen), findsOneWidget);
      expect(find.text('En desarrollo'), findsNothing);
      // Empujada, sin barra (la web la muestra con «Planear» marcado: la app se aparta, como Mi plata).
      expect(find.byType(RindeTabScaffold), findsNothing);
      await tester.tap(find.byTooltip('Volver'));
      await _settle(tester);
      expect(_location(router), Routes.myMoney);

      // Sin pantalla anterior (backPath de la web): Tarjetas → Planear; el detalle → Tarjetas.
      router.go(Routes.cards);
      await _settle(tester);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await _settle(tester);
      expect(_location(router), Routes.plan);

      router.go(Routes.card('t1'));
      await _settle(tester);
      expect(find.byType(CardDetailScreen), findsOneWidget);
      expect(find.text('En desarrollo'), findsNothing);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await _settle(tester);
      expect(_location(router), Routes.cards);
    },
  );

  testWidgets('Cuentas ya es pantalla real; empujada sin barra y, por enlace directo, atrás va a Planear', (
    tester,
  ) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.myMoney);
    await _settle(tester);
    unawaited(router.push(Routes.debts));
    await _settle(tester);
    expect(find.byType(DebtsScreen), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);
    expect(find.byType(RindeTabScaffold), findsNothing);
    await tester.tap(find.byTooltip('Volver'));
    await _settle(tester);
    expect(_location(router), Routes.myMoney);

    router.go(Routes.debts);
    await _settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(_location(router), Routes.plan);
  });

  testWidgets(
    '«Más de tu plata»: Tarjetas y Cuentas abren sus pantallas; Calendario, Por confirmar y Próximos '
    'días siguen «En desarrollo»',
    (tester) async {
      final router = await _pumpApp(tester, session: _session);
      router.go(Routes.myMoney);
      await _settle(tester);
      for (final (hint, screen) in [
        ('Cupo y fechas de pago', CardsScreen),
        ('Lo que te deben y debes', DebtsScreen),
        ('Pagos fijos del mes', PendingModuleScreen),
        ('Gastos que llegaron solos', PendingModuleScreen),
        ('Lo que entra y sale', PendingModuleScreen),
      ]) {
        final shortcut = find.descendant(of: find.byType(MoneyShortcuts), matching: find.text(hint));
        await tester.ensureVisible(shortcut);
        await tester.pump();
        await tester.tap(shortcut);
        await _settle(tester);
        expect(find.byType(screen), findsOneWidget, reason: hint);
        expect(
          find.text('En desarrollo'),
          screen == PendingModuleScreen ? findsOneWidget : findsNothing,
          reason: hint,
        );
        await tester.tap(find.byTooltip('Volver'));
        await _settle(tester);
        expect(_location(router), Routes.myMoney, reason: hint);
      }
    },
  );

  testWidgets('«Anotar» con ?tarjeta= llega a Anotar (la tarjeta la toma el formulario)', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    unawaited(router.push('${Routes.record}?tarjeta=t1'));
    await _settle(tester);
    expect(find.text('Anotar un gasto'), findsOneWidget);
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
