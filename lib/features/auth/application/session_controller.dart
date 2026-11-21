import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/session_holder.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

class SessionState {
  const SessionState({this.session, this.expired = false});

  final Session? session;

  /// La sesión terminó porque el servidor rechazó la renovación (no porque la persona salió).
  /// El login lo usa para explicar por qué volvió ahí, cosa que la web no hace.
  final bool expired;

  bool get signedIn => session != null;
}

/// Quién está dentro. Arranca leyendo el almacenamiento seguro.
class SessionController extends AsyncNotifier<SessionState> {
  SessionHolder get _holder => ref.read(sessionHolderProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<SessionState> build() async {
    final sub = _holder.onExpired.listen((_) => state = const AsyncData(SessionState(expired: true)));
    ref.onDispose(sub.cancel);
    return SessionState(session: await _holder.load());
  }

  /// Lanza ApiException si el servidor rechaza; la pantalla decide el mensaje.
  Future<void> signIn({required String email, required String password}) async {
    final session = await _repo.login(email: email, password: password);
    await _holder.save(session);
    state = AsyncData(SessionState(session: session));
  }

  /// Cierra la sesión en el servidor si se puede; en el dispositivo, siempre.
  Future<void> signOut() async {
    final current = _holder.current;
    if (current != null) {
      try {
        // Tope corto: cerrar sesión en el dispositivo no puede esperar a un servidor dormido.
        await _repo.logout(current.refreshToken).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Sin red o token vencido: igual se borra aquí. El refresh caduca solo en 30 días.
      }
    }
    await _holder.clear();
    state = const AsyncData(SessionState());
  }
}

final sessionControllerProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Perfil del usuario dentro (términos y región). Se vuelve a pedir al cambiar de usuario.
final profileProvider = FutureProvider<UserProfile>((ref) {
  ref.watch(sessionControllerProvider.select((s) => s.value?.session?.user.id));
  return ref.read(authRepositoryProvider).me();
});
