import 'package:material_ui/material_ui.dart';

import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../home/data/home_models.dart' show BudgetLevel;

/// Color de un presupuesto según su alerta (LEVEL_STYLES de BudgetList.jsx).
Color budgetColor(BuildContext context, BudgetLevel level) {
  final p = context.palette;
  return switch (level) {
    BudgetLevel.none => p.positive,
    BudgetLevel.warning => p.caution,
    BudgetLevel.exceeded => p.negative,
  };
}

/// Barra de avance redonda sobre ink/10. [share] de 0 a 1: pasado el 100 % queda llena (el número
/// dice cuánto).
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.share, required this.color, this.height = 8});

  final double share;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: height,
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: context.palette.ink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(RindeRadius.pill),
      ),
      child: FractionallySizedBox(
        widthFactor: share.clamp(0, 1),
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(RindeRadius.pill)),
        ),
      ),
    ),
  );
}

/// Aviso en una caja del color de su tono, con ícono: rojo si [negative], amarillo si no (BudgetAlert
/// y el hueco del Calendario). Con [onTap] es un enlace con flecha.
class PlanAlert extends StatelessWidget {
  const PlanAlert({super.key, required this.message, required this.negative, required this.icon, this.onTap});

  final String message;
  final bool negative;
  final RindeIcons icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = negative ? p.negative : p.caution;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: 14),
      child: Row(
        children: [
          RindeIcon(icon, size: 20, color: color),
          const SizedBox(width: RindeSpace.s3),
          Expanded(
            child: Text(message, style: RindeType.small.w(FontWeight.w500).copyWith(color: color)),
          ),
          if (onTap != null) RindeIcon(RindeIcons.chevronRight, size: 16, color: color),
        ],
      ),
    );
    return Semantics(
      container: true,
      link: onTap != null,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: RindeRadius.brX2,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: RindeRadius.brX2, child: content),
      ),
    );
  }
}
