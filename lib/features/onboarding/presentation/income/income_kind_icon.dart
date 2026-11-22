import 'package:material_ui/material_ui.dart';

import '../../../../design/widgets/rinde_icon.dart';
import '../../domain/income_sources.dart';

/// Ícono y color de cada tipo de ingreso (SOURCE_KINDS de lib/incomeSources.js).
///
/// RindeIcons no trae Wallet, TrendingUp, BriefcaseBusiness, Bike ni Gift. Van aquí como SVG con los
/// trazos LITERALES de lucide-react 1.48.0 (dist/esm/icons/*.mjs de Rinde Web; licencia ISC, la misma
/// de assets/icons/). Cuando entren a RindeIcons, este archivo se reduce a los colores.
class IncomeKindIcon extends StatelessWidget {
  const IncomeKindIcon(this.kind, {super.key, this.size = 20});
  final IncomeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => RindeIcon(
    switch (kind) {
      IncomeKind.sueldo => RindeIcons.wallet,
      IncomeKind.comisiones => RindeIcons.trendingUp,
      IncomeKind.proyectos => RindeIcons.briefcaseBusiness,
      IncomeKind.diario => RindeIcons.bike,
      IncomeKind.mesada => RindeIcons.gift,
    },
    size: size,
    color: incomeTone(kind).icon,
  );
}

/// `tone` de la web: fondo del color al 15 % e ícono en su tono (paleta de Tailwind, igual en los
/// dos temas: todos pasan 3:1 sobre surface claro y oscuro).
({Color background, Color icon}) incomeTone(IncomeKind kind) {
  final (base, icon) = switch (kind) {
    IncomeKind.sueldo => (const Color(0xFF00BC7D), const Color(0xFF009966)), // emerald 500 / 600
    IncomeKind.comisiones => (const Color(0xFF00A6F4), const Color(0xFF0084D1)), // sky 500 / 600
    IncomeKind.proyectos => (const Color(0xFF615FFF), const Color(0xFF615FFF)), // indigo 500
    IncomeKind.diario => (const Color(0xFFFE9A00), const Color(0xFFE17100)), // amber 500 / 600
    IncomeKind.mesada => (const Color(0xFFF6339A), const Color(0xFFF6339A)), // pink 500
  };
  return (background: base.withValues(alpha: 0.15), icon: icon);
}
