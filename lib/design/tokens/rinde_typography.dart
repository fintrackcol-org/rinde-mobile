import 'package:flutter/painting.dart';

/// Escala tipográfica de Rinde Web (Tailwind 4 + tamaños propios), con Inter Tight variable.
///
/// Con una fuente variable el peso se fija en el eje `wght`; por eso cada estilo lleva
/// `fontWeight` y `fontVariations` a la vez. Para cambiar el peso usa [RindeTextWeight.w],
/// no `copyWith(fontWeight:)`, o el eje queda desincronizado.
abstract final class RindeType {
  static const family = 'Inter Tight';

  static TextStyle _style(double size, double height, FontWeight weight, {double trackingEm = 0}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', _axis(weight))],
        letterSpacing: trackingEm * size,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static double _axis(FontWeight w) => switch (w) {
    FontWeight.w100 => 100,
    FontWeight.w200 => 200,
    FontWeight.w300 => 300,
    FontWeight.w400 => 400,
    FontWeight.w500 => 500,
    FontWeight.w600 => 600,
    FontWeight.w700 => 700,
    FontWeight.w800 => 800,
    _ => 900,
  };

  /// Cierre de la landing y bienvenida: clamp(2.5rem, 12vw, 3rem), leading .98, tracking -0.04em.
  static final hero = _style(44, 43, FontWeight.w600, trackingEm: -0.04);

  /// Títulos de acceso: text-4xl font-semibold tracking-tight.
  static final display = _style(36, 40, FontWeight.w600, trackingEm: -0.025);

  /// PageHeader: text-2xl font-semibold tracking-tight.
  static final headline = _style(24, 32, FontWeight.w600, trackingEm: -0.025);

  /// Título de hoja: text-lg font-semibold tracking-tight.
  static final title = _style(18, 28, FontWeight.w600, trackingEm: -0.025);

  /// Botón grande: text-lg font-medium.
  static final buttonLg = _style(18, 24, FontWeight.w500);

  /// text-base.
  static final body = _style(16, 24, FontWeight.w400);
  static final bodyMedium = _style(16, 24, FontWeight.w500);

  /// Controles: pestañas, Segmented, AuthSwitch (text-[15px] font-medium).
  static final control = _style(15, 20, FontWeight.w500);

  /// text-sm: labels (medium), ayudas y errores (regular).
  static final small = _style(14, 20, FontWeight.w400);
  static final label = _style(14, 18, FontWeight.w500);

  /// text-[13px], metadatos.
  static final meta = _style(13, 18, FontWeight.w400);

  /// text-xs.
  static final caption = _style(12, 16, FontWeight.w400);

  /// Sobrerrótulo en mayúsculas: text-sm font-semibold tracking-[0.18em].
  static final overline = _style(14, 20, FontWeight.w600, trackingEm: 0.18);

  /// Cifras de dinero: números tabulares, como `tabular-nums` en la web.
  static const tabular = [FontFeature.tabularFigures()];
}

extension RindeTextWeight on TextStyle {
  /// Cambia el peso manteniendo sincronizado el eje variable.
  TextStyle w(FontWeight weight) =>
      copyWith(fontWeight: weight, fontVariations: [FontVariation('wght', RindeType._axis(weight))]);

  TextStyle get tabular => copyWith(fontFeatures: RindeType.tabular);
}
