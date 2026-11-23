import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_spinner.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';
import 'package:rinde_mobile/features/entry/presentation/entry_screen.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/home/presentation/home_screen.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/fake_home_repository.dart';
import '../../support/home_fixtures.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

UserProfile _profile({bool termsAccepted = true}) => UserProfile(
  id: 'u1',
  email: 'ana@rinde.co',
  name: 'Ana',
  termsAccepted: termsAccepted,
  country: 'CO',
  currency: 'COP',
  language: 'es',
);

const _accept = 'Acepto los términos y la política';

// Lo que la entrada sabe de la cuenta. El tutorial ya visto, para que el Inicio no abra nada encima.
final _newAccount = statusOf(welcomeDone: false, hasTransactions: false, money: null, balanceSet: false);
final _oldAccountNoWelcome = statusOf(welcomeDone: false);
final _done = statusOf();

/// La entrada solo se monta con la sesión ya leída (antes está el arranque).
class _SignedIn extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _session));
}

class _Auth implements AuthRepository {
  Future<UserProfile> Function() onAccept = () async => _profile();
  int accepted = 0;

  @override
  Future<UserProfile> acceptTerms() {
    accepted++;
    return onAccept();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// La entrada montada con un router mínimo. La bienvenida y sus preguntas son marcadores; el Inicio
/// es el de verdad, con un repositorio de prueba (lo que dibuja se prueba aparte).
class _Entry {
  Future<UserProfile> Function() profile = () async => _profile();
  Future<WelcomeStatus> Function() status = () async => _done;
  Future<bool> Function() pendingSources = () async => false;
  int statusCalls = 0;
  final auth = _Auth();

  late final router = GoRouter(
    initialLocation: Routes.app,
    routes: [
      GoRoute(path: Routes.app, builder: (_, _) => const EntryScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const Text('BIENVENIDA')),
      GoRoute(path: Routes.onboardingQuestions, builder: (_, _) => const Text('PREGUNTAS')),
    ],
  );

  Future<void> open(WidgetTester tester) async {
    addTearDown(router.dispose);
    await tester.pumpWidget(
      // ProviderScope (y no un contenedor suelto): al desmontarse cancela los temporizadores del Inicio.
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sessionStorageProvider.overrideWithValue(MemorySessionStorage(_session)),
          sessionControllerProvider.overrideWith(_SignedIn.new),
          authRepositoryProvider.overrideWithValue(auth),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
          profileProvider.overrideWith((ref, _) => profile()),
          welcomeStatusProvider.overrideWith((ref, _) {
            statusCalls++;
            return status();
          }),
          pendingSourcesProvider.overrideWith((ref, _) => pendingSources()),
        ],
        child: MaterialApp.router(routerConfig: router, theme: RindeTheme.light),
      ),
    );
    await settle(tester);
  }

  /// Perfil, estado y la redirección (que sale después del cuadro) con su transición.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  String get location => router.state.matchedLocation;
}

/// Qué decidió la entrada, en una palabra.
String _showing() {
  bool has(Finder finder) => finder.evaluate().isNotEmpty;
  if (has(find.byType(HomeScreen))) return 'inicio';
  if (has(find.text('BIENVENIDA'))) return 'bienvenida';
  if (has(find.text('PREGUNTAS'))) return 'preguntas';
  if (has(find.text(_accept))) return 'términos';
  if (has(find.byType(RindeSpinner))) return 'espera';
  return 'nada';
}

