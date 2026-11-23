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
