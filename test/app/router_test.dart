import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart';
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
import 'package:rinde_mobile/features/export/presentation/export_screen.dart';
import 'package:rinde_mobile/features/insights/application/insights_providers.dart';
import 'package:rinde_mobile/features/insights/data/insights_repository.dart';
import 'package:rinde_mobile/features/insights/presentation/insights_screen.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/presentation/fix_balance_screen.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/money/presentation/payments_screen.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/money_shortcuts.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart' show homeTotalsProvider;
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/notifications/application/notifications_writer.dart';
import 'package:rinde_mobile/features/notifications/data/notifications_repository.dart';
import 'package:rinde_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:rinde_mobile/features/period/application/period_providers.dart';
import 'package:rinde_mobile/features/period/data/period_models.dart';
import 'package:rinde_mobile/features/period/presentation/period_screen.dart';
import 'package:rinde_mobile/features/plan/application/plan_providers.dart';
import 'package:rinde_mobile/features/plan/data/plan_models.dart';
import 'package:rinde_mobile/features/plan/presentation/budget_detail_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/budgets_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/calendar_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/liquidity_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/plan_screen.dart';
import 'package:rinde_mobile/features/renta/presentation/renta_screen.dart';
import 'package:rinde_mobile/features/shell/presentation/rinde_tab_scaffold.dart';
import 'package:rinde_mobile/features/to_confirm/application/to_confirm_writer.dart';
import 'package:rinde_mobile/features/to_confirm/data/to_confirm_repository.dart';
import 'package:rinde_mobile/features/to_confirm/presentation/to_confirm_screen.dart';
import 'package:rinde_mobile/features/vacas/application/vacas_providers.dart';
import 'package:rinde_mobile/features/vacas/data/vaca_models.dart';
import 'package:rinde_mobile/features/vacas/presentation/vaca_detail_screen.dart';
import 'package:rinde_mobile/features/vacas/presentation/vaca_join_screen.dart';
import 'package:rinde_mobile/features/vacas/presentation/vacas_screens.dart';

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

/// Metas y Vacas (etapa 10), que se abren encima de una pestaña, con la pantalla que deben mostrar.
final _pushedRoutes = {
  Routes.goals: MetasScreen,
  Routes.goal('v1'): VacaDetailScreen,
  Routes.vacas: VacasScreen,
  Routes.vaca('v1'): VacaDetailScreen,
  Routes.vacaJoin('K7M2QX'): VacaJoinScreen,
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
        budgetsMonthProvider.overrideWith((ref, _) => Completer<List<BudgetStatus>>().future),
        budgetMovementsProvider.overrideWith((ref, _) => Completer<MovementPage>().future),
        calendarMonthProvider.overrideWith((ref, _) => Completer<PaymentCalendar>().future),
        liquidityProvider.overrideWith((ref, _) => Completer<Liquidity>().future),
        whatsappLinkProvider.overrideWith((ref, _) => Completer<WhatsappLink>().future),
        periodSummaryProvider.overrideWith((ref, _) => Completer<PeriodSummary>().future),
        periodMovementsProvider.overrideWith((ref, _) => Completer<MovementPage>().future),
        periodKakeiboProvider.overrideWith((ref, _) => Completer<MovementPage>().future),
        movementCategoriesProvider.overrideWith((ref, _) => Completer<CategoryLists>().future),
        toConfirmListProvider.overrideWith((ref, _) => Completer<List<IncomingPayment>>().future),
        notificationsListProvider.overrideWith((ref, _) => Completer<List<AppNotification>>().future),
        insightsProvider.overrideWith((ref, _) => Completer<InsightsResult>().future),
        reflectionProvider.overrideWith((ref, _) => Completer<WeekReflection>().future),
        homeTotalsProvider.overrideWith((ref, _) => Completer<MonthTotals>().future),
        vacasProvider.overrideWith((ref, _) => Completer<List<Vaca>>().future),
        vacaDetailProvider.overrideWith((ref, _) => Completer<Vaca>().future),
        invitationPreviewProvider.overrideWith((ref, _) => Completer<InvitationPreview>().future),
      ],
      child: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: const RindeApp()),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(RindeApp))).read(routerProvider);
}

