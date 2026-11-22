import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'rin_motion.dart';
import 'rin_path.dart';

/// Colores del Rin elegido (`COLORS` de `lib/rinLook.js`). Por ahora solo el violeta de la marca;
/// sombreros, franjas con dibujo y gafas llegarán aquí cuando se porte el personalizador.
class RinLook {
  const RinLook({
    required this.body,
    required this.light,
    required this.dark,
    required this.band,
    required this.cheek,
    this.shadow = const Color(0x2616141F),
  });

  final Color body, light, dark, band, cheek;

  /// Sombra del suelo: `ink` al 15 %. En la web cambia con el tema; aquí es la del tema claro.
  final Color shadow;

  static const violeta = RinLook(
    body: Color(0xFF7B5CFF),
    light: Color(0xFFAB95FF),
    dark: Color(0xFF5A3EE6),
    band: Color(0xFF5FE3B6),
    cheek: Color(0xFF5FE3B6),
  );
}

// Colores fijos para todos los looks (`Rin.jsx`).
const _ink = Color(0xFF1C1630);
const _mouthColor = Color(0xFF3A1A4F);
const _tongue = Color(0xFFFF7AA8);
const _billTop = Color(0xFF8FF0CF);
const _billSide = Color(0xFF3FCF9F);
const _billLine = Color(0xFF22B386);
const _stem = Color(0xFF1F7A5C);
const _dollar = Color(0xFF17805C);
const _white = Color(0xFFFFFFFF);
const _amber = Color(0xFFFFB900); // stroke-amber-400 de las chispas

// Trazos literales de `Rin.jsx`.
final _body = parseSvgPath(
  'M0 -128C33 -128 49 -99 52 -60C55 -22 43 -6 0 -6C-43 -6 -55 -22 -52 -60C-49 -99 -33 -128 0 -128Z',
);
final _arm = parseSvgPath('M-8.5 0C-8.5 -6 8.5 -6 8.5 0L7.5 19C7.5 30 -7.5 30 -7.5 19Z');
final _armShade = parseSvgPath('M-7.5 17C-7.5 30 7.5 30 7.5 17C5 24 -5 24 -7.5 17Z');
final _stalk = parseSvgPath('M0 2C-1 -8 6 -14 13 -17');
final _band = parseSvgPath('M-60 -50Q0 -38 60 -50V-37Q0 -25 -60 -37Z');
final _eyeJoy = parseSvgPath('M-8.5 3Q0 -8.5 8.5 3');
final _eyeShut = parseSvgPath('M-8.5 -1Q0 6 8.5 -1');
final _brow = parseSvgPath('M-6 0Q0 -2.6 6 0');
final _smile = parseSvgPath('M-8 -2Q0 6 8 -2');
final _grin = parseSvgPath('M-12 -5Q0 -8 12 -5Q10 12 0 12Q-10 12 -12 -5Z');
final _grinTongue = parseSvgPath('M-6.5 7.5Q0 2.5 6.5 7.5Q4 11.4 0 11.4Q-4 11.4 -6.5 7.5Z');
final _flat = parseSvgPath('M-5 1L6 0');
final _soft = parseSvgPath('M-6 1.5Q0 -0.6 6 1.5');
final _wobble = parseSvgPath('M-10 -1Q-5 5 0 1Q5 5 10 -1');
final _sparks = [
  for (final d in const ['M0 0L10 -9', 'M5 9L19 5', 'M4 20L16 24']) parseSvgPath(d),
];

/// Caja ajustada de la silueta: el degradado del cuerpo usa `objectBoundingBox` (default de SVG).
const _bodyBox = Rect.fromLTRB(-52.435, -128, 52.435, -6);

double _rad(double degrees) => degrees * math.pi / 180;

Paint _fill(Color c, [double opacity = 1]) => Paint()..color = c.withValues(alpha: c.a * opacity);

Paint _line(Color c, double width) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Dibuja a Rin con la geometría de `Rin.jsx` (mismas coordenadas del viewBox).
class RinPainter extends CustomPainter {
  RinPainter({required this.frame, this.compact = false, this.look = RinLook.violeta});

  /// `viewBox` del SVG original: con pila y solo Rin (`compact`).
  static const viewBox = Rect.fromLTWH(0, -14, 200, 290);
  static const compactViewBox = Rect.fromLTWH(14, 84, 172, 194);

