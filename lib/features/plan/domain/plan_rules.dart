/// Lo que Planear pinta a partir de lo que manda el servidor (lib/paymentCalendar.js, lib/calendar.js,
/// lib/liquidity.js, components/budgets/month.js y BudgetAlert de la web). Nada de esto calcula plata
/// nueva: agrupa, elige colores y textos. Lo único que se suma (el total de un día de la cuadrícula)
/// va en centavos enteros.
library;

import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../home/data/home_models.dart' show BudgetLevel, BudgetStatus, readMoney;
import '../../home/domain/home_dates.dart';
import '../data/plan_models.dart';

// ── Meses ────────────────────────────────────────────────────────────────────

/// AAAA-MM movido [delta] meses.
String shiftMonth(String month, int delta) {
  final [year, m] = month.split('-').map(int.parse).toList();
  return isoMonth(DateTime(year, m + delta));
}

/// La primera en mayúscula (el `first-letter:uppercase` de la web).
String capitalized(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// formatMonth de components/budgets/month.js: «octubre de 2026», «October 2026».
String budgetMonthLabel(String month, Region region) {
  final [year, m] = month.split('-').map(int.parse).toList();
  final name = monthName(m, region);
  return region.language == 'en' ? '$name $year' : '$name de $year';
}

/// monthLabel de lib/calendar.js: «Noviembre 2026» (con el mes del idioma de la app).
String calendarMonthLabel(String month, Region region) {
  final [year, m] = month.split('-').map(int.parse).toList();
  return '${capitalized(monthName(m, region))} $year';
}

// ── Presupuestos ─────────────────────────────────────────────────────────────

/// `106,25 %`: hasta 2 decimales con la coma del país (formatPercent de BudgetList.jsx).
String budgetPercent(num value, Region region) {
  final fixed = ((value * 100).round() / 100).toString();
  final text = fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  return '${text.replaceAll('.', formatFor(region).inputDecimal)} %';
}

/// Justo en el límite (exceeded_100 con 100 %): «ya usaste todo», no «te pasaste» (lib/budgetLevel.js).
bool atLimit(BudgetStatus b) => b.level == BudgetLevel.exceeded && b.percentage <= 100;

/// El aviso destacado de BudgetAlert (RN-04): lo más grave manda. null si nada llegó al 80 %.
({String message, bool exceeded})? budgetAlert(
  List<BudgetStatus> budgets,
  Map<String, String> names,
  Tr t,
  Region region,
) {
  final limit = budgets.where(atLimit).toList();
  final exceeded = budgets.where((b) => b.displayLevel == BudgetLevel.exceeded).toList();
  final warning = budgets.where((b) => b.level == BudgetLevel.warning).toList();
  String name(BudgetStatus b) => names[b.category] ?? b.category;
  if (exceeded.isNotEmpty) {
    return (
      message: exceeded.length == 1
          ? t('Te pasaste del presupuesto de {name}.', {'name': name(exceeded.first)})
          : t('Te pasaste en {length} presupuestos.', {'length': '${exceeded.length}'}),
      exceeded: true,
    );
  }
  if (limit.isNotEmpty) {
    return (
      message: limit.length == 1
          ? t('Ya usaste todo tu presupuesto de {name}.', {'name': name(limit.first)})
          : t('Ya usaste todo el presupuesto en {length} categorías.', {'length': '${limit.length}'}),
      exceeded: false,
    );
  }
  if (warning.isEmpty) return null;
  return (
    message: warning.length == 1
        ? t('{name} va en {percentage} % del límite.', {
            'name': name(warning.first),
            'percentage': budgetPercent(warning.first.percentage, region).replaceAll(' %', ''),
          })
        : t('{length} presupuestos pasaron del 80 %.', {'length': '${warning.length}'}),
    exceeded: false,
  );
}

/// «Topes del mes»: la suma de los límites y de lo gastado, en centavos, y la parte usada (0 a 1).
({num limit, num spent, double share}) budgetsTotal(List<BudgetStatus> budgets) {
  final limit = budgets.fold<int>(0, (sum, b) => sum + (b.amount * 100).round());
  final spent = budgets.fold<int>(0, (sum, b) => sum + (b.consumed * 100).round());
  return (
    limit: readMoney(limit / 100)!,
    spent: readMoney(spent / 100)!,
    share: limit > 0 ? (spent / limit).clamp(0, 1).toDouble() : 0,
  );
}

/// Lo que pasa del límite (positivo si se pasó), restado en centavos enteros.
num budgetOver(BudgetStatus b) => readMoney(((b.consumed * 100).round() - (b.amount * 100).round()) / 100)!;

// ── Calendario ───────────────────────────────────────────────────────────────

/// Filtros de la pantalla: `mios` son los pagos propios y los días de pago.
enum CalendarFilter { all, mine, vacas }

List<CalendarEvent> filterEvents(List<CalendarEvent> events, CalendarFilter filter) => switch (filter) {
  CalendarFilter.vacas => events.where((e) => e.kind == 'vaca').toList(),
  CalendarFilter.mine => events.where((e) => e.kind != 'vaca').toList(),
  CalendarFilter.all => events,
};

/// El color de un día o de un pago (FT-0069). null si ya está pagado.
enum CalendarTone { negative, risk, ok, payment, income, card }

CalendarTone? toneOf(CalendarEvent e) {
  if (e.isInflow) return CalendarTone.income;
  if (e.isCardDate) return CalendarTone.card;
  if (e.status == 'pagado') return null;
  if (e.risk == 'negativo' || e.status == 'atrasado') return CalendarTone.negative;
  if (e.risk == 'riesgo') return CalendarTone.risk;
  if (e.risk == 'ok') return CalendarTone.ok;
  return CalendarTone.payment;
}

/// Una celda del mes: el día, lo que falta pagar ese día y su color (lo más grave manda).
class CalendarCell {
  const CalendarCell({
    required this.day,
    required this.date,
    required this.isToday,
    required this.isPast,
    required this.total,
    required this.count,
    this.tone,
  });

  final int day;
  final String date;
  final bool isToday;
  final bool isPast;
  final num total;
  final int count;
  final CalendarTone? tone;
}

/// calendarCells de lib/paymentCalendar.js: empieza en lunes; las primeras son null hasta el día 1.
List<CalendarCell?> calendarCells(String month, List<CalendarEvent> events, String today) {
  final [year, m] = month.split('-').map(int.parse).toList();
  final days = DateTime(year, m + 1, 0).day;
  final blanks = DateTime(year, m).weekday - 1;
  return [
    for (var i = 0; i < blanks; i++) null,
    for (var day = 1; day <= days; day++)
      () {
        final date = '$month-${day.toString().padLeft(2, '0')}';
        final ofDay = events.where((e) => e.date == date).toList();
        final tones = {for (final e in ofDay) ?toneOf(e)};
        final cents = ofDay
            .where((e) => !e.isInflow && !e.isCardDate && e.status != 'pagado')
            .fold<int>(0, (sum, e) => sum + ((e.amount ?? 0) * 100).round());
        return CalendarCell(
          day: day,
          date: date,
          isToday: date == today,
          isPast: date.compareTo(today) < 0,
          total: readMoney(cents / 100)!,
          count: ofDay.length,
          tone: CalendarTone.values.where(tones.contains).firstOrNull,
        );
      }(),
  ];
}

/// groupByDate: los eventos (ya ordenados) por fecha.
List<(String, List<CalendarEvent>)> groupByDate(List<CalendarEvent> events) {
  final groups = <(String, List<CalendarEvent>)>[];
  for (final e in events) {
    if (groups.isNotEmpty && groups.last.$1 == e.date) {
      groups.last.$2.add(e);
    } else {
      groups.add((e.date, [e]));
    }
  }
  return groups;
}

/// shortMoney de lib/paymentCalendar.js: «89 mil», «1,2 M».
String shortMoney(num amount, Tr t) {
  if (amount >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '')} M';
  }
  if (amount >= 1000) return t('{round} mil', {'round': '${(amount / 1000).round()}'});
  return '${amount.round()}';
}

