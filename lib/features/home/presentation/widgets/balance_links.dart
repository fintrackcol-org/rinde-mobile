import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import 'home_tap.dart';

/// Plata en negativo casi siempre es un dato mal anotado (money/NegativeBalanceNote.jsx): se dice y
/// se lleva a revisar los gastos. No dice montos: sale aunque estén ocultos.
class NegativeBalanceNote extends ConsumerWidget {
  const NegativeBalanceNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    // La web escribe todo en rojo sobre rojo al 10 % (4,2:1 en claro): aquí el texto va en ink y el
    // rojo queda en el ícono. Toda la nota se toca, para que el enlace mida 48.
    final style = RindeType.small.copyWith(color: p.ink);
    return HomeTap(
      onTap: () => context.push(Routes.expenses),
      radius: RindeRadius.brXl,
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.negative.withValues(alpha: 0.1), borderRadius: RindeRadius.brXl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: RindeIcon(RindeIcons.circleAlert, size: 16, color: p.negative),
              ),
              const SizedBox(width: RindeSpace.s2),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: '${t('Tus gastos superan lo que tienes. ¿Anotaste algo mal?')} ',
                    children: [
                      TextSpan(
                        text: t('Revisa tus gastos'),
                        style: style.w(FontWeight.w500).copyWith(decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las salidas bajo la tarjeta grande: revisar los gastos (en negativo) y corregir la plata (FT-0057).
class BalanceLinks extends ConsumerWidget {
  const BalanceLinks({super.key, required this.reviewExpenses, required this.balanceSet});

  final bool reviewExpenses;
  final bool balanceSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final style = RindeType.meta
        .w(FontWeight.w500)
        .copyWith(color: context.palette.ink.withValues(alpha: 0.7));
    return Wrap(
      spacing: RindeSpace.s5,
      children: [
        if (reviewExpenses)
          HomeLink(
            label: t('Revisa tus gastos'),
            style: style,
            underline: true,
            onTap: () => context.push(Routes.expenses),
          ),
        HomeLink(
          label: balanceSet
              ? t('¿No es tu plata real? Corrígela')
              : t('¿Ya tenías plata cuando empezaste? Dinos cuánta tienes hoy'),
          style: style,
          underline: true,
          onTap: () => context.push(Routes.fixBalance),
        ),
      ],
    );
  }
}
