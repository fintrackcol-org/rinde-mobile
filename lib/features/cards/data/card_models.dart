/// Modelos de Tarjetas con el contrato de `/api/v1/cards` de Rinde Web. Son ESTRICTOS: una tarjeta
/// ilegible falla el bloque entero en vez de desaparecer en silencio (a diferencia de
/// `CardSummary.tryParse`, que es tolerante a propósito porque solo arma el aviso del Inicio).
/// Los importes los calcula SIEMPRE el servidor; aquí solo se leen.
library;

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readMap, readMoney;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? _isoOrNull(Object? raw) => raw is String && _isoDate.hasMatch(raw) ? raw : null;

/// `expiry` de la tarjeta: lo calcula el servidor (card-expiry.js). null = sin fecha guardada.
class CardExpiry {
  const CardExpiry({required this.label, required this.expired, required this.soon});

  /// «03/27».
  final String label;
  final bool expired;
  final bool soon;

  static CardExpiry? tryParse(Object? raw) {
    if (raw is! Map || raw['label'] is! String) return null;
    return CardExpiry(
      label: raw['label'] as String,
      expired: raw['expired'] == true,
      soon: raw['soon'] == true,
    );
  }
}

/// Una tarjeta de crédito completa (GET /cards y /cards/:id, cards.service.js:52-76).
class CreditCard {
  const CreditCard({
    required this.id,
    required this.name,
    required this.network,
    required this.tier,
    required this.last4,
    required this.limit,
    required this.used,
    required this.available,
    required this.paymentDay,
    required this.daysToPayment,
    required this.paidThisCycle,
    required this.paidAmount,
    this.cutoffDay,
    this.statementTotal,
    this.statementDueDate,
    this.nextPaymentDate,
    this.paidDueDate,
    this.expiryMonth,
    this.expiryYear,
    this.expiry,
  });

  factory CreditCard.fromJson(Object? data) {
    final json = readMap(data);
    final id = json['id'];
    final name = json['name'];
    final network = json['network'];
    final tier = json['tier'];
    final last4 = json['last4'];
    final limit = readMoney(json['limit']);
    final used = readMoney(json['used']);
    // `available` puede ser negativo (compras por encima del cupo): readMoney lo acepta.
    final available = readMoney(json['available']);
    final paymentDay = json['paymentDay'];
    final days = json['daysToPayment'];
    final cutoffDay = json['cutoffDay'];
    if (id is! String || id.isEmpty) throw const ContractException('Falta "id"');
    if (name is! String) throw const ContractException('Falta "name"');
    if (network is! String || tier is! String) throw const ContractException('Falta "network" o "tier"');
    if (last4 is! String) throw const ContractException('Falta "last4"');
    if (limit == null || used == null || available == null) {
      throw const ContractException('Falta "limit", "used" o "available", o no es un número');
    }
    if (paymentDay is! int) throw const ContractException('Falta "paymentDay"');
    if (days is! int) throw const ContractException('Falta "daysToPayment"');
    if (json['paidThisCycle'] is! bool) throw const ContractException('Falta "paidThisCycle"');
    return CreditCard(
      id: id,
      name: name,
      network: network,
      tier: tier,
      last4: last4,
      limit: limit,
      used: used,
      available: available,
      paymentDay: paymentDay,
      cutoffDay: cutoffDay is int ? cutoffDay : null,
      statementTotal: readMoney(json['statementTotal']),
      statementDueDate: _isoOrNull(json['statementDueDate']),
      nextPaymentDate: _isoOrNull(json['nextPaymentDate']),
      daysToPayment: days,
      paidThisCycle: json['paidThisCycle'] as bool,
      paidDueDate: _isoOrNull(json['paidDueDate']),
      paidAmount: readMoney(json['paidAmount']) ?? 0,
      expiryMonth: json['expiryMonth'] is int ? json['expiryMonth'] as int : null,
      expiryYear: json['expiryYear'] is int ? json['expiryYear'] as int : null,
      expiry: CardExpiry.tryParse(json['expiry']),
    );
  }

  final String id;

  /// El del usuario o el que puso el servidor («Visa Gold ••1234»).
  final String name;

  /// `visa`, `mastercard`, `amex` u `otra`.
  final String network;
  final String tier;
  final String last4;
  final num limit;

  /// Lo que se debe. Nunca negativo (un sobrepago queda en 0).
  final num used;

  /// `limit − used`: puede ser negativo si las compras pasan el cupo.
  final num available;
  final int paymentDay;
  final int? cutoffDay;
  final num? statementTotal;
  final String? statementDueDate;
  final String? nextPaymentDate;

  /// Negativo si el pago está atrasado.
  final int daysToPayment;
  final bool paidThisCycle;
  final String? paidDueDate;
  final num paidAmount;
  final int? expiryMonth;
  final int? expiryYear;
  final CardExpiry? expiry;
}

enum CardMovementKind {
  purchase('purchase'),
  payment('payment'),
  adjustment('adjustment');

  const CardMovementKind(this.wire);
  final String wire;

  static CardMovementKind? fromWire(Object? value) => values.where((k) => k.wire == value).firstOrNull;
}

/// Una fila de GET /cards/:id/movements (cards.repository.js:275-304). El ajuste llega con el monto
/// negativo y sin descripción.
class CardMovement {
  const CardMovement({
    required this.kind,
    required this.id,
    required this.date,
    required this.amount,
    this.description,
    this.installments,
  });

  factory CardMovement.fromJson(Object? data) {
    final json = readMap(data);
    final kind = CardMovementKind.fromWire(json['kind']);
    final id = json['id'];
    final date = json['date'];
    final amount = readMoney(json['amount']);
    if (kind == null) throw const ContractException('"kind" desconocido');
    if (id is! String || id.isEmpty) throw const ContractException('Falta "id"');
    if (date is! String || !_isoDate.hasMatch(date)) throw const ContractException('Falta "date"');
    if (amount == null) throw const ContractException('Falta "amount" o no es un número');
    final installments = json['installments'];
    return CardMovement(
      kind: kind,
      id: id,
      date: date,
      amount: amount,
      description: json['description'] is String ? json['description'] as String : null,
      installments: installments is int ? installments : null,
    );
  }

  final CardMovementKind kind;
  final String id;

  /// AAAA-MM-DD.
  final String date;

  /// Negativo solo en los ajustes.
  final num amount;
  final String? description;
  final int? installments;
}

/// El detalle completo: la tarjeta y su historial, pedidos en paralelo (CardDetail.jsx:197).
class CardDetailData {
  const CardDetailData({required this.card, required this.movements});

  final CreditCard card;
  final List<CardMovement> movements;
}
