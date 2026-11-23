import 'package:material_ui/material_ui.dart';

/// Colores fijos de marca (`@theme` de frontend/src/index.css). No cambian con el tema.
abstract final class RindeBrand {
  static const violet = Color(0xFF6142FF); // primary, ring
  static const violetLight = Color(0xFF8B66FF);
  static const mint = Color(0xFFCCFFF0);
  static const success = Color(0xFF2FD6A3); // moneda del logo
  static const destructive = Color(0xFFF04438); // fijo en los dos temas
  static const obsidian = Color(0xFF141414);
  static const orchid = Color(0xFFD8A0DF);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  /// Texto secundario sobre fondo violeta. La web usa blanco/80 (4,2:1); aquí 90 % para llegar a AA (4,8:1).
  static const onVioletMuted = Color(0xE6FFFFFF);
}

/// Colores que cambian con el tema (`--app-*` de index.css). En Rinde Web hay tres:
/// - [public]: `:root`, oscuro, para landing, login y registro (siempre oscuros).
/// - [light] y [dark]: `[data-theme]`, dentro de la app.
@immutable
class RindePalette extends ThemeExtension<RindePalette> {
  const RindePalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.field,
    required this.fieldLine,
    required this.brand,
    required this.brandSoft,
    required this.positive,
    required this.negative,
    required this.caution,
  });

  static const public = RindePalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF000000),
    surface: Color(0x08FFFFFF), // rgb(255 255 255 / .03)
    surfaceMuted: Color(0x0FFFFFFF), // .06
    ink: Color(0xFFFFFFFF),
    field: Color(0xFF000000),
    fieldLine: Color(0xFF323232),
    brand: Color(0xFF8B66FF),
    brandSoft: Color(0x266142FF), // rgb(97 66 255 / .15)
    positive: Color(0xFF2FD6A3),
    negative: Color(0xFFF04438),
    caution: Color(0xFFFCD34D),
  );

  static const light = RindePalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF5F4F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEDF6),
    ink: Color(0xFF16141F),
    field: Color(0xFFFFFFFF),
    fieldLine: Color(0xFFD9D6E4),
    brand: Color(0xFF5B3DF5),
    brandSoft: Color(0xFFECE8FF),
    positive: Color(0xFF087A59),
    negative: Color(0xFFC8321F),
    caution: Color(0xFF9A5B00),
  );

  static const dark = RindePalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF0C0B11),
    surface: Color(0xFF15141C),
    surfaceMuted: Color(0xFF1E1C27),
    ink: Color(0xFFF2F1F7),
    field: Color(0xFF0F0E15),
    fieldLine: Color(0xFF2D2B38),
    brand: Color(0xFF9B85FF),
    brandSoft: Color(0x2E6142FF), // rgb(97 66 255 / .18)
    positive: Color(0xFF34D6A5),
    negative: Color(0xFFFF7A6B),
    caution: Color(0xFFFBBF24),
  );

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color field;
  final Color fieldLine;

  /// Acento de texto e íconos. Para un FONDO violeta con texto blanco usa [brandSolid].
  final Color brand;
  final Color brandSoft;
  final Color positive; // ingresos, éxito
  final Color negative; // gastos, error
  final Color caution;

  /// Violeta como fondo con texto blanco: #6142FF en los dos modos (index.css:296-299,
  /// contraste 5,6:1 frente a 2,9:1 si se usara el brand claro del modo oscuro).
  Color get brandSolid => RindeBrand.violet;

  /// Rojo como fondo con texto blanco (botón de borrar): el del modo claro en los dos modos. Blanco
  /// sobre él da 5,3:1; sobre el rojo claro del modo oscuro (#FF7A6B), solo 2,5:1.
  Color get negativeSolid => const Color(0xFFC8321F);

  // En Rinde Web los textos y bordes secundarios son ink con opacidad, no tokens propios.
  Color get inkMuted => ink.withValues(alpha: 0.6); // text-ink/60, texto de apoyo
  Color get inkSubtle => ink.withValues(alpha: 0.5);
  Color get inkLabel => ink.withValues(alpha: 0.8); // labels
  Color get inkPlaceholder => ink.withValues(alpha: 0.35);
  Color get line => ink.withValues(alpha: 0.10); // border-ink/10
  Color get lineStrong => ink.withValues(alpha: 0.15); // botón outline
  Color get wash => ink.withValues(alpha: 0.05); // bg-ink/5

  @override
  RindePalette copyWith({Color? canvas, Color? surface, Color? ink, Color? brand}) => RindePalette(
    brightness: brightness,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted,
    ink: ink ?? this.ink,
    field: field,
    fieldLine: fieldLine,
    brand: brand ?? this.brand,
    brandSoft: brandSoft,
    positive: positive,
    negative: negative,
    caution: caution,
  );

  @override
  RindePalette lerp(RindePalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RindePalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      ink: l(ink, other.ink),
      field: l(field, other.field),
      fieldLine: l(fieldLine, other.fieldLine),
      brand: l(brand, other.brand),
      brandSoft: l(brandSoft, other.brandSoft),
      positive: l(positive, other.positive),
      negative: l(negative, other.negative),
      caution: l(caution, other.caution),
    );
  }
}

extension RindePaletteContext on BuildContext {
  RindePalette get palette => Theme.of(this).extension<RindePalette>() ?? RindePalette.light;
}
