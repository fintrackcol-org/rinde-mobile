import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/data/home_models.dart';
import '../../home/data/home_repository.dart';
import '../../money/data/money_repository.dart';
import '../../movements/data/movements_repository.dart';
import '../../movements/domain/movement.dart';
import '../data/plan_models.dart';

// Las pantallas de Planear piden lo suyo al abrirse, como la web al montar: al salir se sueltan
// (autoDispose) y al volver se piden de nuevo. Una tarjeta o una cuenta escrita en otra pantalla ya
// se ve aquí. La copia de quien salió no pide nada (como perAccount).

/// GET /budgets?month= de `(cuenta, AAAA-MM)`. El mes en curso lo sigue leyendo también el Inicio.
final budgetsMonthProvider = FutureProvider.autoDispose.family<List<BudgetStatus>, (Session?, String)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<List<BudgetStatus>>().future;
  return ref.watch(homeRepositoryProvider).budgets(key.$2);
});

/// GET /money-profile/calendar?month= completo de `(cuenta, AAAA-MM)`.
final calendarMonthProvider = FutureProvider.autoDispose.family<PaymentCalendar, (Session?, String)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<PaymentCalendar>().future;
  ref.watch(todayProvider);
  return ref.watch(moneyRepositoryProvider).monthCalendar(key.$2);
});

/// GET /liquidity de quien está dentro. Cuenta días desde hoy: al cambiar el día se pide otra vez.
final liquidityProvider = FutureProvider.autoDispose.family<Liquidity, Session?>((ref, account) {
  if (ref.watch(accountProvider) != account) return Completer<Liquidity>().future;
  ref.watch(todayProvider);
  return ref.watch(moneyRepositoryProvider).liquidity();
});

/// Los gastos de un presupuesto (FilteredMovements de la web): `(cuenta, categoría, AAAA-MM)`, los 50
/// más recientes del mes.
final budgetMovementsProvider = FutureProvider.autoDispose.family<MovementPage, (Session?, String, String)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<MovementPage>().future;
  final (_, category, month) = key;
  final first = DateTime.parse('$month-01');
  final last = DateTime(first.year, first.month + 1, 0);
  return ref
      .watch(movementsRepositoryProvider)
      .list(
        MovementQuery(
          type: MovementType.expense,
          category: category,
          from: '$month-01',
          to: '$month-${last.day.toString().padLeft(2, '0')}',
          pageSize: 50,
        ),
      );
});
