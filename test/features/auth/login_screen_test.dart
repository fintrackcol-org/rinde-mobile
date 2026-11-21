import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/presentation/login_screen.dart';

import 'login_forgot_harness.dart';

void main() {
  late FakeAuthRepository repo;
  setUp(() => repo = FakeAuthRepository());

  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField).at(label == 'email' ? 0 : 1);

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(field('email'), email);
    await tester.enterText(field('password'), password);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Iniciar sesión').last);
    await tester.tap(find.text('Iniciar sesión').last);
    await tester.pump();
  }

  testWidgets('vacío muestra los dos errores y no llama al servidor', (tester) async {
    await pumpAuthScreen(tester, const LoginScreen(), repo);
    await submit(tester);
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('correo inválido', (tester) async {
    await pumpAuthScreen(tester, const LoginScreen(), repo);
    await fill(tester, 'ana@correo', 'secreta1');
    await submit(tester);
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('envía el correo normalizado y muestra "Ingresando…" mientras espera', (tester) async {
    final pending = Completer<Session>();
    repo.onLogin = () => pending.future;
    await pumpAuthScreen(tester, const LoginScreen(), repo);
    await fill(tester, '  Ana@Correo.COM ', 'secreta1');
    await submit(tester);
    expect(repo.calls, ['login:ana@correo.com:secreta1']);
    expect(find.text('Ingresando…'), findsOneWidget);
    pending.complete(FakeAuthRepository.session);
    await tester.pumpAndSettle();
    expect(find.text('Ingresando…'), findsNothing);
  });

  testWidgets('UNAUTHORIZED', (tester) async {
    repo.onLogin = () => Future.error(const ApiException(code: ApiCodes.unauthorized, serverMessage: 'x'));
    await pumpAuthScreen(tester, const LoginScreen(initialEmail: 'ana@correo.com'), repo);
    await tester.enterText(field('password'), 'mala1234');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('Reenviar enlace'), findsNothing);
  });

  testWidgets('EMAIL_NOT_VERIFIED ofrece reenviar y luego espera 60 s', (tester) async {
    repo.onLogin = () => Future.error(const ApiException(code: ApiCodes.emailNotVerified));
    await pumpAuthScreen(tester, const LoginScreen(), repo);
    await fill(tester, 'ana@correo.com', 'secreta1');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Confirma tu correo para entrar: abre el enlace que te enviamos.'), findsOneWidget);

    await tester.ensureVisible(find.text('Reenviar enlace'));
    await tester.tap(find.text('Reenviar enlace'));
    await tester.pump();
    expect(repo.calls.last, 'resend:ana@correo.com');
    expect(find.text('Te enviamos un enlace nuevo. Revisa tu correo.'), findsOneWidget);
    expect(find.text('Reenviar enlace en 1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Reenviar enlace'), findsOneWidget);
  });

  testWidgets('sin red muestra el mensaje de conexión', (tester) async {
    repo.onLogin = () => Future.error(const ApiException(code: ApiCodes.network));
    await pumpAuthScreen(tester, const LoginScreen(), repo);
    await fill(tester, 'ana@correo.com', 'secreta1');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text(ApiMessages.network), findsOneWidget);
  });
}
