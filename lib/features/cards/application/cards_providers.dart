import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../money/application/money_providers.dart';
import '../data/card_models.dart';
import '../data/cards_repository.dart';

/// GET /cards de quien está dentro (una copia por cuenta). Vigila el día: `daysToPayment` viene
/// contado desde hoy, igual que `homeCardsProvider`.
final cardsProvider = perAccount<List<CreditCard>>((ref) {
  ref.watch(todayProvider);
  return ref.watch(cardsRepositoryProvider).list();
});

/// El detalle de una tarjeta y su historial, pedidos en paralelo (CardDetail.jsx:197):
/// `ref.watch(cardDetailProvider((account, id)))`. La copia de quien salió no pide nada.
final cardDetailProvider = FutureProvider.family<CardDetailData, (Session?, String)>((ref, key) async {
  if (ref.watch(accountProvider) != key.$1) return Completer<CardDetailData>().future;
  ref.watch(todayProvider);
  final repo = ref.watch(cardsRepositoryProvider);
  final [card as CreditCard, movements as List<CardMovement>] = await Future.wait<Object?>([
    repo.get(key.$2),
    repo.movements(key.$2),
  ]);
  return CardDetailData(card: card, movements: movements);
});

/// Lo que cambia tras escribir en una tarjeta: sus providers y, como el servidor recalcula el
/// calendario y el plan, también Mi plata y el Inicio ([afterMoneyChange], `homeCardsProvider`
/// incluido). [money]: pagar o borrar un pago SÍ cambia la plata misma; entonces la tarjeta tampoco
/// muestra la deuda de antes mientras recarga («Abonar» sugeriría otra vez lo ya pagado).
void afterCardChange(ProviderContainer container, {bool money = false}) {
  container.invalidate(cardsProvider, asReload: money);
  container.invalidate(cardDetailProvider, asReload: money);
  afterMoneyChange(container, money: money);
}
