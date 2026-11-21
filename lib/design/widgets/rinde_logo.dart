import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Isotipo oficial: cuadro violeta, "r" blanca y moneda menta (Logo.jsx, LogoMark).
class RindeLogoMark extends StatelessWidget {
  const RindeLogoMark({super.key, this.size = 32, this.onBrand = false});
  final double size;

  /// Sobre fondo violeta el cuadro se aclara (#A58BFF) para que se distinga, como `tone="light"` en la web.
  final bool onBrand;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    onBrand ? 'assets/brand/rinde-isotipo-claro.svg' : 'assets/brand/rinde-isotipo.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
  );
}

/// Nombre "rinde" dibujado (nunca texto), con la moneda menta sobre la i.
class RindeWordmark extends StatelessWidget {
  const RindeWordmark({super.key, this.height = 18, this.color = const Color(0xFFFFFFFF)});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/rinde-nombre.svg',
    height: height,
    // currentColor = letras; la moneda conserva su menta.
    theme: SvgTheme(currentColor: color),
    excludeFromSemantics: true,
  );
}

/// Isotipo + nombre, como el encabezado de Rinde Web. Se anuncia como "Rinde".
class RindeLogo extends StatelessWidget {
  const RindeLogo({
    super.key,
    this.markSize = 32,
    this.color = const Color(0xFFFFFFFF),
    this.onBrand = false,
  });
  final double markSize;
  final Color color;
  final bool onBrand;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rinde',
    image: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RindeLogoMark(size: markSize, onBrand: onBrand),
        SizedBox(width: markSize * 0.25),
        RindeWordmark(height: markSize * 0.675, color: color),
      ],
    ),
  );
}
