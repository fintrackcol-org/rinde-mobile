/// Modelos de Planear: el calendario completo del mes (GET /money-profile/calendar) y el motor de
/// liquidez (GET /liquidity). Como en el Inicio: no calculan nada; lo que no llegó queda null.
library;

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readList, readMap, readMoney;
import '../../money/data/money_models.dart' show CalendarPayment;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? _date(Object? raw) => raw is String && _isoDate.hasMatch(raw) ? raw : null;
String? _text(Object? raw) => raw is String ? raw : null;

/// Un elemento del calendario (`events[]` o `cardDates[]`): pago fijo, aporte a vaca, día de pago,
/// tarjeta, cuenta que debo (`cuenta`) o que me deben (`cobro`), corte o fecha límite de tarjeta.
class CalendarEvent {
  const CalendarEvent({
    required this.date,
    required this.kind,
    required this.name,
    this.id,
    this.amount,
    this.status,
    this.balanceAfter,
    this.risk,
    this.subscription = false,
  });

  /// AAAA-MM-DD.
  final String date;
  final String kind;
  final String? id;
  final String name;

  /// null en los días de pago y en el corte o la fecha límite.
  final num? amount;

  /// `pagado`, `pendiente`, `atrasado`, `sin_registro` o null.
  final String? status;

  /// Lo que queda después de este pago, según el servidor; null si no se puede saber.
  final num? balanceAfter;

  /// `ok`, `riesgo`, `negativo` o null.
  final String? risk;
  final bool subscription;

  /// Lo que entra (día de pago o plata que me deben): no es un pago mío.
  bool get isInflow => kind == 'ingreso' || kind == 'cobro';

  /// Corte o fecha límite de una tarjeta: solo informa.
  bool get isCardDate => kind == 'corte' || kind == 'limite';

  static CalendarEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final date = _date(raw['date']);
    final kind = raw['kind'];
    final name = raw['name'];
    if (date == null || kind is! String || name is! String) return null;
    return CalendarEvent(
      date: date,
      kind: kind,
      id: raw['id'] == null ? null : '${raw['id']}',
      name: name,
      amount: readMoney(raw['amount']),
      status: _text(raw['status']),
      balanceAfter: readMoney(raw['balanceAfter']),
      risk: _text(raw['risk']),
      subscription: raw['subscription'] == true,
    );
  }
}

/// GET /money-profile/calendar?month=: el mes que se muestra, con todo lo que trae.
class PaymentCalendar {
  const PaymentCalendar({
    required this.month,
    required this.today,
    required this.events,
    required this.cardDates,
    required this.pending,
    required this.payments,
    this.money,
    this.projectedUntil,
  });

  factory PaymentCalendar.fromJson(Object? data) {
    final json = readMap(data);
    final month = json['month'];
    final today = _date(json['today']);
    if (month is! String || today == null) throw const ContractException('Falta "month" o "today"');
    final totals = json['totals'];
    return PaymentCalendar(
      month: month,
      today: today,
      money: readMoney(json['money']),
      projectedUntil: _date(json['projectedUntil']),
      events: [for (final e in readList(json['events'])) ?CalendarEvent.tryParse(e)],
      cardDates: [
        if (json['cardDates'] is List)
          for (final e in json['cardDates'] as List) ?CalendarEvent.tryParse(e),
      ],
      pending: (totals is Map ? readMoney(totals['pending']) : null) ?? 0,
      // Los pagos fijos, con el mismo modelo que Mi plata.
      payments: CalendarPayment.listFromJson(json),
    );
  }

  /// AAAA-MM.
  final String month;
  final String today;

  /// Plata de hoy; null sin Mi plata configurada.
  final num? money;

  /// Hasta qué día (sin incluirlo) se calcula lo que queda; null sin plan.
  final String? projectedUntil;
  final List<CalendarEvent> events;
  final List<CalendarEvent> cardDates;

  /// `totals.pending`: lo que falta pagar este mes, según el servidor.
  final num pending;

  /// Solo los pagos fijos (`kind == 'compromiso'`).
  final List<CalendarPayment> payments;
}

/// Un pago o ingreso esperado de un día de la proyección.
class LiquidityFlow {
  const LiquidityFlow({required this.kind, required this.name, required this.amount, this.date, this.id});

