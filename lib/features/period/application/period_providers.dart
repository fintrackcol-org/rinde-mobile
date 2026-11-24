import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../movements/data/movements_repository.dart';
import '../../movements/domain/movement.dart';
import '../../movements/presentation/list/movement_dates.dart';
import '../data/period_models.dart';
import '../data/period_repository.dart';

// Ingresos y Gastos piden lo suyo al abrirse, como la web al montar: al salir se sueltan (autoDispose).
// La copia de quien salió no pide nada (como perAccount). afterMoneyChange los vuelve a pedir.

/// El resumen de `(cuenta, periodo, día AAAA-MM-DD)`.
final periodSummaryProvider = FutureProvider.autoDispose
    .family<PeriodSummary, (Session?, MovementPeriod, String)>((ref, key) {
      if (ref.watch(accountProvider) != key.$1) return Completer<PeriodSummary>().future;
      return ref.watch(periodRepositoryProvider).summary(key.$2, key.$3);
    });

/// La lista del periodo (FilteredMovements de la web, 50 por página): `(cuenta, consulta)`.
final periodMovementsProvider = FutureProvider.autoDispose.family<MovementPage, (Session?, MovementQuery)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<MovementPage>().future;
  return ref.watch(movementsRepositoryProvider).list(key.$2);
});

/// Los gastos del periodo para el Kakeibo: `(cuenta, desde, hasta)`. KakeiboSplit.jsx pide 200 y el
/// servidor acepta hasta 100 (responde 422 y la web oculta la sección): aquí se piden 100 y la pantalla
/// solo la muestra si llegaron todos (con más, los porcentajes serían de una parte).
final periodKakeiboProvider = FutureProvider.autoDispose.family<MovementPage, (Session?, String, String)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<MovementPage>().future;
  return ref
      .watch(movementsRepositoryProvider)
      .list(MovementQuery(type: MovementType.expense, from: key.$2, to: key.$3, pageSize: 100));
});
