import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../money/application/money_providers.dart' show afterMoneyChange;
import '../../movements/application/movement_saver.dart' show afterMovementChange;
import '../data/vaca_models.dart';
import '../data/vacas_repository.dart';

/// GET /vacas de quien está dentro (una copia por cuenta). Metas y Vacas filtran la misma lista por
/// `personal`, como la web. Vigila el día: el estado y los días que faltan vienen contados desde hoy.
final vacasProvider = perAccount<List<Vaca>>((ref) {
  ref.watch(todayProvider);
  return ref.watch(vacasRepositoryProvider).list();
});

/// El detalle de una vaca o meta: `ref.watch(vacaDetailProvider((account, id)))`. La copia de quien
/// salió no pide nada.
final vacaDetailProvider = FutureProvider.family<Vaca, (Session?, String)>((ref, key) {
  if (ref.watch(accountProvider) != key.$1) return Completer<Vaca>().future;
  ref.watch(todayProvider);
  return ref.watch(vacasRepositoryProvider).get(key.$2);
});

/// El consejo de una vaca con su total de ahora: como la web, se vuelve a pedir cuando alguien aporta
/// (el servidor lo guarda mientras el total no cambie).
final vacaAdviceProvider = FutureProvider.family<VacaAdvice, (Session?, String, num)>((ref, key) {
  if (ref.watch(accountProvider) != key.$1) return Completer<VacaAdvice>().future;
  return ref.watch(vacasRepositoryProvider).advice(key.$2);
});

/// Lo que muestra un código antes de unirse.
final invitationPreviewProvider = FutureProvider.family<InvitationPreview, (Session?, String)>((ref, key) {
  if (ref.watch(accountProvider) != key.$1) return Completer<InvitationPreview>().future;
  return ref.watch(vacasRepositoryProvider).preview(key.$2);
});

/// Lo que cambia tras escribir en una vaca: sus providers y, como el servidor arma con las vacas el
/// calendario de pagos y los próximos días (lo que le falta aportar a cada uno), Mi plata y Planear.
/// [movement]: aportar o borrar un aporte crea o borra un GASTO: Movimientos, Inicio, Mi plata y
/// Calendario cambian ([afterMovementChange]).
void afterVacaChange(ProviderContainer container, {bool movement = false}) {
  container.invalidate(vacasProvider);
  container.invalidate(vacaDetailProvider);
  container.invalidate(vacaAdviceProvider);
  movement ? afterMovementChange(container) : afterMoneyChange(container);
}
