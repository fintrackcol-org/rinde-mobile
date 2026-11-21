import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/rin/rin.dart';
import 'package:rinde_mobile/features/rin/rin_motion.dart';
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

void main() {
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
