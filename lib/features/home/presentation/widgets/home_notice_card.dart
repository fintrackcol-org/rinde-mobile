import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../application/home_providers.dart';
import '../../data/home_models.dart';
import '../../domain/home_notice.dart';
import 'home_money.dart';
import 'home_tap.dart';
import '../../../auth/application/session_controller.dart';
import '../../../cards/domain/card_rules.dart' show cardListLabel, dueWhen;

/// El único aviso del Inicio. Los textos son los de lib/homeNotice.js; cuál aviso gana ya lo
/// decidió `pickHomeNotice`.
class HomeNoticeCard extends ConsumerWidget {
  const HomeNoticeCard({super.key, required this.notice, required this.money});

  final HomeNotice notice;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final card = notice.card;
    final budget = notice.budget;

    // La etiqueta común de Tarjetas («Otra ••1234» también): el aviso, la lista y el detalle dicen lo mismo.
    String cardName(CardSummary card) =>
        cardListLabel(t, network: card.network, name: card.name, last4: card.last4);

    // Si el nombre traducido no llegó, la clave de la categoría (como la web).
    String category(BudgetStatus budget) =>
        ref.watch(homeCategoryNamesProvider(ref.watch(accountProvider))).value?[budget.category] ??
        budget.category;

    final (title, detail) = switch (notice.kind) {
      HomeNoticeKind.cardLate => (
        t('Tu {nextCard} tiene el pago atrasado', {'nextCard': cardName(card!)}),
        t('Debes {used}', {'used': money(card.used)}),
      ),
      HomeNoticeKind.cardSoon || HomeNoticeKind.cardNext => (
        t('Tu {nextCard} se paga {daysToPayment}', {
          'nextCard': cardName(card!),
          'daysToPayment': dueWhen(t, card.daysToPayment),
        }),
        t('Debes {used}', {'used': money(card.used)}),
      ),
      HomeNoticeKind.budgetExceeded => (
        t('Te pasaste en {exceeded}', {'exceeded': category(budget!)}),
        t('Llevas {consumed} de {amount}', {
          'consumed': money(budget.consumed),
          'amount': money(budget.amount),
        }),
      ),
      HomeNoticeKind.budgetWarning => (
        t('{warning} ya casi llega al límite', {'warning': category(budget!)}),
        t('Quedan {money}', {'money': money(budget.left)}),
      ),
    };

    return HomeTap(
      onTap: () => context.push(card != null ? Routes.card(card.id) : Routes.budgets),
      label: money.spoken('$title. $detail'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: p.brandSolid, shape: BoxShape.circle),
              ),
              const SizedBox(width: RindeSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: RindeType.small.w(FontWeight.w600).copyWith(color: p.ink)),
                    MoneyText(
                      detail,
                      money: money,
                      style: RindeType.small.copyWith(color: p.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RindeSpace.s3),
              RindeIcon(RindeIcons.chevronRight, size: 18, color: p.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acceso a Mi plata para quien omitió la bienvenida o no la respondió completa
/// (money/MoneySetupLink.jsx): sin esto, nada en el Inicio dice dónde configurarlo.
class MoneySetupLink extends ConsumerWidget {
  const MoneySetupLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return HomeTap(
      onTap: () => context.push(Routes.myMoney),
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Row(
          children: [
            RindeIcon(RindeIcons.wallet, color: p.brand),
            const SizedBox(width: RindeSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('¿Cuánta plata tienes hoy?'),
                    style: RindeType.small.w(FontWeight.w500).copyWith(color: p.ink),
                  ),
                  Text(
                    t('Dínoslo y cómo te entra la plata: así ves tu plata real y cuánto puedes gastar.'),
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: RindeSpace.s3),
            // La web usa ink/40 (2,6:1 en claro): con ink/60 la flecha sí se distingue.
            RindeIcon(RindeIcons.chevronRight, color: p.inkMuted),
          ],
        ),
      ),
    );
  }
}
