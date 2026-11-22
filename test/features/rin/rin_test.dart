import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/rin/rin.dart';
import 'package:rinde_mobile/features/rin/rin_motion.dart';
import 'package:rinde_mobile/features/rin/rin_painter.dart';
import 'package:rinde_mobile/features/rin/rin_path.dart';

/// Rin dentro de un ancho fijo, con o sin movimiento reducido del sistema.
Widget _host(Widget rin, {double width = 120, bool still = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: still),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(width: width, child: rin),
    ),
  ),
);

/// El fotograma que Rin está pintando ahora.
RinFrame _frame(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(Rin), matching: find.byType(CustomPaint)),
  );
  return (paint.painter! as RinPainter).frame;
}

/// Si algún valor de gesto se sale del reposo.
bool _moving(RinFrame f) {
  bool off(double value, double rest) => (value - rest).abs() > 1e-9;
  return off(f.actY, 0) ||
      off(f.actSX, 1) ||
      off(f.actSY, 1) ||
      off(f.coinY, 0) ||
      off(f.coinSX, 1) ||
      off(f.coinSY, 1) ||
      off(f.waveL, 0) ||
      off(f.waveR, 0) ||
      f.sparks.any((s) => off(s.$1, 0));
}

void _expectPose(RinFrame frame, RinPose pose) {
  for (final c in RinChannel.values) {
    expect(frame.pose[c], closeTo(pose[c], 1e-6), reason: c.name);
  }
}

const _newGestures = [RinGesture.celebrar, RinGesture.asentir, RinGesture.toque];

