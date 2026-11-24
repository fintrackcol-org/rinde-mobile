/// Cuotas y avance de una cuenta con abonos: copia de `lib/debtSchedule.js` de Rinde Web, que a su vez
/// copia `backend/src/services/debt-schedule.js`. SOLO sirve para la vista previa del formulario y para
/// la demostración: los importes que se muestran de una cuenta real son siempre los del servidor.
library;

import 'dart:math' as math;

import '../../home/domain/home_dates.dart' show isoDay;
import '../data/debt_models.dart';

num _cents(num n) {
  final cents = (n * 100).round();
  return cents % 100 == 0 ? cents ~/ 100 : cents / 100;
}

/// Suma [k] periodos a una fecha AAAA-MM-DD. Quincenal son 15 días, como se paga en Colombia; mensual
/// es el mismo día del mes que toca, o el último si ese mes es más corto (31 de enero → 28 de febrero).
String addPeriods(String date, DebtFrequency frequency, int k) {
  final [y, m, d] = [for (final part in date.split('-')) int.parse(part)];
  if (frequency == DebtFrequency.monthly) {
    final target = DateTime.utc(y, m + k);
    final last = DateTime.utc(target.year, target.month + 1, 0).day;
    return isoDay(DateTime.utc(target.year, target.month, math.min(d, last)));
  }
  final days = frequency == DebtFrequency.weekly ? 7 : 15;
  return isoDay(DateTime.utc(y, m, d + days * k));
}

/// Las cuotas: el monto se reparte en partes iguales truncadas a centavos y la última absorbe la
/// diferencia.
List<Installment> schedule({
  required num amount,
  required int installments,
  required DebtFrequency frequency,
  required String firstDueDate,
}) {
  final each = (amount / installments * 100).floor() / 100;
  return [
    for (var i = 0; i < installments; i++)
      Installment(
        number: i + 1,
        date: addPeriods(firstDueDate, frequency, i),
        amount: i == installments - 1 ? _cents(amount - each * (installments - 1)) : _cents(each),
      ),
  ];
}

/// Cuánto se pagó, cuánto falta y cuál es la próxima cuota. Los abonos cubren primero la cuota 1,
/// luego la 2…; uno parcial deja la cuota «en curso» con lo que le falta (tolerancia de 0,004).
({num paid, num pending, int paidInstallments, Installment? next}) progress({
  required num amount,
  required num paid,
  int? installments,
  DebtFrequency? frequency,
  String? firstDueDate,
  String? dueDate,
}) {
  final total = _cents(paid);
  final pending = math.max<num>(0, _cents(amount - total));
  if (installments == null || frequency == null || firstDueDate == null) {
    return (
      paid: total,
      pending: pending,
      paidInstallments: 0,
      next: pending > 0 && dueDate != null ? Installment(number: 1, date: dueDate, amount: pending) : null,
    );
  }
  var left = total;
  var paidInstallments = 0;
  Installment? next;
  for (final cuota in schedule(
    amount: amount,
    installments: installments,
    frequency: frequency,
    firstDueDate: firstDueDate,
  )) {
    if (left >= cuota.amount - 0.004) {
      left = _cents(left - cuota.amount);
      paidInstallments += 1;
      continue;
    }
    next = Installment(number: cuota.number, date: cuota.date, amount: _cents(cuota.amount - left));
    break;
  }
  return (paid: total, pending: pending, paidInstallments: paidInstallments, next: next);
}
