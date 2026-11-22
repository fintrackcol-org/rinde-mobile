import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'region.dart';

/// Guarda la región en el dispositivo para abrir con el formato correcto antes de hablar con el
/// servidor (en la web, localStorage `rinde.region`). No es un secreto, pero se usa el mismo
/// almacenamiento seguro para no sumar otra dependencia.
class RegionStore {
  RegionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'rinde.region';
  final FlutterSecureStorage _storage;

  Future<Region?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : Region.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Region region) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(region.toJson()));
    } catch (_) {
      // Sin almacenamiento dura hasta cerrar la app, como en la web.
    }
  }
}

/// Región con la que abre la app (la guardada o la de los idiomas del sistema). Se fija en main.
final initialRegionProvider = Provider<Region>((ref) => kDefaultRegion);

final regionStoreProvider = Provider<RegionStore>((ref) => RegionStore());

/// Región vigente: país, moneda principal e idioma.
class AppRegion extends Notifier<Region> {
  @override
  Region build() => ref.watch(initialRegionProvider);

  /// Solo después de que el servidor la confirmó (o en demostración, sin guardarla): no es un borrador.
  Future<void> set(Region region, {bool persist = true}) async {
    state = region;
    if (persist) await ref.read(regionStoreProvider).write(region);
  }
}

final appRegionProvider = NotifierProvider<AppRegion, Region>(AppRegion.new);
