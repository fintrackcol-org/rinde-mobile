// Ingresos y Gastos (etapa 8): lectura del resumen del periodo, las cuentas de la web portadas en
// centavos (balance, «Otras N categorías», Kakeibo, días transcurridos), el contrato del GET y la demo
// (la semilla del escenario solo en el mes y el año de hoy, más lo anotado en su fecha).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/demo_home_repository.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/presentation/list/movement_dates.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/period/data/period_models.dart';
import 'package:rinde_mobile/features/period/data/period_repository.dart';

import '../../support/fake_http.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);

Map<String, dynamic> _summary({num savings = 200000}) => {
  'period': 'month',
  'from': '2026-11-01',
  'to': '2026-11-30',
  'income': {
    'total': 0.3,
    'byCategory': [
      {'category': 'salario', 'total': 0.3, 'percentage': 100},
    ],
  },
  'expense': {
    'total': 0.1,
    'byCategory': [
      {'category': null, 'total': 0.1, 'percentage': 100},
    ],
  },
  'savings': {'total': savings},
  'timeSeries': const [],
};

Movement _expense(num amount, {String? kakeibo, String date = '2026-11-20', String? category}) => Movement(
  id: 'm$amount$kakeibo',
  type: MovementType.expense,
  amount: amount,
  description: 'x',
  source: 'manual',
  date: date,
  kakeibo: kakeibo,
  category: category,
);

void main() {
  group('modelos', () {
    test('el balance es ingresos menos gastos y ahorro, en centavos (sin residuos de 0.3 - 0.1)', () {
      final s = PeriodSummary.fromJson(_summary(savings: 0));
      expect((s.income.total, s.expense.total, s.balance), (0.3, 0.1, 0.2));
      expect(s.expense.byCategory.single.category, isNull, reason: 'sin clasificar');
      final withSavings = PeriodSummary.fromJson({..._summary(), 'savings': null});
      expect(withSavings.savings, 0, reason: 'un backend que aún no manda `savings`');
      expect(() => PeriodSummary.fromJson({..._summary(), 'from': 'nov'}), throwsA(isA<ContractException>()));
    });

    test(
      '«Por categoría»: hasta 6 filas tal cual; con 7, las 5 primeras y «Otras 2» sumadas en centavos',
      () {
        List<CategoryTotal> rows(int n) => [
          for (var i = 0; i < n; i++) CategoryTotal(category: 'c$i', total: 0.1, percentage: 10.05),
        ];
        expect(categoryRows(rows(6)).map((r) => r.key), ['c0', 'c1', 'c2', 'c3', 'c4', 'c5']);
        final seven = categoryRows(rows(7));
        expect(seven.map((r) => r.key), ['c0', 'c1', 'c2', 'c3', 'c4', 'otras']);
        expect((seven.last.others, seven.last.total, seven.last.percentage), (2, 0.2, 20.1));
      },
    );

    test('Kakeibo: suma por grupo en centavos; lo que no tiene grupo no cuenta en los porcentajes', () {
      final split = splitByKakeibo([
        _expense(0.1, kakeibo: 'deseo'),
        _expense(0.2, kakeibo: 'deseo'),
        _expense(0.7, kakeibo: 'necesidad'),
        _expense(500),
        _expense(1, kakeibo: 'otro'),
      ]);
      expect(
        (split.totals['deseo'], split.totals['necesidad'], split.grouped, split.ungrouped),
        (0.3, 0.7, 1, 2),
      );
      expect(split.shares['deseo'], closeTo(30, 1e-9));
      expect(splitByKakeibo(const []).shares.values, everyElement(0));
    });

    test('días del periodo: hasta hoy si es el actual, todo si ya pasó, al menos 1', () {
      final today = DateTime(2026, 11, 22);
      expect(elapsedDays('2026-11-01', '2026-11-30', today), 22);
      expect(elapsedDays('2026-10-01', '2026-10-31', today), 31);
      expect(elapsedDays('2026-11-22', '2026-11-28', today), 1);
    });
  });

  test('pide el resumen con el periodo y el día, como la web', () async {
    final holder = SessionHolder(MemorySessionStorage(_session));
    await holder.load();
    addTearDown(holder.dispose);
    final http = FakeHttpAdapter((_) => jsonBody(200, _summary()));
    final repo = ApiPeriodRepository(
      ApiClient(
        config: const AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa'),
        session: holder,
        adapter: http,
      ),
    );
    await repo.summary(MovementPeriod.week, '2026-11-22');
    expect(
      http.requests.single.uri.toString(),
      endsWith('/transactions/summary?period=week&date=2026-11-22'),
    );
  });

  group('demo', () {
    late ProviderContainer c;
    late MemoryJsonListStore movements;

    setUp(() {
      movements = MemoryJsonListStore();
      c = ProviderContainer.test(
        overrides: [
          demoMovementsStoreProvider.overrideWithValue(movements),
          demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        ],
      );
      c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
    });

    DemoPeriodRepository demo(String user) => DemoPeriodRepository(c.read(demoHomeRepositoryProvider(user)));

    test(
      'el mes de hoy dice lo mismo que «Este mes» del Inicio; la semana y otro mes, solo lo anotado',
      () async {
        const user = 'demo-movimientos';
        await movements.write(user, [
          _expense(30000, category: 'alimentacion').toJson(),
          _expense(50000, category: 'ahorro_inversion').toJson(),
          _expense(1000, date: '2026-10-05').toJson(),
        ]);
        final month = await demo(user).summary(MovementPeriod.month, '2026-11-22');
        final home = await c.read(demoHomeRepositoryProvider(user)).monthTotals('2026-11-22');
        expect((month.income.total, month.expense.total), (home.income, home.expense));
        expect(month.savings, 50000, reason: 'lo apartado no es gasto');
        expect(month.expense.byCategory.first.category, 'vivienda', reason: 'de mayor a menor');

        final week = await demo(user).summary(MovementPeriod.week, '2026-11-22');
        expect(
          (week.from, week.to, week.income.total, week.expense.total),
          ('2026-11-16', '2026-11-22', 0, 30000),
        );
        final october = await demo(user).summary(MovementPeriod.month, '2026-10-10');
        expect(october.expense.total, 1000);
      },
    );
  });
}
