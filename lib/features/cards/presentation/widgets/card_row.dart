import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../data/card_models.dart';
import '../../domain/card_rules.dart';
import 'expiry_badge.dart';

/// La barra de uso: solo presentación (el % lo calcula el cliente, Cards.jsx:58). Lleva el nombre
/// «Uso de {name}» y el % para el lector, que la web solo pone en el detalle.
class CardUsageBar extends ConsumerWidget {
  const CardUsageBar({super.key, required this.card});

  final CreditCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final pct = usagePercent(card);
    return Semantics(
      container: true,
      label: t('Uso de {name}', {'name': card.name}),
      value: '$pct %',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RindeRadius.pill),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: p.ink.withValues(alpha: 0.1))),
              // heightFactor: sin él, el relleno queda de 0 de alto dentro del Stack y no se ve.
              FractionallySizedBox(
                widthFactor: pct / 100,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.brandSolid,
                    borderRadius: BorderRadius.circular(RindeRadius.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila compacta de la lista del celular (Cards.jsx:62-83): «{Franquicia} ••{last4}», lo usado a la
/// derecha, cuándo se paga, la barra, «Disponible {x} de {cupo}» y la pastilla de vencimiento.
class CardRow extends ConsumerWidget {
  const CardRow({super.key, required this.card, required this.money, required this.onTap});

  final CreditCard card;
  final HomeMoney money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final label = cardListLabel(t, network: card.network, name: card.name, last4: card.last4);
    final soon = dueSoon(card);
    final due = showDueLine(card) ? dueText(t, card, region) : null;
    return HomeTap(
      onTap: onTap,
      child: HomeSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Con la letra grande lo usado baja a la línea siguiente en vez de cortarse.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RindeSpace.s3,
              children: [
                Text(label, style: RindeType.bodyMedium.copyWith(color: p.ink)),
                MoneyText(
                  money(card.used),
                  money: money,
                  style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
                ),
              ],
            ),
            if (due != null)
              Text(
                due,
                style: soon
                    ? RindeType.small.w(FontWeight.w500).copyWith(color: p.caution)
                    : RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
              ),
            const SizedBox(height: 10),
            CardUsageBar(card: card),
            const SizedBox(height: 6),
            MoneyText(
              '${t('Disponible')} ${money(card.available)} ${t('de')} ${money(card.limit)}',
              money: money,
              style: RindeType.small.tabular.copyWith(color: p.ink.withValues(alpha: 0.7)),
            ),
            ExpiryBadge(expiry: card.expiry),
          ],
        ),
      ),
    );
  }
}
