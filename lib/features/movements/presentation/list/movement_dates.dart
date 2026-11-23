import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../home/domain/home_dates.dart';

/// Periodo del listado (lib/period.js de la web): semana de lunes a domingo, mes o año.
enum MovementPeriod { week, month, year }

DateTime parseIsoDay(String iso) {
  final p = iso.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Días de calendario entre dos fechas, sin que el cambio de hora reste uno.
int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// periodRange de la web: primer y último día del periodo que contiene [date].
({DateTime from, DateTime to}) periodRange(MovementPeriod period, DateTime date) => switch (period) {
  MovementPeriod.year => (from: DateTime(date.year), to: DateTime(date.year, 12, 31)),
  // El día 0 del mes siguiente es el último de este.
  MovementPeriod.month => (from: DateTime(date.year, date.month), to: DateTime(date.year, date.month + 1, 0)),
  MovementPeriod.week => (
    from: DateTime(date.year, date.month, date.day - (date.weekday - 1)),
    to: DateTime(date.year, date.month, date.day - (date.weekday - 1) + 6),
  ),
};

/// shiftPeriod: el periodo anterior (-1) o el siguiente (1).
DateTime shiftPeriod(MovementPeriod period, DateTime date, int delta) {
  final from = periodRange(period, date).from;
  return switch (period) {
    MovementPeriod.week => DateTime(from.year, from.month, from.day + 7 * delta),
    MovementPeriod.month => DateTime(from.year, from.month + delta),
    MovementPeriod.year => DateTime(from.year + delta),
  };
}

bool isCurrentPeriod(MovementPeriod period, DateTime date, DateTime now) =>
    periodRange(period, date).from == periodRange(period, _day(now)).from;

/// formatDate de la web: «12 oct 2026»; sin año, «12 oct».
String shortDate(DateTime d, Region region, {bool withYear = true}) {
  final month = shortMonthName(d.month, region);
  final en = region.language == 'en';
  final dayMonth = en ? '$month ${d.day}' : '${d.day} $month';
  if (!withYear) return dayMonth;
  return en ? '$dayMonth, ${d.year}' : '$dayMonth ${d.year}';
}

/// formatRelativeDay: «Hoy», «Ayer» o «12 oct» (con año solo si no es el actual).
String relativeDay(String iso, DateTime now, Region region, Tr t) {
  final date = parseIsoDay(iso);
  final days = _daysBetween(date, now);
  if (days == 0) return t('Hoy');
  if (days == 1) return t('Ayer');
  return shortDate(date, region, withYear: date.year != now.year);
}

/// longDay del detalle: «Hoy, 4 nov 2026» o solo la fecha.
String longDay(String iso, DateTime now, Region region, Tr t) {
  final near = _daysBetween(parseIsoDay(iso), now);
  final date = shortDate(parseIsoDay(iso), region);
  if (near == 0) return '${t('Hoy')}, $date';
  if (near == 1) return '${t('Ayer')}, $date';
  return date;
}

/// periodLabel: «noviembre», «septiembre de 2025», «2026», «esta semana», «semana del 6 al 12 oct».
String periodLabel(MovementPeriod period, DateTime date, DateTime now, Region region, Tr t) {
  switch (period) {
    case MovementPeriod.year:
      return '${date.year}';
    case MovementPeriod.month:
      final month = monthName(date.month, region);
      if (date.year == now.year) return month;
      return region.language == 'en' ? '$month ${date.year}' : '$month de ${date.year}';
    case MovementPeriod.week:
      if (isCurrentPeriod(period, date, now)) return t('esta semana');
      final range = periodRange(period, date);
      final startText = range.from.month == range.to.month
          ? '${range.from.day}'
          : shortDate(range.from, region, withYear: false);
      final endText = shortDate(range.to, region, withYear: range.to.year != now.year);
      return t('semana del {startText} al {endText}', {'startText': startText, 'endText': endText});
  }
}
