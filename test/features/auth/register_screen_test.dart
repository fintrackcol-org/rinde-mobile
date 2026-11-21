import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/design/widgets/rinde_checkbox.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';
import 'package:rinde_mobile/features/auth/presentation/register_screen.dart';

/// Repositorio falso: guarda lo que se envió y responde lo que diga [onRegister].
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.onRegister});

  Future<String> Function(String email)? onRegister;
  final calls = <Map<String, String>>[];
  final resent = <String>[];

  @override
  Future<String> register({required String name, required String email, required String password}) {
    calls.add({'name': name, 'email': email, 'password': password});
    return onRegister?.call(email) ?? Future.value(email);
  }

  @override
  Future<void> resendVerification(String email) async => resent.add(email);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeAuthRepository> _open(WidgetTester tester, {_FakeAuthRepository? repo}) async {
  final fake = repo ?? _FakeAuthRepository();
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.register,
    routes: [
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.login,
        builder: (_, state) => Text('login:${state.uri.queryParameters['correo'] ?? ''}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Finder _field(int i) => find.byType(TextFormField).at(i);

/// Toca la casilla (no la etiqueta, que tiene enlaces).
Future<void> _tapTerms(WidgetTester tester) async {
  await tester.tapAt(tester.getTopLeft(find.byType(RindeCheckboxField)) + const Offset(12, 24));
  await tester.pump();
}

Future<void> _fillValid(WidgetTester tester) async {
  await tester.enterText(_field(0), '  Ana   María ');
  await tester.enterText(_field(1), ' Ana@Correo.COM ');
  await tester.enterText(_field(2), 'clave1234');
  await _tapTerms(tester);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Crear cuenta').last);
  await tester.pump();
}

/// Desmonta la pantalla para que no quede corriendo la cuenta regresiva del reenvío.
Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('muestra el error exacto de cada campo y no envía', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(_field(0), '    ');
    await tester.enterText(_field(1), 'ana@correo');
    await tester.enterText(_field(2), 'abcdefgh');
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu nombre: no puede quedar solo con espacios.'), findsOneWidget);
    expect(
      find.text('Al correo le falta algo: revisa la @ y el final, por ejemplo .com o .co'),
      findsOneWidget,
    );
    expect(find.text('Incluye al menos un número'), findsOneWidget);
    expect(find.text('Debes ser mayor de edad y aceptar los términos para continuar'), findsOneWidget);
    // La ayuda se oculta cuando el campo tiene error.
    expect(find.text('Así te saludamos en la app.'), findsNothing);
    expect(repo.calls, isEmpty);
  });

  testWidgets('las reglas pasan de pendiente a cumplido al escribir', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    for (final rule in ['8 caracteres o más', 'Una letra', 'Un número']) {
      expect(find.bySemanticsLabel('$rule (pendiente)'), findsOneWidget);
    }

    await tester.enterText(_field(2), 'a');
    await tester.pump();
    expect(find.bySemanticsLabel('Una letra (cumplido)'), findsOneWidget);
    expect(find.bySemanticsLabel('Un número (pendiente)'), findsOneWidget);

    await tester.enterText(_field(2), 'clave1234');
    await tester.pump();
    for (final rule in ['8 caracteres o más', 'Una letra', 'Un número']) {
      expect(find.bySemanticsLabel('$rule (cumplido)'), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('envía nombre normalizado y correo en minúsculas; muestra "Confirma tu correo"', (
    tester,
  ) async {
    final done = Completer<String>();
    final repo = await _open(tester, repo: _FakeAuthRepository(onRegister: (_) => done.future));
    await _fillValid(tester);
    await _submit(tester);

    expect(repo.calls.single, {'name': 'Ana María', 'email': 'ana@correo.com', 'password': 'clave1234'});
    // Mientras envía: texto de carga y botón inactivo (no envía dos veces).
    expect(find.text('Creando cuenta…'), findsOneWidget);
    await tester.tap(find.text('Creando cuenta…'));
    await tester.pump();
    expect(repo.calls, hasLength(1));

    done.complete('ana@correo.com');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Confirma tu correo'), findsOneWidget);
    expect(
      find.text(
        'Te enviamos un enlace a ana@correo.com. Ábrelo para activar tu cuenta y entrar.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Iniciar sesión'), findsNothing, reason: 'sin selector en la confirmación');

    await tester.tap(find.text('Ya lo confirmé, iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('login:ana@correo.com'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('"Usar otro correo" vuelve al formulario con los datos', (tester) async {
    await _open(tester);
    await _fillValid(tester);
    await _submit(tester);
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Usar otro correo'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Que tu plata alcance'), findsOneWidget);
    expect(find.text(' Ana@Correo.COM '), findsOneWidget);
    await _close(tester);
  });

  testWidgets('EMAIL_TAKEN muestra el texto propio', (tester) async {
    await _open(
      tester,
      repo: _FakeAuthRepository(
        onRegister: (_) => Future.error(
          const ApiException(
            code: ApiCodes.emailTaken,
            status: 409,
            serverMessage: 'El correo ya está registrado',
          ),
        ),
      ),
    );
    await _fillValid(tester);
    await _submit(tester);
    await tester.pump();

    expect(find.text('Ya existe una cuenta con ese correo.'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsWidgets);
  });

  testWidgets('el 422 se muestra en el aviso y en su campo, y se borra al editar', (tester) async {
    await _open(
      tester,
      repo: _FakeAuthRepository(
        onRegister: (_) => Future.error(
          const ApiException(
            code: ApiCodes.validation,
            status: 422,
            fields: {'email': 'Debe ser un correo válido'},
          ),
        ),
      ),
    );
    await _fillValid(tester);
    await _submit(tester);
    await tester.pump();
    expect(find.text('Debe ser un correo válido'), findsNWidgets(2));

    await tester.enterText(_field(1), 'otra@correo.com');
    await tester.pump();
    expect(find.text('Debe ser un correo válido'), findsOneWidget, reason: 'queda solo el aviso');
  });
}
