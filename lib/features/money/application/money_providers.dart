import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart';
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
  // Corregir el saldo deja un ajuste en Movimientos.
  invalidate(balanceAdjustmentsProvider);
  invalidateHome(invalidate);
}