void main() {
  group('Gestos', () {
    for (final gesture in _newGestures) {
      testWidgets('${gesture.name} se mueve, termina y deja la postura de la emoción', (tester) async {
        await tester.pumpWidget(_host(const Rin(emotion: RinEmotion.feliz, level: 3)));
        await tester.pumpWidget(_host(Rin(emotion: RinEmotion.feliz, level: 3, gesture: gesture)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_moving(_frame(tester)), isTrue);

        await tester.pump(gesture.duration);
        await tester.pump(RinPose.transition);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final frame = _frame(tester);
        expect(_moving(frame), isFalse);
        expect(frame.sparks, isEmpty);
        _expectPose(frame, RinPose.target(emotion: RinEmotion.feliz, level: 3));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('con movimiento reducido no anima ningún gesto', (tester) async {
      for (final gesture in [..._newGestures, RinGesture.saludar]) {
        await tester.pumpWidget(_host(Rin(gesture: gesture, gestureKey: 1), still: true));
        await tester.pumpWidget(_host(Rin(gesture: gesture, gestureKey: 2), still: true));
        await tester.pumpAndSettle();
        expect(tester.hasRunningAnimations, isFalse);
        expect(_moving(_frame(tester)), isFalse);
        _expectPose(_frame(tester), RinPose.target());
      }
    });

    testWidgets('gestureKey repite el mismo gesto; reconstruir con la misma clave no', (tester) async {
      await tester.pumpWidget(_host(const Rin(gesture: RinGesture.toque, gestureKey: 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_moving(_frame(tester)), isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_moving(_frame(tester)), isFalse);

      await tester.pumpWidget(_host(const Rin(gesture: RinGesture.toque, gestureKey: 0)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_moving(_frame(tester)), isFalse);

      await tester.pumpWidget(_host(const Rin(gesture: RinGesture.toque, gestureKey: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_moving(_frame(tester)), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('RinFrame.alive', () {
    // Cubic resuelve la curva con un margen de 0.001; justo antes de un porcentaje no da exacto.
    final pose = RinPose.target();
    RinFrame at(RinGesture gesture, double seconds) =>
        RinFrame.alive(pose, 0, RinEmotion.tranquilo, gesture: gesture, at: seconds);

    test('celebrar sigue los porcentajes de rin-cheer, rin-toss, rin-shake y rin-twinkle', () {
      // rin-cheer 1.5 s: 26 % translateY(-30px) scale(0.95, 1.07).
      final jump = at(RinGesture.celebrar, 0.26 * 1.5);
      expect(jump.actY, closeTo(-30, 1e-3));
      expect(jump.actSX, closeTo(0.95, 1e-3));
      expect(jump.actSY, closeTo(1.07, 1e-3));
      // rin-toss 1.5 s: 24 % scaleX(-1) a -22 px y 38 % arriba del todo, a -36 px.
      expect(at(RinGesture.celebrar, 0.24 * 1.5).coinSX, closeTo(-1, 1e-3));
      expect(at(RinGesture.celebrar, 0.38 * 1.5).coinY, closeTo(-36, 1e-3));
      // 76 % scale(1.18, 0.86): la moneda aterriza aplastada.
      final land = at(RinGesture.celebrar, 0.76 * 1.5);
      expect(land.coinSX, closeTo(1.18, 1e-3));
      expect(land.coinSY, closeTo(0.86, 1e-3));
      // rin-shake 0.5 s, retardo 0.2 s, dos veces, en ambos brazos.
      expect(at(RinGesture.celebrar, 0.1).waveL, 0);
      final shake = at(RinGesture.celebrar, 0.2 + 0.25 * 0.5);
      expect(shake.waveL, closeTo(-14, 1e-3));
      expect(shake.waveR, closeTo(-14, 1e-3));
      expect(at(RinGesture.celebrar, 0.2 + 0.5 + 0.75 * 0.5).waveR, closeTo(14, 1e-3));
      expect(at(RinGesture.celebrar, 1.25).waveR, 0);
      // rin-twinkle 0.9 s, retardo 0.25 s + n × 0.13 s, dos veces.
      final sparks = at(RinGesture.celebrar, 0.38 + 0.45).sparks;
      expect(sparks, hasLength(3));
      expect(sparks[1].$1, closeTo(1, 1e-3));
      expect(sparks[1].$2, closeTo(1, 1e-3));
      expect(at(RinGesture.celebrar, 0.2).sparks.every((s) => s.$1 == 0), isTrue);
      expect(at(RinGesture.celebrar, 0.51 + 0.9 + 0.45).sparks[2].$1, closeTo(1, 1e-3));
      // Al terminar todo vuelve al reposo.
      expect(_moving(at(RinGesture.celebrar, 2.32)), isFalse);
    });

    test('asentir y toque siguen rin-nod y rin-tap', () {
      final nod = at(RinGesture.asentir, 0.25 * 0.8);
      expect(nod.actSX, closeTo(1.03, 1e-3));
      expect(nod.actSY, closeTo(0.94, 1e-3));
      expect(_moving(at(RinGesture.asentir, 0.5 * 0.8)), isFalse); // 50 %: none
      expect(at(RinGesture.asentir, 0.75 * 0.8).actSY, closeTo(0.96, 1e-3));

      final squash = at(RinGesture.toque, 0.3 * 0.6);
      expect(squash.actSX, closeTo(1.1, 1e-3));
      expect(squash.actSY, closeTo(0.88, 1e-3));
      final hop = at(RinGesture.toque, 0.6 * 0.6);
      expect(hop.actY, closeTo(-6, 1e-3));
      expect(hop.actSY, closeTo(1.08, 1e-3));
      expect(_moving(at(RinGesture.toque, 0.6)), isFalse);
    });

    test('duraciones hasta la última animación', () {
      expect(RinGesture.celebrar.duration, const Duration(milliseconds: 2310));
      expect(RinGesture.asentir.duration, const Duration(milliseconds: 800));
      expect(RinGesture.toque.duration, const Duration(milliseconds: 600));
      expect(RinGesture.saludar.duration, const Duration(milliseconds: 1560));
      expect(RinGesture.saltar.duration, isNull);
    });
  });

  group('Rin', () {
    for (final emotion in RinEmotion.values) {
      testWidgets('se dibuja pequeño y grande: ${emotion.name}', (tester) async {
        for (final width in [24.0, 400.0]) {
          for (final compact in [false, true]) {
            await tester.pumpWidget(
              _host(
                Rin(emotion: emotion, level: 4, tidy: 2, compact: compact),
                width: width,
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            final size = tester.getSize(find.byType(Rin));
            expect(size.width, width);
            expect(size.width / size.height, closeTo(compact ? 172 / 194 : 200 / 290, 0.01));
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('con movimiento reducido no deja animaciones pendientes', (tester) async {
      await tester.pumpWidget(_host(const Rin(gesture: RinGesture.saludar, level: 6), still: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(_host(const Rin(emotion: RinEmotion.dormido, level: 2), still: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('animate: false también lo deja quieto', (tester) async {
      await tester.pumpWidget(_host(const Rin(emotion: RinEmotion.feliz, animate: false)));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('saluda una vez y vuelve a reposo sin errores', (tester) async {
      await tester.pumpWidget(_host(const Rin()));
      await tester.pumpWidget(_host(const Rin(gesture: RinGesture.saludar)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      // El reposo sigue en bucle aunque el gesto ya terminó.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('expone la etiqueta para lector de pantalla', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(const Rin(semanticLabel: 'Rin está tranquilo', animate: false)));
      expect(find.bySemanticsLabel('Rin está tranquilo'), findsOneWidget);

      await tester.pumpWidget(_host(const Rin(animate: false)));
      expect(find.byType(ExcludeSemantics), findsOneWidget);
      semantics.dispose();
    });
  });

  group('RinPose', () {
    test('valores de rin.css', () {
      final calm = RinPose.target();
      expect(calm[RinChannel.armL], 16);
      expect(calm[RinChannel.armR], -16);
      expect(calm.mouth(RinMouth.smile, 0), 1);

      final wave = RinPose.target(emotion: RinEmotion.feliz, gesture: RinGesture.saludar, level: 3, tidy: 1);
      expect(wave[RinChannel.armR], -150);
      expect(wave[RinChannel.armL], 148);
      expect(wave[RinChannel.rise], 266 - 3 * 13);
      expect(wave.billX(0), 0); // acomodado
      expect(wave.billX(1), 5); // torcido
      expect(wave.billOpacity(3), 0);
    });

    test('la transición llega exacta a la meta', () {
      final from = RinPose.target();
      final to = RinPose.target(emotion: RinEmotion.pensativo);
      final end = RinPose.lerp(from, to, RinPose.transition.inMilliseconds.toDouble());
      for (final c in RinChannel.values) {
        expect(end[c], closeTo(to[c], 1e-9), reason: c.name);
      }
    });
  });

  group('parseSvgPath', () {
    test('M, L, H, V y Z absolutos', () {
      expect(parseSvgPath('M0 0L10 0V10H0Z').getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('comandos relativos', () {
      expect(parseSvgPath('m5 5l10 0v10h-10z').getBounds(), const Rect.fromLTRB(5, 5, 15, 15));
    });

    test('curvas Q y C', () {
      final q = parseSvgPath('M0 0Q10 20 20 0Z');
      expect(q.contains(const Offset(10, 5)), isTrue);
      expect(q.contains(const Offset(10, 15)), isFalse);

      final body = parseSvgPath(
        'M0 -128C33 -128 49 -99 52 -60C55 -22 43 -6 0 -6C-43 -6 -55 -22 -52 -60C-49 -99 -33 -128 0 -128Z',
      );
      expect(body.contains(const Offset(0, -60)), isTrue);
      expect(body.contains(const Offset(56, -60)), isFalse);
    });

    test('rechaza trazos dañados', () {
      expect(() => parseSvgPath('10 10'), throwsFormatException);
      expect(() => parseSvgPath('M10'), throwsFormatException);
    });
  });
}
