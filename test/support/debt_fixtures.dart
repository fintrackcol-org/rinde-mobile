import 'package:rinde_mobile/features/debts/data/debt_models.dart';

/// Una cuenta con la forma EXACTA de GET /debts de QA (23-nov-2026, cuenta sintética): «Prueba QA»,
/// 300.000 en 3 cuotas mensuales, con un abono de 100.000 (el `dueDate` leído ya es la 2.ª cuota).
Map<String, dynamic> debtJson({
  String id = '85d2a84f-a7fe-45c3-b46e-84d16a8e83b6',
  String kind = 'payable',
  String person = 'Prueba QA',
  num amount = 300000,
  String? dueDate = '2027-01-01',
  String? note = 'sintética',
  String? settledAt,
  String? transactionId,
  String? loanDate,
  int? installments = 3,
  String? frequency = 'monthly',
  String? firstDueDate = '2026-12-01',
  num paid = 100000,
  num? pending,
  int paidInstallments = 1,
  Map<String, dynamic>? nextInstallment = const {'number': 2, 'date': '2027-01-01', 'amount': 100000},
  List<Map<String, dynamic>>? payments,
}) => {
  'id': id,
  'kind': kind,
  'person': person,
  'amount': amount,
  'dueDate': dueDate,
  'note': note,
  'settledAt': settledAt,
  'transactionId': transactionId,
  'createdAt': '2026-11-23T22:44:25.428Z',
  'updatedAt': '2026-11-23T22:44:26.171Z',
  'loanDate': loanDate,
  'installments': installments,
  'frequency': frequency,
  'firstDueDate': firstDueDate,
  'paid': paid,
  'pending': pending ?? (settledAt == null ? amount - paid : 0),
  'paidInstallments': paidInstallments,
  'nextInstallment': settledAt == null ? nextInstallment : null,
  'payments':
      payments ??
      [
        {
          'id': 'b4ed7bf7-78f4-4264-87b0-e92d109905f8',
          'amount': 100000,
          'date': '2026-11-23',
          'transactionId': '359a15f5-01db-4c28-9f5d-f7ab570d9f11',
          'createdAt': '2026-11-23T22:44:26.171Z',
        },
      ],
  'reminder': const {
    'daysBefore': [1],
    'time': null,
    'channel': 'push',
  },
};

/// Una cuenta de una vez, sin abonos.
Map<String, dynamic> onceJson({
  String id = 'd2',
  String kind = 'receivable',
  String person = 'Laura',
  num amount = 60000,
  String? dueDate = '2026-11-30',
  String? note,
  String? settledAt,
  String? transactionId,
  num paid = 0,
  List<Map<String, dynamic>> payments = const [],
}) => debtJson(
  id: id,
  kind: kind,
  person: person,
  amount: amount,
  dueDate: dueDate,
  note: note,
  settledAt: settledAt,
  transactionId: transactionId,
  installments: null,
  frequency: null,
  firstDueDate: null,
  paid: paid,
  paidInstallments: 0,
  nextInstallment: dueDate == null || amount - paid <= 0
      ? null
      : {'number': 1, 'date': dueDate, 'amount': amount - paid},
  payments: payments,
);

Map<String, dynamic> debtsJson(List<Map<String, dynamic>> items) {
  num total(String kind) => items
      .where((d) => d['kind'] == kind && d['settledAt'] == null)
      .fold<num>(0, (sum, d) => sum + (d['pending'] is num ? d['pending'] as num : 0));
  return {
    'items': items,
    'totals': {'receivable': total('receivable'), 'payable': total('payable')},
  };
}

Debt debtOf([Map<String, dynamic>? json]) => Debt.fromJson(json ?? debtJson());

DebtsList debtsOf(List<Map<String, dynamic>> items) => DebtsList.fromJson(debtsJson(items));
