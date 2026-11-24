/// Reglas puras de Cuentas: SOLO presentación y validación previa (lib/debts.js, lib/validation/debt.js
/// y DebtForm.jsx de Rinde Web). Los importes autoritativos vienen del servidor.
library;

import '../../../core/i18n/tr.dart';
import '../../../core/region/money_text.dart' show maxAmount, moneyValue;
import '../../../core/region/region.dart';
import '../../home/domain/home_dates.dart' show shortMonthName;
import '../data/debt_models.dart';
import 'debt_schedule.dart';

int _daysBetween(String from, String to) =>
    DateTime.parse('${to}T00:00:00Z').difference(DateTime.parse('${from}T00:00:00Z')).inDays;

/// El mes corto del idioma de la app; en español, el de MONTHS de lib/debts.js («sept», no «sep»).
String _month(int month, Region region) =>
    region.language == 'es' && month == 9 ? 'sept' : shortMonthName(month, region);

/// «12 nov» o «12 nov 2027» si no es de este año (shortDate de lib/debts.js), con el mes del idioma de
/// la app: la web deja los meses en español aunque la app esté en inglés.
String debtShortDate(String date, String today, Region region) {
  final [y, m, d] = [for (final part in date.split('-')) int.parse(part)];
  final year = today.substring(0, 4) == date.substring(0, 4) ? '' : ' $y';
  // En inglés el mes va primero, como «Due {v2} {d}» del mismo cuadro («Nov 12», no «12 Nov»).
  return region.language == 'en' ? '${_month(m, region)} $d$year' : '$d ${_month(m, region)}$year';
}

/// Cuándo vence una cuota (dueText de lib/debts.js). null si no hay fecha; `late` = ya venció.
({String text, bool late})? debtDueText(Tr t, String? dueDate, String today, Region region) {
  if (dueDate == null) return null;
  final days = _daysBetween(today, dueDate);
  if (days < 0) {
    return (text: days == -1 ? t('Venció ayer') : t('Venció hace {v1} días', {'v1': -days}), late: true);
  }
  if (days == 0) return (text: t('Vence hoy'), late: false);
  if (days == 1) return (text: t('Vence mañana'), late: false);
  if (days <= 7) return (text: t('Vence en {days} días', {'days': days}), late: false);
  final [y, m, d] = [for (final part in dueDate.split('-')) int.parse(part)];
  final year = today.substring(0, 4) == dueDate.substring(0, 4) ? '' : ' $y';
  return (text: t('Vence el {d} {v2}{year}', {'d': d, 'v2': _month(m, region), 'year': year}), late: false);
}

/// «Pagado $50.000 de $200.000 · 1 de 4 cuotas» (progressText de lib/debts.js).
String debtProgressText(Tr t, Debt debt, String Function(num) money) {
  final base = t('Pagado {money} de {amount}', {'money': money(debt.paid), 'amount': money(debt.amount)});
  return debt.installments == null
      ? base
      : t('{base} · {v2} de {installments} cuotas', {
          'base': base,
          'v2': debt.paidInstallments,
          'installments': debt.installments,
        });
}

/// Las iniciales del avatar: «Laura Gómez» → «LG», «mamá» → «M», vacío → «?».
String debtInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String first(String part) => String.fromCharCode(part.runes.first);
  return (first(parts.first) + (parts.length > 1 ? first(parts.last) : '')).toUpperCase();
}

/// Las palabras de cada lado (DEBT_WORDS de lib/debts.js).
({String tab, String settleAll, String left, String movement, String empty}) debtWords(Tr t, DebtKind kind) =>
    switch (kind) {
      DebtKind.receivable => (
        tab: t('Me deben'),
        settleAll: t('Ya me pagó todo'),
        left: t('Te falta recibir'),
        movement: t('Registrar el ingreso en Movimientos'),
        empty: t('Nadie te debe nada. Anota aquí cuando le prestes plata a alguien.'),
      ),
      DebtKind.payable => (
        tab: t('Debo'),
        settleAll: t('Ya pagué todo'),
        left: t('Te falta pagar'),
        movement: t('Registrar el gasto en Movimientos'),
        empty: t('No le debes a nadie. Anota aquí lo que te prestan para no olvidarlo.'),
      ),
    };

/// FREQUENCY_LABELS de lib/debts.js.
String frequencyLabel(Tr t, DebtFrequency frequency) => switch (frequency) {
  DebtFrequency.weekly => t('Cada semana'),
  DebtFrequency.biweekly => t('Cada quincena'),
  DebtFrequency.monthly => t('Cada mes'),
};

/// Lo que escribe el formulario de una cuenta (los dos pasos de DebtForm.jsx).
class DebtFormValues {
  const DebtFormValues({
    required this.person,
    required this.amount,
    required this.loanDate,
    required this.inInstallments,
    required this.installments,
    required this.frequency,
    required this.dueDate,
    required this.note,
  });

  final String person;

  /// Crudo de RindeMoneyField («60000.5»).
  final String amount;
  final String? loanDate;
  final bool inInstallments;

