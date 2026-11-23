/// Modelos de Mi plata, leídos del contrato de `/api/v1/money-profile` (los mismos endpoints de Rinde
/// Web). Como en el Inicio: no calculan nada y un dato que no llegó queda null, nunca se vuelve 0.
library;

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readList, readMap, readMoney;
import '../../onboarding/domain/income_sources.dart';

List<int> _ints(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is int) item,
];

String? _text(Object? raw) => raw is String ? raw : null;

/// Un pago fijo o una suscripción (`commitments[]` de GET /money-profile). Solo lectura.
class Commitment {
  const Commitment({
    required this.id,
    required this.name,
    required this.amount,
    required this.dayOfMonth,
    this.kind = 'fixed',
    this.frequency = 'monthly',
    this.month,
  });

  final String id;
  final String name;
  final num amount;
  final int dayOfMonth;

  /// `fixed` o `subscription`.
  final String kind;

  /// `monthly` o `yearly`.
  final String frequency;

  /// 1 a 12, solo los anuales.
  final int? month;

  static Commitment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final amount = readMoney(raw['amount']);
    final day = raw['dayOfMonth'];
    if (raw['id'] == null || name is! String || amount == null || day is! int) return null;
    return Commitment(
      id: '${raw['id']}',
      name: name,
      amount: amount,
      dayOfMonth: day,
      kind: raw['kind'] == 'subscription' ? 'subscription' : 'fixed',
      frequency: raw['frequency'] == 'yearly' ? 'yearly' : 'monthly',
      month: raw['month'] is int ? raw['month'] as int : null,
    );
  }
}

/// GET /money-profile.
class MoneyProfile {
  const MoneyProfile({
    required this.welcomeDone,
    this.tutorialDone = false,
    this.incomeType,
    this.payDays = const [],
    this.balance,
    this.balanceAt,
    this.money,
    this.income,
    this.expense,
    this.commitments = const [],
    this.subscriptionCount,
    this.subscriptionsMonthly,
    this.version,
  });

  factory MoneyProfile.fromJson(Object? data) {
    final json = readMap(data);
    if (json['welcomeDone'] is! bool) throw const ContractException('Falta "welcomeDone"');
    final totals = json['totals'] is Map ? json['totals'] as Map : const {};
    final subscriptions = json['subscriptions'] is Map ? json['subscriptions'] as Map : const {};
    return MoneyProfile(
      welcomeDone: json['welcomeDone'] as bool,
      tutorialDone: json['tutorialDone'] == true,
      incomeType: _text(json['incomeType']),
      payDays: _ints(json['payDays']),
      balance: readMoney(json['balance']),
      balanceAt: _text(json['balanceAt']),
      money: readMoney(json['money']),
      income: readMoney(totals['income']),
      expense: readMoney(totals['expense']),
      commitments: [
        if (json['commitments'] is List)
          for (final item in json['commitments'] as List) ?Commitment.tryParse(item),
      ],
      subscriptionCount: subscriptions['count'] is int ? subscriptions['count'] as int : null,
      subscriptionsMonthly: readMoney(subscriptions['monthly']),
      version: json['version'] is int ? json['version'] as int : null,
    );
  }

  final bool welcomeDone;
  final bool tutorialDone;

  /// `fecha_fija`, `sin_fecha` o null.
  final String? incomeType;
  final List<int> payDays;

  /// El saldo que la persona dijo (null = no lo ha dicho) y cuándo.
  final num? balance;
  final String? balanceAt;

  /// La plata actual según el servidor. null = no la sabe.
  final num? money;

  /// Todo el historial (`totals`).
  final num? income;
  final num? expense;
  final List<Commitment> commitments;
  final int? subscriptionCount;
  final num? subscriptionsMonthly;

  /// Versión del perfil para escribir el saldo sin pisar uno más nuevo. El backend de hoy no la manda
  /// (propuesta §5 del plan de la etapa 4): mientras sea null, el saldo no se escribe desde la app.
  final int? version;
}

/// Una fuente de ingreso guardada (`sources[]` de GET /money-profile/income).
class IncomeSource {
  const IncomeSource({
    required this.id,
    required this.kind,
    this.frequency = 'mensual',
    this.payDays = const [],
    this.amount,
    this.low,
    this.high,
    this.lastMonths = const [],
    this.workDays,
  });

