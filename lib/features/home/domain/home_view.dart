import '../../../core/network/api_exception.dart';
import '../../onboarding/data/onboarding_repository.dart' show WelcomeStatus;
import '../data/home_models.dart';
import 'home_dates.dart';
import 'home_notice.dart';
import 'runway.dart';

/// Qué mostrar en el Inicio según lo que llegó, lo que falta y lo que falló. Es una función pura
/// (sin widgets ni red) para poder probar todas las combinaciones. Parte de `Dashboard.jsx` y
/// `MobileHome.jsx` de Rinde Web, con una regla que la web no cumple siempre:
///
///   NUNCA se muestra una cifra que no llegó. Un dato que falta no es un cero.

/// Un bloque de datos del Inicio: su último valor, si se está pidiendo y con qué falló.
class Block<T> {
  const Block({this.value, this.loading = false, this.error});
  const Block.data(T this.value) : loading = false, error = null;
  const Block.loading() : value = null, loading = true, error = null;
  const Block.failed(Object this.error) : value = null, loading = false;

  /// Último valor bueno de ESTA cuenta en esta sesión. Puede estar viejo si [error] no es null.
  final T? value;
  final bool loading;

  /// Con qué falló el último intento (se limpia cuando uno sale bien).
  final Object? error;

  bool get failed => error != null;

  /// Sin conexión: la petición no salió del teléfono.
  bool get offline => _code == ApiCodes.network;

  /// La sesión venció: el router ya lleva al login, no es un error del Inicio.
  bool get expired => _code == ApiCodes.tokenExpired || _code == ApiCodes.unauthorized;

  String? get _code => switch (error) {
    final ApiException e => e.code,
    _ => null,
  };
}

sealed class HomeHero {
  const HomeHero();
}

/// Aún no se sabe qué tarjeta va: un solo esqueleto hasta que lleguen el saldo y el plan.
class HeroLoading extends HomeHero {
  const HeroLoading();
}

enum PlanTone { free, short, negative }

/// El servidor entregó el plan: «Libre para gastar», «Te faltan» o «Estás en negativo».
class HeroPlan extends HomeHero {
  const HeroPlan(this.plan);
  final MoneyPlan plan;

  PlanTone get tone => plan.negative
      ? PlanTone.negative
      : plan.short
      ? PlanTone.short
      : PlanTone.free;
}

enum RunwayNote {
  /// Aún no llegan los gastos del mes.
  calculating,

  /// Llegaron y no hay gastos con qué medir el ritmo.
  needsData,
}

/// Sin plan: el saldo («Mi plata») y, si hay con qué, hasta cuándo alcanza al ritmo del mes.
class HeroMoney extends HomeHero {
  const HeroMoney({required this.money, this.runway, this.note});
  final num money;
  final Runway? runway;

  /// Qué decir cuando no hay [runway]; null si los gastos del mes no se pudieron traer.
  final RunwayNote? note;
}

enum UnknownReason {
  /// El servidor respondió y no sabe cuánta plata hay (nadie se lo ha dicho).
  noBalance,
  offline,
  error,
}

/// No hay una cifra que mostrar. Se dice por qué; nunca se pinta un cero.
class HeroUnknown extends HomeHero {
  const HeroUnknown(this.reason);
  final UnknownReason reason;
}

enum HomeFooter { none, invite, setup }

class HomeView {
  const HomeView({
    required this.hero,
    required this.showLinks,
    required this.balanceSet,
    required this.negativeNote,
    required this.nextPayments,
    required this.totals,
    required this.toConfirm,
    required this.notice,
    required this.footer,
    required this.empty,
    required this.offline,
    required this.stale,
    required this.loadError,
    required this.tourEligible,
  });

  final HomeHero hero;

  /// Enlaces bajo la tarjeta («Corrígela», y «Revisa tus gastos» en negativo).
  final bool showLinks;

  /// La persona ya dijo cuánta plata tiene (FT-0057).
  final bool balanceSet;

  /// Saldo bajo cero sin plan: nota con salida a revisar los gastos.
  final bool negativeNote;

  /// Como mucho [maxNextPayments], en el orden del servidor.
  final List<PendingPayment> nextPayments;

  /// Ingresos y gastos del mes en curso.
  final Block<MonthTotals> totals;
  final int toConfirm;
  final HomeNotice? notice;
  final HomeFooter footer;

  /// La cuenta no tiene ningún movimiento (dato fresco del servidor).
  final bool empty;

  /// Algún bloque principal no salió del teléfono.
  final bool offline;

