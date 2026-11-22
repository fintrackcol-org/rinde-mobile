import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/onboarding/presentation/steps/tour_step.dart';

const _usd = Region(country: 'US', currency: 'USD', language: 'es');

/// Monto en pesos colombianos: Intl pone un espacio duro después del signo.
String _cop(String n) => '\$\u00a0$n';

const _titles = [
  'Empieza con tu plata de hoy',
  'Anota hablando',
  'Mi plata te dice cuánto puedes gastar',
  'Vacas con tus amigos',
  'También por WhatsApp',
];

const _whatsappNote = 'Se activa por cuenta: pídelo en Cuenta.';

/// El paso dentro de un scroll vertical, como en el marco de la bienvenida. TourStep no usa el
/// controlador: solo la región (moneda) y el idioma.
Widget _host(
  int index, {
  Region region = kDefaultRegion,
  bool still = true,
  double textScale = 1,
  ThemeData? theme,
  VoidCallback? onNext,
  VoidCallback? onBack,
}) => ProviderScope(
  overrides: [initialRegionProvider.overrideWithValue(region)],
  child: MaterialApp(
    theme: theme ?? RindeTheme.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: still, textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: TourStep(index: index, onNext: onNext ?? () {}, onBack: onBack ?? () {}),
          ),
        ),
      ),
    ),
  ),
);

/// Opacidad efectiva de un texto (producto de los Opacity que lo envuelven).
double _opacity(WidgetTester tester, String text) {
  var value = 1.0;
  final finder = find.ancestor(of: find.text(text), matching: find.byType(Opacity));
  for (final o in tester.widgetList<Opacity>(finder)) {
    value *= o.opacity;
  }
  return value;
}

