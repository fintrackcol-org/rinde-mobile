import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/presentation/forgot_password_screen.dart';

import 'login_forgot_harness.dart';

void main() {
  late FakeAuthRepository repo;
  setUp(() => repo = FakeAuthRepository());

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
  }

  testWidgets('vacío e inválido muestran los textos de la web', (tester) async {
    await pumpAuthScreen(tester, const ForgotPasswordScreen(), repo);
    await submit(tester);
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ana@');
    await tester.pump();
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('envía el correo precargado normalizado y pasa a "Revisa tu correo"', (tester) async {
    await pumpAuthScreen(tester, const ForgotPasswordScreen(initialEmail: ' Ana@Correo.com'), repo);
    await submit(tester);
    expect(repo.calls, ['forgot:ana@correo.com']);
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(find.text('El enlace vence en 30 minutos y sirve una sola vez.'), findsOneWidget);

    await tester.ensureVisible(find.text('Usar otro correo'));
    await tester.tap(find.text('Usar otro correo'));
    await tester.pumpAndSettle();
    expect(find.text('Recupera tu contraseña'), findsOneWidget);
  });

  testWidgets('error del servidor', (tester) async {
    repo.onForgot = () => Future.error(const ApiException(code: ApiCodes.network));
    await pumpAuthScreen(tester, const ForgotPasswordScreen(initialEmail: 'ana@correo.com'), repo);
    await submit(tester);
    expect(find.text(ApiMessages.network), findsOneWidget);
    expect(find.text('Revisa tu correo'), findsNothing);
  });
}
