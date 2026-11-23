import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart';
import '../data/money_models.dart';
import '../data/money_repository.dart';

/// GET /money-profile de quien está dentro (una copia por cuenta).
final moneyProfileProvider = perAccount<MoneyProfile>((ref) => ref.watch(moneyRepositoryProvider).profile());

/// GET /money-profile/income. La meta del día depende de hoy: al cambiar el día se pide otra vez.
final incomeOverviewProvider = perAccount<IncomeOverview>((ref) {
  ref.watch(todayProvider);
  return ref.watch(moneyRepositoryProvider).income();
});

/// Lo que cambia tras escribir en Mi plata: sus datos y todo el Inicio (el servidor recalcula el plan).
/// [money]: cambió la plata misma; lo viejo ya no se muestra mientras llega lo nuevo.
void afterMoneyChange(ProviderContainer container, {bool money = false}) {
  void invalidate(ProviderOrFamily provider) =>
      money ? container.invalidate(provider, asReload: true) : container.invalidate(provider);
  invalidate(moneyProfileProvider);
  invalidate(incomeOverviewProvider);
  invalidateHome(invalidate);
}
