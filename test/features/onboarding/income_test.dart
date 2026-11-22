import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_segmented.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';
import 'package:rinde_mobile/features/onboarding/presentation/income/income_source_tile.dart';
import 'package:rinde_mobile/features/onboarding/presentation/income/pay_days_field.dart';
import 'package:rinde_mobile/features/onboarding/presentation/steps/income_step.dart';
import 'package:rinde_mobile/features/onboarding/presentation/widgets/onboarding_shell.dart';
import 'package:rinde_mobile/features/rin/rin.dart';

/// Repositorio mínimo: la bienvenida no está hecha y no hay propuesta de saldo.
class _Repo implements OnboardingRepository {
  @override
  bool get isDemo => true;

  @override
  Future<WelcomeStatus> status() async =>
      const WelcomeStatus(welcomeDone: false, tutorialDone: false, hasTransactions: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Marco real con el paso de ingresos y un «Seguir» que llama a controller.next, como el anfitrión.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = onboardingControllerProvider(OnboardingMode.full);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return OnboardingShell(
      step: state.step,
      total: state.total,
      direction: state.direction,
      onBack: () => controller.back(),
      onSkip: controller.skip,
      labels: OnboardingShellLabels(
        back: 'Atrás',
        skip: 'Omitir',
        progress: 'Avance de la bienvenida',
        stepOf: (s, total) => 'Paso $s de $total',
      ),
      action: RindeButton(label: 'Seguir', onPressed: controller.next),
      child: const IncomeStep(mode: OnboardingMode.full),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(412, 2600),
  double textScale = 1,
  ThemeData? theme,
  bool reduceMotion = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryDraftStore()
    ..data['anon'] = jsonEncode({
      'v': 1,
      'position': OnboardingSteps.income,
      'country': 'CO',
      'language': 'es',
    });
  final container = ProviderContainer(
    overrides: [
      draftStoreProvider.overrideWithValue(store),
      onboardingRepositoryProvider.overrideWithValue(_Repo()),
      sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
      systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
    ],
  );
  // Contenedor propio para leer el estado del controlador desde la prueba.
  container.listen(onboardingControllerProvider(OnboardingMode.full), (_, _) {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion, textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const _Host(),
      ),
    ),
  );
  // Con movimiento, Rin respira sin parar: pumpAndSettle nunca terminaría.
  reduceMotion ? await tester.pumpAndSettle() : await tester.pump(const Duration(milliseconds: 500));
}

OnboardingState _state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IncomeStep)))
        .read(onboardingControllerProvider(OnboardingMode.full));

Map<IncomeKind, IncomeSourceForm> _sources(WidgetTester tester) => _state(tester).draft.sources;

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Finder _field(String id) =>
    find.descendant(of: find.byKey(ValueKey('income-$id')), matching: find.byType(TextField));

Finder _day(int day) => find.descendant(of: find.byType(PayDaysField), matching: find.text('$day'));

/// Cada prueba termina dejando correr la escritura pendiente del borrador (temporizador del controlador).
void _testIncome(String description, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pump(draftWriteDelay);
    });

