/// Textos de «Cómo te entra la plata» (incomeHeadline y sourceSummary de lib/incomeSources.js de
/// Rinde Web). Funciones puras: las cifras ya vienen del servidor y aquí solo se escriben.
library;

import '../../../core/i18n/tr.dart';
import '../../home/data/home_models.dart' show readMoney;
import '../../onboarding/domain/income_sources.dart';
import '../data/money_models.dart';

/// Cómo se escribe un monto (HomeMoney: respeta los montos ocultos).
typedef FormatMoney = String Function(num value);

/// La frase del mes normal y el flaco. null si todavía no se sabe. Montos redondos, como la web.
String? incomeHeadline(IncomeOverview income, Tr t, FormatMoney money) {
  final normal = income.normal;
  final lean = income.lean;
  if (income.basis == 'none' || normal == null || normal <= 0) return null;
  if (lean == null || lean >= normal) {
    return t('Te entran unos {normal} al mes.', {'normal': money(normal.round())});
  }
  return t(
    'En un mes normal te entran {normal}; en uno flaco, {lean}. Planeamos con el flaco para que no te coja la tarde.',
    {'normal': money(normal.round()), 'lean': money(lean.round())},
  );
}

/// Una línea por fuente, para la lista de la hoja. Un monto en 0 cuenta como no dicho (como la web).
String sourceSummary(IncomeSource source, Tr t, FormatMoney money) {
  String? amount(num? value) => value == null || value == 0 ? null : money(value.round());
  String joined(List<String> parts, String empty) => parts.isEmpty ? empty : parts.join(' · ');
  final a = amount(source.amount);
  return switch (source.kind) {
    IncomeKind.sueldo => joined([
      if (a != null) t('{amount} al mes', {'amount': a}),
      if (source.payDays.isNotEmpty) t('días {join}', {'join': source.payDays.join(' ${t('y')} ')}),
    ], t('Sueldo fijo')),
    IncomeKind.comisiones =>
      a == null ? t('Base + comisiones') : t('Base de {amount} + comisiones', {'amount': a}),
    IncomeKind.proyectos =>
      source.lastMonths.isEmpty
          ? t('Por proyectos')
          : t('Últimos meses: {join}', {'join': source.lastMonths.map((m) => money(m.round())).join(', ')}),
    IncomeKind.diario => joined([
      if (source.workDays case final days? when days != 0)
        t('{workDays} días a la semana', {'workDays': days}),
      if (a != null) t('{amount} en un día normal', {'amount': a}),
    ], t('Por días')),
    IncomeKind.mesada =>
      a == null
          ? t('Mesada')
          : switch (source.frequency) {
              'mensual' => t('{amount} al mes', {'amount': a}),
              'quincenal' => t('{amount} cada quincena', {'amount': a}),
              _ => t('{amount} cada semana', {'amount': a}),
            },
  };
}

/// «Tu sueldo» en una línea (incomeSummary de lib/moneyProfile.js). La «y» del final pasa por la
/// traducción (la web la deja en español).
String incomeSummary(MoneyProfile profile, Tr t) {
  if (profile.incomeType == 'sin_fecha') return t('Sin fecha fija');
  if (profile.incomeType != 'fecha_fija') return t('Aún no nos has dicho');
  final days = profile.payDays;
  final joined = days.length < 2
      ? days.join()
      : '${days.sublist(0, days.length - 1).join(', ')} ${t('y')} ${days.last}';
  return t('Con fecha fija, {v1} {days}', {
    'v1': days.length == 1 ? t('el día') : t('los días'),
    'days': joined,
  });
}

/// ¿Lo guardado es lo que se envió? Para un PUT /sources que quedó en duda: los id cambian en cada
/// envío, así que se compara el contenido (tipo, frecuencia, días, montos y días de trabajo).
bool sameSources(List<Map<String, dynamic>> sent, List<IncomeSource> saved) {
  if (sent.length != saved.length) return false;
  bool sameMoney(Object? a, num? b) => readMoney(a) == b;
  bool sameList(List<Object?> a, List<Object?> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
  final byKind = {for (final s in saved) s.kind.name: s};
  return sent.every((s) {
    final o = byKind[s['kind']];
    if (o == null) return false;
    final days = [for (final d in (s['payDays'] as List? ?? const [])) d as int]..sort();
    final months = [for (final m in (s['lastMonths'] as List? ?? const [])) readMoney(m)];
    return s['frequency'] == o.frequency &&
        sameList(days.toSet().toList(), o.payDays) &&
        sameMoney(s['amount'], o.amount) &&
        sameMoney(s['low'], o.low) &&
        sameMoney(s['high'], o.high) &&
        sameList(months, o.lastMonths) &&
        s['workDays'] == o.workDays;
  });
}
