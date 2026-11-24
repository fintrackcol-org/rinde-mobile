// Pantallas de Planear con los datos del servidor ya cargados: qué muestran (textos de la web, lo
// que calcula el servidor tal cual), a dónde llevan y que nada se desborde a 320 de ancho con la
// letra al doble, en los dos temas.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/plan/application/plan_providers.dart';
import 'package:rinde_mobile/features/plan/data/plan_models.dart';
import 'package:rinde_mobile/features/plan/presentation/budget_detail_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/budgets_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/calendar_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/liquidity_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/plan_screen.dart';

String _m(num value) => formatFor(kDefaultRegion).money(value);

const _budgets = [
  BudgetStatus(
    id: 'p1',
    category: 'alimentacion',
    amount: 200000,
    consumed: 172000,
    percentage: 86,
    level: BudgetLevel.warning,
  ),
  BudgetStatus(
    id: 'p2',
    category: 'entretenimiento',
    amount: 150000,
    consumed: 186000,
    percentage: 124,
    level: BudgetLevel.exceeded,
  ),
];

final _calendar = PaymentCalendar.fromJson({
  'month': '2026-11',
  'today': '2026-11-22',
  'money': 180000,
  'projectedUntil': null,
  'events': [
    {
      'date': '2026-11-24',
      'kind': 'compromiso',
      'id': 'c1',
      'name': 'Plan celular',
      'amount': 45000,
      'status': 'pendiente',
      'balanceAfter': 135000,
      'risk': 'ok',
    },
    {
      'date': '2026-11-27',
      'kind': 'compromiso',
      'id': 'c2',
      'name': 'PILA',
      'amount': 228000,
      'status': 'pendiente',
      'balanceAfter': -93000,
      'risk': 'negativo',
    },
    {
      'date': '2026-11-28',
      'kind': 'cobro',
      'id': 'd1',
      'name': 'Laura',
      'amount': 20000,
      'status': 'pendiente',
    },
  ],
  'cardDates': [
    {'date': '2026-11-30', 'kind': 'corte', 'id': 't1', 'name': 'Mi Visa', 'amount': null, 'status': null},
  ],
  'totals': {'pending': 273000, 'paid': 0},
});

final _liquidity = Liquidity.fromJson({
  'ready': true,
  'today': '2026-11-22',
  'money': 180000,
  'pace': null,
  'until': '2026-11-30',
  'days': [
    {'date': '2026-11-22', 'end': 180000, 'events': []},
    {
      'date': '2026-11-24',
      'end': 135000,
      'events': [
        {'kind': 'compromiso', 'name': 'Plan celular', 'amount': 45000},
      ],
    },
    {
      'date': '2026-11-27',
      'end': -93000,
      'events': [
        {'kind': 'compromiso', 'name': 'PILA', 'amount': 228000},
      ],
    },
  ],
  'firstShortfall': {
    'date': '2026-11-27',
    'missing': 93000,
    'causes': [
      {'kind': 'compromiso', 'name': 'PILA', 'amount': 228000, 'date': '2026-11-27'},
    ],
  },
  'lowest': {'date': '2026-11-27', 'amount': -93000},
  'risk': 'falta',
  'safeDailySpend': 0,
  'receivable': 20000,
  'assumptions': ['No contamos ingresos futuros: solo la plata que ya tienes.'],
});

