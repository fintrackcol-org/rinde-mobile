import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/app/router.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';

const _signedIn = AsyncData(
  SessionState(
    session: Session(
      user: AuthUser(id: 'u1', email: 'ana@rinde.co'),
      accessToken: 'a',
      refreshToken: 'r',
    ),
  ),
);
const _signedOut = AsyncData(SessionState());
const _loading = AsyncLoading<SessionState>();
final _error = AsyncError<SessionState>(Exception('llavero dañado'), StackTrace.empty);

String? _go(AsyncValue<SessionState> session, String location) =>
    sessionRedirect(session: session, location: location);

void main() {
  group('cargando la sesión', () {
    test('cualquier ruta va a /arranque', () {
      for (final l in [Routes.welcome, Routes.login, Routes.register, Routes.forgot, Routes.app]) {
        expect(_go(_loading, l), Routes.boot, reason: l);
      }
    });

    test('en /arranque se queda', () {
      expect(_go(_loading, Routes.boot), isNull);
    });
  });

  group('sin sesión', () {
    test('al abrir la app (/arranque) va a /bienvenida', () {
      expect(_go(_signedOut, Routes.boot), Routes.welcome);
    });

    test('dentro de /app (o una subruta) va a /login', () {
      expect(_go(_signedOut, Routes.app), Routes.login);
      expect(_go(_signedOut, '${Routes.app}/movimientos'), Routes.login);
    });

    test('una ruta que solo empieza igual que /app no cuenta como dentro', () {
      expect(_go(_signedOut, '/application'), isNull);
    });

    test('las pantallas de acceso se quedan donde están', () {
      for (final l in [Routes.welcome, Routes.login, Routes.register, Routes.forgot]) {
        expect(_go(_signedOut, l), isNull, reason: l);
      }
    });

    test('expirada se trata igual que sin sesión', () {
      expect(_go(const AsyncData(SessionState(expired: true)), Routes.app), Routes.login);
    });
  });

  group('con sesión', () {
    test('las pantallas de acceso y /arranque van a /app', () {
      for (final l in [Routes.boot, Routes.welcome, Routes.login, Routes.register, Routes.forgot]) {
        expect(_go(_signedIn, l), Routes.app, reason: l);
      }
    });

    test('dentro de /app se queda', () {
      expect(_go(_signedIn, Routes.app), isNull);
      expect(_go(_signedIn, '${Routes.app}/movimientos'), isNull);
    });
  });

  group('error al leer la sesión: se trata como sin sesión', () {
    test('/arranque → /bienvenida, /app → /login, /login se queda', () {
      expect(_go(_error, Routes.boot), Routes.welcome);
      expect(_go(_error, Routes.app), Routes.login);
      expect(_go(_error, Routes.login), isNull);
    });
  });
}
