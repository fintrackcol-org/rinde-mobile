import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [DraftStore.read] no pudo leer (p. ej. teléfono bloqueado). No es lo mismo que «no hay borrador»:
/// sobre esto no se escribe ni se borra.
const draftUnreadable = 'borrador ilegible';

/// Dónde vive el BORRADOR LOCAL de la bienvenida. Una clave por usuario (`rinde.bienvenida.<id>`,
/// la misma idea de la web) y cifrado, porque tiene montos de plata. Nunca se registra en logs.
abstract class DraftStore {
  Future<Object?> read(String userId);
  Future<void> write(String userId, Map<String, dynamic> draft);
  Future<void> clear(String userId);
}

class SecureDraftStore implements DraftStore {
  const SecureDraftStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  String _key(String userId) => 'rinde.bienvenida.$userId';

  @override
  Future<Object?> read(String userId) async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key(userId));
    } catch (_) {
      // El llavero no respondió (p. ej. teléfono bloqueado): no se borra lo que no se pudo leer.
      return draftUnreadable;
    }
    try {
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      // Dañado: se empieza de cero sin bloquear la app.
      await clear(userId);
      return null;
    }
  }

  @override
  Future<void> write(String userId, Map<String, dynamic> draft) async {
    try {
      await _storage.write(key: _key(userId), value: jsonEncode(draft));
    } catch (_) {
      // Si el llavero falla, las respuestas siguen en memoria mientras la app esté abierta.
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {}
  }
}

/// En memoria, para pruebas.
class MemoryDraftStore implements DraftStore {
  final data = <String, String>{};
  int writes = 0;

  @override
  Future<Object?> read(String userId) async => data[userId] == null ? null : jsonDecode(data[userId]!);
  @override
  Future<void> write(String userId, Map<String, dynamic> draft) async {
    writes++;
    data[userId] = jsonEncode(draft);
  }

  @override
  Future<void> clear(String userId) async => data.remove(userId);
}

final draftStoreProvider = Provider<DraftStore>((ref) => const SecureDraftStore());
