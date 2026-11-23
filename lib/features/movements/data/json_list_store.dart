import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Una lista JSON por usuario en el almacenamiento seguro (`<prefijo><userId>`). La usan la cola de
/// pendientes y los movimientos de la demostración.
abstract class JsonListStore {
  /// null: el llavero no respondió o el valor está dañado. Quien escribe no debe pisar lo que no
  /// pudo leer.
  Future<List<Object?>?> read(String userId);

  Future<void> write(String userId, List<Object?> items);
}

class SecureJsonListStore implements JsonListStore {
  const SecureJsonListStore(this.prefix, [this._storage = const FlutterSecureStorage()]);

  final String prefix;
  final FlutterSecureStorage _storage;

  @override
  Future<List<Object?>?> read(String userId) async {
    try {
      final raw = await _storage.read(key: '$prefix$userId');
      if (raw == null) return [];
      final list = jsonDecode(raw);
      return list is List ? list : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String userId, List<Object?> items) =>
      _storage.write(key: '$prefix$userId', value: jsonEncode(items));
}

/// En memoria, para pruebas. Guarda el JSON, como el almacenamiento real.
class MemoryJsonListStore implements JsonListStore {
  final data = <String, String>{};

  /// Simula un llavero que no responde al leer.
  bool failReads = false;

  @override
  Future<List<Object?>?> read(String userId) async {
    if (failReads) return null;
    final raw = data[userId];
    return raw == null ? [] : jsonDecode(raw) as List;
  }

  @override
  Future<void> write(String userId, List<Object?> items) async => data[userId] = jsonEncode(items);
}
