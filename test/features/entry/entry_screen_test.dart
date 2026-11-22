import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/entry/presentation/entry_screen.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@correo.com', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _profile = UserProfile(
  id: 'u1',
  email: 'ana@correo.com',
  name: 'Ana',
  termsAccepted: true,
  country: 'CO',
  currency: 'COP',
  language: 'es',
);

WelcomeStatus _status({required bool done, bool movements = false}) =>
    WelcomeStatus(welcomeDone: done, tutorialDone: false, hasTransactions: movements);

/// Monta la entrada con un router mínimo; la bienvenida es un marcador.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Future<WelcomeStatus> Function() status,
  bool pendingSources = false,
}) async {
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => const EntryScreen()),
      GoRoute(path: '/app/bienvenida', builder: (_, _) => const Text('BIENVENIDA')),
      GoRoute(path: '/app/bienvenida/preguntas', builder: (_, _) => const Text('PREGUNTAS')),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sessionStorageProvider.overrideWithValue(MemorySessionStorage(_session)),
      profileProvider.overrideWith((ref) async => _profile),
      welcomeStatusProvider.overrideWith((ref) => status()),
      pendingSourcesProvider.overrideWith((ref) async => pendingSources),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: RindeTheme.light),
    ),
  );
  // Perfil, estado y la redirección (después del cuadro) con su transición.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  return container;
}

void main() {
  testWidgets('sin bienvenida y sin movimientos: va a la bienvenida', (tester) async {
    await _pump(tester, status: () async => _status(done: false));
    expect(find.text('BIENVENIDA'), findsOneWidget);
  });

  testWidgets('bienvenida hecha: se queda en el inicio', (tester) async {
    await _pump(tester, status: () async => _status(done: true));
    expect(find.text('BIENVENIDA'), findsNothing);
    expect(find.text('Hola, Ana'), findsOneWidget);
  });

  testWidgets('bienvenida hecha pero con fuentes pendientes en el dispositivo: retoma solo las preguntas', (
    tester,
  ) async {
    await _pump(tester, status: () async => _status(done: true), pendingSources: true);
    expect(find.text('PREGUNTAS'), findsOneWidget);
  });

  testWidgets('mientras se vuelve a pedir el estado, el valor viejo no redirige', (tester) async {
    var next = Completer<WelcomeStatus>()..complete(_status(done: false, movements: true));
    final c = await _pump(tester, status: () => next.future);
    expect(find.text('Hola, Ana'), findsOneWidget);

    // Al terminar la bienvenida se invalida: el dato viejo («pendiente») no debe mandar de vuelta.
    next = Completer<WelcomeStatus>();
    c.invalidate(welcomeStatusProvider);
    await tester.pump();
    expect(find.text('BIENVENIDA'), findsNothing);
    expect(find.text('Hola, Ana'), findsNothing);

    next.complete(_status(done: true, movements: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('BIENVENIDA'), findsNothing);
    expect(find.text('Hola, Ana'), findsOneWidget);
  });
}
