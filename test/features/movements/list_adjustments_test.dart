// Ajustes de saldo en Movimientos (bloque 4B): intercalados al inicio de su día como withAdjustments
// de MovementList.jsx, en gris, ocultos con un filtro, tolerantes a que /adjustments falle, y su hoja
// con el saldo de antes, el de después y la diferencia.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/presentation/list/adjustment_row.dart';
import 'package:rinde_mobile/features/movements/presentation/list/movements_screen.dart';

import '../../support/fake_money_repository.dart';
import '../../support/fake_movements_repository.dart';
import '../../support/home_fixtures.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _NoStore extends HiddenAmountsStore {
  const _NoStore();
  @override
  Future<bool> read() async => false;
  @override
  Future<void> write(bool hidden) async {}
}

final _cop = formatFor(kDefaultRegion);
String _m(num value) => _cop.money(value);

final _movements = [
  movementOf('m1', date: '2026-11-22', description: 'Almuerzo', amount: 12500),
  movementOf('m2', date: '2026-11-21', description: 'Mercado', amount: 80000),
  movementOf('m3', date: '2026-11-20', description: 'Taxi', amount: 9000),
];

/// Del más nuevo al más viejo, como los manda el servidor: subió el 21 y bajó el 15.
const _adjustments = [
  BalanceAdjustment(id: 'aj2', before: 300000, after: 450000, date: '2026-11-21'),
  BalanceAdjustment(id: 'aj1', before: 500000, after: 350000, date: '2026-11-15'),
];

MovementPage _page(MovementQuery q, List<Movement> all) =>
    MovementPage(items: all, page: q.page, pageSize: q.pageSize, total: all.length);

