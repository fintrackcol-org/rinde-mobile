import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/presentation/login_screen.dart';
import 'package:rinde_mobile/features/auth/presentation/register_screen.dart';
import 'package:rinde_mobile/features/welcome/presentation/welcome_screen.dart';

/// Recorrido real con el router de la app: bienvenida → login → registro (selector) → atrás.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionStorageProvider.overrideWithValue(MemorySessionStorage())],
        child: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: const RindeApp()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin sesión abre la bienvenida', (tester) async {
    await pumpApp(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('el selector cambia de login a registro y atrás vuelve a la bienvenida', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ya tengo cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await tester.tap(find.text('Iniciar sesión').first);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // Atrás del sistema: vuelve a la bienvenida, no sale de la app.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
