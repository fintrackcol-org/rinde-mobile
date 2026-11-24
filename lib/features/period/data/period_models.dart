import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readList, readMap, readMoney;
import '../../movements/domain/movement.dart';

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int _cents(num value) => (value * 100).round();
num _fromCents(int cents) => readMoney(cents / 100)!;

/// Una categoría del resumen. [category] null: «Sin clasificar».
class CategoryTotal {
  const CategoryTotal({required this.category, required this.total, required this.percentage});

  final String? category;
  final num total;

  /// Sobre el total de su tipo, como lo manda el servidor.
  final num percentage;
}

/// `{ total, byCategory }` de un tipo, de mayor a menor (como lo ordena el servidor).
class TypeTotals {
  const TypeTotals({required this.total, required this.byCategory});

  factory TypeTotals.fromJson(Object? data) {
    final json = readMap(data);
    return TypeTotals(
      total: readMoney(json['total']) ?? (throw const ContractException('Falta "total"')),
      byCategory: [
        for (final raw in readList(json['byCategory']))
          if (raw is Map && readMoney(raw['total']) != null && raw['percentage'] is num)
            CategoryTotal(
              category: raw['category'] is String ? raw['category'] as String : null,
              total: readMoney(raw['total'])!,
              percentage: raw['percentage'] as num,
            ),
      ],
    );
  }

  final num total;
  final List<CategoryTotal> byCategory;
}

/// GET /transactions/summary?period=&date= (getSummary de la web). El ahorro no cuenta como gasto.
class PeriodSummary {
  const PeriodSummary({
    required this.from,
    required this.to,
    required this.income,
    required this.expense,
    required this.savings,
  });

  factory PeriodSummary.fromJson(Object? data) {
    final json = readMap(data);
    final from = json['from'], to = json['to'];
    if (from is! String || to is! String || !_isoDate.hasMatch(from) || !_isoDate.hasMatch(to)) {
      throw const ContractException('Falta "from" o "to"');
    }
    final savings = json['savings'];
    return PeriodSummary(
      from: from,
      to: to,
      income: TypeTotals.fromJson(json['income']),
      expense: TypeTotals.fromJson(json['expense']),
      // `?? 0` como la web: un backend que aún no manda `savings`.
      savings: (savings is Map ? readMoney(savings['total']) : null) ?? 0,
    );
  }

  /// AAAA-MM-DD.
  final String from;
  final String to;
  final TypeTotals income;
  final TypeTotals expense;
  final num savings;

  /// Ingresos menos gastos y ahorro, en centavos (getSummary de la web lo calcula igual).
  num get balance => _fromCents(_cents(income.total) - _cents(expense.total) - _cents(savings));
}

/// Una fila de «Por categoría» ([key] 'otras' junta las pequeñas).
typedef CategoryRow = ({String key, String? category, int others, num total, num percentage});

/// toRows de ExpenseByCategory.jsx: hasta 6 filas; con más, las 5 primeras y «Otras N categorías».
List<CategoryRow> categoryRows(List<CategoryTotal> rows) {
  CategoryRow row(CategoryTotal r) => (
    key: r.category ?? 'sin_clasificar',
    category: r.category,
    others: 0,
    total: r.total,
    percentage: r.percentage,
  );
  if (rows.length <= 6) return [for (final r in rows) row(r)];
  final rest = rows.skip(5);
  return [
    for (final r in rows.take(5)) row(r),
    (
      key: 'otras',
      category: null,
      others: rest.length,
      total: _fromCents(rest.fold(0, (sum, r) => sum + _cents(r.total))),
      percentage: (rest.fold<num>(0, (sum, r) => sum + r.percentage) * 10).round() / 10,
    ),
  ];
}

/// Los 4 grupos del método Kakeibo, en el orden de la web.
const kakeiboGroups = ['necesidad', 'deseo', 'cultura', 'imprevisto'];

/// splitByKakeibo de KakeiboSplit.jsx, en centavos. Lo que no tiene grupo no cuenta en los porcentajes.
({Map<String, num> totals, Map<String, double> shares, num grouped, int ungrouped}) splitByKakeibo(
  List<Movement> expenses,
) {
  final sums = {for (final g in kakeiboGroups) g: 0};
  var ungrouped = 0;
  for (final m in expenses) {
    if (sums.containsKey(m.kakeibo)) {
      sums[m.kakeibo!] = sums[m.kakeibo!]! + _cents(m.amount);
    } else {
      ungrouped++;
    }
  }
  final grouped = sums.values.fold(0, (a, b) => a + b);
  return (
    totals: {for (final e in sums.entries) e.key: _fromCents(e.value)},
    shares: {for (final e in sums.entries) e.key: grouped == 0 ? 0 : e.value * 100 / grouped},
    grouped: _fromCents(grouped),
    ungrouped: ungrouped,
  );
}

/// elapsedDays de PeriodDetail.jsx: días del periodo hasta hoy (o hasta su final), al menos 1.
int elapsedDays(String from, String to, DateTime today) {
  DateTime utc(String iso) => DateTime.utc(
    int.parse(iso.substring(0, 4)),
    int.parse(iso.substring(5, 7)),
    int.parse(iso.substring(8)),
  );
  final start = utc(from), end = utc(to);
  final now = DateTime.utc(today.year, today.month, today.day);
  final last = now.isBefore(end) ? now : end;
  final days = last.difference(start).inDays + 1;
  return days < 1 ? 1 : days;
}
