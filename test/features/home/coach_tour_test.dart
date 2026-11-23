import 'dart:convert';
import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/tokens/rinde_colors.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/home/presentation/tour/coach_tour.dart';
import 'package:rinde_mobile/features/home/presentation/tour/tour_steps.dart';
import 'package:rinde_mobile/features/home/presentation/tour_anchors.dart';

const _es = Tr('es', {});

const _titles = [
  'Esto es lo que te queda',
  'Anota en dos toques',
  'Ingresos y Gastos se tocan',
  'En qué gastas y cómo van tus topes',
  'Lo que viene, en Planear',
  '¿Quieres ver lo demás?',
  'Mi plata reúne lo demás',
  'Yo: tu cuenta',
];

/// Un Inicio de mentira con los cinco elementos que el tutorial resalta y el tutorial encima.
class _Home extends StatefulWidget {
  const _Home({
    required this.closes,
    required this.present,
    required this.totalesGap,
    required this.totalesHeight,
    required this.strip,
    required this.below,
  });

  final List<bool> closes;
  final Set<TourTarget> present;
  final double totalesGap;
  final double totalesHeight;

  /// Lo que ocupa arriba la franja DEMO: la lista empieza debajo.
  final double strip;

  /// Lo que le quita abajo a la lista el aviso de error.
  final double below;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final anchors = TourAnchors();
  bool open = true;
  double notice = 0;

  /// Algo del Inicio cambió: con [height], le salió un aviso encima del saldo.
  void refresh([double height = 0]) => setState(() => notice = height);

  Widget _box(TourTarget target, String label, {double? height}) => widget.present.contains(target)
      ? Container(
          key: anchors.key(target),
          height: height,
          decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(24)),
          child: Text(label),
        )
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(top: widget.strip, bottom: widget.below),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: notice),
                _box(TourTarget.saldo, 'SALDO', height: 160),
                SizedBox(height: widget.totalesGap),
                _box(TourTarget.totales, 'TOTALES', height: widget.totalesHeight),
                const SizedBox(height: 300),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          height: 64,
          child: Row(
            children: [
              const Spacer(flex: 2),
              Expanded(child: _box(TourTarget.anotar, 'ANOTAR')),
              Expanded(child: _box(TourTarget.planear, 'PLANEAR')),
              Expanded(child: _box(TourTarget.cuenta, 'YO')),
            ],
          ),
        ),
        if (open)
          Positioned.fill(
            child: CoachTour(
              anchors: anchors,
              onClose: (completed) {
                widget.closes.add(completed);
                setState(() => open = false);
              },
            ),
          ),
      ],
    ),
  );
}