  /// `compromiso`, `card`, `vaca`, `deuda` o `esperado` (ingreso que se espera).
  final String kind;
  final String name;
  final num amount;
  final String? date;
  final String? id;

  static LiquidityFlow? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final name = raw['name'];
    final amount = readMoney(raw['amount']);
    if (kind is! String || name is! String || amount == null) return null;
    return LiquidityFlow(
      kind: kind,
      name: name,
      amount: amount,
      date: _date(raw['date']),
      id: raw['id'] == null ? null : '${raw['id']}',
    );
  }

  static List<LiquidityFlow> listOf(Object? raw) => [
    if (raw is List)
      for (final item in raw) ?tryParse(item),
  ];
}

/// Un día de la proyección: la plata al terminar el día y lo que pasa ese día.
class LiquidityDay {
  const LiquidityDay({required this.date, required this.end, required this.events});

  final String date;
  final num end;
  final List<LiquidityFlow> events;

  static LiquidityDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final date = _date(raw['date']);
    final end = readMoney(raw['end']);
    if (date == null || end == null) return null;
    return LiquidityDay(date: date, end: end, events: LiquidityFlow.listOf(raw['events']));
  }
}

/// El primer día en que la plata queda bajo cero.
class Shortfall {
  const Shortfall({required this.date, required this.missing, required this.causes});

  final String date;
  final num missing;
  final List<LiquidityFlow> causes;
}

/// GET /liquidity (FT-0059). Con `ready: false` (Mi plata sin configurar) solo trae `today`.
class Liquidity {
  const Liquidity({
    required this.ready,
    this.today,
    this.money = 0,
    this.pace,
    this.until,
    this.days = const [],
    this.firstShortfall,
    this.lowestDate,
    this.lowestAmount,
    this.risk = 'ok',
    this.safeDailySpend = 0,
    this.receivable = 0,
    this.assumptions = const [],
  });

  factory Liquidity.fromJson(Object? data) {
    final json = readMap(data);
    if (json['ready'] != true) return Liquidity(ready: false, today: _date(json['today']));
    final money = readMoney(json['money']);
    final until = _date(json['until']);
    final today = _date(json['today']);
    if (money == null || until == null || today == null) {
      throw const ContractException('Falta "money", "today" o "until"');
    }
    final shortfall = json['firstShortfall'];
    final lowest = json['lowest'];
    Shortfall? first;
    if (shortfall is Map) {
      final date = _date(shortfall['date']);
      final missing = readMoney(shortfall['missing']);
      if (date != null && missing != null) {
        first = Shortfall(date: date, missing: missing, causes: LiquidityFlow.listOf(shortfall['causes']));
      }
    }
    return Liquidity(
      ready: true,
      today: today,
      money: money,
      pace: readMoney(json['pace']),
      until: until,
      days: [for (final d in readList(json['days'])) ?LiquidityDay.tryParse(d)],
      firstShortfall: first,
      lowestDate: lowest is Map ? _date(lowest['date']) : null,
      lowestAmount: lowest is Map ? readMoney(lowest['amount']) : null,
      risk: json['risk'] is String ? json['risk'] as String : 'ok',
      safeDailySpend: readMoney(json['safeDailySpend']) ?? 0,
      receivable: readMoney(json['receivable']) ?? 0,
      assumptions: [
        if (json['assumptions'] is List)
          for (final a in json['assumptions'] as List)
            if (a is String) a,
      ],
    );
  }

  final bool ready;
  final String? today;
  final num money;

  /// Gasto normal de un día; null sin historial suficiente.
  final num? pace;
  final String? until;
  final List<LiquidityDay> days;
  final Shortfall? firstShortfall;
  final String? lowestDate;
  final num? lowestAmount;

  /// `ok`, `riesgo` o `falta`.
  final String risk;
  final num safeDailySpend;

  /// Lo que me deben: el servidor NO lo suma a la plata.
  final num receivable;

  /// Lo que el servidor supone (ya traducido por él).
  final List<String> assumptions;

  /// hasData de lib/liquidity.js: sin pagos ni gasto normal la gráfica sería una línea plana.
  bool get hasData => pace != null || days.any((d) => d.events.isNotEmpty);
}
