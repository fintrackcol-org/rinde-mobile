import 'package:flutter/widgets.dart';

import '../../../../core/region/region.dart';
import '../../../../design/tokens/rinde_typography.dart';

/// Cómo se escribe un monto en el Inicio. Es el ÚNICO camino por el que una cifra llega a la
/// pantalla o al lector de pantalla: con los montos ocultos devuelve la máscara del país
/// («$ ••••••», «•••••• €») y ningún dígito.
class HomeMoney {
  const HomeMoney({required this.format, required this.hidden, required this.hiddenLabel});

  final MoneyFormat format;
  final bool hidden;

  /// «Monto oculto», ya traducido.
  final String hiddenLabel;

  String get _mask => '${format.prefix}••••••${format.suffix}';

  String call(num value) => hidden ? _mask : format.money(value);

  /// Lo que oye el lector de pantalla en un texto que lleva montos: «Monto oculto» en vez de la
  /// moneda y seis viñetas.
  String spoken(String text) => hidden ? text.replaceAll(_mask, hiddenLabel) : text;
}

/// Texto con montos: cifras tabulares y, oculto, se lee «Monto oculto». Sin animación al ocultar ni
/// región viva: una cifra nunca se anuncia sola.
class MoneyText extends StatelessWidget {
  const MoneyText(this.text, {super.key, required this.money, this.style, this.fit = false});

  final String text;
  final HomeMoney money;
  final TextStyle? style;

  /// Una sola línea que se achica para caber entera: un monto cortado no sirve.
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: fit ? 1 : null,
      softWrap: !fit,
      semanticsLabel: money.spoken(text),
      style: (style ?? DefaultTextStyle.of(context).style).tabular,
    );
    return fit
        ? FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: label)
        : label;
  }
}
