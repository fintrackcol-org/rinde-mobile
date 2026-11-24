import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/data/cards_repository.dart';

/// Repositorio de tarjetas con respuestas a la medida. Guarda cada llamada con lo enviado.
class FakeCardsRepository implements CardsRepository {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];

  Future<List<CreditCard>> Function() onList = () async => const [];
  Future<CreditCard> Function(String id) onGet = (id) async => throw UnimplementedError(id);
  Future<List<CardMovement>> Function(String id) onMovements = (id) async => const [];
  Future<CreditCard> Function(Map<String, dynamic> body) onCreate = (body) async =>
      throw UnimplementedError();
  Future<CreditCard> Function(String id, Map<String, dynamic> body) onUpdate = (id, body) async =>
      throw UnimplementedError(id);
  Future<void> Function(String id) onDelete = (id) async {};
  Future<void> Function(String id, num amount, String date) onPay = (id, amount, date) async {};
  Future<void> Function(String id, String paymentId) onDeletePayment = (id, paymentId) async {};
  Future<num?> Function(String id, Map<String, dynamic> body) onSync = (id, body) async => null;

  @override
  bool get isDemo => false;

  @override
  Future<List<CreditCard>> list() {
    calls.add('list');
    return onList();
  }

  @override
  Future<CreditCard> get(String id) {
    calls.add('get $id');
    return onGet(id);
  }

  @override
  Future<List<CardMovement>> movements(String id) {
    calls.add('movements $id');
    return onMovements(id);
  }

  @override
  Future<CreditCard> create(Map<String, dynamic> body) {
    calls.add('create');
    bodies.add(body);
    return onCreate(body);
  }

  @override
  Future<CreditCard> update(String id, Map<String, dynamic> body) {
    calls.add('update $id');
    bodies.add(body);
    return onUpdate(id, body);
  }

  @override
  Future<void> delete(String id) {
    calls.add('delete $id');
    return onDelete(id);
  }

  @override
  Future<void> pay(String id, {required num amount, required String date}) {
    calls.add('pay $id');
    bodies.add({'amount': amount, 'date': date});
    return onPay(id, amount, date);
  }

  @override
  Future<void> deletePayment(String id, String paymentId) {
    calls.add('deletePayment $id $paymentId');
    return onDeletePayment(id, paymentId);
  }

  @override
  Future<num?> syncWithBank(String id, Map<String, dynamic> body) {
    calls.add('sync $id');
    bodies.add(body);
    return onSync(id, body);
  }
}
