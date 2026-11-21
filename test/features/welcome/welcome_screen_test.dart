import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/welcome/presentation/welcome_screen.dart';

/// Bienvenida dentro de un GoRouter propio con destinos falsos.
Widget _app({double textScale = 1, bool still = false}) {
  final router = GoRouter(
    initialLocation: Routes.welcome,
    routes: [
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const Text('registro falso')),
      GoRoute(path: Routes.login, builder: (_, _) => const Text('login falso')),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: RindeTheme.public,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: still),
        child: child!,
      ),
    ),
  );
}

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('muestra título, texto, botones y a Rin con su semántica', (tester) async {
    _phone(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Empieza a controlar tus gastos hoy.'), findsOneWidget);
    expect(
      find.text('Crea tu cuenta en menos de un minuto. Sin tarjeta, sin letra pequeña.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Rin, la mascota de Rinde, te saluda'), findsOneWidget);
    expect(find.bySemanticsLabel('Rinde'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Empieza a controlar tus gastos hoy.')),
      isSemantics(isHeader: true, label: 'Empieza a controlar tus gastos hoy.'),
    );
    for (final label in ['Crear cuenta gratis', 'Ya tengo cuenta']) {
      expect(
        tester.getSemantics(find.text(label)),
        isSemantics(label: label, isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
      );
      expect(tester.getSize(find.widgetWithText(InkWell, label)).height, greaterThanOrEqualTo(48));
    }
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  for (final (label, destination) in [
    ('Crear cuenta gratis', 'registro falso'),
    ('Ya tengo cuenta', 'login falso'),
  ]) {
    testWidgets('«$label» abre su pantalla', (tester) async {
      _phone(tester, const Size(390, 844));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 600));

      await tester.ensureVisible(find.text(label));
      await tester.pump();
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(destination), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a 320x568 con texto 1,3x no se desborda y deja llegar a los botones', (tester) async {
    _phone(tester, const Size(320, 568));
    await tester.pumpWidget(_app(textScale: 1.3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Ya tengo cuenta'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Ya tengo cuenta')).bottom, lessThanOrEqualTo(568));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con movimiento reducido no deja animaciones pendientes', (tester) async {
    _phone(tester, const Size(390, 844));
    await tester.pumpWidget(_app(still: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Empieza a controlar tus gastos hoy.'), findsOneWidget);
  });
}