/// Deja correr el reloj con cuadros de 50 ms (los temporizadores y las animaciones avanzan).
Future<void> _play(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('las 5 escenas se dibujan con su contador, título, texto y la etiqueta Ejemplo', (
    tester,
  ) async {
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(_host(i));
      await tester.pumpAndSettle();
      expect(find.text('Cómo funciona · ${i + 1} de 5'), findsOneWidget);
      expect(find.text(_titles[i]), findsOneWidget);
      expect(find.text('Ejemplo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(
      find.text('Escríbele a Rinde desde WhatsApp para anotar o preguntar cómo vas, sin abrir la app.'),
      findsOneWidget,
    );
  });

  testWidgets('con movimiento reducido todo queda quieto en su estado final y sin botón de repetir', (
    tester,
  ) async {
    // Escena 1: el saldo ya bajó y se ve el almuerzo (decisión: estado final; la web deja $ 100.000).
    await tester.pumpWidget(_host(0));
    await tester.pumpAndSettle(); // Se asienta: no hay nada animándose sin fin.
    expect(find.text(_cop('80.000')), findsOneWidget);
    expect(find.text(_cop('100.000')), findsNothing);
    expect(_opacity(tester, '− ${_cop('20.000')} · almuerzo'), 1);
    expect(find.byTooltip('Repetir el ejemplo'), findsNothing);

    // Escena 2: frase, fichas y «Anotado» de una vez; la onda oculta.
    await tester.pumpWidget(_host(1));
    await tester.pumpAndSettle();
    expect(_opacity(tester, '“gasolina 40 mil”'), 1);
    expect(_opacity(tester, 'Transporte'), 1);
    expect(_opacity(tester, _cop('40.000')), 1);
    expect(_opacity(tester, 'Anotado'), 1);
    expect(find.text('Transporte · gasolina'), findsOneWidget);
    expect(find.text('− ${_cop('40.000')}'), findsOneWidget);

    // Escenas 3 y 4: las barras ya llenas.
    await tester.pumpWidget(_host(2));
    await tester.pumpAndSettle();
    expect(tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor, 0.45);
    expect(find.text(_cop('32.000')), findsOneWidget);
    await tester.pumpWidget(_host(3));
    await tester.pumpAndSettle();
    expect(tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor, 0.75);

    // Escena 5: la respuesta ya está.
    await tester.pumpWidget(_host(4));
    await tester.pumpAndSettle();
    expect(
      _opacity(tester, 'Listo, anoté un ingreso de ${_cop('38.000')}. Hoy llevas ${_cop('38.000')}.'),
      1,
    );
  });

  testWidgets('las escenas animan con los tiempos de la web', (tester) async {
    await tester.pumpWidget(_host(0, still: false));
    await tester.pump();
    expect(find.text(_cop('100.000')), findsOneWidget);
    await _play(tester, 1500);
    expect(find.text(_cop('100.000')), findsOneWidget);
    await _play(tester, 600);
    expect(find.text(_cop('80.000')), findsOneWidget);
    expect(find.text('− ${_cop('20.000')} · almuerzo'), findsOneWidget);

    await tester.pumpWidget(_host(1, still: false));
    await tester.pump();
    expect(_opacity(tester, '“gasolina 40 mil”'), 0);
    await _play(tester, 1550); // 1300 ms + el fundido de 200.
    expect(_opacity(tester, '“gasolina 40 mil”'), 1);
    expect(_opacity(tester, 'Transporte'), 0);
    await _play(tester, 900); // 2100 ms + 300.
    expect(_opacity(tester, 'Transporte'), 1);
    expect(_opacity(tester, 'Anotado'), 0);
    await _play(tester, 800); // 2900 ms + 300.
    expect(_opacity(tester, 'Anotado'), 1);

    await tester.pumpWidget(_host(4, still: false));
    await tester.pump();
    final reply = 'Listo, anoté un ingreso de ${_cop('38.000')}. Hoy llevas ${_cop('38.000')}.';
    expect(_opacity(tester, reply), 0);
    await _play(tester, 1400);
    expect(_opacity(tester, reply), 1);
  });

  testWidgets('repetir el ejemplo vuelve a empezar la secuencia', (tester) async {
    await tester.pumpWidget(_host(1, still: false));
    await _play(tester, 3400);
    expect(_opacity(tester, 'Anotado'), 1);

    await tester.tap(find.byTooltip('Repetir el ejemplo'));
    await tester.pump();
    expect(_opacity(tester, 'Anotado'), 0);
    expect(_opacity(tester, '“gasolina 40 mil”'), 0);
    // El contador y el título no se repiten: siguen ahí.
    expect(find.text('Cómo funciona · 2 de 5'), findsOneWidget);

    await _play(tester, 3400);
    expect(_opacity(tester, 'Anotado'), 1);
  });

  testWidgets('deslizar a la izquierda avanza y a la derecha vuelve; poco o en vertical, nada', (
    tester,
  ) async {
    var next = 0;
    var back = 0;
    await tester.pumpWidget(_host(1, still: false, onNext: () => next++, onBack: () => back++));
    await tester.pump();

    await tester.drag(find.text('Anota hablando'), const Offset(-120, 0));
    await tester.pump();
    expect((next, back), (1, 0));

    await tester.drag(find.text('Anota hablando'), const Offset(120, 0));
    await tester.pump();
    expect((next, back), (1, 1));

    await tester.drag(find.text('Anota hablando'), const Offset(-50, 0));
    await tester.drag(find.text('Anota hablando'), const Offset(0, -200));
    await _play(tester, 500);
    expect((next, back), (1, 1));
  });

  testWidgets('con movimiento reducido no se arrastra', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(1, onNext: () => calls++, onBack: () => calls++));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Anota hablando'), const Offset(-120, 0));
    await tester.drag(find.text('Anota hablando'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('en dólares los montos y las frases van a la escala de la moneda (÷ 1000)', (tester) async {
    await tester.pumpWidget(_host(0, region: _usd));
    await tester.pumpAndSettle();
    expect(find.text(r'$80'), findsOneWidget);
    expect(find.text(r'− $20 · almuerzo'), findsOneWidget);

    await tester.pumpWidget(_host(1, region: _usd));
    await tester.pumpAndSettle();
    expect(find.text('“gasolina 40”'), findsOneWidget);
    expect(find.text('gasolina'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text(r'$40'), findsOneWidget);
    expect(find.text(r'− $40'), findsOneWidget);
    expect(
      find.text(
        'Di “gasolina 40” o “corte 25” y Rinde lo anota con su categoría. También puedes escribirlo.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(_host(2, region: _usd));
    await tester.pumpAndSettle();
    expect(find.text(r'$32'), findsOneWidget);

    await tester.pumpWidget(_host(3, region: _usd));
    await tester.pumpAndSettle();
    expect(find.text(r'$450 de $600 · 4 amigos'), findsOneWidget);

    await tester.pumpWidget(_host(4, region: _usd));
    await tester.pumpAndSettle();
    expect(find.text('hice 38'), findsOneWidget);
    expect(find.text(r'Listo, anoté un ingreso de $38. Hoy llevas $38.'), findsOneWidget);
  });

  testWidgets('en pesos colombianos se habla en miles', (tester) async {
    await tester.pumpWidget(_host(1));
    await tester.pumpAndSettle();
    expect(find.text('40 mil'), findsOneWidget);
    expect(
      find.text(
        'Di “gasolina 40 mil” o “corte 25 mil” y Rinde lo anota con su categoría. También puedes escribirlo.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(_host(3));
    await tester.pumpAndSettle();
    expect(find.text('${_cop('450.000')} de ${_cop('600.000')} · 4 amigos'), findsOneWidget);
    await tester.pumpWidget(_host(4));
    await tester.pumpAndSettle();
    expect(find.text('hice 38 mil'), findsOneWidget);
  });

  testWidgets('la nota de WhatsApp sale solo en la escena 5', (tester) async {
    await tester.pumpWidget(_host(4));
    await tester.pumpAndSettle();
    expect(find.text(_whatsappNote), findsOneWidget);
    await tester.pumpWidget(_host(3));
    await tester.pumpAndSettle();
    expect(find.text(_whatsappNote), findsNothing);
  });

  testWidgets('texto grande en celular chico y tema oscuro: sin desbordes', (tester) async {
    _phone(tester, const Size(320, 568));
    for (final scale in [1.3, 2.0]) {
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(_host(i, textScale: scale, theme: RindeTheme.dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'escena ${i + 1} a ${scale}x');
      }
    }
  });

  testWidgets('el botón de repetir tiene nombre y área de 48', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(0, still: false));
    await tester.pump();
    final button = find.byTooltip('Repetir el ejemplo');
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.byType(IconButton)),
      isSemantics(tooltip: 'Repetir el ejemplo', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });
}
