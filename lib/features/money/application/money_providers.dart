import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart';
import '../../home/domain/home_dates.dart';
import '../../movements/data/json_list_store.dart';
import '../../plan/application/plan_providers.dart';
import '../data/money_models.dart';
import '../data/money_repository.dart';
import '../domain/money_view.dart';

/// GET /money-profile de quien está dentro (una copia por cuenta).
final moneyProfileProvider = perAccount<MoneyProfile>((ref) => ref.watch(moneyRepositoryProvider).profile());

/// GET /money-profile/income. La meta del día depende de hoy: al cambiar el día se pide otra vez.
final incomeOverviewProvider = perAccount<IncomeOverview>((ref) {
  ref.watch(todayProvider);
  return ref.watch(moneyRepositoryProvider).income();
});

/// GET /money-profile/calendar del mes de hoy (solo los pagos fijos). Al cambiar el mes se pide otra vez.
final paymentCalendarProvider = perAccount<List<CalendarPayment>>(
  (ref) => ref.watch(moneyRepositoryProvider).calendar(isoMonth(ref.watch(todayProvider))),
);

/// Avisos de pago cerrados: por usuario y solo en este teléfono (en la web, `fintrack:avisos-cerrados`
/// del navegador).
final dismissedStoreProvider = Provider<JsonListStore>(
  (ref) => const SecureJsonListStore('rinde.avisos-cerrados.'),
);

/// Los avisos de pago que cerró quien está dentro (`{id}-{date}`): el pago del mes siguiente trae otra
/// fecha y vuelve a avisar.
class DismissedPayments extends AsyncNotifier<Set<String>> {
  /// false: no se pudo leer lo guardado; lo que se cierre dura solo mientras la app siga abierta, para
  /// no pisar lo que no se leyó.
  bool _readable = true;

  @override
  Future<Set<String>> build() async {
    final account = ref.watch(accountProvider);
    if (account == null) return const {};
    final raw = await ref.read(dismissedStoreProvider).read(account.user.id);
    _readable = raw != null;
    return {
      for (final key in raw ?? const <Object?>[])
        if (key is String) key,
    };
  }

  Future<void> dismiss(String key) async {
    final account = ref.read(accountProvider);
    final current = await future;
    // Otra cuenta entró mientras se leía: este aviso no es suyo.
    if (account == null || !ref.mounted || ref.read(accountProvider) != account) return;
    final next = {...current, key};
    state = AsyncData(next);
    if (!_readable) return;
    try {
      await ref.read(dismissedStoreProvider).write(account.user.id, next.toList());
    } on Object {
      // Sin almacenamiento: queda cerrado solo en esta visita (como la web).
    }
  }
}

final dismissedPaymentsProvider = AsyncNotifierProvider<DismissedPayments, Set<String>>(
  DismissedPayments.new,
);

/// El «Ya lo pagué» que se está guardando (`{id}-{date}`); mientras haya uno, los demás no responden
/// (como la web). Es de quien está dentro: al cambiar de cuenta empieza vacío.
class PayingPayment extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(accountProvider);
    return null;
  }

  // ignore: use_setters_to_change_properties
  void set(String key) => state = key;

  /// Suelta [key] si sigue siendo el que se guarda: lo de una cuenta que ya salió no toca a la nueva.
  void release(String key) {
    if (ref.mounted && state == key) state = null;
  }
}

final payingPaymentProvider = NotifierProvider<PayingPayment, String?>(PayingPayment.new);

/// Lo de arriba de Mi plata: la plata del plan del Inicio (o la del perfil) y los gastos del mes.
final myMoneyViewProvider = Provider<MyMoneyView>((ref) {
  final account = ref.watch(accountProvider);
  return buildMyMoneyView(
    profile: blockOf(ref.watch(moneyProfileProvider(account))),
    plan: blockOf(ref.watch(homePlanProvider(account))),
    totals: blockOf(ref.watch(homeTotalsProvider(account))),
    today: ref.watch(todayProvider),
  );
});

/// Correcciones de saldo de un periodo: `(cuenta, desde, hasta)` en AAAA-MM-DD. La copia de quien salió
/// no pide nada. Si fallan, Movimientos se ve igual, sin ellas (como la web).
final balanceAdjustmentsProvider = FutureProvider.family<List<BalanceAdjustment>, (Session?, String, String)>(
  (ref, key) {
    if (ref.watch(accountProvider) != key.$1) return Completer<List<BalanceAdjustment>>().future;
    return ref.watch(moneyRepositoryProvider).adjustments(from: key.$2, to: key.$3);
  },
);

/// Lo que cambia tras escribir en Mi plata: sus datos y todo el Inicio (el servidor recalcula el plan).
/// [money]: cambió la plata misma; lo viejo ya no se muestra mientras llega lo nuevo.
void afterMoneyChange(ProviderContainer container, {bool money = false}) {
  void invalidate(ProviderOrFamily provider) =>
      money ? container.invalidate(provider, asReload: true) : container.invalidate(provider);
  invalidate(moneyProfileProvider);
  invalidate(incomeOverviewProvider);
  invalidate(paymentCalendarProvider);
  // Corregir el saldo deja un ajuste en Movimientos.
  invalidate(balanceAdjustmentsProvider);
  // Lo abierto de Planear: el calendario y los próximos días (pagos), los presupuestos (gastos).
  invalidate(calendarMonthProvider);
  invalidate(liquidityProvider);
  invalidate(budgetsMonthProvider);
  invalidate(budgetMovementsProvider);
  invalidateHome(invalidate);
}
