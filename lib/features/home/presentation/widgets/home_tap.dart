import 'package:material_ui/material_ui.dart';

import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';

/// Texto de la persona agrandado: las filas de dos columnas pasan a una para que nada se corte.
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 13;

/// Zona tocable del Inicio: sin onda, se encoge un poco al presionar (`active:scale` de la web; no
/// con movimiento reducido), mide al menos 48 y muestra el foco del teclado con el anillo violeta.
class HomeTap extends StatefulWidget {
  const HomeTap({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.toggled,
    this.radius = RindeRadius.brX2,
    this.scale = 0.98,
  });

  final VoidCallback onTap;
  final Widget child;

  /// Lo que lee el lector de pantalla. Sin él, lee los textos de [child].
  final String? label;

  /// Para un interruptor (ocultar montos): estado encendido o apagado.
  final bool? toggled;
  final BorderRadius radius;
  final double scale;

  @override
  State<HomeTap> createState() => _HomeTapState();
}

class _HomeTapState extends State<HomeTap> {
  bool _pressed = false;
  bool _focused = false;

  void _press(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: widget.toggled,
        label: widget.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => _press(true),
            onTapUp: (_) => _press(false),
            onTapCancel: () => _press(false),
            child: AnimatedScale(
              scale: _pressed && !still ? widget.scale : 1,
              duration: still ? Duration.zero : RindeMotion.fast,
              curve: RindeMotion.standard,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: widget.radius,
                  // Por fuera y separado, como el outline-offset-2 de la web: pegado, sobre la
                  // tarjeta violeta no se ve.
                  border: _focused
                      ? Border.all(color: context.palette.brand, width: 2, strokeAlign: 3)
                      : null,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: RindeSize.tapTarget,
                    minWidth: RindeSize.tapTarget,
                  ),
                  child: widget.label == null ? widget.child : ExcludeSemantics(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace de texto del Inicio, de al menos 48 de alto.
class HomeLink extends StatelessWidget {
  const HomeLink({super.key, required this.label, required this.onTap, this.style, this.underline = false});

  final String label;
  final VoidCallback onTap;

  /// Por defecto, violeta de 14 en semibold (`text-sm font-semibold text-brand`).
  final TextStyle? style;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? RindeType.small.w(FontWeight.w600).copyWith(color: context.palette.brand);
    return HomeTap(
      onTap: onTap,
      radius: const BorderRadius.all(Radius.circular(RindeRadius.sm)),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: underline
              ? style.copyWith(decoration: TextDecoration.underline, decorationColor: style.color)
              : style,
        ),
      ),
    );
  }
}

/// Título de bloque (`h2 text-lg font-semibold tracking-tight`), marcado como encabezado.
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: RindeType.title.copyWith(color: context.palette.ink)),
  );
}

/// Tarjeta de superficie del Inicio (`rounded-2xl bg-surface ring-1 ring-ink/10`).
class HomeSurface extends StatelessWidget {
  const HomeSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = RindeRadius.brX2,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: radius,
        border: Border.all(color: p.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