// ── Próximos días ────────────────────────────────────────────────────────────

/// liquidityMessage de LiquidityCard.jsx: la frase del resumen según el motor.
({String title, String? detail}) liquidityMessage(
  Liquidity l,
  Tr t,
  Region region,
  String Function(num) money,
) {
  if (l.risk == 'falta' && l.firstShortfall != null) {
    // Con 0 al día tampoco llega: decir «gasta máximo 0 y llegas» sería mentirle.
    final reach = l.safeDailySpend > 0 && l.pace != null && l.safeDailySpend < l.pace!
        ? t('Si gastas máximo {safeDailySpend} al día, llegas.', {'safeDailySpend': money(l.safeDailySpend)})
        : null;
    return (
      title: t('El {date} te faltan {missing}', {
        'date': dayAndMonth(l.firstShortfall!.date, region),
        'missing': money(l.firstShortfall!.missing),
      }),
      detail: reach,
    );
  }
  if (l.risk == 'riesgo' && l.lowestDate != null) {
    return (
      title: t('Justo: el {date} te quedan {amount}', {
        'date': dayAndMonth(l.lowestDate!, region),
        'amount': money(l.lowestAmount ?? 0),
      }),
      detail: t('Cuida el gasto de estos días.'),
    );
  }
  return (
    title: t('Vas bien hasta el {until}', {'until': dayAndMonth(l.until!, region)}),
    detail: t('Con lo que tienes y lo que debes pagar, te alcanza.'),
  );
}

/// avoidTips de lib/liquidity.js: hasta 4 sugerencias, de la más fácil a la más difícil.
List<String> avoidTips(Liquidity l, Tr t, String Function(num) money) {
  final shortfall = l.firstShortfall;
  if (l.risk != 'falta' || shortfall == null) return const [];
  final tips = <String>[];
  final pace = l.pace;
  if (pace != null && l.safeDailySpend > 0 && l.safeDailySpend < pace) {
    tips.add(
      t('Gasta máximo {safeDailySpend} al día (hoy gastas unos {pace}).', {
        'safeDailySpend': money(l.safeDailySpend),
        'pace': money(pace),
      }),
    );
  }
  if (l.receivable > 0) {
    tips.add(
      l.receivable >= shortfall.missing
          ? t('Cobra lo que te deben ({receivable}): con eso llegas.', {'receivable': money(l.receivable)})
          : t('Cobra lo que te deben ({receivable}): te faltaría menos.', {
              'receivable': money(l.receivable),
            }),
    );
  }
  final seen = <String>{};
  for (final cause in [...shortfall.causes]..sort((a, b) => b.amount.compareTo(a.amount))) {
    final tip = switch (cause.kind) {
      // D11 (Rinde v5): no se sugiere pagar el mínimo.
      'card' => t('Pagar menos de {name} te cobra intereses: mejor pídele a un cliente que te pague antes.', {
        'name': cause.name,
      }),
      'compromiso' => t('Mira si puedes correr unos días «{name}».', {'name': cause.name}),
      'deuda' => t('Habla con {name} para pagarle por partes.', {'name': cause.name}),
      _ => null,
    };
    if (tip != null && seen.add(tip)) tips.add(tip);
    if (tips.length >= 4) break;
  }
  return tips;
}
