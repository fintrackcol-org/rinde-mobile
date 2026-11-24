import 'package:rinde_mobile/features/debts/data/debt_models.dart';
import 'package:rinde_mobile/features/debts/data/debts_repository.dart';

/// Repositorio de cuentas con respuestas a la medida. Guarda cada llamada con lo enviado.
class FakeDebtsRepository implements DebtsRepository {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];

  Future<DebtsList> Function() onList = () async => const DebtsList(items: [], receivable: 0, payable: 0);
  Future<void> Function(Map<String, dynamic> body) onCreate = (body) async {};
  Future<void> Function(String id, Map<String, dynamic> body) onUpdate = (id, body) async {};
  Future<void> Function(String id) onDelete = (id) async {};
  Future<void> Function(String id, bool createTransaction) onSettle = (id, createTransaction) async {};
  Future<void> Function(String id, num amount, String date, bool createTransaction) onPay = (
    id,
    amount,
    date,
    createTransaction,
  ) async {};
  Future<Debt> Function(String id, String paymentId) onDeletePayment = (id, paymentId) async =>
      throw UnimplementedError(paymentId);

  int count(String call) => calls.where((c) => c == call || c.startsWith('$call ')).length;

  @override
  bool get isDemo => false;

  @override
  Future<DebtsList> list() {
    calls.add('list');
    return onList();
  }

  @override
  Future<void> create(Map<String, dynamic> body) {
    calls.add('create');
    bodies.add(body);
    return onCreate(body);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> body) {
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
  Future<void> settle(String id, {required bool createTransaction}) {
    calls.add('settle $id');
    bodies.add({'createTransaction': createTransaction});
    return onSettle(id, createTransaction);
  }

  @override
  Future<void> pay(String id, {required num amount, required String date, required bool createTransaction}) {
    calls.add('pay $id');
    bodies.add({'amount': amount, 'date': date, 'createTransaction': createTransaction});
    return onPay(id, amount, date, createTransaction);
  }

  @override
  Future<Debt> deletePayment(String id, String paymentId) {
    calls.add('deletePayment $id $paymentId');
    return onDeletePayment(id, paymentId);
  }
}
