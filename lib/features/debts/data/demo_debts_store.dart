import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../movements/data/json_list_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Cuentas de cada usuario demo en un almacén propio (`rinde.demo.cuentas.<userId>`), como las
//  tarjetas de la demo: fuera de DemoState. «Reiniciar demostración» las borra. En cuentas reales no
//  se guarda nada de cuentas en el teléfono.
// ─────────────────────────────────────────────────────────────────────────────

final demoDebtsStoreProvider = Provider<JsonListStore>(
  (ref) => const SecureJsonListStore('rinde.demo.cuentas.'),
);