/// Abre el tutorial y devuelve la lista donde queda cada cierre (`completed`).
Future<List<bool>> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool reduceMotion = false,
  ThemeData? theme,
  Tr tr = _es,
  Set<TourTarget>? present,
  double totalesGap = 16,
  double totalesHeight = 100,
  double strip = 0,
  double below = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final closes = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [trProvider.overrideWithValue(tr)],
      child: MaterialApp(
        theme: theme ?? RindeTheme.light,
        home: _Home(
          closes: closes,
          present: present ?? TourTarget.values.toSet(),
          totalesGap: totalesGap,
          totalesHeight: totalesHeight,
          strip: strip,
          below: below,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return closes;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _goTo(WidgetTester tester, int index) async {
  for (var i = 0; i < index; i++) {
    await _tap(tester, i == 5 ? 'Ver lo demás' : 'Siguiente');
  }
}

/// La tarjeta, por el título del paso que muestra.
Rect _card(WidgetTester tester, int index) =>
    tester.getRect(find.ancestor(of: find.text(_titles[index]), matching: find.byType(DecoratedBox)).first);

Rect _target(WidgetTester tester, TourTarget target) =>
    tester.getRect(find.byKey(tester.state<_HomeState>(find.byType(_Home)).anchors.key(target)));

/// El hueco, por el aro que se pinta alrededor: lo último que dibuja el fondo.
Rect _hole(WidgetTester tester) {
  final dim = find.descendant(
    of: find.byType(CoachTour),
    matching: find.byWidgetPredicate((w) => w is CustomPaint && w.size == Size.infinite),
  );
  final canvas = TestRecordingCanvas();
  tester.widget<CustomPaint>(dim).painter!.paint(canvas, tester.view.physicalSize);
  return (canvas.invocations.last.invocation.positionalArguments.first as RRect).outerRect.deflate(1);
}

/// Dónde le dice el lector que está un elemento, en coordenadas de la pantalla.
Rect _spoken(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform case final transform?) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

/// Los puntos de avance: (ancho, color).
List<(double, Color?)> _dots(WidgetTester tester) => [
  for (final c in tester.widgetList<Container>(
    find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 6),
  ))
    (c.constraints!.maxWidth, (c.decoration! as BoxDecoration).color),
];

void main() {
  test('los 8 pasos de la web, en su orden, con sus tramos y lo que resaltan', () {
    final steps = coachSteps(_es);
    expect([for (final s in steps) s.title], _titles);
    expect(
      [for (final s in steps) s.section],
      [...List.filled(5, TourSection.corto), TourSection.pregunta, TourSection.largo, TourSection.largo],
    );
    expect(
      [for (final s in steps) s.target],
      [
        TourTarget.saldo,
        TourTarget.anotar,
        TourTarget.totales,
        // «graficos» no existe en el Inicio de celular.
        null,
        TourTarget.planear,
        null,
        TourTarget.saldo,
        TourTarget.cuenta,
      ],
    );
    expect(steps[1].text, contains('«taxi 9 mil»'));
    expect(steps.every((s) => s.text.isNotEmpty), isTrue);
  });

  group('recorrido', () {
    testWidgets('de principio a fin: rótulos, puntos, la pregunta y Listo', (tester) async {
      final closes = await _pump(tester);
      final p = RindePalette.light;

      for (var i = 0; i < 5; i++) {
        expect(find.text(_titles[i]), findsOneWidget);
        expect(find.text('PASO ${i + 1} DE 5'), findsOneWidget);
        expect(find.bySemanticsLabel('Paso ${i + 1} de 5'), findsOneWidget);
        expect(find.text('Omitir'), findsOneWidget);
        expect(find.text('Atrás'), i == 0 ? findsNothing : findsOneWidget);
        // El punto del paso actual es el ancho; los ya vistos quedan pintados.
        expect(_dots(tester), [
          for (var k = 0; k < 5; k++) (k == i ? 18.0 : 6.0, k <= i ? p.brand : p.lineStrong),
        ]);
        await _tap(tester, 'Siguiente');
      }

      // La pregunta: sin rótulo, sin puntos y con sus dos botones.
      expect(find.text(_titles[5]), findsOneWidget);
      expect(find.textContaining('PASO'), findsNothing);
      expect(_dots(tester), isEmpty);
      expect(find.text('Siguiente'), findsNothing);
      expect(find.text('Atrás'), findsNothing);
      expect(find.text('Ya entendí'), findsOneWidget);
      expect(find.text('Omitir'), findsOneWidget);
      await _tap(tester, 'Ver lo demás');

      expect(find.text(_titles[6]), findsOneWidget);
      expect(find.text('LO DEMÁS · 1 DE 2'), findsOneWidget);
      expect(_dots(tester), [(18.0, RindeBrand.success), (6.0, p.lineStrong)]);
      await _tap(tester, 'Siguiente');

      expect(find.text(_titles[7]), findsOneWidget);
      expect(find.text('LO DEMÁS · 2 DE 2'), findsOneWidget);
      expect(find.text('Siguiente'), findsNothing);
      expect(closes, isEmpty);
      await _tap(tester, 'Listo');

      expect(closes, [true]);
      expect(find.byType(CoachTour), findsNothing);
    });

    testWidgets('Atrás devuelve un paso; desde el primero del largo vuelve a la pregunta', (tester) async {
      final closes = await _pump(tester);
      await _tap(tester, 'Siguiente');
      expect(find.text(_titles[1]), findsOneWidget);
      await _tap(tester, 'Atrás');
      expect(find.text(_titles[0]), findsOneWidget);
      expect(find.text('PASO 1 DE 5'), findsOneWidget);

      await _goTo(tester, 6);
      expect(find.text(_titles[6]), findsOneWidget);
      await _tap(tester, 'Atrás');
      expect(find.text(_titles[5]), findsOneWidget);
      expect(closes, isEmpty);
    });

    testWidgets('Omitir cierra sin completar, desde cualquier paso', (tester) async {
      var closes = await _pump(tester);
      await _tap(tester, 'Omitir');
      expect(closes, [false]);
      expect(find.byType(CoachTour), findsNothing);

      await tester.pumpWidget(const SizedBox());
      closes = await _pump(tester);
      await _goTo(tester, 5);
      await _tap(tester, 'Omitir');
      expect(closes, [false]);
    });

    testWidgets('«Ya entendí» en la pregunta lo da por completado', (tester) async {
      final closes = await _pump(tester);
      await _goTo(tester, 5);
      await _tap(tester, 'Ya entendí');
      expect(closes, [true]);
    });

    testWidgets('tocar el fondo lo cierra sin completar, también sobre lo resaltado', (tester) async {
      var closes = await _pump(tester);
      // Tocar la tarjeta no es tocar el fondo.
      await _tap(tester, _titles[0]);
      expect(closes, isEmpty);
      await tester.tapAt(const Offset(4, 400));
      await tester.pumpAndSettle();
      expect(closes, [false]);

      await tester.pumpWidget(const SizedBox());
      closes = await _pump(tester);
      await tester.tapAt(_target(tester, TourTarget.saldo).center);
      await tester.pumpAndSettle();
      expect(closes, [false]);
    });

    testWidgets('el «atrás» del sistema lo cierra sin completar y no saca de la pantalla', (tester) async {
      final closes = await _pump(tester);
      await _tap(tester, 'Siguiente');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(closes, [false]);
      expect(find.byType(CoachTour), findsNothing);
      expect(find.text('SALDO'), findsOneWidget);
    });
  });

  group('dónde va la tarjeta', () {
    const screen = Size(390, 844);
    const card = Size(360, 200);

    test('debajo del hueco si cabe', () {
      final at = placeCoachCard(
        screen: screen,
        card: card,
        hole: const Rect.fromLTWH(10, 100, 370, 160),
        safe: EdgeInsets.zero,
      );
      expect(at, const Offset(15, 272));
    });

    test('encima si debajo no cabe', () {
      final at = placeCoachCard(
        screen: screen,
        card: card,
        hole: const Rect.fromLTWH(160, 760, 70, 70),
        safe: EdgeInsets.zero,
      );
      expect(at, const Offset(15, 760 - 12 - 200));
    });

    test('pegada abajo si no cabe ni debajo ni encima', () {
      final at = placeCoachCard(
        screen: screen,
        card: card,
        hole: const Rect.fromLTWH(10, 100, 370, 700),
        safe: EdgeInsets.zero,
      );
      expect(at.dy, 844 - 12 - 200);
    });

    test('sin hueco, en el centro', () {
      final at = placeCoachCard(screen: screen, card: card, hole: null, safe: EdgeInsets.zero);
      expect(at, const Offset(15, 322));
    });

    test('sigue al hueco a los lados sin salirse de la pantalla', () {
      Offset at(double left) => placeCoachCard(
        screen: const Size(800, 844),
        card: card,
        hole: Rect.fromLTWH(left, 100, 60, 60),
        safe: EdgeInsets.zero,
      );
      expect(at(0).dx, 12);
      expect(at(370).dx, 220);
      expect(at(740).dx, 800 - 12 - 360);
    });

    test('nunca bajo la barra de estado ni la de navegación', () {
      const safe = EdgeInsets.only(top: 48, bottom: 34);
      // Encima quedaría bajo la barra de estado: se pega abajo, sobre la de navegación.
      var at = placeCoachCard(
        screen: screen,
        card: card,
        hole: const Rect.fromLTWH(10, 250, 370, 500),
        safe: safe,
      );
      expect(at.dy, 844 - 34 - 12 - 200);
      // Una tarjeta más alta que el espacio libre empieza bajo la barra de estado.
      at = placeCoachCard(screen: screen, card: const Size(360, 900), hole: null, safe: safe);
      expect(at.dy, 48 + 12);
      expect(coachCardWidth(const Size(320, 568), EdgeInsets.zero), 296);
      expect(coachCardWidth(screen, EdgeInsets.zero), 360);
      expect(coachCardWidth(const Size(390, 844), const EdgeInsets.symmetric(horizontal: 20)), 326);
    });

    testWidgets('debajo de lo de arriba, encima de la barra y en el centro si no hay qué resaltar', (
      tester,
    ) async {
      await _pump(tester);
      // Paso 1: el saldo está arriba.
      expect(_card(tester, 0).top, _target(tester, TourTarget.saldo).bottom + 6 + 12);
      expect(_card(tester, 0).width, 360);

      // Paso 2: Anotar está en la barra de abajo.
      await _tap(tester, 'Siguiente');
      expect(_card(tester, 1).bottom, _target(tester, TourTarget.anotar).top - 6 - 12);

      // Paso 4: los gráficos no existen en celular.
      await _goTo(tester, 2);
      expect(_card(tester, 3).center.dy, moreOrLessEquals(422, epsilon: 0.5));
      expect(_card(tester, 3).center.dx, 195);

      // Paso 5: Planear, a la derecha de la barra; la tarjeta no se sale.
      await _tap(tester, 'Siguiente');
      final plan = _card(tester, 4);
      expect(plan.bottom, _target(tester, TourTarget.planear).top - 6 - 12);
      expect(plan.right, lessThanOrEqualTo(390 - 12));
    });

    testWidgets('si lo que se explica no está en pantalla, el paso sale en el centro', (tester) async {
      await _pump(tester, present: {TourTarget.anotar});
      expect(_card(tester, 0).center.dy, moreOrLessEquals(422, epsilon: 0.5));
      await _tap(tester, 'Siguiente');
      expect(_card(tester, 1).bottom, _target(tester, TourTarget.anotar).top - 6 - 12);
    });

    testWidgets('trae a la vista lo que quedó más abajo antes de resaltarlo', (tester) async {
      await _pump(tester, totalesGap: 1200);
      expect(_target(tester, TourTarget.totales).top, greaterThan(844));

      await _goTo(tester, 2);
      final totales = _target(tester, TourTarget.totales);
      expect(totales.top, greaterThanOrEqualTo(0));
      expect(totales.bottom, lessThanOrEqualTo(844));
      // Medido después de desplazar: la tarjeta queda pegada a donde está ahora (quedó centrado, y
      // la tarjeta va encima porque debajo ya no cabe).
      expect(_card(tester, 2).bottom, totales.top - 6 - 12);

      // Y de vuelta arriba al devolverse al saldo.
      await _tap(tester, 'Atrás');
      await _tap(tester, 'Atrás');
      final saldo = _target(tester, TourTarget.saldo);
      expect(saldo.top, greaterThanOrEqualTo(0));
      expect(_card(tester, 0).top, saldo.bottom + 6 + 12);
    });

    testWidgets('lo que tapa la barra flotante se trae arriba de ella', (tester) async {
      // Cabe en la pantalla, pero su parte de abajo queda detrás de la barra (104 desde abajo).
      await _pump(tester, totalesGap: 480);
      expect(_target(tester, TourTarget.totales).bottom, inExclusiveRange(844 - 104, 844));

      await _goTo(tester, 2);
      final totales = _target(tester, TourTarget.totales);
      expect(totales.bottom, lessThanOrEqualTo(844 - 104));
      expect(_hole(tester), totales.inflate(6));
    });

    testWidgets('con el aviso de error la lista ya termina arriba: la barra no se resta otra vez', (
      tester,
    ) async {
      await _pump(tester, totalesGap: 300, below: 200);
      final before = _target(tester, TourTarget.totales);

      await _goTo(tester, 2);
      expect(_target(tester, TourTarget.totales), before);
      expect(_hole(tester), before.inflate(6));
    });

    testWidgets('lo que no cabe se recorta entre la franja DEMO y la barra', (tester) async {
      await _pump(tester, strip: 56, totalesHeight: 1000);
      await _goTo(tester, 2);
      expect(_hole(tester).top, 56);
      expect(_hole(tester).bottom, 844 - 104);
    });

    testWidgets('lo que quedó detrás de la franja DEMO baja antes de resaltarlo', (tester) async {
      await _pump(tester, strip: 56, totalesGap: 1200);
      Scrollable.of(tester.element(find.text('SALDO'))).position.jumpTo(60);
      tester.state<_HomeState>(find.byType(_Home)).refresh();
      await tester.pumpAndSettle();

      final saldo = _target(tester, TourTarget.saldo);
      expect(saldo.top, greaterThanOrEqualTo(56));
      expect(_hole(tester), saldo.inflate(6));
    });

    testWidgets('si el Inicio cambia debajo, lo resaltado lo sigue', (tester) async {
      await _pump(tester);
      final before = _target(tester, TourTarget.saldo);
      tester.state<_HomeState>(find.byType(_Home)).refresh(52);
      await tester.pumpAndSettle();

      final saldo = _target(tester, TourTarget.saldo);
      expect(saldo.top, before.top + 52);
      expect(_hole(tester), saldo.inflate(6));
      expect(_card(tester, 0).top, saldo.bottom + 6 + 12);
    });

    testWidgets('al girar la pantalla se vuelve a medir', (tester) async {
      await _pump(tester);
      await _tap(tester, 'Siguiente');
      tester.view.physicalSize = const Size(844, 700);
      await tester.pumpAndSettle();

      final anotar = _target(tester, TourTarget.anotar);
      final card = _card(tester, 1);
      expect(card.bottom, anotar.top - 6 - 12);
      expect(card.center.dx, moreOrLessEquals(anotar.center.dx, epsilon: 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('accesibilidad', () {
    testWidgets('es un diálogo con nombre y lo de atrás no existe para el lector', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      List<String> read() => [for (final n in tester.semantics.simulatedAccessibilityTraversal()) n.label];
      var labels = read();
      expect(labels.join('|'), isNot(contains('SALDO')));
      expect(labels.join('|'), isNot(contains('PLANEAR')));
      expect(labels, contains('Paso 1 de 5'));
      expect(labels.any((l) => l.startsWith(_titles[0])), isTrue);
      expect(labels, containsAll(['Omitir', 'Siguiente', 'Cerrar el tutorial']));

      final body = tester.getSemantics(find.text(_titles[0]));
      expect(body.flagsCollection.namesRoute, isTrue);
      expect(body.label, startsWith(_titles[0]));
      SemanticsNode? scope = body;
      while (scope != null && !scope.flagsCollection.scopesRoute) {
        scope = scope.parent;
      }
      expect(scope, isNotNull, reason: 'la tarjeta abre una ruta para el lector');

      // Al cerrar, el Inicio vuelve a leerse.
      await _tap(tester, 'Omitir');
      labels = read();
      expect(labels.join('|'), contains('SALDO'));
      handle.dispose();
    });

    for (final reduceMotion in [false, true]) {
      testWidgets('el lector ubica los botones donde se ven en cada paso (sin animar: $reduceMotion)', (
        tester,
      ) async {
        await _pump(tester, size: const Size(360, 640), reduceMotion: reduceMotion);
        for (var i = 0; i < 5; i++) {
          final button = find.text('Siguiente');
          final (heard, seen) = (_spoken(tester, button), tester.getRect(button));
          expect(heard.center.dy, moreOrLessEquals(seen.center.dy, epsilon: 2), reason: 'paso ${i + 1}');
          expect(heard.center.dx, moreOrLessEquals(seen.center.dx, epsilon: 2), reason: 'paso ${i + 1}');
          await _tap(tester, 'Siguiente');
        }
      });
    }

    testWidgets('el foco entra a la tarjeta al abrir y en cada paso', (tester) async {
      await _pump(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tutorial');
      for (var i = 0; i < 7; i++) {
        await _tap(tester, i == 5 ? 'Ver lo demás' : 'Siguiente');
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tutorial', reason: 'paso ${i + 2}');
      }
    });

    testWidgets('todos los botones miden al menos 48 de alto', (tester) async {
      await _pump(tester);
      for (var i = 0; i < 8; i++) {
        final buttons = tester.widgetList<RindeButton>(find.byType(RindeButton)).toList();
        expect(buttons, isNotEmpty);
        for (final button in buttons) {
          expect(
            tester.getSize(find.byWidget(button)).height,
            greaterThanOrEqualTo(48),
            reason: '${button.label}, paso ${i + 1}',
          );
        }
        if (i < 7) await _tap(tester, i == 5 ? 'Ver lo demás' : 'Siguiente');
      }
    });

    for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
      testWidgets('320x568 con letra al doble, tema $name: nada se desborda y todo se alcanza', (
        tester,
      ) async {
        final closes = await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
        for (var i = 0; i < 8; i++) {
          expect(tester.takeException(), isNull, reason: 'paso ${i + 1}');
          final card = _card(tester, i);
          expect(card.width, 296);
          expect(card.top, greaterThanOrEqualTo(12), reason: 'paso ${i + 1}');
          expect(card.bottom, lessThanOrEqualTo(568 - 12), reason: 'paso ${i + 1}');
          // Cada paso abre arriba, con Omitir a la mano; lo que no cabe se alcanza desplazando la tarjeta.
          expect(find.text('Omitir').hitTestable(), findsOneWidget, reason: 'paso ${i + 1}');
          final next = i == 5 ? 'Ver lo demás' : (i == 7 ? 'Listo' : 'Siguiente');
          await tester.ensureVisible(find.text(next));
          await tester.pumpAndSettle();
          expect(card.contains(tester.getRect(find.text(next)).bottomRight), isTrue, reason: 'paso ${i + 1}');
          await _tap(tester, next);
        }
        expect(tester.takeException(), isNull);
        expect(closes, [true]);
      });
    }

    testWidgets('tema oscuro: la tarjeta usa la superficie oscura', (tester) async {
      await _pump(tester, theme: RindeTheme.dark);
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text(_titles[0]), matching: find.byType(DecoratedBox)).first,
      );
      expect((box.decoration as BoxDecoration).color, RindePalette.dark.surface);
      expect(tester.widget<Text>(find.text(_titles[0])).style?.color, RindePalette.dark.ink);
    });
  });

  group('movimiento', () {
    testWidgets('entre pasos la tarjeta se desliza 240 ms', (tester) async {
      await _pump(tester);
      final from = _card(tester, 0);
      await tester.tap(find.text('Siguiente'));
      await tester.pump();
      // Empieza donde estaba la anterior.
      expect(_card(tester, 1).top, from.top);
      await tester.pump(const Duration(milliseconds: 120));
      final middle = _card(tester, 1).top;
      await tester.pump(const Duration(milliseconds: 120));
      final end = _card(tester, 1).top;
      expect(end, isNot(from.top));
      expect(middle, inExclusiveRange(from.top < end ? from.top : end, from.top < end ? end : from.top));
      await tester.pumpAndSettle();
      expect(_card(tester, 1).top, end);
    });

    testWidgets('con «reducir movimiento» cambia de una, sin animar', (tester) async {
      await _pump(tester, reduceMotion: true);
      final from = _card(tester, 0);
      await tester.tap(find.text('Siguiente'));
      await tester.pump();
      final first = _card(tester, 1);
      expect(first.top, isNot(from.top));
      await tester.pumpAndSettle();
      expect(_card(tester, 1), first);
    });
  });

  testWidgets('en inglés todo el tutorial sale traducido', (tester) async {
    final en = (jsonDecode(File('assets/l10n/en.json').readAsStringSync()) as Map).cast<String, String>();
    final tr = Tr('en', en);
    final steps = coachSteps(tr);
    for (final (i, step) in steps.indexed) {
      expect(step.title, isNot(_titles[i]), reason: 'título ${i + 1}');
      expect(step.text, isNot(coachSteps(_es)[i].text), reason: 'texto ${i + 1}');
    }

    final closes = await _pump(tester, tr: tr);
    expect(find.text(steps[0].title), findsOneWidget);
    expect(find.text(steps[0].text), findsOneWidget);
    expect(find.text('STEP 1 OF 5'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.bySemanticsLabel('Close the tutorial'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await _tap(tester, 'Next');
    }
    expect(find.text('Got it'), findsOneWidget);
    await _tap(tester, 'See the rest');
    expect(find.text('THE REST · 1 OF 2'), findsOneWidget);
    await _tap(tester, 'Next');
    expect(find.text('Back'), findsOneWidget);
    await _tap(tester, 'Done');
    expect(closes, [true]);
  });
}