  final RinFrame frame;
  final bool compact;
  final RinLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final box = compact ? compactViewBox : viewBox;
    // preserveAspectRatio por defecto: xMidYMid meet. Sin recorte: el SVG usa overflow visible.
    final scale = math.min(size.width / box.width, size.height / box.height);
    canvas.save();
    canvas.translate((size.width - box.width * scale) / 2, (size.height - box.height * scale) / 2);
    canvas.scale(scale);
    canvas.translate(-box.left, -box.top);
    _paintRin(canvas);
    canvas.restore();
  }

  /// Opacidad de un `<g>`: se compone el grupo entero, no cada figura (como en SVG).
  void _group(Canvas canvas, double opacity, VoidCallback draw) {
    if (opacity <= 0) return;
    if (opacity >= 1) return draw();
    canvas.saveLayer(null, Paint()..color = _white.withValues(alpha: opacity));
    draw();
    canvas.restore();
  }

  void _text(Canvas canvas, String text, double size, Color color, Offset baseline, {bool center = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Inter Tight',
          fontSize: size,
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final ascent = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(canvas, baseline - Offset(center ? painter.width / 2 : 0, ascent));
    painter.dispose();
  }

  void _paintRin(Canvas canvas) {
    final p = frame.pose;

    // Sombra en el suelo.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, rinGround + 3), width: 128, height: 12),
      _fill(look.shadow),
    );

    // Pila de billetes: el progreso.
    if (!compact) {
      for (var i = 0; i < rinCrooked.length; i++) {
        _group(canvas, p.billOpacity(i), () {
          canvas.save();
          canvas.translate(100 + p.billX(i), rinGround - (i + 1) * rinBillHeight);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-66, 1, 132, rinBillHeight),
              const Radius.circular(5.5),
            ),
            _fill(_billSide),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-66, 0, 132, rinBillHeight - 3.5),
              const Radius.circular(5),
            ),
            _fill(_billTop),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(-22, 2.6, 44, 3), const Radius.circular(1.5)),
            _fill(_billLine, 0.55),
          );
          canvas.restore();
        });
      }
    }

    // .rin-rise > .rin-act > .rin-breath > .rin-tilt
    canvas.save();
    canvas.translate(100, p[RinChannel.rise]);
    canvas.translate(0, frame.actY);
    canvas.scale(frame.actSX, frame.actSY);
    canvas.scale(frame.breathX, frame.breathY);
    canvas.rotate(_rad(p[RinChannel.tilt]));

    // Pies redondos.
    for (final x in const [-22.0, 22.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, -3.5), width: 32, height: 19), _fill(look.dark));
    }

    // Antena corta con la moneda.
    canvas.save();
    canvas.translate(4, -126);
    canvas.rotate(_rad(p[RinChannel.ant]));
    canvas.rotate(_rad(frame.sway));
    canvas.drawPath(_stalk, _line(_stem, 3.6));
    canvas.translate(20, -27);
    // .rin-coin: la moneda al aire de celebrar.
    canvas.translate(0, frame.coinY);
    canvas.scale(frame.coinSX, frame.coinSY);
    canvas.drawCircle(Offset.zero, 14, _fill(_billLine));
    canvas.drawCircle(Offset.zero, 11.4, _fill(_billTop));
    _text(canvas, r'$', 17, _dollar, const Offset(0, 6), center: true);
    canvas.restore();

    // Chispas de la moneda: cada rayita crece desde el origen del grupo, como en el SVG.
    canvas.save();
    canvas.translate(62, -112);
    for (var n = 0; n < frame.sparks.length && n < _sparks.length; n++) {
      final (opacity, scale) = frame.sparks[n];
      if (opacity <= 0) continue;
      canvas.save();
      canvas.scale(scale);
      canvas.drawPath(_sparks[n], _line(_amber.withValues(alpha: opacity.clamp(0.0, 1.0)), 4));
      canvas.restore();
    }
    canvas.restore();

    // Cuerpo blandito: luz arriba a la izquierda, sombra abajo, y la franja.
    canvas.drawPath(
      _body,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(0.34, 0.24),
          0.95,
          [look.light, look.body, look.dark],
          const [0, 0.5, 1],
          TileMode.clamp,
          // Del cuadro unitario a la caja de la silueta (columnas de una Matrix4).
          Float64List.fromList([
            _bodyBox.width, 0, 0, 0, //
            0, _bodyBox.height, 0, 0, //
            0, 0, 1, 0, //
            _bodyBox.left, _bodyBox.top, 0, 1,
          ]),
        ),
    );
    canvas.save();
    canvas.clipPath(_body);
    canvas.drawPath(_band, _fill(look.band));
    canvas.translate(-22, -102);
    canvas.rotate(_rad(24));
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 34, height: 48), _fill(_white, 0.14));
    canvas.restore();

    // Zzz al dormir.
    final zzz = p[RinChannel.zzzO] * frame.zzzOpacity;
    if (zzz > 0) {
      canvas.save();
      canvas.translate(50 + frame.zzzX, -124 + frame.zzzY);
      canvas.scale(frame.zzzScale);
      _group(canvas, zzz, () {
        _text(canvas, 'z', 16, _white, Offset.zero);
        _text(canvas, 'z', 12, _white, const Offset(12, -13));
      });
      canvas.restore();
    }

    // Mejillas menta.
    for (final x in const [-37.0, 37.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, -71), width: 17, height: 10.4),
        _fill(look.cheek, p[RinChannel.blush].clamp(0.0, 1.0)),
      );
    }

    // Ojos negros con un brillo; mirada (.rin-pupil) + vistazo en reposo (.rin-glance).
    canvas.save();
    canvas.translate(p[RinChannel.lookX] + frame.glanceX, p[RinChannel.lookY] + frame.glanceY);
    for (final x in const [-19.0, 19.0]) {
      canvas.save();
      canvas.translate(x, -88);
      canvas.scale(p[RinChannel.eye]);
      _group(canvas, p[RinChannel.openO], () {
        canvas.save();
        canvas.scale(1, p[RinChannel.openS] * frame.blink);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 18.4, height: 21.2), _fill(_ink));
        canvas.drawCircle(const Offset(3.2, -3.8), 3.3, _fill(_white));
        final wet = p[RinChannel.wetO];
        if (wet > 0) canvas.drawCircle(const Offset(-3, 4.2), 1.5, _fill(_white, wet));
        canvas.restore();
      });
      for (final (path, opacity, scale) in [
        (_eyeJoy, RinChannel.joyO, RinChannel.joyS),
        (_eyeShut, RinChannel.shutO, RinChannel.shutS),
      ]) {
        _group(canvas, p[opacity], () {
          canvas.save();
          canvas.scale(1, p[scale]);
          canvas.drawPath(path, _line(_ink, 3.6));
          canvas.restore();
        });
      }
      canvas.restore();
    }
    canvas.restore();

    // Cejas discretas.
    for (final (x, opacity, y, turn) in const [
      (-19.0, RinChannel.browLO, RinChannel.browLY, RinChannel.browLR),
      (19.0, RinChannel.browRO, RinChannel.browRY, RinChannel.browRR),
    ]) {
      canvas.save();
      canvas.translate(x, -105 + p[y]);
      canvas.rotate(_rad(p[turn]));
      _group(canvas, p[opacity], () => canvas.drawPath(_brow, _line(_ink, 3)));
      canvas.restore();
    }

    // Boca flexible: todas existen y solo se ve la de la emoción.
    canvas.save();
    canvas.translate(0, -70);
    for (final m in RinMouth.values) {
      canvas.save();
      canvas.translate(p.mouth(m, 2), 0);
      canvas.scale(p.mouth(m, 1));
      _group(canvas, p.mouth(m, 0), () => _paintMouth(canvas, m));
      canvas.restore();
    }
    canvas.restore();

    // Brazos cortos: giran desde el hombro.
    for (final (x, angle, wave) in [
      (-48.0, p[RinChannel.armL], frame.waveL),
      (48.0, p[RinChannel.armR], frame.waveR),
    ]) {
      canvas.save();
      canvas.translate(x, -64);
      canvas.rotate(_rad(angle + wave));
      canvas.drawPath(_arm, _fill(look.body));
      canvas.drawPath(_armShade, _fill(look.dark, 0.45));
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintMouth(Canvas canvas, RinMouth m) {
    final stroke = _line(_mouthColor, 3.4);
    switch (m) {
      case RinMouth.smile:
        canvas.drawPath(_smile, stroke);
      case RinMouth.grin:
        canvas.drawPath(_grin, _fill(_mouthColor));
        canvas.drawPath(_grin, _line(_mouthColor, 1.6));
        canvas.drawPath(_grinTongue, _fill(_tongue));
      case RinMouth.o:
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, 1), width: 9.2, height: 11.6),
          _fill(_mouthColor),
        );
      case RinMouth.flat:
        canvas.drawPath(_flat, stroke);
      case RinMouth.soft:
        canvas.drawPath(_soft, stroke);
      case RinMouth.wobble:
        canvas.drawPath(_wobble, stroke);
    }
  }

  @override
  bool shouldRepaint(RinPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.compact != compact || oldDelegate.look != look;
}
