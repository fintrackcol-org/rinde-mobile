import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import 'movement_dates.dart';

/// PeriodSelector apilado de la web: Semana, Mes o Año y debajo las flechas con el nombre del periodo.
/// No deja ir más allá del periodo actual. Lo usan Movimientos, Ingresos y Gastos.
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.t,
    required this.period,
    required this.label,
    required this.atCurrent,
    required this.onPeriod,
    required this.onShift,
  });

  final Tr t;
  final MovementPeriod period;
  final String label;
  final bool atCurrent;
  final ValueChanged<MovementPeriod> onPeriod;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget arrow(String tooltip, RindeIcons icon, VoidCallback? onTap) => IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: RindeIcon(icon, size: 20, color: onTap == null ? p.ink.withValues(alpha: 0.3) : p.ink),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RindeSegmented<MovementPeriod>(
          semanticLabel: t('Periodo del resumen'),
          options: {
            MovementPeriod.week: t('Semana'),
            MovementPeriod.month: t('Mes'),
            MovementPeriod.year: t('Año'),
          },
          value: period,
          onChanged: onPeriod,
        ),
        const SizedBox(height: RindeSpace.s2),
        Row(
          children: [
            arrow(t('Periodo anterior'), RindeIcons.chevronLeft, () => onShift(-1)),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
              ),
            ),
            arrow(t('Periodo siguiente'), RindeIcons.chevronRight, atCurrent ? null : () => onShift(1)),
          ],
        ),
      ],
    );
  }
}

/// Chip de filtro de una lista (tipo, categoría): marcado en violeta.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RindeIcons? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.brand : p.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? p.brandSoft : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? p.brand : p.lineStrong, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: RindeSpace.s1,
                children: [
                  Text(
                    label,
                    style: RindeType.small
                        .w(selected ? FontWeight.w600 : FontWeight.w500)
                        .copyWith(color: color),
                  ),
                  if (trailing != null) RindeIcon(trailing!, size: 16, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