void main() {
  _testIncome('dibuja las 5 fuentes como casillas sin marcar', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.text('¿Cómo te entra la plata?'), findsOneWidget);
    expect(
      find.text('Elige todas las que apliquen. Los montos son aproximados: más o menos está bien.'),
      findsOneWidget,
    );
    expect(find.byType(IncomeSourceTile), findsNWidgets(5));
    for (final kind in IncomeKind.values) {
      expect(
        tester.getSemantics(find.text(kind.title)),
        isSemantics(hasCheckedState: true, isChecked: false, hasTapAction: true),
      );
    }
    expect(find.textContaining('Con esto sé cuándo te entra plata'), findsOneWidget);
    semantics.dispose();
  });

  _testIncome('marcar dos conserva ambas, cada una con sus preguntas', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await _tapText(tester, 'Sueldo fijo');
    await _tapText(tester, 'Mesada o ayuda');

    expect(_sources(tester).keys, [IncomeKind.sueldo, IncomeKind.mesada]);
    expect(find.text('¿Cuánto te pagan al mes?'), findsOneWidget);
    expect(find.text('¿Qué días te pagan? (opcional)'), findsOneWidget);
    expect(find.text('¿Cuánto te dan cada vez?'), findsOneWidget);
    expect(find.text('Tu base fija al mes'), findsNothing);
    expect(
      tester.getSemantics(find.text('Sueldo fijo')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(
      tester.getSemantics(find.text('Mesada o ayuda')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    semantics.dispose();
  });

  _testIncome('los montos llegan crudos al borrador y desmarcar borra lo escrito', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Sueldo fijo');
    await tester.enterText(_field('sueldo-amount'), '1.500.000');
    await tester.pump();
    expect(_sources(tester)[IncomeKind.sueldo]!.amount, '1500000');
    expect(find.text('1.500.000'), findsOneWidget);

    await _tapText(tester, 'Sueldo fijo');
    expect(_sources(tester), isEmpty);
    expect(find.text('¿Cuánto te pagan al mes?'), findsNothing);

    await _tapText(tester, 'Sueldo fijo');
    expect(_sources(tester)[IncomeKind.sueldo]!.amount, '');
    expect(find.text('1.500.000'), findsNothing);
  });

  _testIncome('comisiones: base, mes malo y mes bueno, con «siguiente» en el teclado', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Sueldo + comisiones');
    await tester.enterText(_field('comisiones-amount'), '1300000');
    await tester.enterText(_field('comisiones-low'), '200000');
    await tester.enterText(_field('comisiones-high'), '900000');
    await tester.pump();
    final form = _sources(tester)[IncomeKind.comisiones]!;
    expect((form.amount, form.low, form.high), ('1300000', '200000', '900000'));
    expect(find.text('Comisión en un mes malo'), findsOneWidget);
    expect(find.text('En un mes bueno'), findsOneWidget);
    expect(tester.widget<TextField>(_field('comisiones-amount')).textInputAction, TextInputAction.next);
    expect(tester.widget<TextField>(_field('comisiones-low')).textInputAction, TextInputAction.next);
    expect(tester.widget<TextField>(_field('comisiones-high')).textInputAction, TextInputAction.done);
  });

  _testIncome('días de pago: quedan ordenados, máximo 4, y el quinto avisa', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Sueldo fijo');
    for (final day in [15, 1, 30, 5]) {
      await tester.tap(_day(day));
      await tester.pump();
    }
    expect(_sources(tester)[IncomeKind.sueldo]!.payDays, [1, 5, 15, 30]);
    expect(find.text('Hasta 4 días.'), findsNothing);

    await tester.tap(_day(20));
    await tester.pump();
    expect(_sources(tester)[IncomeKind.sueldo]!.payDays, [1, 5, 15, 30]);
    expect(find.text('Hasta 4 días.'), findsOneWidget);

    await tester.tap(_day(1));
    await tester.pump();
    expect(_sources(tester)[IncomeKind.sueldo]!.payDays, [5, 15, 30]);
    expect(find.text('Hasta 4 días.'), findsNothing);
    expect(find.text('Si eliges 31, en los meses cortos contamos el último día.'), findsOneWidget);
  });

  _testIncome('diario y mesada: los segmentados cambian la fuente', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Por días o por apps');
    expect(_sources(tester)[IncomeKind.diario]!.workDays, '6');
    await tester.tap(find.descendant(of: find.byType(RindeSegmented<String>), matching: find.text('4')));
    await tester.pump();
    expect(_sources(tester)[IncomeKind.diario]!.workDays, '4');
    expect(find.text('¿Cuánto haces en un día normal?'), findsOneWidget);

    await _tapText(tester, 'Mesada o ayuda');
    await _tapText(tester, 'Quincena');
    expect(_sources(tester)[IncomeKind.mesada]!.frequency, 'quincenal');
    // Cambiar la mesada no toca la otra fuente.
    expect(_sources(tester)[IncomeKind.diario]!.workDays, '4');
  });

  _testIncome('proyectos: tres montos, cada uno en su mes', (tester) async {
    await _pump(tester);
    await _tapText(tester, 'Por proyectos u honorarios');
    expect(find.text('¿Cuánto te entró los últimos 3 meses? Más o menos.'), findsOneWidget);
    for (final label in ['Este mes', 'Hace 1 mes', 'Hace 2']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(RindeMoneyField), findsNWidgets(3));
    await tester.enterText(_field('proyectos-month-0'), '3000000');
    await tester.enterText(_field('proyectos-month-2'), '2500000');
    await tester.pump();
    final form = _sources(tester)[IncomeKind.proyectos]!;
    expect(form.lastMonths, ['3000000', '', '2500000']);
    expect(form.toApi()['lastMonths'], [3000000, 2500000]);
  });

  _testIncome('sin elegir nada, «Seguir» avanza a Saldo', (tester) async {
    await _pump(tester);
    expect(_state(tester).position, OnboardingSteps.income);
    await tester.tap(find.text('Seguir'));
    await tester.pumpAndSettle();
    expect(_state(tester).position, OnboardingSteps.balance);
    expect(_state(tester).draft.sources, isEmpty);
  });

  _testIncome('al marcar, la fila abierta se acerca a la vista sin quedar bajo el botón', (tester) async {
    await _pump(tester, size: const Size(412, 760));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels, 0);
    await tester.tap(find.text('Sueldo fijo'));
    await tester.pumpAndSettle();

    expect(scroll.pixels, greaterThan(0));
    final tile = find.byType(IncomeSourceTile).first;
    final viewport = tester.getRect(find.byType(Scrollable).first);
    expect(tester.getRect(tile).bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.getRect(find.text('Sueldo fijo')).top, greaterThanOrEqualTo(viewport.top));
    expect(tester.getRect(find.text('Seguir')).top, greaterThan(tester.getRect(tile).bottom));
  });

  _testIncome('texto al doble y tema oscuro, con todo abierto, sin desbordes', (tester) async {
    await _pump(tester, size: const Size(360, 6000), textScale: 2, theme: RindeTheme.dark);
    for (final kind in IncomeKind.values) {
      await _tapText(tester, kind.title);
    }
    expect(_sources(tester).length, 5);
    expect(tester.takeException(), isNull);
  });

  _testIncome('con movimiento: abre y cierra suave, y Rin se alegra un momento', (tester) async {
    await _pump(tester, reduceMotion: false);
    final reveal = find.descendant(
      of: find.byType(IncomeSourceTile).first,
      matching: find.byType(SizeTransition),
    );
    Rin rin() => tester.widget<Rin>(find.byType(Rin));

    await tester.tap(find.text('Sueldo fijo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getSize(reveal).height;
    expect(rin().emotion, RinEmotion.feliz);
    expect(rin().gesture, RinGesture.asentir);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opening, inExclusiveRange(0, tester.getSize(reveal).height));

    // Al desmarcar, el borrador se vacía al instante, pero las preguntas se ven mientras se cierran.
    await tester.tap(find.text('Sueldo fijo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_sources(tester), isEmpty);
    expect(find.text('¿Cuánto te pagan al mes?'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('¿Cuánto te pagan al mes?'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(rin().emotion, RinEmotion.tranquilo);
  });
}
