import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_button.dart';
import 'rinde_icon.dart';

/// Botón con confirmación EN LÍNEA (common/ConfirmButton.jsx): primero el botón rojo; al tocarlo,
/// la pregunta con «Sí, eliminar» y «Cancelar» en el mismo lugar, y el error ahí dentro si falla.
class ConfirmInline extends StatefulWidget {
  const ConfirmInline({
    super.key,
    required this.label,
    required this.question,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.errorText,
    this.compact = false,
    this.questionSemantics,
    this.labelSemantics,
    this.icon = RindeIcons.trash2,
  });

  /// El ícono del botón inicial: la papelera para borrar; otro cuando la acción no borra.
  final RindeIcons icon;

  final String label;

  /// Lo que oye el lector en vez de [label] (con montos ocultos: «Monto oculto», no la máscara).
  final String? labelSemantics;
  final String question;
  final String confirmLabel;
  final String cancelLabel;

  /// Lanza si falla; el mensaje lo arma [errorText].
  final Future<void> Function() onConfirm;
  final String Function(Object error) errorText;

  /// true: el botón inicial es pequeño (el de una fila del historial).
  final bool compact;

  /// Lo que oye el lector en vez de [question] (con montos ocultos: «Monto oculto», no la máscara).
  final String? questionSemantics;

  @override
  State<ConfirmInline> createState() => _ConfirmInlineState();
}

class _ConfirmInlineState extends State<ConfirmInline> {
  bool _confirming = false;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      // Quien confirma suele navegar o recargar; si seguimos aquí, se vuelve al botón.
      if (mounted) {
        setState(() {
          _confirming = false;
          _busy = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!_confirming) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => _confirming = true),
          style: TextButton.styleFrom(
            foregroundColor: p.negative,
            minimumSize: Size(RindeSize.tapTarget, widget.compact ? RindeSize.tapTarget : RindeSize.button),
            textStyle: widget.compact ? RindeType.small.w(FontWeight.w600) : RindeType.bodyMedium,
          ),
          icon: RindeIcon(widget.icon, size: widget.compact ? 16 : 18, color: p.negative),
          label: Text(widget.label, semanticsLabel: widget.labelSemantics),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: p.negative.withValues(alpha: 0.05), borderRadius: RindeRadius.brXl),
      child: Padding(
        padding: const EdgeInsets.all(RindeSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El botón tocado desaparece: la pregunta se anuncia para que el lector sepa qué pasó.
            Semantics(
              liveRegion: true,
              child: Text(
                widget.question,
                semanticsLabel: widget.questionSemantics,
                style: RindeType.small.copyWith(color: p.ink),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: RindeSpace.s2),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
              ),
            ],
            const SizedBox(height: RindeSpace.s2),
            Wrap(
              spacing: RindeSpace.s2,
              runSpacing: RindeSpace.s2,
              // El aspecto del size="sm" de la web con el área táctil mínima, como «Ya lo pagué» (4B).
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                  child: RindeButton(
                    label: widget.confirmLabel,
                    variant: RindeButtonVariant.outline,
                    size: RindeButtonSize.sm,
                    expand: false,
                    loading: _busy,
                    onPressed: _run,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                  child: RindeButton(
                    label: widget.cancelLabel,
                    variant: RindeButtonVariant.ghost,
                    size: RindeButtonSize.sm,
                    expand: false,
                    onPressed: _busy ? null : () => setState(() => _confirming = false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
