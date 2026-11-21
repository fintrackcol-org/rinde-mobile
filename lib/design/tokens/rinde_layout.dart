import 'package:flutter/widgets.dart';

/// Espaciado en múltiplos de 4 (escala de Tailwind que usa Rinde Web).
abstract final class RindeSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0; // gutter lateral en celular (px-4)
  static const s5 = 20.0; // padding de tarjetas (p-5)
  static const s6 = 24.0;
  static const s8 = 32.0; // separación entre bloques de formulario (space-y-8)
  static const s10 = 40.0;
  static const s12 = 48.0;

  /// Ancho máximo de la columna de acceso (max-w-[400px]) y de la bienvenida (max-w-md).
  static const authColumn = 400.0;
  static const readableColumn = 448.0;
}

abstract final class RindeRadius {
  static const sm = 8.0; // rounded-lg
  static const segment = 9.0; // pieza de Segmented / AuthSwitch
  static const xl = 12.0; // botones e inputs
  static const x2 = 16.0; // tarjetas
  static const x3 = 24.0; // tarjetas grandes, hojas
  static const pill = 999.0;

  static const brXl = BorderRadius.all(Radius.circular(xl));
  static const brX2 = BorderRadius.all(Radius.circular(x2));
  static const brX3 = BorderRadius.all(Radius.circular(x3));
}

/// Alturas reales de Rinde Web.
abstract final class RindeSize {
  static const buttonLg = 48.0;
  static const button = 44.0;
  static const buttonSm = 36.0;
  static const field = 48.0;

  /// Área táctil mínima (Android 48 dp, iOS 44 pt).
  static const tapTarget = 48.0;
}

/// Duraciones y curvas de index.css.
abstract final class RindeMotion {
  static const fast = Duration(milliseconds: 150); // transition-colors
  static const base = Duration(milliseconds: 200);
  static const page = Duration(milliseconds: 240); // page-in / switch-in
  static const rise = Duration(milliseconds: 420);
  static const fadeUp = Duration(milliseconds: 600);

  static const out = Cubic(0.22, 1, 0.36, 1); // salida
  static const screen = Cubic(0.32, 0.72, 0, 1); // pantallas y hojas
  static const segment = Cubic(0.23, 1, 0.32, 1);
  static const pop = Cubic(0.34, 1.56, 0.64, 1);
  static const standard = Cubic(0.4, 0, 0.2, 1);
}
