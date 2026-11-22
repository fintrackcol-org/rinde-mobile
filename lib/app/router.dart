import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/entry/presentation/boot_screen.dart';
import '../features/entry/presentation/entry_screen.dart';
import '../features/onboarding/domain/onboarding_flow.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/welcome/presentation/welcome_screen.dart';
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
      GoRoute(path: Routes.app, builder: (_, _) => const EntryScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(mode: OnboardingMode.full),
      ),
      GoRoute(
        path: Routes.onboardingQuestions,
        builder: (_, _) => const OnboardingScreen(mode: OnboardingMode.questions),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// El correo viaja como `?correo=` para precargarlo (de registro a login, de login a recuperar).
String? _email(GoRouterState state) => state.uri.queryParameters['correo'];