  /// Cambia en cada PUT /sources: no sirve de clave.
  final String id;
  final IncomeKind kind;
  final String frequency;
  final List<int> payDays;
  final num? amount;
  final num? low;
  final num? high;
  final List<num> lastMonths;
  final int? workDays;

  /// Sin un tipo conocido no se puede mostrar ni editar: se descarta.
  static IncomeSource? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = IncomeKind.parse(raw['kind']);
    if (kind == null) return null;
    return IncomeSource(
      id: '${raw['id']}',
      kind: kind,
      frequency: _text(raw['frequency']) ?? 'mensual',
      payDays: _ints(raw['payDays'])..sort(),
      amount: readMoney(raw['amount']),
      low: readMoney(raw['low']),
      high: readMoney(raw['high']),
      lastMonths: [
        if (raw['lastMonths'] is List)
          for (final m in raw['lastMonths'] as List) ?readMoney(m),
      ],
      workDays: raw['workDays'] is int ? raw['workDays'] as int : null,
    );
  }
}

/// Colchón para meses flacos (`cushion`).
class Cushion {
  const Cushion({this.goal, this.suggestedGoal, this.saved, this.metaId});

  final num? goal;
  final num? suggestedGoal;
  final num? saved;

  /// La meta personal del colchón; null si todavía no existe.
  final String? metaId;

  static Cushion? tryParse(Object? raw) => raw is Map
      ? Cushion(
          goal: readMoney(raw['goal']),
          suggestedGoal: readMoney(raw['suggestedGoal']),
          saved: readMoney(raw['saved']),
          metaId: raw['metaId'] == null ? null : '${raw['metaId']}',
        )
      : null;
}

/// Salud y pensión de un independiente (`socialSecurity`). Valor aproximado del servidor.
class SocialSecurity {
  const SocialSecurity({required this.health, required this.pension, required this.total});

  final num health;
  final num pension;
  final num total;

  static SocialSecurity? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final health = readMoney(raw['health']);
    final pension = readMoney(raw['pension']);
    final total = readMoney(raw['total']);
    if (health == null || pension == null || total == null) return null;
    return SocialSecurity(health: health, pension: pension, total: total);
  }
}

/// Meta por día de trabajo de quien trabaja por días (`workDay`).
class WorkDay {
  const WorkDay({
    required this.target,
    required this.earned,
    required this.daysLeft,
    required this.perDay,
    required this.extraToday,
  });

  final num target;
  final num earned;
  final int daysLeft;
  final num perDay;
  final num extraToday;

  static WorkDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final target = readMoney(raw['target']);
    final earned = readMoney(raw['earned']);
    final perDay = readMoney(raw['perDay']);
    final extra = readMoney(raw['extraToday']);
    final days = raw['daysLeft'];
    if (target == null || earned == null || perDay == null || extra == null || days is! num) return null;
    return WorkDay(target: target, earned: earned, daysLeft: days.toInt(), perDay: perDay, extraToday: extra);
  }
}

/// GET /money-profile/income: cómo le entra la plata a la persona. El mes normal y el flaco, el
/// sueldo propio, el colchón y la seguridad social los calcula SOLO el servidor.
class IncomeOverview {
  const IncomeOverview({
    this.sources = const [],
    this.normal,
    this.lean,
    this.basis = 'none',
    this.estimated = false,
    this.ownSalary,
    this.cushion,
    this.socialSecurity,
    this.workDay,
  });

  factory IncomeOverview.fromJson(Object? data) {
    final json = readMap(data);
    return IncomeOverview(
      sources: [for (final item in readList(json['sources'])) ?IncomeSource.tryParse(item)],
      normal: readMoney(json['normal']),
      lean: readMoney(json['lean']),
      basis: _text(json['basis']) ?? 'none',
      estimated: json['estimated'] == true,
      ownSalary: readMoney(json['ownSalary']),
      cushion: Cushion.tryParse(json['cushion']),
      socialSecurity: SocialSecurity.tryParse(json['socialSecurity']),
      workDay: WorkDay.tryParse(json['workDay']),
    );
  }

  final List<IncomeSource> sources;
  final num? normal;
  final num? lean;

  /// `history`, `declared` o `none`.
  final String basis;

  /// Algo se estimó a partir de lo que contó la persona.
  final bool estimated;
  final num? ownSalary;
  final Cushion? cushion;

  /// Solo para independientes con ingreso.
  final SocialSecurity? socialSecurity;
  final WorkDay? workDay;
}