  /// Hay cifras a la vista que no se pudieron actualizar: son lo último que llegó, no lo vigente.
  final bool stale;

  /// Algún bloque principal falló por otra causa: aviso con «Reintentar».
  final bool loadError;

  /// Bienvenida hecha y tutorial sin ver, con el Inicio ya cargado.
  final bool tourEligible;

  bool get reviewExpenses => hero is HeroPlan && (hero as HeroPlan).tone == PlanTone.negative;
}

/// `NEXT` de MobileHome.jsx.
const maxNextPayments = 2;

HomeView buildHomeView({
  required Block<WelcomeStatus> status,
  required Block<MoneyPlan> plan,
  required Block<MonthTotals> totals,
  Block<List<BudgetStatus>> budgets = const Block(),
  Block<List<CardSummary>> cards = const Block(),
  int toConfirm = 0,
  required DateTime today,
}) {
  final profile = status.value;
  // Un resumen de otro mes (la app quedó abierta a medianoche del último día) no es «este mes».
  final monthTotals = totals.value == null || totals.value!.month == isoMonth(today)
      ? totals
      : Block<MonthTotals>(loading: !totals.failed, error: totals.error);
  // Un plan cuyo último intento falló puede estar viejo: no se muestra como vigente.
  final freshPlan = plan.failed ? null : plan.value;

  final HomeHero hero;
  if (profile == null) {
    // El plan sí llegó: un fallo del perfil o de los movimientos no lo esconde, ni al reintentar.
    hero = status.failed && freshPlan != null && freshPlan.ready
        ? HeroPlan(freshPlan)
        : status.loading
        ? const HeroLoading()
        : HeroUnknown(status.offline ? UnknownReason.offline : UnknownReason.error);
  } else if (freshPlan == null && plan.loading && !plan.failed) {
    hero = const HeroLoading();
  } else if (freshPlan != null && freshPlan.ready) {
    hero = HeroPlan(freshPlan);
  } else if (profile.money == null) {
    // «No sabemos cuánta plata tienes» solo lo puede decir una respuesta vigente.
    hero = HeroUnknown(
      !status.failed
          ? UnknownReason.noBalance
          : status.offline
          ? UnknownReason.offline
          : UnknownReason.error,
    );
  } else {
    final expense = monthTotals.failed ? null : monthTotals.value?.expense;
    final r = runway(balance: profile.money, monthExpense: expense, today: today);
    hero = HeroMoney(
      money: profile.money!,
      runway: r,
      note: r != null
          ? null
          : monthTotals.failed
          ? null
          : monthTotals.value == null
          ? RunwayNote.calculating
          : RunwayNote.needsData,
    );
  }

  final notice = pickHomeNotice(
    cards: cards.failed ? const [] : cards.value ?? const [],
    budgets: budgets.failed ? const [] : budgets.value ?? const [],
  );
  final settled = profile != null && !status.failed && !status.loading;
  final main = [status, plan, totals];

  return HomeView(
    hero: hero,
    // Sin perfil no se sabe si ya dijo su saldo: no se le pregunta.
    showLinks:
        profile != null &&
        (profile.balanceSet || !status.failed) &&
        (hero is HeroPlan ||
            hero is HeroMoney ||
            (hero is HeroUnknown && hero.reason == UnknownReason.noBalance)),
    balanceSet: profile?.balanceSet ?? false,
    negativeNote: hero is HeroMoney && hero.money < 0,
    nextPayments: hero is HeroPlan ? hero.plan.pending.take(maxNextPayments).toList() : const [],
    totals: monthTotals,
    toConfirm: toConfirm,
    notice: notice,
    footer: notice != null || profile == null
        ? HomeFooter.none
        : !profile.welcomeDone
        // Con un dato viejo no se invita: puede estar pidiendo lo que acaba de responder.
        ? (status.failed ? HomeFooter.none : HomeFooter.invite)
        : freshPlan != null && !freshPlan.ready
        ? HomeFooter.setup
        : HomeFooter.none,
    // De una petición fallida no se concluye que no hay movimientos. Al refrescar se conserva: si
    // no, la tarjeta parpadearía cada vez que se hala para recargar.
    empty: profile != null && !status.failed && !profile.hasTransactions,
    offline: main.any((b) => b.offline),
    stale: (status.failed && profile != null) || (monthTotals.failed && monthTotals.value != null),
    loadError: main.any((b) => b.failed && !b.offline && !b.expired),
    tourEligible: settled && profile.welcomeDone && !profile.tutorialDone && hero is! HeroLoading,
  );
}
