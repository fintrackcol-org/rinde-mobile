/// Modelos del Inicio, leídos del contrato de la API de Rinde (`/api/v1`). Solo guardan lo que el
/// Inicio muestra. No calculan nada: las cifras son las que manda el servidor.
library;

import '../../auth/data/auth_models.dart' show ContractException;

/// Importe del servidor (NUMERIC(12,2) que llega como número JSON). Se normaliza a centavos al leer:
/// quita residuos de coma flotante (−1e-11 se mostraría como «-$ 0,00») y deja entero lo que es entero.
num? readMoney(Object? value) {
  if (value is! num || !value.isFinite) return null;
  final cents = (value * 100).round();
  return cents % 100 == 0 ? cents ~/ 100 : cents / 100;
}

num _money(Map<String, dynamic> json, String key) =>
    readMoney(json[key]) ?? (throw ContractException('Falta "$key" o no es un número'));

Map<String, dynamic> readMap(Object? data) =>
    data is Map<String, dynamic> ? data : (throw const ContractException('La respuesta no es un objeto'));

List<Object?> readList(Object? data) =>
    data is List ? data : (throw const ContractException('La respuesta no es una lista'));

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Un pago fijo que falta (`pending[]` de GET /money-profile/plan). Puede estar vencido.
class PendingPayment {
  const PendingPayment({required this.id, required this.name, required this.amount, required this.date});

  final String id;
  final String name;
  final num amount;

  /// AAAA-MM-DD.
  final String date;

  static PendingPayment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final amount = readMoney(raw['amount']);
    final name = raw['name'];
    final date = raw['date'];
    if (amount == null || name is! String || date is! String || !_isoDate.hasMatch(date)) return null;
    return PendingPayment(id: '${raw['id']}', name: name, amount: amount, date: date);
  }
}

/// GET /money-profile/plan. «Libre para gastar» y todo lo demás lo calcula SOLO el servidor.
class MoneyPlan {
  const MoneyPlan({
    required this.money,
    required this.pendingTotal,
    required this.free,
    required this.shortfall,
    required this.mode,
    this.perDay,
    this.nextPay,
    this.pending = const [],
    this.ledger,
  }) : ready = true;

  /// `{ "ready": false }`: falta saber cómo le entra la plata o cuánta tiene.
  const MoneyPlan.notReady()
    : ready = false,
      money = 0,
      pendingTotal = 0,
      free = 0,
      shortfall = 0,
      mode = '',
      perDay = null,
      nextPay = null,
      pending = const [],
      ledger = null;

  factory MoneyPlan.fromJson(Object? data) {
    final json = readMap(data);
    if (json['ready'] is! bool) throw const ContractException('Falta "ready"');
    if (json['ready'] == false) return const MoneyPlan.notReady();
    final nextPay = json['nextPay'];
    return MoneyPlan(
      money: _money(json, 'money'),
      pendingTotal: _money(json, 'pendingTotal'),
      free: _money(json, 'free'),
      shortfall: _money(json, 'shortfall'),
      mode: json['mode'] is String ? json['mode'] as String : '',
      perDay: readMoney(json['perDay']),
      nextPay: nextPay is String && _isoDate.hasMatch(nextPay) ? nextPay : null,
      pending: [
        if (json['pending'] is List)
          for (final item in json['pending'] as List) ?PendingPayment.tryParse(item),
      ],
      ledger: readMoney(json['ledger']),
    );
  }

  final bool ready;

  /// Plata actual.
  final num money;

  /// Lo apartado para pagos.
  final num pendingTotal;

  /// Libre para gastar. Negativo si no alcanza.
  final num free;

  /// Cuánto falta (0 si alcanza).
  final num shortfall;

  /// `daily`, `goal` o `runway`.
  final String mode;
  final num? perDay;

  /// AAAA-MM-DD, solo en `daily`.
  final String? nextPay;
  final List<PendingPayment> pending;

