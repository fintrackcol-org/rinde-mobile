import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../domain/card_rules.dart';

/// Degradados ORIGINALES por nivel (lib/cardStyles.js): no copian el arte de ningún banco ni
/// franquicia, y la franquicia se escribe como texto. «Otra» usa siempre el gris.
({Color from, Color to, Color foreground}) cardArtColors(String network, String tier) {
  const light = Color(0xFFFFFFFF);
  const dark = Color(0xFF111827);
  final key = network == 'otra' ? 'otra' : tier;
  return switch (key) {
    'gold' => (from: const Color(0xFFB8860B), to: const Color(0xFFF5D76E), foreground: dark),
    'platinum' => (from: const Color(0xFF9CA3AF), to: const Color(0xFFE5E7EB), foreground: dark),
    'black' => (from: const Color(0xFF0A0A0A), to: const Color(0xFF262626), foreground: light),
    'green' => (from: const Color(0xFF064E3B), to: const Color(0xFF047857), foreground: light),
    'blue' => (from: const Color(0xFF7DD3FC), to: const Color(0xFFE0F2FE), foreground: dark),
    'clasica' => (from: const Color(0xFF1E3A8A), to: const Color(0xFF2563EB), foreground: light),
    _ => (from: const Color(0xFF374151), to: const Color(0xFF6B7280), foreground: light),
  };
}

/// Tarjeta de crédito dibujada (CreditCardArt.jsx): sin logos reales, solo los últimos 4 dígitos y,
/// si hay, el vencimiento MM/AA abajo a la derecha, como en el plástico.
class CreditCardArt extends ConsumerWidget {
  const CreditCardArt({
    super.key,
    required this.network,
    required this.tier,
    required this.last4,
    this.name,
    this.expiry,
    this.small = false,
  });

  final String network;
  final String tier;
  final String last4;
  final String? name;

  /// «03/27».
  final String? expiry;
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final colors = cardArtColors(network, tier);
    final width = small ? 192.0 : 336.0;
    final base = small ? 10.0 : 12.0;
    final label = networkTierLabel(t, network, tier);
    final text = TextStyle(color: colors.foreground, fontSize: base, fontWeight: FontWeight.w600);
    return Semantics(
      image: true,
      label: t('{network} terminada en {last4}{v3}', {
        'network': label,
        'last4': last4,
        // TEXTO NUEVO (en la web va sin t(), CreditCardArt.jsx:17)
        'v3': expiry == null ? '' : t(', vence {expiry}', {'expiry': expiry}),
      }),
      // Es un dibujo de tamaño fijo (lo que dice va en la etiqueta de arriba): sus letras no crecen
      // con la letra del sistema, como no crece una foto.
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          child: Container(
            width: width,
            height: width / 1.586,
            padding: EdgeInsets.all(small ? RindeSpace.s3 : RindeSpace.s5),
            decoration: BoxDecoration(
              borderRadius: RindeRadius.brX2,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.from, colors.to],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
                    ),
                    const SizedBox(width: RindeSpace.s2),
                    Flexible(
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
                    ),
                  ],
                ),
                const Spacer(),
                CustomPaint(
                  size: Size(small ? 27 : 36, small ? 20 : 27),
                  painter: _ChipPainter(colors.foreground),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        '•••• $last4',
                        style: TextStyle(
                          color: colors.foreground,
                          fontSize: base + 4,
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (expiry case final expiry?)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            t('Vence').toUpperCase(),
                            style: TextStyle(
                              color: colors.foreground.withValues(alpha: 0.8),
                              fontSize: base * 0.7,
                            ),
                          ),
                          Text(
                            expiry,
                            style: TextStyle(color: colors.foreground, fontSize: base),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El chip dibujado: un rectángulo con sus líneas, como el SVG de la web.
class _ChipPainter extends CustomPainter {
  _ChipPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 20
      ..color = color;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.width / 8),
    );
    canvas.drawRRect(rect, stroke);
    final lines = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 26
      ..color = color.withValues(alpha: 0.6);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), lines);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), lines);
    canvas.drawLine(Offset(size.width * 0.38, 0), Offset(size.width * 0.38, size.height), lines);
    canvas.drawLine(Offset(size.width * 0.62, 0), Offset(size.width * 0.62, size.height), lines);
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.color != color;
}
