import '../../home/data/home_models.dart';
import '../../home/domain/home_dates.dart';
import '../../home/domain/home_view.dart';
import '../../home/domain/runway.dart';
import '../data/money_models.dart';
import 'commitment_rules.dart';

/// Qué mostrar arriba de Mi plata («¿Hasta cuándo te alcanza?», MiPlataMobile.jsx) según lo que llegó.
/// Función pura, como `buildHomeView`. La cifra es la del servidor: la del plan si está listo y
/// vigente; si no, la del perfil. Aquí solo se presenta: NUNCA se pinta un cero por un dato que falta.

sealed class MoneyLeft {
  const MoneyLeft();
}

/// Aún no se sabe qué cifra va.
class MoneyLeftLoading extends MoneyLeft {
  const MoneyLeftLoading();
}

/// La plata que queda y, si hay gastos del mes con qué medir el ritmo, hasta cuándo alcanza.
class MoneyLeftValue extends MoneyLeft {
  const MoneyLeftValue(this.money, {this.runway});
  final num money;
  final Runway? runway;
}

/// No hay cifra: «—» y el porqué.
class MoneyLeftUnknown extends MoneyLeft {
  const MoneyLeftUnknown(this.reason);
  final UnknownReason reason;
}

class MyMoneyView {
  const MyMoneyView({
    required this.left,
    required this.totals,
    required this.warn,
    required this.stale,
    required this.loadError,
  });

  final MoneyLeft left;

  /// Ingresos y gastos del mes en curso; null si no llegaron (la línea no sale).
  final MonthTotals? totals;

  /// «Ojo con el …»: el primer pago que a este ritmo no alcanza.
  final Commitment? warn;

  /// Hay cifras a la vista que no se pudieron actualizar.
  final bool stale;

  /// El perfil no se pudo traer: aviso con «Reintentar».
  final bool loadError;

  bool get negative => switch (left) {
    MoneyLeftValue(:final money) => money < 0,
    _ => false,
  };
}

MyMoneyView buildMyMoneyView({
  required Block<MoneyProfile> profile,
  required Block<MoneyPlan> plan,
  required Block<MonthTotals> totals,
  required DateTime today,
}) {
  final p = profile.value;
  // Un resumen de otro mes (la app quedó abierta a medianoche del último día) no es «este mes».
  final month = totals.value?.month == isoMonth(today) ? totals.value : null;
  // Un plan que falló (o sin conexión) puede estar viejo: se usa la plata del perfil.
  final freshPlan = plan.failed ? null : plan.value;
  UnknownReason failure() => profile.offline ? UnknownReason.offline : UnknownReason.error;

  final MoneyLeft left;
  if (freshPlan != null && freshPlan.ready) {
    left = MoneyLeftValue(freshPlan.money);
  } else if ((freshPlan == null && plan.loading && !plan.failed) || (p == null && profile.loading)) {
    // Se espera al plan: así la cifra no salta de la del perfil a la del plan.
    left = const MoneyLeftLoading();
  } else if (p == null) {
    left = MoneyLeftUnknown(failure());
  } else if (p.money case final money?) {
    left = MoneyLeftValue(money);
  } else {
    // «No sabemos cuánta plata tienes» solo lo puede decir una respuesta vigente.
    left = MoneyLeftUnknown(profile.failed ? failure() : UnknownReason.noBalance);
  }

  final money = left is MoneyLeftValue ? left.money : null;
  final r = money == null || totals.failed
      ? null
      : runway(balance: money, monthExpense: month?.expense, today: today);
  return MyMoneyView(
    left: money == null ? left : MoneyLeftValue(money, runway: r),
    totals: month,
    warn: firstUncovered(p?.commitments ?? const [], r, today),
    stale: (profile.failed && p != null) || (totals.failed && month != null),
    loadError: profile.failed && !profile.expired,
  );
}