  /// Lo que dicen los movimientos (todos los ingresos menos todos los gastos). Corregir saldo lo
  /// ofrece con «Usar lo que dicen mis movimientos». null si no llegó.
  final num? ledger;

  /// Como la web (MobileHome.jsx): no alcanza para los pagos.
  bool get short => free < 0;

  /// La plata misma está bajo cero.
  bool get negative => money < 0;
}

/// Ingresos y gastos del mes (GET /transactions/summary?period=month).
class MonthTotals {
  const MonthTotals({required this.month, required this.income, required this.expense});

  factory MonthTotals.fromJson(Object? data) {
    final json = readMap(data);
    final from = json['from'];
    if (from is! String || !_isoDate.hasMatch(from)) throw const ContractException('Falta "from"');
    return MonthTotals(
      month: from.substring(0, 7),
      income: _money(readMap(json['income']), 'total'),
      expense: _money(readMap(json['expense']), 'total'),
    );
  }

  /// AAAA-MM del resumen.
  final String month;
  final num income;
  final num expense;
}

enum BudgetLevel { none, warning, exceeded }

/// Un presupuesto del mes con su avance (GET /budgets?month=).
class BudgetStatus {
  const BudgetStatus({
    required this.category,
    required this.amount,
    required this.consumed,
    required this.percentage,
    required this.level,
  });

  final String category;
  final num amount;
  final num consumed;
  final num percentage;

  /// Nivel que manda el servidor (RN-04: `exceeded_100` incluye gastar exactamente el límite).
  final BudgetLevel level;

  /// Nivel con el que se muestra (lib/budgetLevel.js): justo en el límite es advertencia, no exceso.
  BudgetLevel get displayLevel =>
      level == BudgetLevel.exceeded && percentage <= 100 ? BudgetLevel.warning : level;

  /// «Quedan»: se resta en centavos enteros, para no arrastrar residuos de coma flotante.
  num get left {
    final cents = (amount * 100).round() - (consumed * 100).round();
    return cents <= 0 ? 0 : readMoney(cents / 100)!;
  }

  static BudgetStatus? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final amount = readMoney(raw['amount']);
    final consumed = readMoney(raw['consumed']);
    final alert = raw['alert'];
    final category = raw['category'];
    if (amount == null || consumed == null || alert is! Map || category is! String) return null;
    final percentage = alert['percentage'];
    return BudgetStatus(
      category: category,
      amount: amount,
      consumed: consumed,
      percentage: percentage is num && percentage.isFinite ? percentage : 0,
      level: switch (alert['level']) {
        'warning_80' => BudgetLevel.warning,
        'exceeded_100' => BudgetLevel.exceeded,
        _ => BudgetLevel.none,
      },
    );
  }
}

/// Lo que el aviso del Inicio necesita de una tarjeta de crédito (GET /cards).
class CardSummary {
  const CardSummary({
    required this.id,
    required this.name,
    required this.network,
    required this.last4,
    required this.used,
    required this.daysToPayment,
    required this.paidThisCycle,
  });

  final String id;
  final String name;

  /// `visa`, `mastercard`, `amex` u `otra`.
  final String network;
  final String last4;

  /// Lo que se debe.
  final num used;

  /// Negativo si el pago está atrasado.
  final int daysToPayment;
  final bool paidThisCycle;

  /// Sin días enteros o sin deuda legible no hay nada cierto que avisar: se descarta.
  static CardSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final used = readMoney(raw['used']);
    final days = raw['daysToPayment'];
    if (used == null || days is! int || raw['paidThisCycle'] is! bool) return null;
    return CardSummary(
      id: '${raw['id']}',
      name: raw['name'] is String ? raw['name'] as String : '',
      network: raw['network'] is String ? raw['network'] as String : 'otra',
      last4: raw['last4'] is String ? raw['last4'] as String : '',
      used: used,
      daysToPayment: days,
      paidThisCycle: raw['paidThisCycle'] as bool,
    );
  }
}