Future<void> _pump(
  WidgetTester tester,
  FakeMovementsRepository movements,
  FakeMoneyRepository money, {
  bool hidden = false,
  // Alta: la lista se arma a medida que se ve y el ajuste más viejo va al final.
  Size size = const Size(390, 1400),
  double textScale = 1,
  // false: unos cuadros, sin esperar a que todo llegue (la página puede no llegar nunca).
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.movements,
    routes: [GoRoute(path: Routes.movements, builder: (_, _) => const MovementsScreen())],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(_ana)),
        movementsRepositoryProvider.overrideWithValue(movements),
        moneyRepositoryProvider.overrideWithValue(money),
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        initialRegionProvider.overrideWithValue(kDefaultRegion),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        hiddenAmountsStoreProvider.overrideWithValue(const _NoStore()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

double _y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  group('withAdjustments', () {
    test('cada ajuste al inicio de su día; con todo cargado entran también los más viejos', () {
      final rows = withAdjustments(_movements, _adjustments, complete: true);
      expect(rows.map((r) => r is Movement ? r.id : (r as BalanceAdjustment).id), [
        'm1',
        'aj2',
        'm2',
        'm3',
        'aj1',
      ]);
    });

    test('con páginas por cargar, solo los de los días ya visibles', () {
      final rows = withAdjustments(_movements, _adjustments, complete: false);
      expect(rows.whereType<BalanceAdjustment>().map((a) => a.id), ['aj2']);
    });

    test('sin movimientos, los ajustes solos', () {
      expect(withAdjustments(const [], _adjustments, complete: true), _adjustments);
      expect(withAdjustments(const [], _adjustments, complete: false), isEmpty);
    });
  });

  group('la lista', () {
    late FakeMovementsRepository movements;
    late FakeMoneyRepository money;

    setUp(() {
      movements = FakeMovementsRepository()..onList = ((q) async => _page(q, _movements));
      money = FakeMoneyRepository()..onAdjustments = (_, _) async => _adjustments;
    });

    testWidgets('pide los del periodo y los intercala en gris al inicio de su día', (tester) async {
      await _pump(tester, movements, money);
      expect(money.calls, contains('adjustments 2026-11-01 2026-11-30'));
      expect(find.text('Ajuste de saldo'), findsNWidgets(2));
      expect(find.text('Ajuste · no es un ingreso'), findsOneWidget);
      expect(find.text('Ajuste · no es un gasto'), findsOneWidget);
      expect(find.text('+${_m(150000)}'), findsOneWidget);
      expect(find.text('−${_m(150000)}'), findsOneWidget);
      final up = tester.getTopLeft(find.text('Ajuste · no es un ingreso')).dy;
      expect(_y(tester, 'Almuerzo') < up && up < _y(tester, 'Mercado'), isTrue);
      expect(_y(tester, 'Ajuste · no es un gasto'), greaterThan(_y(tester, 'Taxi')));
      expect(find.text('15 NOV'), findsOneWidget);
      // El conteo es de movimientos: los ajustes no cuentan.
      expect(find.text('3 movimientos'), findsOneWidget);
    });

    testWidgets('con un filtro puesto no aparecen', (tester) async {
      await _pump(tester, movements, money);
      await tester.tap(find.text('Gastos'));
      await tester.pumpAndSettle();
      expect(find.text('Ajuste de saldo'), findsNothing);
      expect(find.text('Almuerzo'), findsOneWidget);
    });

    testWidgets('si /adjustments falla, la lista se ve igual, sin ellos', (tester) async {
      money.onAdjustments = (_, _) async => throw serverError;
      await _pump(tester, movements, money);
      expect(find.text('Ajuste de saldo'), findsNothing);
      expect(find.text('Almuerzo'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('mientras llega la primera página, o si falla, no salen ajustes sueltos', (tester) async {
      final page = Completer<MovementPage>();
      movements.onList = (q) => page.future;
      await _pump(tester, movements, money, settle: false);
      expect(money.calls, contains('adjustments 2026-11-01 2026-11-30'));
      expect(find.text('Cargando…'), findsOneWidget);
      expect(find.text('Ajuste de saldo'), findsNothing);
      page.complete(_page(const MovementQuery(), _movements));
      await tester.pumpAndSettle();
      expect(find.text('Ajuste de saldo'), findsNWidgets(2));

      movements.onList = (q) async => throw serverError;
      await _pump(tester, movements, money);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Ajuste de saldo'), findsNothing);
    });

    testWidgets('sin movimientos pero con un ajuste: el ajuste, no «No hay movimientos»', (tester) async {
      movements.onList = (q) async => _page(q, const []);
      await _pump(tester, movements, money);
      expect(find.text('Ajuste de saldo'), findsNWidgets(2));
      expect(find.text('No hay movimientos en noviembre.'), findsNothing);
    });

    testWidgets('al tocarlo, la hoja con el saldo de antes, el de después y la diferencia', (tester) async {
      await _pump(tester, movements, money);
      await tester.tap(find.text('Ajuste · no es un gasto'));
      await tester.pumpAndSettle();
      expect(
        find.text('Corregiste tu saldo el 15 nov 2026. No cuenta como ingreso ni como gasto.'),
        findsOneWidget,
      );
      expect(find.text('Saldo antes'), findsOneWidget);
      expect(find.text(_m(500000)), findsOneWidget);
      expect(find.text('Saldo después'), findsOneWidget);
      expect(find.text(_m(350000)), findsOneWidget);
      expect(find.text('Diferencia'), findsOneWidget);
      expect(find.text('−${_m(150000)}'), findsNWidgets(2));
    });

    testWidgets('con montos ocultos, ni la fila ni la hoja muestran un dígito', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, movements, money, hidden: true);
      expect(find.textContaining('150.000'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('El saldo subió Monto oculto')), findsOneWidget);
      await tester.tap(find.text('Ajuste · no es un ingreso'));
      await tester.pumpAndSettle();
      for (final digits in ['300.000', '450.000', '150.000']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      handle.dispose();
    });

    testWidgets('deslizar para recargar también los vuelve a pedir', (tester) async {
      await _pump(tester, movements, money);
      final before = money.count('adjustments');
      await tester.fling(find.text('¿En qué se te fue?'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(money.count('adjustments'), before + 1);
    });

    testWidgets('320 de ancho con letra al doble: la fila y la hoja sin desbordes', (tester) async {
      money.onAdjustments = (_, _) async => const [
        BalanceAdjustment(id: 'x', before: 0, after: 9999999999.99, date: '2026-11-21'),
      ];
      await _pump(tester, movements, money, size: const Size(320, 568), textScale: 2);
      expect(tester.takeException(), isNull);
      // La lista se arma a medida que se desplaza.
      await tester.scrollUntilVisible(
        find.text('Ajuste de saldo'),
        200,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuste de saldo'));
      await tester.pumpAndSettle();
      expect(find.text('Diferencia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