  /// Crudo («4»).
  final String installments;
  final DebtFrequency frequency;

  /// Con cuotas es la PRIMERA cuota (como espera la API); de una vez, la fecha (opcional).
  final String? dueDate;
  final String note;
}

/// Los campos que revisa cada paso antes de «Siguiente» (STEPS de DebtForm.jsx; «Cuándo avisar» no
/// se porta). Un 422 vuelve al paso de su primer campo con error.
const debtStepFields = [
  ['kind', 'person', 'amount', 'loanDate', 'note'],
  ['installments', 'frequency', 'dueDate'],
];

String? _amountProblem(Tr t, String raw) {
  if (raw.trim().isEmpty) return t('Ingresa un monto');
  final value = moneyValue(raw);
  if (value == null) return t('Ingresa un monto válido');
  if (value <= 0) return t('El monto debe ser mayor que 0');
  if (value > maxAmount) return t('El monto es demasiado grande');
  return null;
}

/// debtSchema de lib/validation/debt.js, campo → mensaje. [paid] (al editar): con lo ya abonado, el
/// monto tiene que ser MAYOR. La web no lo revisa y el servidor tampoco (B4): con un monto igual o
/// menor la cuenta queda en 0 sin saldarse y «Ya me pagó todo» da 500.
/// [paidText] es lo abonado ya escrito (con la máscara si los montos están ocultos).
Map<String, String> debtFormProblems(Tr t, DebtFormValues v, {num paid = 0, String paidText = ''}) {
  final person = v.person.trim();
  final amount = _amountProblem(t, v.amount);
  final problems = <String, String>{
    if (person.isEmpty)
      'person': t('Escribe el nombre')
    else if (person.length > 60)
      'person': t('Máximo 60 caracteres'),
    if (amount != null)
      'amount': amount
    else if (paid > 0 && moneyValue(v.amount)! <= paid)
      // TEXTO NUEVO (B4: la web no lo valida)
      'amount': t('Tiene que ser mayor que lo que ya se abonó ({paid})', {'paid': paidText}),
    if (v.note.trim().length > 200) 'note': t('Máximo 200 caracteres'),
  };
  if (v.inInstallments) {
    final n = int.tryParse(v.installments.trim());
    if (n == null || n < 2 || n > 60) problems['installments'] = t('De 2 a 60 cuotas');
    if (v.dueDate == null) problems['dueDate'] = t('Elige la fecha de la primera cuota');
  }
  if (v.loanDate != null && v.dueDate != null && v.loanDate!.compareTo(v.dueDate!) > 0) {
    problems['dueDate'] = t('No puede ser antes del préstamo');
  }
  return problems;
}

/// El cuerpo de POST (con [kind]) o PUT /debts (sin `kind`). Nunca lleva `reminder` (plan §6.1): sin
/// él, el servidor avisa 1 día antes y, al editar, conserva el aviso que había. Montos y cuotas van
/// como NÚMEROS JSON; los opcionales vacíos, en null.
Map<String, dynamic> debtBody(DebtFormValues v, {DebtKind? kind}) {
  final note = v.note.trim();
  return {
    'kind': ?kind?.wire,
    'person': v.person.trim(),
    'amount': moneyValue(v.amount),
    'loanDate': v.loanDate,
    // Con cuotas es la PRIMERA cuota (al editar sale de firstDueDate, nunca del dueDate leído).
    'dueDate': v.dueDate,
    'installments': v.inInstallments ? int.parse(v.installments.trim()) : null,
    'frequency': v.inInstallments ? v.frequency.wire : null,
    'note': note.isEmpty ? null : note,
  };
}

/// «4 cuotas de $50.000 · la última el 12 feb» antes de guardar (planPreview de DebtForm.jsx). null si
/// falta algo para calcularla.
String? debtPlanPreview(
  Tr t,
  DebtFormValues v, {
  required String today,
  required Region region,
  required String Function(num) money,
}) {
  final total = moneyValue(v.amount);
  final n = int.tryParse(v.installments.trim());
  if (!v.inInstallments || total == null || total <= 0 || n == null || n < 2 || n > 60 || v.dueDate == null) {
    return null;
  }
  final cuotas = schedule(amount: total, installments: n, frequency: v.frequency, firstDueDate: v.dueDate!);
  return t('{n} cuotas de {amount} · la última el {date}', {
    'n': n,
    'amount': money(cuotas.first.amount),
    'date': debtShortDate(cuotas.last.date, today, region),
  });
}

/// debtPaymentSchema + «No puede pasar de lo que falta» (PaymentForm.jsx:39-42, tolerancia 0,004).
/// [pendingText] es lo pendiente ya escrito (con la máscara si los montos están ocultos, como la web).
Map<String, String> debtPaymentProblems(
  Tr t, {
  required String amount,
  required num pending,
  required String pendingText,
}) {
  final problem = _amountProblem(t, amount);
  if (problem != null) return {'amount': problem};
  if (moneyValue(amount)! > pending + 0.004) {
    return {
      'amount': t('No puede pasar de lo que falta ({pending})', {'pending': pendingText}),
    };
  }
  return const {};
}
