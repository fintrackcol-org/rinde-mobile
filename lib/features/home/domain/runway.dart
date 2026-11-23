import 'dart:math' as math;

/// «Te alcanza N días más» de la tarjeta Mi plata (lib/runway.js de Rinde Web). Es una cuenta de
/// PRESENTACIÓN, hecha en el dispositivo con dos datos que ya llegaron (el saldo y lo gastado en el
/// mes): a tu ritmo de este mes (gastado ÷ días que van), ¿cuántos días dura la plata que tienes?
/// No es «libre para gastar»: esa cifra la calcula solo el servidor.
class Runway {
  const Runway({
    required this.days,
    required this.until,
    required this.coverage,
    required this.lasts,
    required this.pace,
  });

  final int days;

  /// Día en que se acaba. Solo sirve si [lasts] es false.
  final DateTime until;

  /// De 0 a 1: qué parte de lo que queda del mes cubre la plata.
  final double coverage;

  /// Llega a fin de mes.
  final bool lasts;

  /// Gasto promedio por día en el mes, redondeado como la web («Gastas en promedio … al día.»).
  final num pace;
}

/// null si falta el saldo o aún no hay gastos para medir el ritmo: no se inventa un número.
///
/// Tres diferencias a propósito con la web, las tres para no dar un día de menos o romperse:
/// - primero se multiplica («saldo × día ÷ gastado» es exacto cuando da entero; dividir antes por el
///   ritmo pierde un día: 17.949 con 17.949 gastados al día 7 daba 6 y son 7);
/// - el día final se cuenta por calendario, no sumando milisegundos (un cambio de hora lo corría);
/// - un resultado enorme se recorta: basta saber que pasa del mes.
Runway? runway({required num? balance, required num? monthExpense, required DateTime today}) {
  if (balance == null || monthExpense == null || monthExpense <= 0) return null;
  final day = today.day;
  final exact = balance * day / monthExpense;
  final lastDay = DateTime(today.year, today.month + 1, 0).day;
  final left = math.max(lastDay - day, 1);
  final days = exact.isFinite ? math.max(0, math.min(exact.floor(), 100000)) : 100000;
  return Runway(
    days: days,
    until: DateTime(today.year, today.month, day + math.min(days, left)),
    coverage: math.min(days / left, 1),
    lasts: days >= left,
    // Recortado como los días: un gasto absurdo no rompe la cuenta.
    pace: math.min(monthExpense / day, 1e12).round(),
  );
}
