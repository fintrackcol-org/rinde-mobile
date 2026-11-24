import 'dart:math' as math;

import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../debts/domain/debt_rules.dart' show debtShortDate;
import '../../home/domain/home_dates.dart' show shortMonthName;
import '../../home/domain/runway.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../money/data/money_models.dart' show Commitment;
import '../data/vaca_models.dart';

/// Textos de Metas y Vacas (vacaFormat.js y goalPlan.js de Rinde Web). Todo sale de lo que manda el
/// servidor (proyección, estados, cuotas); aquí solo se arma lo que se lee. Las cuentas del plan por
/// semana y del colchón son de PRESENTACIÓN, las mismas que hace la web en el navegador.

/// Monto sin centavos (formatPesos de la web): las cuotas repartidas no ayudan con centavos.
String pesos(HomeMoney money, num value) => money(value.round());

/// `62,5 %`, con el separador decimal del país.
String formatPercent(num value, MoneyFormat format) {
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
  return '${text.replaceAll('.', format.decimal)} %';
}

/// `15 dic` (o con el año si no es este), como shortDate y formatDate de la web.
String vacaDate(String iso, String today, Region region) => debtShortDate(iso, today, region);

String memberStatusLabel(Tr t, MemberStatus status) => switch (status) {
  MemberStatus.done => t('Cumplió'),
  MemberStatus.onTime => t('Al día'),
  MemberStatus.late => t('Atrasado'),
  MemberStatus.pending => t('Le falta'),
};

String vacaStatusLabel(Tr t, VacaStatus status) => switch (status) {
  VacaStatus.active => t('Activa'),
  VacaStatus.completed => t('Meta cumplida'),
  VacaStatus.expired => t('Venció'),
};

/// Frase corta del plazo (deadlineText): días que faltan, si venció o que no tiene fecha.
String deadlineText(Tr t, Vaca vaca, String today, Region region, {bool withDate = true}) {
  final deadline = vaca.deadline;
  if (deadline == null) return t('Sin fecha límite');
  final date = vacaDate(deadline, today, region);
  if (vaca.status == VacaStatus.completed) {
    return withDate ? t('Fecha límite: {date}', {'date': date}) : t('Cumplida');
  }
  final days = vaca.projection.daysLeft ?? 0;
  if (days < 0) return withDate ? t('Venció el {date}', {'date': date}) : t('Venció');
  if (days == 0) return withDate ? t('Vence hoy ({date})', {'date': date}) : t('Vence hoy');
  final left = days == 1 ? t('Falta 1 día') : t('Faltan {days} días', {'days': days});
  return withDate ? '$left · $date' : left;
}

enum VacaTone { positive, caution, neutral }

/// La lectura del ritmo (projectionText): al grupo en una vaca, a la persona en una meta.
({VacaTone tone, String text}) projectionText(Tr t, Vaca vaca, HomeMoney money, String today, Region region) {
  final solo = vaca.personal;
  final p = vaca.projection;
  if (vaca.status == VacaStatus.completed) {
    return (
      tone: VacaTone.positive,
      text: solo
          ? t('¡Meta cumplida! Ya tienes toda la plata.')
          : t('¡Meta cumplida! Ya juntaron toda la plata.'),
    );
  }
  if (vaca.total == 0) {
    return (
      tone: VacaTone.neutral,
      text: solo
          ? t('Aún no has apartado nada. Con el primer aporte calculamos tu ritmo.')
          : t('Aún no hay aportes. Con el primero calculamos el ritmo del grupo.'),
    );
  }
  final estimated = p.estimatedDate == null ? null : vacaDate(p.estimatedDate!, today, region);
  // TEXTO NUEVO: la web deja «completan», «completas», «no llegan» y «no llegas» sin traducir.
  final complete = solo ? t('completas') : t('completan');
  if (vaca.status == VacaStatus.expired) {
    return (
      tone: VacaTone.caution,
      text: t('Pasó la fecha límite y faltan {remaining}.', {'remaining': pesos(money, p.remaining)}),
    );
  }
  if (vaca.deadline == null) {
    return (
      tone: VacaTone.neutral,
      text: estimated != null
          ? t('A este ritmo ({averagePerDay} por día) {complete} la meta hacia el {estimated}.', {
              'averagePerDay': pesos(money, p.averagePerDay),
              'complete': complete,
              'estimated': estimated,
            })
          : solo
          ? t('Sigue aportando para ver cuándo completas la meta.')
          : t('Sigan aportando para ver cuándo completan la meta.'),
    );
  }
  if (p.onTrack == true) {
    return (
      tone: VacaTone.positive,
      text: t('{onTime}: a este ritmo {complete} la meta hacia el {estimated}.', {
        'onTime': solo ? t('Vas a tiempo') : t('Van a tiempo'),
        'complete': complete,
        'estimated': estimated ?? '',
      }),
    );
  }
  final would = solo ? t('terminarías') : t('terminarían');
  return (
    tone: VacaTone.caution,
    text: t('A este ritmo {late}{v2}. {need} {formatPesos} por semana{each}.', {
      'late': solo ? t('no llegas') : t('no llegan'),
      // TEXTO NUEVO: «hacia el» (la web lo deja sin traducir).
      'v2': estimated == null ? '' : ' ($would ${t('hacia el')} $estimated)',
      'need': solo ? t('Necesitas') : t('Necesitan'),
      'formatPesos': pesos(money, p.neededPerWeek ?? p.remaining),
      'each': solo ? '' : t(' entre todos'),
    }),
  );
}

