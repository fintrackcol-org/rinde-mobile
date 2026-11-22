import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_models.dart';
import '../config/app_config.dart';
import '../storage/session_storage.dart';

/// Dueño único de la sesión en memoria y en el almacenamiento seguro.
/// El cliente HTTP lo usa para poner el token y renovarlo; el controlador de sesión,
/// para saber si hay alguien dentro. Así ninguno depende del otro.
class SessionHolder {
  SessionHolder(this._storage, {this.allowDemo = false});

  final SessionStorage _storage;

  /// Si la compilación no es de demostración, una sesión demo guardada se descarta al abrir.
  final bool allowDemo;
  final _expired = StreamController<void>.broadcast();
  Session? _current;

  Session? get current => _current;

  /// Se emite cuando el servidor rechaza la renovación: hay que volver a entrar.
  Stream<void> get onExpired => _expired.stream;

  Future<Session?> load() async {
    final saved = await _storage.read();
    if (saved != null && saved.demo && !allowDemo) {
      await _storage.clear();
      return _current = null;
    }
    return _current = saved;
  }

  Future<void> save(Session session) async {
    _current = session;
    await _storage.write(session);
  }

  Future<void> clear() async {
    _current = null;
    await _storage.clear();
  }

  Future<void> expire() async {
    await clear();
    _expired.add(null);
  }

  void dispose() => _expired.close();
}

final sessionHolderProvider = Provider<SessionHolder>((ref) {
  final holder = SessionHolder(
    ref.watch(sessionStorageProvider),
    allowDemo: ref.watch(appConfigProvider).demoMode,
  );
  ref.onDispose(holder.dispose);
  return holder;
});
