/// Modelos de Cuentas (deudas) con el contrato de `/api/v1/debts` de Rinde Web (formas reales de QA,
/// 23-nov-2026). Son ESTRICTOS, como Tarjetas: una cuenta ilegible falla el bloque entero en vez de
/// desaparecer en silencio. Los importes (`paid`, `pending`, `paidInstallments`, `nextInstallment`,
/// `totals`) los calcula SIEMPRE el servidor; aquí solo se leen.
///
/// `reminder` llega en cada cuenta y no se modela: la app no porta «Avisarme» (plan §6.1) y nada lo
/// usa. Al editar no se manda, y el servidor conserva el aviso que ya tenía.
library;

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readMap, readList, readMoney;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? _isoOrNull(Object? raw, String key) {
  if (raw == null) return null;
  if (raw is String && _isoDate.hasMatch(raw)) return raw;
  throw ContractException('"$key" no es una fecha AAAA-MM-DD');
}

String? _textOrNull(Object? raw, String key) {
  if (raw == null || raw is String) return raw as String?;
  throw ContractException('"$key" no es un texto');
}

num _money(Map<String, dynamic> json, String key) =>
    readMoney(json[key]) ?? (throw ContractException('Falta "$key" o no es un número'));

/// `receivable` = me deben; `payable` = debo.
enum DebtKind {
  receivable('receivable'),
  payable('payable');

  const DebtKind(this.wire);
  final String wire;

  static DebtKind? fromWire(Object? value) => values.where((k) => k.wire == value).firstOrNull;
}

/// Cada cuánto se paga una cuenta en cuotas. Quincenal = cada 15 días (debt-schedule.js).
enum DebtFrequency {
  weekly('weekly'),
  biweekly('biweekly'),
  monthly('monthly');

  const DebtFrequency(this.wire);
  final String wire;

  static DebtFrequency? fromWire(Object? value) => values.where((f) => f.wire == value).firstOrNull;
}

/// Una cuota: la próxima que manda el servidor (`nextInstallment`) o una de la vista previa.
class Installment {
  const Installment({required this.number, required this.date, required this.amount});

  factory Installment.fromJson(Object? data) {
    final json = readMap(data);
    final number = json['number'];
    if (number is! int) throw const ContractException('Falta "number" de la cuota');
    return Installment(
      number: number,
      date: _isoOrNull(json['date'], 'date') ?? (throw const ContractException('Falta "date" de la cuota')),
      amount: _money(json, 'amount'),
    );
  }

  final int number;

  /// AAAA-MM-DD.
  final String date;

  /// Lo que falta de esa cuota (una en curso trae solo lo que le falta).
  final num amount;
}

/// Un abono (`payments[]`), del más reciente al más viejo (orden del servidor).
class DebtPayment {
  const DebtPayment({required this.id, required this.amount, required this.date, this.transactionId});

  factory DebtPayment.fromJson(Object? data) {
    final json = readMap(data);
    final id = json['id'];
    if (id is! String || id.isEmpty) throw const ContractException('Falta "id" del abono');
    return DebtPayment(
      id: id,
      amount: _money(json, 'amount'),
      date: _isoOrNull(json['date'], 'date') ?? (throw const ContractException('Falta "date" del abono')),
      transactionId: _textOrNull(json['transactionId'], 'transactionId'),
    );
  }

  final String id;
  final num amount;
  final String date;

  /// El movimiento que se anotó con el abono; null si se registró sin la casilla.
  final String? transactionId;
}

/// Una cuenta (`present` de debts.service.js:50-60).
class Debt {
  const Debt({
    required this.id,
    required this.kind,
    required this.person,
    required this.amount,
    required this.paid,
    required this.pending,
    required this.paidInstallments,
    required this.payments,
    this.dueDate,
    this.note,
    this.settledAt,
    this.transactionId,
    this.loanDate,
    this.installments,
    this.frequency,
    this.firstDueDate,
    this.nextInstallment,
  });

  factory Debt.fromJson(Object? data) {
    final json = readMap(data);
    final id = json['id'];
    final kind = DebtKind.fromWire(json['kind']);
    final person = json['person'];
    final installments = json['installments'];
    final frequencyRaw = json['frequency'];
    final frequency = DebtFrequency.fromWire(frequencyRaw);
    final paidInstallments = json['paidInstallments'];
    if (id is! String || id.isEmpty) throw const ContractException('Falta "id"');
    if (kind == null) throw const ContractException('"kind" desconocido');
    if (person is! String) throw const ContractException('Falta "person"');
    if (installments != null && installments is! int) {
      throw const ContractException('"installments" no es entero');
    }
    if (frequencyRaw != null && frequency == null) throw const ContractException('"frequency" desconocida');
    if (paidInstallments is! int) throw const ContractException('Falta "paidInstallments"');
    final next = json['nextInstallment'];
    return Debt(
      id: id,
      kind: kind,
      person: person,
      amount: _money(json, 'amount'),
      paid: _money(json, 'paid'),
      pending: _money(json, 'pending'),
      paidInstallments: paidInstallments,
      payments: [for (final p in readList(json['payments'])) DebtPayment.fromJson(p)],
      dueDate: _isoOrNull(json['dueDate'], 'dueDate'),
      note: _textOrNull(json['note'], 'note'),
      settledAt: _textOrNull(json['settledAt'], 'settledAt'),
      transactionId: _textOrNull(json['transactionId'], 'transactionId'),
      loanDate: _isoOrNull(json['loanDate'], 'loanDate'),
      installments: installments as int?,
      frequency: frequency,
      firstDueDate: _isoOrNull(json['firstDueDate'], 'firstDueDate'),
      nextInstallment: next == null ? null : Installment.fromJson(next),
    );
  }

  final String id;
  final DebtKind kind;
  final String person;
  final num amount;
  final num paid;

  /// `max(0, amount − paid)`; 0 si está saldada.
  final num pending;
  final int paidInstallments;
  final List<DebtPayment> payments;

  /// AL LEER es la PRÓXIMA cuota (el servidor la corre sola). Al crear y al editar con cuotas se
  /// manda la PRIMERA: esa es [firstDueDate]. Nunca se reenvía este valor.
  final String? dueDate;
  final String? note;

  /// Marca de tiempo; null = pendiente.
  final String? settledAt;

  /// El movimiento que creó «Ya me pagó todo» / «Ya pagué todo». null si se saldó con un abono.
  final String? transactionId;
  final String? loanDate;

  /// De 2 a 60; null = de una vez.
  final int? installments;
  final DebtFrequency? frequency;
  final String? firstDueDate;
  final Installment? nextInstallment;

  bool get settled => settledAt != null;
}

/// GET /debts: las cuentas en el orden del servidor (pendientes por fecha, luego saldadas) y lo
/// pendiente de cada lado.
class DebtsList {
  const DebtsList({required this.items, required this.receivable, required this.payable});

  factory DebtsList.fromJson(Object? data) {
    final json = readMap(data);
    final totals = readMap(json['totals']);
    return DebtsList(
      items: [for (final item in readList(json['items'])) Debt.fromJson(item)],
      receivable: _money(totals, 'receivable'),
      payable: _money(totals, 'payable'),
    );
  }

  final List<Debt> items;
  final num receivable;
  final num payable;

  num total(DebtKind kind) => kind == DebtKind.receivable ? receivable : payable;
}
