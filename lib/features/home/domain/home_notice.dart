import '../data/home_models.dart';

/// Días antes del pago en los que la tarjeta se avisa como «por vencer» (CARD_SOON_DAYS de la web).
const cardSoonDays = 3;

enum HomeNoticeKind { cardLate, budgetExceeded, cardSoon, budgetWarning, cardNext }

/// El único aviso del Inicio. Quien lo dibuja arma el texto (idioma, montos ocultos).
class HomeNotice {
  const HomeNotice.card(this.kind, CardSummary this.card) : budget = null;
  const HomeNotice.budget(this.kind, BudgetStatus this.budget) : card = null;

  final HomeNoticeKind kind;
  final CardSummary? card;
  final BudgetStatus? budget;
}

/// `pickHomeNotice` de lib/homeNotice.js: el aviso más urgente y solo uno. Orden: tarjeta atrasada,
/// presupuesto pasado, tarjeta por vencer, presupuesto cerca del límite y, por último, la próxima
/// tarjeta. Los pagos fijos no entran: en el celular ya salen en «Lo próximo» (MobileHome.jsx).
///
/// Tres diferencias a propósito con la web, las tres para no avisar algo falso:
/// - una tarjeta sin deuda no avisa (la web llega a decir «pago atrasado · Debes 0»);
/// - un presupuesto justo en el 100 % avisa como «casi llega al límite» (en la web no avisa nada);
/// - entre dos tarjetas con el mismo plazo gana la primera que mandó el servidor.
HomeNotice? pickHomeNotice({List<CardSummary> cards = const [], List<BudgetStatus> budgets = const []}) {
  // La que se paga primero; el `<` estricto conserva el orden del servidor en los empates.
  CardSummary? next;
  for (final card in cards) {
    if (card.paidThisCycle || card.used <= 0) continue;
    if (next == null || card.daysToPayment < next.daysToPayment) next = card;
  }

  if (next != null && next.daysToPayment < 0) return HomeNotice.card(HomeNoticeKind.cardLate, next);

  for (final budget in budgets) {
    if (budget.displayLevel == BudgetLevel.exceeded) {
      return HomeNotice.budget(HomeNoticeKind.budgetExceeded, budget);
    }
  }

  if (next != null && next.daysToPayment <= cardSoonDays) {
    return HomeNotice.card(HomeNoticeKind.cardSoon, next);
  }

  for (final budget in budgets) {
    if (budget.displayLevel == BudgetLevel.warning) {
      return HomeNotice.budget(HomeNoticeKind.budgetWarning, budget);
    }
  }

  return next == null ? null : HomeNotice.card(HomeNoticeKind.cardNext, next);
}
