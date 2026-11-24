import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_screen.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/cards/presentation/card_detail_screen.dart';
import '../features/cards/presentation/cards_screen.dart';
import '../features/debts/presentation/debts_screen.dart';
import '../features/entry/presentation/boot_screen.dart';
import '../features/entry/presentation/entry_screen.dart';
import '../features/money/presentation/fix_balance_screen.dart';
import '../features/money/presentation/my_money_screen.dart';
import '../features/money/presentation/payments_screen.dart';
import '../features/home/domain/home_dates.dart';
import '../features/movements/domain/movement.dart';
import '../features/movements/presentation/detail/movement_detail_screen.dart';
import '../features/movements/presentation/list/movements_screen.dart';
import '../features/movements/presentation/record/record_screen.dart';
import '../features/onboarding/domain/onboarding_flow.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/plan/presentation/budget_detail_screen.dart';
import '../features/plan/presentation/budgets_screen.dart';
import '../features/plan/presentation/calendar_screen.dart';
import '../features/plan/presentation/liquidity_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/shell/presentation/pending_module_screen.dart';
import '../features/welcome/presentation/welcome_screen.dart';
import 'pending_modules.dart';
import 'routes.dart';

/// Decide adónde va la persona según la sesión. Es una función pura para poder probarla.
String? sessionRedirect({required AsyncValue<SessionState> session, required String location}) {
  if (!session.hasValue && !session.hasError) return location == Routes.boot ? null : Routes.boot;
  final signedIn = session.value?.signedIn ?? false;
  final inApp = location == Routes.app || location.startsWith('${Routes.app}/');
  if (signedIn) return inApp ? null : Routes.app;
  // Sin sesión: al abrir la app, bienvenida; si estaba dentro (cerró sesión o venció), login,
  // como en Rinde Web.
  if (location == Routes.boot) return Routes.welcome;
  if (inApp) return Routes.login;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.boot,
    refreshListenable: refresh,
    redirect: (context, state) =>
        sessionRedirect(session: ref.read(sessionControllerProvider), location: state.matchedLocation),
    routes: [
      GoRoute(path: Routes.boot, builder: (_, _) => const BootScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: Routes.login,
        builder: (_, state) => LoginScreen(initialEmail: _email(state)),
      ),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.forgot,
        builder: (_, state) => ForgotPasswordScreen(initialEmail: _email(state)),
      ),
      // El Inicio y las demás pestañas entran sin transición: al cambiar de pestaña la barra no se mueve.
      GoRoute(
        path: Routes.app,
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const EntryScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(mode: OnboardingMode.full),
      ),
      GoRoute(
        path: Routes.onboardingQuestions,
        builder: (_, _) => const OnboardingScreen(mode: OnboardingMode.questions),
      ),
      GoRoute(
        path: Routes.movements,
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const MovementsScreen()),
      ),
      GoRoute(
        path: Routes.record,
        // Como Anotar.jsx: sin `?tipo=ingreso` es un gasto.
        builder: (_, state) => RecordScreen(
          initialType: state.uri.queryParameters['tipo'] == 'ingreso'
              ? MovementType.income
              : MovementType.expense,
          initialCard: state.uri.queryParameters['tarjeta'],
          initialCategory: state.uri.queryParameters['categoria'],
        ),
      ),
      GoRoute(
        path: Routes.account,
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const AccountScreen()),
      ),
      GoRoute(path: Routes.myMoney, builder: (_, _) => const MyMoneyScreen()),
      GoRoute(path: Routes.fixBalance, builder: (_, _) => const FixBalanceScreen()),
      GoRoute(path: Routes.payments, builder: (_, _) => const MoneyPaymentsScreen()),
      GoRoute(path: Routes.cards, builder: (_, _) => const CardsScreen()),
      GoRoute(path: Routes.debts, builder: (_, _) => const DebtsScreen()),
      GoRoute(
        path: Routes.plan,
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const PlanScreen()),
      ),
      GoRoute(path: Routes.budgets, builder: (_, _) => const BudgetsScreen()),
      GoRoute(
        path: '${Routes.budgets}/:category',
        // Sin `?mes=`, el mes en curso (BudgetDetail.jsx).
        builder: (_, state) => BudgetDetailScreen(
          category: state.pathParameters['category']!,
          month: _month(state.uri.queryParameters['mes']) ?? isoMonth(DateTime.now()),
        ),
      ),
      GoRoute(path: Routes.calendar, builder: (_, _) => const CalendarScreen()),
      GoRoute(path: Routes.liquidity, builder: (_, _) => const LiquidityScreen()),
      GoRoute(
        path: Routes.card(':id'),
        builder: (_, state) => CardDetailScreen(cardId: state.pathParameters['id']!),
      ),
      // Destinos de Rinde Web que aún no tienen pantalla: «En desarrollo». Todos bajo /app (con sesión).
      for (final module in pendingModules)
        if (module.tab != null)
          GoRoute(
            path: module.path,
            pageBuilder: (_, state) =>
                NoTransitionPage(key: state.pageKey, child: PendingModuleScreen(module)),
          )
        else
          GoRoute(
            path: module.path,
            builder: (_, state) => PendingModuleScreen(module, query: state.uri.queryParameters),
          ),
      // Después de los pendientes: /app/transacciones/exportar no es el movimiento «exportar».
      GoRoute(
        path: '/app/transacciones/:id',
        builder: (_, state) => MovementDetailScreen(movementId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/app/transacciones/:id/editar',
        builder: (_, state) => EditMovementScreen(movementId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// `?mes=AAAA-MM` válido (01 a 12), o null.
String? _month(String? raw) => raw != null && RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(raw) ? raw : null;

/// El correo viaja como `?correo=` para precargarlo (de registro a login, de login a recuperar).
String? _email(GoRouterState state) => state.uri.queryParameters['correo'];