String _location(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

void main() {
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
      Routes.budgets,
      Routes.budget('alimentacion', '2026-11'),
      Routes.calendar,
      Routes.liquidity,
      Routes.movement('m1'),
      Routes.income,
      Routes.expenses,
      Routes.toConfirm,
      Routes.notifications,
      Routes.insights,
      Routes.export,
      Routes.renta,
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
      // Movimientos (etapa 3), Yo (etapa 6) y Planear (etapa 7) ya son pantallas reales.
      expect(find.text('En desarrollo'), findsNothing, reason: route);
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

  testWidgets('con sesión, Metas, Vacas, su detalle y la invitación abren su pantalla sin barra y «Volver» '
      'regresa', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    for (final MapEntry(key: route, value: screen) in _pushedRoutes.entries) {
      router.go(Routes.plan);
      await _settle(tester);
      unawaited(router.push(route));
      await _settle(tester);
      expect(find.byType(screen), findsOneWidget, reason: route);
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

  testWidgets(
    'Ingresos, Gastos y Por confirmar ya son pantallas reales; por enlace directo, atrás va al Inicio y a Movimientos',
    (tester) async {
      final router = await _pumpApp(tester, session: _session);
      for (final (route, screen) in [
        (Routes.income, PeriodScreen),
        (Routes.expenses, PeriodScreen),
        (Routes.toConfirm, ToConfirmScreen),
      ]) {
        router.go(Routes.plan);
        await _settle(tester);
        unawaited(router.push(route));
        await _settle(tester);
        expect(find.byType(screen), findsOneWidget, reason: route);
        expect(find.text('En desarrollo'), findsNothing, reason: route);
        expect(find.byType(RindeTabScaffold), findsNothing, reason: route);
        await tester.tap(find.byTooltip('Volver'));
        await _settle(tester);
        expect(_location(router), Routes.plan, reason: route);
      }

      // Sin pantalla anterior (backPath de la web): Ingresos y Gastos → Inicio; Por confirmar → Movimientos.
      for (final (route, back) in [
        (Routes.income, Routes.app),
        (Routes.expenses, Routes.app),
        (Routes.toConfirm, Routes.movements),
      ]) {
        router.go(route);
        await _settle(tester);
        expect(await tester.binding.handlePopRoute(), isTrue, reason: route);
        await _settle(tester);
        expect(_location(router), back, reason: route);
      }
    },
  );

  testWidgets(
    'Notificaciones, Consejos, Exportar y Renta ya son pantallas reales; por enlace directo, atrás va a su pantalla de origen',
    (tester) async {
      final router = await _pumpApp(tester, session: _session);
      for (final (route, screen) in [
        (Routes.notifications, NotificationsScreen),
        (Routes.insights, InsightsScreen),
        // Antes que /app/transacciones/:id: no es el movimiento «exportar».
        (Routes.export, ExportScreen),
        (Routes.renta, RentaScreen),
      ]) {
        router.go(Routes.plan);
        await _settle(tester);
        unawaited(router.push(route));
        await _settle(tester);
        expect(find.byType(screen), findsOneWidget, reason: route);
        expect(find.text('En desarrollo'), findsNothing, reason: route);
        expect(find.byType(RindeTabScaffold), findsNothing, reason: route);
        await tester.tap(find.byTooltip('Volver'));
        await _settle(tester);
        expect(_location(router), Routes.plan, reason: route);
      }

      // Sin pantalla anterior (backPath de la web).
      for (final (route, back) in [
        (Routes.notifications, Routes.app),
        (Routes.insights, Routes.myMoney),
        (Routes.export, Routes.account),
        (Routes.renta, Routes.insights),
      ]) {
        router.go(route);
        await _settle(tester);
        expect(await tester.binding.handlePopRoute(), isTrue, reason: route);
        await _settle(tester);
        expect(_location(router), back, reason: route);
      }
    },
  );

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

  testWidgets('«Más de tu plata»: Tarjetas, Cuentas, Calendario, Por confirmar y Próximos días abren sus '
      'pantallas', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.myMoney);
    await _settle(tester);
    for (final (hint, screen) in [
      ('Cupo y fechas de pago', CardsScreen),
      ('Lo que te deben y debes', DebtsScreen),
      ('Topes por categoría', BudgetsScreen),
      ('Pagos fijos del mes', CalendarScreen),
      ('Gastos que llegaron solos', ToConfirmScreen),
      ('Lo que entra y sale', LiquidityScreen),
    ]) {
      final shortcut = find.descendant(of: find.byType(MoneyShortcuts), matching: find.text(hint));
      await tester.ensureVisible(shortcut);
      await tester.pump();
      await tester.tap(shortcut);
      await _settle(tester);
      expect(find.byType(screen), findsOneWidget, reason: hint);
      await tester.tap(find.byTooltip('Volver'));
      await _settle(tester);
      expect(_location(router), Routes.myMoney, reason: hint);
    }
  });

  testWidgets('Planear: cada acceso abre su pantalla encima y «Volver» regresa', (tester) async {
    final router = await _pumpApp(tester, session: _session);
    router.go(Routes.plan);
    await _settle(tester);
    expect(find.byType(PlanScreen), findsOneWidget);
    expect(find.text('Tus planes'), findsOneWidget);
    for (final (hint, screen) in [
      ('Lo que se repite cada mes', MoneyPaymentsScreen),
      ('Qué toca pagar y cuándo', CalendarScreen),
      ('Topes por categoría', BudgetsScreen),
      ('Para qué estás ahorrando', MetasScreen),
      ('Lo que te deben y debes', DebtsScreen),
      ('Cupo y fechas de pago', CardsScreen),
    ]) {
      final shortcut = find.text(hint);
      await tester.ensureVisible(shortcut);
      await tester.pump();
      await tester.tap(shortcut);
      await _settle(tester);
      expect(find.byType(screen), findsOneWidget, reason: hint);
      expect(find.byType(RindeTabScaffold), findsNothing, reason: hint);
      await tester.tap(find.byTooltip('Volver'));
      await _settle(tester);
      expect(_location(router), Routes.plan, reason: hint);
    }
  });

  testWidgets(
    'por enlace directo, atrás: Presupuestos y Calendario a Planear, un presupuesto a Presupuestos y '
    'Próximos días a Mi plata',
    (tester) async {
      final router = await _pumpApp(tester, session: _session);
      for (final (route, screen, back) in [
        (Routes.budgets, BudgetsScreen, Routes.plan),
        (Routes.calendar, CalendarScreen, Routes.plan),
        (Routes.budget('alimentacion', '2026-11'), BudgetDetailScreen, Routes.budgets),
        (Routes.liquidity, LiquidityScreen, Routes.myMoney),
      ]) {
        router.go(route);
        await _settle(tester);
        expect(find.byType(screen), findsOneWidget, reason: route);
        expect(await tester.binding.handlePopRoute(), isTrue, reason: route);
        await _settle(tester);
        expect(_location(router), back, reason: route);
      }
      // El mes y la categoría del detalle salen de la ruta; un mes inválido es el mes en curso.
      router.go('${Routes.budgets}/ocio?mes=2026-13');
      await _settle(tester);
      final detail = tester.widget<BudgetDetailScreen>(find.byType(BudgetDetailScreen));
      expect(
        (detail.category, RegExp(r'^\d{4}-\d{2}$').hasMatch(detail.month), detail.month == '2026-13'),
        ('ocio', true, false),
      );
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
