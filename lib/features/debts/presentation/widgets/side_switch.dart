import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../data/debt_models.dart';
import '../../domain/debt_rules.dart';

/// Los dos lados como pestañas grandes con su total (SideSwitch de Debts.jsx): «Me deben · N» con lo
/// pendiente en verde y «Debo · N» en rojo; en gris si no hay nada. La cuenta de pendientes la hace el
/// cliente, el total viene del servidor. El color no va solo: cada pestaña dice su lado.
class DebtSideSwitch extends ConsumerWidget {
  const DebtSideSwitch({
    super.key,
    required this.value,
    required this.data,
    required this.money,
    required this.onChanged,
  });

  final DebtKind value;
  final DebtsList data;
  final HomeMoney money;
  final ValueChanged<DebtKind> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;

    Widget tab(DebtKind kind) {
      final selected = kind == value;
      final count = data.items.where((d) => d.kind == kind && !d.settled).length;
      final total = data.total(kind);
      final name = debtWords(t, kind).tab;
      final amount = money(total);
      return Semantics(
        button: true,
        selected: selected,
        label: money.spoken('$name${count > 0 ? ' · $count' : ''}, $amount'),
        excludeSemantics: true,
        onTap: () => onChanged(kind),
        child: InkWell(
          onTap: () => onChanged(kind),
          borderRadius: RindeRadius.brXl,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? p.canvas : Colors.transparent,
              borderRadius: RindeRadius.brXl,
              border: selected ? Border.all(color: p.lineStrong) : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: name,
                        children: [
                          if (count > 0)
                            TextSpan(
                              text: ' · $count',
                              style: TextStyle(color: p.ink.withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                      style: RindeType.small
                          .w(FontWeight.w500)
                          .copyWith(color: selected ? p.ink : p.ink.withValues(alpha: 0.7)),
                    ),
                    MoneyText(
                      amount,
                      money: money,
                      fit: true,
                      style: RindeType.title.copyWith(
                        color: total > 0
                            ? (kind == DebtKind.receivable ? p.positive : p.negative)
                            : p.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: t('Cuentas'),
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s1),
        // Las dos del mismo alto aunque una parta en dos líneas con la letra grande.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tab(DebtKind.receivable)),
              const SizedBox(width: RindeSpace.s1),
              Expanded(child: tab(DebtKind.payable)),
            ],
          ),
        ),
      ),
    );
  }
}
