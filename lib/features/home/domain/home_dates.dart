import '../../../core/region/region.dart';

/// Fechas del Inicio sin depender de Intl: salen igual que `toLocaleDateString(dateLocale())` de
/// Rinde Web (idioma de la app + país), comprobado contra ICU para los 72 países.

const _months = {
  'es': [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ],
  'en': [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ],
  'pt': [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', //
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ],
};

const _shortMonths = {
  'es': ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  'pt': ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'],
};

/// Países donde el inglés escribe el día antes del mes («30 November»).
const _enDayFirst = {
  'JM', 'TT', 'DE', 'NL', 'BE', 'IE', 'AT', 'FI', 'GB', 'CH', 'SE', 'DK', 'HK', //
  'MO', 'SG', 'IN', 'ID', 'MY', 'AE', 'IL', 'AU', 'NZ', 'ZA', 'NG', 'KE',
};

String _language(Region region) => _months.containsKey(region.language) ? region.language : 'es';

/// `noviembre` (mes 1 a 12).
String monthName(int month, Region region) {
  final language = _language(region);
  // Perú y Uruguay escriben «setiembre».
  if (language == 'es' && month == 9 && (region.country == 'PE' || region.country == 'UY')) {
    return 'setiembre';
  }
  return _months[language]![month - 1];
}

/// `nov`, para «hasta el 24 nov».
String shortMonthName(int month, Region region) => _shortMonths[_language(region)]![month - 1];

/// `30 de noviembre` a partir de `2026-11-30` (dayAndMonth de lib/moneyPlan.js).
String dayAndMonth(String isoDate, Region region) {
  final parts = isoDate.split('-');
  final month = monthName(int.parse(parts[1]), region);
  final day = int.parse(parts[2]);
  return switch (_language(region)) {
    'en' => _enDayFirst.contains(region.country) ? '$day $month' : '$month $day',
    _ => '$day de $month',
  };
}

/// `2026-11-30`, con la fecha local del dispositivo (no UTC: de noche no salta de día).
String isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// `2026-11`.
String isoMonth(DateTime date) => isoDay(date).substring(0, 7);
