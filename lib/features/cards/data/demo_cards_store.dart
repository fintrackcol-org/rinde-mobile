import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../movements/data/json_list_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Tarjetas de cada usuario demo en un almacén propio (`rinde.demo.tarjetas.<userId>`), como los
//  movimientos de la demo. NO van dentro de DemoState: sus `withX` copian cada campo a mano y un
//  olvido borraría las tarjetas (riesgo 5 del plan).
// ─────────────────────────────────────────────────────────────────────────────

final demoCardsStoreProvider = Provider<JsonListStore>(
  (ref) => const SecureJsonListStore('rinde.demo.tarjetas.'),
);

/// Las tarjetas guardadas de un recorrido, crudas. Un llavero ilegible falla en vez de leerse como
/// vacío: escribir encima borraría lo guardado.
Future<List<Map<String, dynamic>>> readDemoCards(JsonListStore store, String userId) async {
  final raw =
      await store.read(userId) ?? (throw StateError('No se pudieron leer las tarjetas de la demostración'));
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// El nombre que se muestra: el de la persona o el por defecto que pondría el servidor
/// («Visa Gold ••1234»). La demo lo arma en español, como una cuenta creada en es.
String demoCardDisplayName(Map<String, dynamic> raw) {
  if (raw['name'] is String && (raw['name'] as String).isNotEmpty) return raw['name'] as String;
  const networks = {'visa': 'Visa', 'mastercard': 'Mastercard', 'amex': 'Amex', 'otra': 'Otra'};
  const tiers = {
    'clasica': 'Clásica',
    'gold': 'Gold',
    'platinum': 'Platinum',
    'black': 'Black',
    'green': 'Green',
    'blue': 'Blue',
  };
  final network = networks[raw['network']] ?? 'Otra';
  final label = raw['network'] == 'otra' ? network : '$network ${tiers[raw['tier']] ?? ''}'.trim();
  return '$label ••${raw['last4']}';
}