/// Desmonta la app para montar otra en la misma prueba.
Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('términos', () {
    testWidgets('sin aceptar los vigentes: bloquea, y ni siquiera pregunta por la bienvenida', (
      tester,
    ) async {
      final entry = _Entry()
        ..profile = (() async => _profile(termsAccepted: false))
        ..status = (() async => _newAccount);
      await entry.open(tester);

      expect(_showing(), 'términos');
      expect(find.text('Leer los términos de uso'), findsOneWidget);
      expect(find.text('Leer la política de privacidad'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(entry.statusCalls, 0);
      expect(entry.location, Routes.app);
    });

    testWidgets('al aceptarlos sigue: una cuenta nueva pasa a la bienvenida', (tester) async {
      var accepted = false;
      final entry = _Entry()
        ..profile = (() async => _profile(termsAccepted: accepted))
        ..status = (() async => _newAccount);
      entry.auth.onAccept = () async {
        accepted = true;
        return _profile();
      };
      await entry.open(tester);

      await tester.ensureVisible(find.text(_accept));
      await tester.tap(find.text(_accept));
      await entry.settle(tester);

      expect(entry.auth.accepted, 1);
      expect(_showing(), 'bienvenida');
    });

    testWidgets('si aceptar falla, lo dice y se queda en los términos', (tester) async {
      final entry = _Entry()..profile = (() async => _profile(termsAccepted: false));
      entry.auth.onAccept = () async => throw offlineError;
      await entry.open(tester);

      await tester.ensureVisible(find.text(_accept));
      await tester.tap(find.text(_accept));
      await entry.settle(tester);

      expect(_showing(), 'términos');
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(entry.statusCalls, 0);
    });
  });

  testWidgets('términos: ni recargar ni que la recarga falle levanta el bloqueo', (tester) async {
    var down = false;
    final entry = _Entry()
      ..profile = (() async => down ? throw offlineError : _profile(termsAccepted: false));
    await entry.open(tester);
    expect(_showing(), 'términos');

    down = true;
    entry.container(tester).invalidate(profileProvider);
    await entry.settle(tester);
    expect(_showing(), 'términos');
    expect(entry.statusCalls, 0);
  });

  group('perfil', () {
    testWidgets('espera solo la primera vez que se pide', (tester) async {
      final first = Completer<UserProfile>();
      final entry = _Entry()..profile = (() => first.future);
      await entry.open(tester);
      expect(_showing(), 'espera');
      expect(entry.statusCalls, 0);

      first.complete(_profile());
      await entry.settle(tester);
      expect(_showing(), 'inicio');

      // Una recarga del perfil no tapa el Inicio.
      entry.profile = () => Completer<UserProfile>().future;
      entry.container(tester).invalidate(profileProvider);
      await entry.settle(tester);
      expect(_showing(), 'inicio');
    });

    testWidgets('si el perfil no llega no se bloquea la entrada', (tester) async {
      for (final error in [offlineError, serverError]) {
        final entry = _Entry()..profile = (() async => throw error);
        await entry.open(tester);
        expect(_showing(), 'inicio', reason: '$error');
        await _close(tester);
      }
    });
  });

  group('bienvenida: solo con un dato fresco del servidor', () {
    testWidgets('sin bienvenida y sin movimientos: va a la bienvenida completa', (tester) async {
      final entry = _Entry()..status = (() async => _newAccount);
      await entry.open(tester);
      expect(_showing(), 'bienvenida');
      expect(entry.location, Routes.onboarding);
    });

    testWidgets('sin bienvenida pero con movimientos: se queda en el Inicio (que invita)', (tester) async {
      final entry = _Entry()..status = (() async => _oldAccountNoWelcome);
      await entry.open(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });

    testWidgets('bienvenida hecha: se queda en el Inicio, con o sin movimientos', (tester) async {
      for (final status in [_done, statusOf(hasTransactions: false)]) {
        final entry = _Entry()..status = (() async => status);
        await entry.open(tester);
        expect(_showing(), 'inicio');
        expect(entry.location, Routes.app);
        await _close(tester);
      }
    });

    testWidgets('mientras llega por primera vez espera: ni Inicio ni redirección', (tester) async {
      final first = Completer<WelcomeStatus>();
      final entry = _Entry()..status = (() => first.future);
      await entry.open(tester);
      expect(_showing(), 'espera');
      expect(entry.location, Routes.app);

      first.complete(_newAccount);
      await entry.settle(tester);
      expect(_showing(), 'bienvenida');
    });

    testWidgets('si no se pudo saber (sin conexión o falló el servidor) no redirige: entra al Inicio', (
      tester,
    ) async {
      for (final error in [offlineError, serverError]) {
        final entry = _Entry()..status = (() async => throw error);
        await entry.open(tester);
        expect(_showing(), 'inicio', reason: '$error');
        expect(entry.location, Routes.app);
        await _close(tester);
      }
    });

    testWidgets('mientras se vuelve a pedir, el Inicio sigue a la vista y lo viejo no decide', (
      tester,
    ) async {
      final entry = _Entry()..status = (() async => _oldAccountNoWelcome);
      await entry.open(tester);
      expect(_showing(), 'inicio');

      final next = Completer<WelcomeStatus>();
      entry.status = () => next.future;
      entry.container(tester).invalidate(welcomeStatusProvider);
      await entry.settle(tester);
      expect(_showing(), 'inicio');
      expect(entry.statusCalls, 2);

      // El dato fresco sí decide: ya no hay movimientos y la bienvenida sigue sin hacerse.
      next.complete(_newAccount);
      await entry.settle(tester);
      expect(_showing(), 'bienvenida');
    });

    testWidgets('si la recarga falla, no redirige con el dato viejo', (tester) async {
      final entry = _Entry()..status = (() async => _oldAccountNoWelcome);
      await entry.open(tester);

      entry.status = () async => throw offlineError;
      entry.container(tester).invalidate(welcomeStatusProvider);
      await entry.settle(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });
  });

  group('justo al terminar la bienvenida', () {
    /// Cuenta nueva que la entrada mandó a la bienvenida; al terminarla, la bienvenida invalida el
    /// estado y vuelve a /app antes de que el servidor responda.
    Future<(_Entry, Completer<WelcomeStatus>)> finishWelcome(WidgetTester tester) async {
      final entry = _Entry()..status = (() async => _newAccount);
      await entry.open(tester);
      expect(_showing(), 'bienvenida');

      final fresh = Completer<WelcomeStatus>();
      entry.status = () => fresh.future;
      entry.container(tester).invalidate(welcomeStatusProvider);
      entry.router.go(Routes.app);
      await entry.settle(tester);
      return (entry, fresh);
    }

    testWidgets('el dato viejo («cuenta nueva») no devuelve a la bienvenida ni deja ver un Inicio falso', (
      tester,
    ) async {
      final (entry, fresh) = await finishWelcome(tester);
      expect(_showing(), 'espera');
      expect(entry.location, Routes.app);

      fresh.complete(statusOf(hasTransactions: false, money: 850000));
      await entry.settle(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });

    testWidgets('si esa respuesta falla, entra al Inicio (que dice qué falló) y no vuelve a la bienvenida', (
      tester,
    ) async {
      final (entry, fresh) = await finishWelcome(tester);
      fresh.completeError(offlineError);
      await entry.settle(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });
  });

  group('fuentes de ingreso pendientes en este dispositivo', () {
    testWidgets('bienvenida guardada: retoma solo las preguntas de plata', (tester) async {
      final entry = _Entry()..pendingSources = (() async => true);
      await entry.open(tester);
      expect(_showing(), 'preguntas');
      expect(entry.location, Routes.onboardingQuestions);
    });

    testWidgets('si en esta sesión ya dijo que después, no la devuelve ahí: llega al Inicio', (tester) async {
      final entry = _Entry()..pendingSources = (() async => true);
      await entry.open(tester);
      expect(_showing(), 'preguntas');

      // Lo que hace la pantalla de preguntas al salir sin terminar.
      entry.container(tester).read(resumeDeferredProvider.notifier).defer();
      entry.router.go(Routes.app);
      await entry.settle(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });

    testWidgets('sin la bienvenida guardada no se retoman las preguntas sueltas', (tester) async {
      // Cuenta nueva: la bienvenida completa. Cuenta con movimientos: el Inicio.
      final fresh = _Entry()
        ..status = (() async => _newAccount)
        ..pendingSources = (() async => true);
      await fresh.open(tester);
      expect(_showing(), 'bienvenida');
      await _close(tester);

      final old = _Entry()
        ..status = (() async => _oldAccountNoWelcome)
        ..pendingSources = (() async => true);
      await old.open(tester);
      expect(_showing(), 'inicio');
    });

    testWidgets('mientras no se sabe si quedó algo pendiente, espera en vez de mostrar el Inicio y saltar', (
      tester,
    ) async {
      final pending = Completer<bool>();
      final entry = _Entry()..pendingSources = (() => pending.future);
      await entry.open(tester);
      expect(_showing(), 'espera');

      pending.complete(true);
      await entry.settle(tester);
      expect(_showing(), 'preguntas');
    });

    testWidgets('si el estado no llegó, lo pendiente no redirige', (tester) async {
      final entry = _Entry()
        ..status = (() async => throw offlineError)
        ..pendingSources = (() async => true);
      await entry.open(tester);
      expect(_showing(), 'inicio');
      expect(entry.location, Routes.app);
    });
  });
}
