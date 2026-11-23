import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';

enum RindeLineTone {
  /// Sobre una superficie: riel ink/10 y relleno violeta.
  surface,

  /// Sobre un fondo violeta (`tone="brand"` de la web): riel blanco al 30 % y relleno blanco.
  brand,
}

/// «La línea que rinde» (common/RindeLine.jsx): riel, relleno y la moneda verde en la punta.
/// Es decorativa: quien la usa anuncia el avance con su propio Semantics.
class RindeLine extends StatelessWidget {
  const RindeLine({super.key, required this.value, this.tone = RindeLineTone.surface, double? height})
    : height = height ?? (tone == RindeLineTone.brand ? 4 : 6);

  /// 0 a 1.
  final double value;
  final RindeLineTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onBrand = tone == RindeLineTone.brand;
    final v = value.clamp(0.0, 1.0);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 300),
        curve: RindeMotion.segment,
        builder: (context, t, _) => SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: onBrand ? RindeBrand.white.withValues(alpha: 0.3) : p.ink.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
                Container(
                  height: height,
                  width: c.maxWidth * t,
                  // En oscuro el relleno usa #6142FF (regla bg-brand de index.css).
                  decoration: BoxDecoration(
                    color: onBrand
                        ? RindeBrand.white
                        : p.brightness == Brightness.dark
                        ? p.brandSolid
                        : p.brand,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth * t - 5).clamp(-5.0, c.maxWidth - 5),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: RindeBrand.success, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