Future<GoRouter> _pump(
  WidgetTester tester,
  String initial, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: Routes.plan, builder: (_, _) => const PlanScreen()),
      GoRoute(path: Routes.budgets, builder: (_, _) => const BudgetsScreen()),
      GoRoute(
        path: '${Routes.budgets}/:category',
        builder: (_, s) => BudgetDetailScreen(
          category: s.pathParameters['category']!,
          month: s.uri.queryParameters['mes'] ?? '2026-11',
        ),
      ),
      GoRoute(path: Routes.calendar, builder: (_, _) => const CalendarScreen()),
      GoRoute(path: Routes.liquidity, builder: (_, _) => const LiquidityScreen()),
      // Los destinos a los que llevan: un marcador con su ruta.
      for (final path in [Routes.app, Routes.myMoney, Routes.payments, Routes.debts, Routes.record])
        GoRoute(
          path: path,
          builder: (_, s) => Scaffold(body: Text('DESTINO ${s.uri}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        budgetsMonthProvider.overrideWith((ref, _) async => _budgets),
        homeCategoryNamesProvider.overrideWith(
          (ref, _) async => const {'alimentacion': 'Alimentación', 'entretenimiento': 'Entretenimiento'},
        ),
        budgetMovementsProvider.overrideWith(
          (ref, _) async => const MovementPage(items: [], page: 1, pageSize: 50, total: 0),
        ),
        calendarMonthProvider.overrideWith((ref, _) async => _calendar),
        liquidityProvider.overrideWith((ref, _) async => _liquidity),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('Presupuestos: topes del mes, el aviso más grave y cada fila con lo que dice el servidor', (
    tester,
  ) async {
    await _pump(tester, Routes.budgets);
    expect(find.text('Tus presupuestos'), findsOneWidget);
    expect(find.text('Noviembre de 2026'), findsOneWidget);
    expect(find.text('TOPES DEL MES'), findsOneWidget);
    // La suma de los límites y de lo gastado (en centavos), no un cálculo del porcentaje de cada uno.
    expect(find.textContaining('350.000'), findsOneWidget);
    expect(find.text('Te pasaste del presupuesto de Entretenimiento.'), findsOneWidget);
    expect(find.text('86 %'), findsOneWidget);
    expect(find.textContaining('Quedan ${_m(28000)} de ${_m(200000)}'), findsOneWidget);
    expect(find.textContaining('Te pasaste por ${_m(36000)} de ${_m(150000)}'), findsOneWidget);

    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Diciembre de 2026'), findsOneWidget);

    await tester.tap(find.text('Alimentación'));
    await tester.pumpAndSettle();
    final detail = tester.widget<BudgetDetailScreen>(find.byType(BudgetDetailScreen));
    expect((detail.category, detail.month), ('alimentacion', '2026-12'));
    expect(find.text('Vas en'), findsOneWidget);
    expect(find.text('Aún no hay movimientos en este presupuesto.'), findsOneWidget);
  });

  testWidgets('Calendario: lo que queda después de cada pago, el hueco del motor y lo que me deben aparte', (
    tester,
  ) async {
    await _pump(tester, Routes.calendar);
    expect(find.text('Noviembre 2026'), findsOneWidget);
    expect(find.text('No te alcanza: ${_m(-93000)}'), findsOneWidget);
    expect(find.text('Te quedan ${_m(135000)}'), findsOneWidget);
    expect(find.text('Te debe · no se suma a tu plata'), findsOneWidget);
    expect(find.text('+${_m(20000)}'), findsOneWidget);
    expect(
      find.text('Corte de la tarjeta · lo que compres después va al siguiente extracto'),
      findsOneWidget,
    );
    expect(find.textContaining('te faltan ${_m(93000)}. Ver qué pasa'), findsOneWidget);

    // Tocar un día abre lo que tiene y deja agregarle algo.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^27 nov, 1 elemento')));
    await tester.pumpAndSettle();
    expect(find.text('Agregar a este día'), findsOneWidget);
    await tester.tap(find.text('Agregar a este día'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar al 27 nov'), findsOneWidget);
    expect(find.text('Arriendo, servicios, cuotas. Se repite el día 27 de cada mes.'), findsOneWidget);
  });

  testWidgets('Próximos días: el resumen, por qué pasa y cómo evitarlo salen de la proyección del servidor', (
    tester,
  ) async {
    await _pump(tester, Routes.liquidity);
    expect(find.text('El 27 de noviembre te faltan ${_m(93000)}'), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'sin gasto normal no se inventa uno');
    expect(find.text('Pago del mes · 27 nov'), findsOneWidget);
    expect(find.textContaining('Cobra lo que te deben (${_m(20000)}): te faltaría menos.'), findsOneWidget);
    expect(find.text('No contamos ingresos futuros: solo la plata que ya tienes.'), findsOneWidget);
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
      for (final route in [
        Routes.plan,
        Routes.budgets,
        '${Routes.budgets}/entretenimiento',
        Routes.calendar,
        Routes.liquidity,
      ]) {
        await _pump(tester, route, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(tester.takeException(), isNull, reason: route);
      }
    });
  }
}
