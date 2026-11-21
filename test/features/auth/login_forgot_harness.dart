import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';

/// Repositorio falso: registra las llamadas y responde lo que diga cada prueba.
class FakeAuthRepository implements AuthRepository {
  final calls = <String>[];
  Future<Session> Function()? onLogin;
  Future<void> Function()? onForgot;
  Future<void> Function()? onResend;

  static const session = Session(
    user: AuthUser(id: 'u1', email: 'ana@correo.com'),
    accessToken: 'a',
    refreshToken: 'r',
  );

  @override
  Future<Session> login({required String email, required String password}) {
    calls.add('login:$email:$password');
    return onLogin?.call() ?? Future.value(session);
  }

  @override
  Future<void> forgotPassword(String email) {
    calls.add('forgot:$email');
    return onForgot?.call() ?? Future.value();
  }

  @override
  Future<void> resendVerification(String email) {
    calls.add('resend:$email');
    return onResend?.call() ?? Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Monta [screen] con un router mínimo (AuthScaffold lee GoRouterState) y el repositorio falso.
Future<void> pumpAuthScreen(WidgetTester tester, Widget screen, FakeAuthRepository repo) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/recuperar', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/registro', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
