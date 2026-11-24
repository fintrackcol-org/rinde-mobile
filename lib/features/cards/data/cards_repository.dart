import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/home_models.dart' show readList, readMap, readMoney;
import 'card_models.dart';
import 'demo_cards_repository.dart';

/// Tarjetas en el servidor (los mismos endpoints que cardService.js de Rinde Web).
/// - [ApiCardsRepository]: la real.
/// - `DemoCardsRepository`: MODO DEMOSTRACIÓN, guarda en el teléfono y nunca sale a la red.
///
/// Ninguna escritura de tarjetas es idempotente en el backend de hoy: las salvaguardas (un envío a
/// la vez, confirmar leyendo) viven en `CardsWriter`, no aquí.
abstract interface class CardsRepository {
  bool get isDemo;

  /// GET /cards, de la más antigua a la más nueva (orden del servidor).
  Future<List<CreditCard>> list();

  /// GET /cards/:id. 404 «Tarjeta no encontrada» si no existe o es de otro usuario.
  Future<CreditCard> get(String id);

  /// GET /cards/:id/movements: compras desde la base, todos los pagos y los ajustes negativos.
  Future<List<CardMovement>> movements(String id);

  /// POST /cards. El servidor guarda `deuda_base = cupo − disponible`.
  Future<CreditCard> create(Map<String, dynamic> body);

  /// PUT /cards/:id con SOLO los campos que cambiaron; nunca `available`.
  Future<CreditCard> update(String id, Map<String, dynamic> body);

  /// DELETE /cards/:id (borrado lógico). El 404 lo trata quien llama.
  Future<void> delete(String id);

  /// POST /cards/:id/payments. Resta de Mi plata y NO crea un movimiento. Con [idempotencyKey]
  /// (cabecera `Idempotency-Key`) el servidor lo aplica una sola vez: la repetición responde 201 con
  /// `Idempotent-Replayed: true`, que también es «hecho». Un servidor sin ese cambio la ignora.
  Future<void> pay(String id, {required num amount, required String date, String? idempotencyKey});

  /// DELETE /cards/:id/payments/:paymentId.
  Future<void> deletePayment(String id, String paymentId);

  /// POST /cards/:id/sync-with-bank. Devuelve el monto del gasto «Cargos del banco» si se creó.
  Future<num?> syncWithBank(String id, Map<String, dynamic> body);
}

class ApiCardsRepository implements CardsRepository {
  ApiCardsRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id) => '/cards/${Uri.encodeComponent(id)}';

  @override
  Future<List<CreditCard>> list() async => [
    // Estricto: una tarjeta ilegible falla el bloque entero (no se esconde en silencio).
    for (final item in readList(await _api.get('/cards'))) CreditCard.fromJson(item),
  ];

  @override
  Future<CreditCard> get(String id) async => CreditCard.fromJson(await _api.get(_path(id)));

  @override
  Future<List<CardMovement>> movements(String id) async => [
    for (final item in readList(await _api.get('${_path(id)}/movements'))) CardMovement.fromJson(item),
  ];

  @override
  Future<CreditCard> create(Map<String, dynamic> body) async =>
      CreditCard.fromJson(await _api.post('/cards', body: body, auth: true));

  @override
  Future<CreditCard> update(String id, Map<String, dynamic> body) async =>
      CreditCard.fromJson(await _api.put(_path(id), body: body));

  @override
  Future<void> delete(String id) => _delete(_path(id));

  @override
  Future<void> pay(String id, {required num amount, required String date, String? idempotencyKey}) =>
      _api.post(
        '${_path(id)}/payments',
        body: {'amount': amount, 'date': date},
        auth: true,
        headers: {'Idempotency-Key': ?idempotencyKey},
      );

  @override
  Future<void> deletePayment(String id, String paymentId) =>
      _delete('${_path(id)}/payments/${Uri.encodeComponent(paymentId)}');

  @override
  Future<num?> syncWithBank(String id, Map<String, dynamic> body) async {
    final result = readMap(await _api.post('${_path(id)}/sync-with-bank', body: body, auth: true));
    final charge = result['chargeTransaction'];
    return charge is Map ? readMoney(charge['amount']) : null;
  }

  Future<void> _delete(String path) => _api.delete(path);
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final cardsRepositoryProvider = Provider<CardsRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) return ref.watch(demoCardsRepositoryProvider(session.user.id));
  return ApiCardsRepository(ref.watch(apiClientProvider));
});
