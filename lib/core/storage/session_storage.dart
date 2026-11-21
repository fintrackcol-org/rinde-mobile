import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/data/auth_models.dart';

/// Guarda la sesión fuera del alcance de otras apps (Keystore en Android, Keychain en iOS).
abstract class SessionStorage {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'rinde.session';
  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Un valor dañado no debe impedir abrir la app: se descarta y se pide entrar de nuevo.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) => _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Si el llavero falla al borrar, la sesión en memoria igual se descarta.
    }
  }
}

/// En memoria, para pruebas.
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this._session]);
  Session? _session;

  @override
  Future<Session?> read() async => _session;
  @override
  Future<void> write(Session session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
}

final sessionStorageProvider = Provider<SessionStorage>((ref) => SecureSessionStorage());
