import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_spinner.dart';

/// Variantes de `components/ui/button.jsx` más las dos del cierre violeta de la landing.
enum RindeButtonVariant {
  /// bg-primary (#6142FF) con texto blanco, fijo en los dos temas.
  primary,

  /// Borde ink/15, fondo transparente.
  outline,

  /// Texto ink/60, sin fondo.
  ghost,

  /// Fondo brand-soft, texto brand.
  soft,

  /// Sobre fondo violeta: blanco con texto violeta ("Crear cuenta gratis").
  onBrand,

  /// Sobre fondo violeta: borde blanco/40 ("Ya tengo cuenta").
  onBrandOutline,
}

enum RindeButtonSize {
  sm(RindeSize.buttonSm),
  md(RindeSize.button),
  lg(RindeSize.buttonLg);

  const RindeButtonSize(this.height);
  final double height;
}

/// Botón de Rinde: radio 12 (o píldora), sin onda, se encoge un poco al presionar.
/// Mientras [loading] muestra el spinner y [loadingLabel], y no responde.
class RindeButton extends StatefulWidget {
  const RindeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = RindeButtonVariant.primary,
    this.size = RindeButtonSize.lg,
    this.loading = false,
    this.loadingLabel,
    this.expand = true,
    this.pill = false,
    this.trailing,
    this.leading,
    this.semanticsLabel,
  });

  final String label;

  /// Lo que oye el lector en vez de [label] (con montos ocultos, `money.spoken(label)`).
  final String? semanticsLabel;
  final VoidCallback? onPressed;
  final RindeButtonVariant variant;
  final RindeButtonSize size;
  final bool loading;
  final String? loadingLabel;
  final bool expand;
  final bool pill;
  final Widget? trailing;
  final Widget? leading;

  @override
  State<RindeButton> createState() => _RindeButtonState();
}

class _RindeButtonState extends State<RindeButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, border) = switch (widget.variant) {
      RindeButtonVariant.primary => (RindeBrand.violet, RindeBrand.white, null),
      RindeButtonVariant.outline => (Colors.transparent, p.ink, p.lineStrong),
      RindeButtonVariant.ghost => (Colors.transparent, p.inkMuted, null),
      RindeButtonVariant.soft => (p.brandSoft, p.brand, p.brand.withValues(alpha: 0.2)),
      RindeButtonVariant.onBrand => (RindeBrand.white, RindeBrand.violet, null),
      RindeButtonVariant.onBrandOutline => (
        Colors.transparent,
        RindeBrand.white,
        RindeBrand.white.withValues(alpha: 0.4),
      ),
    };
    final textStyle = (widget.size == RindeButtonSize.lg ? RindeType.buttonLg : RindeType.bodyMedium)
        .copyWith(color: fg, fontSize: widget.size == RindeButtonSize.sm ? 14 : null);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(widget.pill ? RindeRadius.pill : RindeRadius.xl);
    final label = widget.loading ? (widget.loadingLabel ?? widget.label) : widget.label;

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[RindeSpinner(size: 16, color: fg), const SizedBox(width: RindeSpace.s2)],
        if (!widget.loading && widget.leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: fg, size: 16),
            child: widget.leading!,
          ),
          const SizedBox(width: RindeSpace.s2),
        ],
        Flexible(
          child: Text(
            label,
            semanticsLabel: widget.loading ? null : widget.semanticsLabel,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
        ),
        if (!widget.loading && widget.trailing != null) ...[
          const SizedBox(width: RindeSpace.s2),
          DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: widget.trailing!,
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      // El lector anuncia el estado de carga, no solo el texto.
      label: widget.loading ? label : null,
      excludeSemantics: widget.loading,
      child: AnimatedOpacity(
        opacity: widget.onPressed == null && !widget.loading ? 0.5 : 1,
        duration: RindeMotion.fast,
        child: AnimatedScale(
          scale: _pressed && !reduceMotion ? 0.98 : 1,
          duration: RindeMotion.fast,
          curve: RindeMotion.standard,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.size.height),
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: border == null ? BorderSide.none : BorderSide(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                hoverColor: fg.withValues(alpha: 0.05),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.size == RindeButtonSize.sm ? RindeSpace.s4 : RindeSpace.s6,
                    vertical: RindeSpace.s2,
                  ),
                  child: Center(widthFactor: widget.expand ? null : 1, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace de texto (variante `link`): violeta, sin subrayado hasta presionarlo.
class RindeTextLink extends StatelessWidget {
  const RindeTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.style,
    this.semanticsLabel,
  });

  final String label;

  /// Lo que oye el lector en vez de [label] (con montos ocultos, `money.spoken(label)`).
  final String? semanticsLabel;
  final VoidCallback? onPressed;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.brand;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(RindeRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s1),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                semanticsLabel: semanticsLabel,
                style: (style ?? RindeType.small.w(FontWeight.w500)).copyWith(color: c),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
