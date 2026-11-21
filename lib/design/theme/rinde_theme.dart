import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';

/// Temas de Rinde construidos desde los tokens. Material aporta la mecánica (foco, teclado,
/// accesibilidad), no la apariencia: sin ondas ni colores por defecto.
abstract final class RindeTheme {
  /// Acceso (bienvenida, login, registro): siempre oscuro, como Rinde Web.
  static final public = _build(RindePalette.public);
  static final light = _build(RindePalette.light);
  static final dark = _build(RindePalette.dark);

  static ThemeData _build(RindePalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: RindeBrand.violet,
      onPrimary: RindeBrand.white,
      secondary: p.brand,
      onSecondary: RindeBrand.white,
      error: p.negative,
      onError: RindeBrand.white,
      surface: p.surface,
      onSurface: p.ink,
    );

    TextStyle ink(TextStyle s) => s.copyWith(color: p.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      fontFamily: RindeType.family,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      // Rinde no usa ondas: la respuesta táctil es un leve encogimiento (active:scale-[0.98]).
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      focusColor: RindeBrand.violet.withValues(alpha: 0.4),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: RindeBrand.violet,
        selectionColor: RindeBrand.violet.withValues(alpha: 0.35),
        selectionHandleColor: RindeBrand.violet,
      ),
      textTheme: TextTheme(
        displayLarge: ink(RindeType.hero),
        displayMedium: ink(RindeType.display),
        headlineMedium: ink(RindeType.headline),
        titleLarge: ink(RindeType.title),
        titleMedium: ink(RindeType.bodyMedium),
        bodyLarge: ink(RindeType.body),
        bodyMedium: ink(RindeType.small),
        bodySmall: RindeType.caption.copyWith(color: p.inkMuted),
        labelLarge: ink(RindeType.control),
        labelMedium: ink(RindeType.label),
        labelSmall: RindeType.caption.copyWith(color: p.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: p.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [p],
    ).copyWith(
      // Inputs: los dibuja RindeTextField; esto cubre cualquier campo suelto.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.field,
        hintStyle: RindeType.body.copyWith(color: p.inkPlaceholder),
        contentPadding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: RindeRadius.brXl,
          borderSide: BorderSide(color: p.fieldLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: RindeRadius.brXl,
          borderSide: BorderSide(color: p.fieldLine),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: RindeRadius.brXl,
          borderSide: BorderSide(color: RindeBrand.violet, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: RindeRadius.brXl,
          borderSide: BorderSide(color: RindeBrand.destructive),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: RindeRadius.brXl,
          borderSide: BorderSide(color: RindeBrand.destructive, width: 1.5),
        ),
      ),
    );
  }
}
