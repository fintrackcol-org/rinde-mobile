import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';

/// Control segmentado (common/Segmented.jsx): franja ink/5, pieza blanca que se desliza en 200 ms,
/// opciones de 44 de alto. Siempre hay una elegida.
class RindeSegmented<T> extends StatelessWidget {
  const RindeSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  /// Valor → etiqueta, en orden.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final entries = options.entries.toList();
    final index = entries.indexWhere((e) => e.key == value).clamp(0, entries.length - 1);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      // El margen de 4 está dentro de cada opción (no alrededor): todo el alto responde al toque.
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(RindeSpace.s1),
                child: AnimatedAlign(
                  alignment: Alignment(entries.length == 1 ? 0 : -1 + 2 * index / (entries.length - 1), 0),
                  duration: reduce ? Duration.zero : RindeMotion.base,
                  curve: RindeMotion.segment,
                  child: FractionallySizedBox(
                    widthFactor: 1 / entries.length,
                    heightFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(RindeRadius.segment),
                          boxShadow: const [
                            BoxShadow(color: Color(0x14141414), blurRadius: 2, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s1),
              child: Row(
                children: [
                  for (final e in entries)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: e.key == value,
                        label: e.value,
                        excludeSemantics: true,
                        onTap: onChanged == null ? null : () => onChanged!(e.key),
                        child: InkWell(
                          onTap: onChanged == null ? null : () => onChanged!(e.key),
                          borderRadius: BorderRadius.circular(RindeRadius.segment),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: RindeSize.button + 2 * RindeSpace.s1,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: RindeSpace.s1,
                                  vertical: RindeSpace.s2,
                                ),
                                // Con texto grande se achica antes que partir la palabra.
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    e.value,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: RindeType.control.copyWith(
                                      color: e.key == value ? p.ink : p.ink.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
