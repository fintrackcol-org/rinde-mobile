import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../home/data/home_models.dart' show readMoney;
import '../../home/domain/home_dates.dart';
import '../../home/domain/runway.dart';
import '../data/money_models.dart';

/// Reglas puras de los pagos fijos de Mi plata (MiPlataMobile.jsx). Solo presentan lo que llegó: qué
/// pago está pendiente o pagado lo decide el servidor.

/// Los pagos de cada mes: los anuales solo cuentan en su mes (`monthly` de la web).
List<Commitment> commitmentsOfMonth(List<Commitment> all, DateTime today) => [
  for (final c in all)
    if (c.frequency != 'yearly' || c.month == today.month) c,
];

/// El primer pago fijo del mes que, a este ritmo, ya no alcanza a cubrirse: vence después del día en
/// que se acaba la plata (`firstUncovered` de la web). null si la plata llega a fin de mes, si no hay
/// ritmo o si no hay pagos después de ese día. A igual día gana el primero del servidor.
Commitment? firstUncovered(List<Commitment> commitments, Runway? r, DateTime today) {
  if (r == null || r.lasts) return null;
  final sameMonth = r.until.year == today.year && r.until.month == today.month;
  final limit = sameMonth ? r.until.day : 0;
  Commitment? first;
  for (final c in commitmentsOfMonth(commitments, today)) {
    if (c.dayOfMonth > today.day &&
        c.dayOfMonth > limit &&
        (first == null || c.dayOfMonth < first.dayOfMonth)) {
      first = c;
    }
  }
  return first;
}

/// Cuándo se cobra, en pocas palabras (commitmentWhen de lib/moneyProfile.js): «día 20», «cada año, el
/// 5 de marzo». El mes, en el idioma de la app (la web lo tiene fijo en español).
String commitmentWhen(Commitment c, Tr t, Region region) => c.frequency == 'yearly' && c.month != null
    ? t('cada año, el {dayOfMonth} de {v2}', {'dayOfMonth': c.dayOfMonth, 'v2': monthName(c.month!, region)})
    : t('día {dayOfMonth}', {'dayOfMonth': c.dayOfMonth});

/// «Falta por pagar» (pendiente y atrasado) y «Ya pagaste» (paymentTotals de MoneyPayments.jsx).
/// Excepción a «no se suman importes en el cliente» (pregunta 5 del plan): el servidor no los da solo
/// de los pagos fijos (`totals` del calendario suma también tarjetas, vacas y cuentas). Se suma en
/// centavos enteros, sin residuos de coma flotante. Solo llegan pagos fijos ([CalendarPayment]).
({num pending, num paid}) paymentTotals(List<CalendarPayment> payments) {
  var pending = 0;
  var paid = 0;
  for (final p in payments) {
    final cents = (p.amount * 100).round();
    if (p.paid) {
      paid += cents;
    } else {
      pending += cents;
    }
  }
  return (pending: readMoney(pending / 100)!, paid: readMoney(paid / 100)!);
}

/// ¿Se ofrece «Ya lo pagué»? Solo para lo del mes en curso: el gasto se anota hoy y solo da por pagado
/// el pago de este mes. El del mes siguiente (que el plan trae con fecha fija) seguiría pendiente y se
/// restaría dos veces (estudio react-pagos-saldo §11.1).
bool payableNow(String date, DateTime today) => date.startsWith(isoMonth(today));

/// Clave de un aviso cerrado (paymentKey de la web): lleva la fecha, así el del mes siguiente vuelve a
/// avisar.
String dismissKey(String id, String date) => '$id-$date';