// ── Metas (goalPlan.js) ──────────────────────────────────────────────────────

/// Redondea hacia arriba a miles, como el plan por semana de la web.
num upToThousand(num value) => (value / 1000).ceil() * 1000;

/// Cuánto apartar cada semana para llegar a tiempo; null sin fecha o con la fecha pasada.
({num perWeek, int weeks})? weeklyPlan({
  required num goal,
  num saved = 0,
  String? deadline,
  required String today,
}) {
  if (!(goal > 0) || deadline == null || deadline.isEmpty) return null;
  final days =
      DateTime.utc(
            int.parse(deadline.substring(0, 4)),
            int.parse(deadline.substring(5, 7)),
            int.parse(deadline.substring(8, 10)),
          )
          .difference(
            DateTime.utc(
              int.parse(today.substring(0, 4)),
              int.parse(today.substring(5, 7)),
              int.parse(today.substring(8, 10)),
            ),
          )
          .inDays;
  if (days <= 0) return null;
  final weeks = math.max(1, (days / 7).ceil());
  return (perWeek: upToThousand(math.max(0, goal - saved) / weeks), weeks: weeks);
}

/// ¿El plan pasa del 30 % de lo que entra por semana?
bool isTooMuch(num perWeek, num? weeklyIncome) =>
    weeklyIncome != null && weeklyIncome > 0 && perWeek > weeklyIncome * 0.3;

/// Gastos fijos de un mes, con los anuales repartidos en 12.
num monthlyFixed(List<Commitment> commitments) =>
    commitments.fold<num>(0, (sum, c) => sum + (c.frequency == 'yearly' ? c.amount / 12 : c.amount)).round();

/// El colchón: 3 meses de gastos fijos y cuántos días se aguanta hoy sin ingresos. null sin fijos.
({num goal, int days})? cushion({required num fixed, required num saved}) {
  if (!(fixed > 0)) return null;
  return (goal: fixed * 3, days: (saved / (fixed / 30)).floor());
}

/// ¿Es la meta del colchón? Por el nombre, como la web.
bool isCushionGoal(Vaca meta) =>
    RegExp(r'emergenc|colch[oó]n|cushion|reserva para', caseSensitive: false).hasMatch(meta.name);

/// El chip de una meta: «Cumplida», «Venció», «Vas bien» o «Vas lento» (paceChip).
({String label, bool good})? paceChip(Tr t, Vaca meta) {
  if (meta.status == VacaStatus.completed) return (label: t('Cumplida'), good: true);
  if (meta.status == VacaStatus.expired) return (label: t('Venció'), good: false);
  if (meta.projection.onTrack == true) return (label: t('Vas bien'), good: true);
  if (meta.projection.onTrack == false) return (label: t('Vas lento'), good: false);
  return null;
}

/// Qué hacer para llegar (adviceText de Metas.jsx).
String metaAdvice(Tr t, Vaca meta, HomeMoney money, String today, Region region) {
  final p = meta.projection;
  if (meta.status == VacaStatus.completed) return t('Ya completaste la meta.');
  if (meta.deadline != null && (p.neededPerWeek ?? 0) > 0) {
    return t('Si apartas {formatPesos} cada semana, llegas a tiempo.', {
      'formatPesos': pesos(money, upToThousand(p.neededPerWeek!)),
    });
  }
  if (p.estimatedDate != null) {
    return t('A tu ritmo la completas el {estimatedDate}.', {
      'estimatedDate': vacaDate(p.estimatedDate!, today, region),
    });
  }
  return t('Aparta algo hoy para arrancar.');
}

/// «hasta el 24 nov» o «pasa el fin de mes» (untilText de lib/runway.js).
String untilText(Tr t, Runway r, Region region) => r.lasts
    ? t('pasa el fin de mes')
    : t('hasta el {getDate} {v2}', {'getDate': r.until.day, 'v2': shortMonthName(r.until.month, region)});
