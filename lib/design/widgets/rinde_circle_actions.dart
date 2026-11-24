import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_icon.dart';

/// Una acción de la fila de círculos. [primary]: círculo violeta lleno (la principal).
class RindeCircleAction {
  const RindeCircleAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final RindeIcons icon;
  final VoidCallback onTap;
  final bool primary;
}

/// Fila de círculos que se desliza, con las acciones de una pantalla en el celular
/// (common/CircleActions.jsx): círculo de 60, etiqueta debajo, la primera suele ser la principal.
class RindeCircleActions extends StatelessWidget {
  const RindeCircleActions({super.key, required this.label, required this.actions});

  /// Nombre del grupo para el lector de pantalla («Acciones de Tarjetas»).
  final String label;
  final List<RindeCircleAction> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = actions.length <= 4 ? 88.0 : 78.0;
    return Semantics(
      container: true,
      label: label,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final action in actions)
              Semantics(
                button: true,
                label: action.label,
                onTap: action.onTap,
                excludeSemantics: true,
                child: InkWell(
                  onTap: action.onTap,
                  borderRadius: RindeRadius.brX2,
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s1),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: action.primary ? p.brandSolid : p.brandSoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: RindeIcon(
                              action.icon,
                              size: 24,
                              color: action.primary ? RindeBrand.white : p.brand,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            action.label,
                            textAlign: TextAlign.center,
                            style: RindeType.meta.w(FontWeight.w500).copyWith(color: p.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
