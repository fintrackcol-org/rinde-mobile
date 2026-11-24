// Ingresos, Gastos y Por confirmar con los datos del servidor ya cargados: los textos de la web, las
// cifras del servidor tal cual, que «Anotar el gasto» con dos toques manda un solo envío y que nada se
// desborde a 320 de ancho con la letra al doble, en los dos temas.
import 'dart:async';

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
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/period/application/period_providers.dart';
import 'package:rinde_mobile/features/period/data/period_models.dart';
import 'package:rinde_mobile/features/period/presentation/period_screen.dart';
import 'package:rinde_mobile/features/to_confirm/application/to_confirm_writer.dart';
import 'package:rinde_mobile/features/to_confirm/data/to_confirm_repository.dart';
import 'package:rinde_mobile/features/to_confirm/presentation/to_confirm_screen.dart';

String _m(num value) => formatFor(kDefaultRegion).money(value);

final _summary = PeriodSummary.fromJson({
  'period': 'month',
  'from': '2026-11-01',
  'to': '2026-11-30',
  'income': {
    'total': 700000,
    'byCategory': [
      {'category': 'freelance', 'total': 700000, 'percentage': 100},
    ],
  },
  'expense': {
    'total': 220000,
    'byCategory': [
      {'category': 'alimentacion', 'total': 172000, 'percentage': 78.2},
      {'category': null, 'total': 48000, 'percentage': 21.8},
    ],
  },
  'savings': {'total': 50000},
});

final _lunch = Movement(
  id: 'm1',
  type: MovementType.expense,
  amount: 172000,
  description: 'Mercado',
  source: 'manual',
  date: '2026-11-20',
  category: 'alimentacion',
  kakeibo: 'deseo',
);

const _payments = [
  IncomingPayment(id: 'p1', merchant: 'Taxi', amount: 12400, date: '2026-11-21', card: 'Mi Visa'),
  IncomingPayment(
    id: 'p2',
    merchant: 'Panadería del barrio',
    amount: 8900,
    date: '2026-11-22',
    possibleDuplicate: true,
  ),
];

class _FakeToConfirm implements ToConfirmRepository {
  final sent = <String>[];
  final gate = Completer<void>();

  @override
  bool get isDemo => false;

  @override
  Future<List<IncomingPayment>> list() async => _payments;

  @override
  Future<void> confirm(String id, {required String description, String? category, String? card}) {
    sent.add('confirm $id $description');
    return gate.future;
  }

  @override
  Future<void> discard(String id) async => sent.add('discard $id');
}

Future<void> _pump(
  WidgetTester tester,
  String initial, {
  _FakeToConfirm? repo,
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
      GoRoute(
        path: Routes.income,
        builder: (_, _) => const PeriodScreen(type: MovementType.income),
      ),
      GoRoute(
        path: Routes.expenses,
        builder: (_, _) => const PeriodScreen(type: MovementType.expense),
      ),
      GoRoute(path: Routes.toConfirm, builder: (_, _) => const ToConfirmScreen()),
      for (final path in [Routes.app, Routes.movements, Routes.myMoney, '/app/transacciones/:id'])
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
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        periodSummaryProvider.overrideWith((ref, _) async => _summary),
        periodMovementsProvider.overrideWith(
          (ref, key) async => MovementPage(
            items: key.$2.type == MovementType.expense ? [_lunch] : const [],
            page: 1,
            pageSize: 50,
            total: key.$2.type == MovementType.expense ? 1 : 0,
          ),
        ),
        periodKakeiboProvider.overrideWith(
          (ref, _) async => MovementPage(items: [_lunch], page: 1, pageSize: 100, total: 1),
        ),
        movementCategoriesProvider.overrideWith(
          (ref, _) async => CategoryLists.fromJson({
            'expense': [
              {'key': 'alimentacion', 'name': 'Alimentación'},
              {'key': 'transporte', 'name': 'Transporte'},
            ],
            'income': [
              {'key': 'freelance', 'name': 'Freelance'},
            ],
          }),
        ),
        toConfirmRepositoryProvider.overrideWithValue(repo ?? _FakeToConfirm()),
        toConfirmListProvider.overrideWith((ref, _) async => _payments),
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
}

void main() {
  testWidgets('Gastos: la pregunta, el total del servidor con su promedio, ahorro, balance y Kakeibo', (
    tester,
  ) async {
    await _pump(tester, Routes.expenses);
    expect(find.text('Gastos · noviembre'), findsOneWidget);
    expect(find.text('¿En qué se fue tu plata?'), findsOneWidget);
    expect(find.text('− ${_m(220000)}'), findsOneWidget);
    expect(find.text('En 22 días · promedio ${_m(10000)} al día'), findsOneWidget);
    expect(find.text(_m(700000)), findsOneWidget);
    expect(find.text(_m(50000)), findsOneWidget, reason: 'Ahorro');
    expect(find.text(_m(430000)), findsOneWidget, reason: 'Balance: 700.000 − 220.000 − 50.000');
    expect(find.text('${_m(172000)} · 78 %'), findsOneWidget);
    expect(find.text('Sin clasificar'), findsWidgets);
    expect(find.text('¿PODÍAS EVITARLO? · KAKEIBO'), findsOneWidget);
    expect(
      find.text('En deseos llevas ${_m(172000)}. Bajarlos un 10 % te deja ${_m(17200)} más.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Ver todos los movimientos'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mercado'), findsOneWidget);
    expect(find.text('Alimentación · 20 nov'), findsOneWidget, reason: 'withDay de la web');
  });

  testWidgets('Ingresos: sin movimientos dice el vacío de la web y no hay Kakeibo', (tester) async {
    await _pump(tester, Routes.income);
    expect(find.text('¿De dónde entró tu plata?'), findsOneWidget);
    expect(find.text('+ ${_m(700000)}'), findsOneWidget);
    expect(find.text('¿PODÍAS EVITARLO? · KAKEIBO'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('No hay ingresos en este periodo.').last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  });

  testWidgets('Por confirmar: total, filas con tarjeta y posible duplicado; dos toques, un envío', (
    tester,
  ) async {
    final repo = _FakeToConfirm();
    await _pump(tester, Routes.toConfirm, repo: repo);
    expect(find.text('2 pagos sin revisar'), findsOneWidget);
    expect(find.text(_m(21300)), findsOneWidget);
    expect(find.text('Ayer · Mi Visa'), findsOneWidget);
    expect(find.text('Puede que ya lo hayas anotado: hay un gasto igual por esos días.'), findsOneWidget);

    await tester.tap(find.text('Confirmar').first);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar pago'), findsOneWidget);
    expect(find.text('Se anota un gasto de ${_m(12400)} con fecha 21 nov 2026.'), findsOneWidget);
    await tester.tap(find.text('Anotar el gasto'));
    await tester.pump();
    await tester.tap(find.text('Anotar el gasto'), warnIfMissed: false);
    await tester.pump();
    expect(repo.sent, ['confirm p1 Taxi']);

    repo.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Confirmar pago'), findsNothing);
    expect(find.text('Anotado: Taxi, ${_m(12400)}.'), findsOneWidget);
    expect(repo.sent, ['confirm p1 Taxi']);
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
      for (final route in [Routes.expenses, Routes.income, Routes.toConfirm]) {
        await _pump(tester, route, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(tester.takeException(), isNull, reason: route);
      }
    });
  }
}
