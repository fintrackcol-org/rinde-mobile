import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';

/// Control segmentado (common/Segmented.jsx): franja ink/5, pieza blanca que se desliza en 200 ms,
/// opciones de 44 de alto. Siempre hay una elegida. Si una etiqueta no cabe a su tamaño (texto grande,
/// pantalla angosta), las opciones van una debajo de otra en vez de achicar la letra.
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
    final piece = BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(RindeRadius.segment),
      boxShadow: const [BoxShadow(color: Color(0x14141414), blurRadius: 2, offset: Offset(0, 1))],
    );

    Widget option(MapEntry<T, String> e, {required bool stacked}) {
      final label = Text(
        e.value,
        // Apilada tiene todo el ancho y puede partir en dos líneas; en fila, una sola.
        maxLines: stacked ? null : 1,
        textAlign: TextAlign.center,
        style: RindeType.control.copyWith(color: e.key == value ? p.ink : p.ink.withValues(alpha: 0.7)),
      );
      return Semantics(
        button: true,
        selected: e.key == value,
        label: e.value,
        excludeSemantics: true,
        onTap: onChanged == null ? null : () => onChanged!(e.key),
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(e.key),
          borderRadius: BorderRadius.circular(RindeRadius.segment),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RindeSize.button + 2 * RindeSpace.s1),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s1, vertical: RindeSpace.s2),
                // En fila ya se midió que cabe; el ajuste solo cubre una diferencia de redondeo.
                child: stacked ? label : FittedBox(fit: BoxFit.scaleDown, child: label),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      // El margen de 4 está dentro de cada opción (no alrededor): todo el alto responde al toque.
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
        child: LayoutBuilder(
          builder: (context, box) {
            // Ancho libre para el texto de cada opción en fila.
            final room = (box.maxWidth - 2 * RindeSpace.s1) / entries.length - 2 * RindeSpace.s1;
            if (entries.any((e) => _width(context, e.value) > room)) {
              // Sin pieza deslizante: las filas pueden medir distinto, la elegida lleva su fondo.
              return Padding(
                padding: const EdgeInsets.all(RindeSpace.s1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in entries)
                      DecoratedBox(
                        decoration: e.key == value ? piece : const BoxDecoration(),
                        child: option(e, stacked: true),
                      ),
                  ],
                ),
              );
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(RindeSpace.s1),
                    child: AnimatedAlign(
                      alignment: Alignment(
                        entries.length == 1 ? 0 : -1 + 2 * index / (entries.length - 1),
                        0,
                      ),
                      duration: reduce ? Duration.zero : RindeMotion.base,
                      curve: RindeMotion.segment,
                      child: FractionallySizedBox(
                        widthFactor: 1 / entries.length,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: DecoratedBox(decoration: piece),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s1),
                  child: Row(children: [for (final e in entries) Expanded(child: option(e, stacked: false))]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Ancho de la etiqueta en una línea, con el tamaño de texto que pidió la persona.
  double _width(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: DefaultTextStyle.of(context).style.merge(RindeType.control)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
