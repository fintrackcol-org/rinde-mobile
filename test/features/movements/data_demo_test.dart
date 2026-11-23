import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';

MovementInput _input({
  MovementType type = MovementType.expense,
  num amount = 12500,
  String description = 'Almuerzo',
  String date = '2026-11-21',
  String? category,
}) => MovementInput(type: type, amount: amount, description: description, date: date, category: category);

void main() {
  late MemoryJsonListStore store;
  late ProviderContainer c;

  setUp(() {
    store = MemoryJsonListStore();
    c = ProviderContainer.test(
      overrides: [
        demoMovementsStoreProvider.overrideWithValue(store),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
    );
    c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
  });

  DemoMovementsRepository repo(String userId) => c.read(demoMovementsRepositoryProvider(userId));

  test('crear, leer, editar y borrar, guardado por usuario', () async {
    final ana = repo('demo-nuevo');
    expect(ana.isDemo, isTrue);
    final created = await ana.create(_input(category: 'alimentacion'), localId: 'm-1');
    expect(created.source, 'manual');
    expect(store.data.keys, ['demo-nuevo']);
    expect((await ana.get(created.id)).description, 'Almuerzo');

    final updated = await ana.update(created.id, _input(amount: 9000, description: 'Taxi'));
    expect(updated.amount, 9000);
    expect(updated.source, 'sin_clasificar');
    expect(updated.createdAt, created.createdAt);

    await ana.delete(created.id);
    expect((await ana.list(const MovementQuery())).total, 0);
    await expectLater(
      ana.get(created.id),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
    );
  });

  test('llavero ilegible: falla en vez de leerlo vacío y no pisa lo anotado', () async {
    final ana = repo('demo-nuevo');
    await ana.create(_input(), localId: 'm-1');
    store.failReads = true;
    await expectLater(ana.create(_input(), localId: 'm-2'), throwsA(isA<StateError>()));
    await expectLater(demoMovementTotals(store, 'demo-nuevo', '2026-11-22'), throwsA(isA<StateError>()));
    store.failReads = false;
    expect((await ana.list(const MovementQuery())).total, 1);
  });

  test('otro usuario demo no ve ni toca los movimientos ajenos', () async {
    final created = await repo('demo-nuevo').create(_input(), localId: 'm-1');
    final beto = repo('demo-movimientos');
    expect((await beto.list(const MovementQuery())).items, isEmpty);
    await expectLater(beto.delete(created.id), throwsA(isA<ApiException>()));
    expect((await repo('demo-nuevo').list(const MovementQuery())).total, 1);
  });

  test('el mismo localId devuelve el mismo movimiento, como el servidor', () async {
    final first = await repo('demo-nuevo').create(_input(), localId: 'm-1');
    final again = await repo('demo-nuevo').create(_input(), localId: 'm-1');
    expect(again.id, first.id);
    expect((await repo('demo-nuevo').list(const MovementQuery())).total, 1);
  });

  test('filtra, ordena del más reciente y pagina', () async {
    final r = repo('demo-nuevo');
    await r.create(
      _input(date: '2026-11-01', description: 'Taxi'),
      localId: 'a',
    );
    await r.create(
      _input(date: '2026-11-20', description: 'Mercado'),
      localId: 'b',
    );
    await r.create(
      _input(type: MovementType.income, date: '2026-11-15', description: 'Pago'),
      localId: 'c',
    );
    final all = await r.list(const MovementQuery(pageSize: 2));
    expect([for (final m in all.items) m.description], ['Mercado', 'Pago']);
    expect(all.hasMore, isTrue);
    final page2 = await r.list(const MovementQuery(page: 2, pageSize: 2));
    expect([for (final m in page2.items) m.description], ['Taxi']);
    final income = await r.list(const MovementQuery(type: MovementType.income));
    expect([for (final m in income.items) m.description], ['Pago']);
    final search = await r.list(const MovementQuery(search: 'TAX', from: '2026-11-01', to: '2026-11-05'));
    expect(search.total, 1);
  });

  test(
    'rechaza lo que rechaza el servidor: monto, descripción, fecha futura, categoría de otro tipo',
    () async {
      Future<Map<String, String>> fields(MovementInput input) async {
        try {
          await repo('demo-nuevo').create(input, localId: 'x');
        } on ApiException catch (e) {
          expect(e.status, 422);
          return e.fields;
        }
        fail('debía rechazarse');
      }

      expect((await fields(_input(amount: 0))).keys, ['amount']);
      expect((await fields(_input(description: '  '))).keys, ['description']);
      expect((await fields(_input(date: '2026-11-23'))).keys, ['date']);
      expect((await fields(_input(category: 'salario'))).keys, ['category']);
    },
  );

  test('categorías de la demo separadas por tipo, Otros al final', () async {
    final lists = await repo('demo-nuevo').categories();
    expect(lists.income.map((c) => c.key), [
      'salario',
      'freelance',
      'inversion_rendimientos',
      'otros_ingresos',
    ]);
    expect(lists.expense.last.key, 'otros');
    expect(lists.expense, hasLength(11));
  });

  test('totales del mes para el Inicio demo: lo apartado no es gasto', () async {
    final r = repo('demo-nuevo');
    await r.create(_input(amount: 10000.1), localId: 'a');
    await r.create(_input(amount: 0.2), localId: 'b');
    await r.create(_input(amount: 50000, category: 'ahorro_inversion'), localId: 'c');
    await r.create(_input(type: MovementType.income, amount: 2500000), localId: 'd');
    await r.create(_input(amount: 999, date: '2026-10-31'), localId: 'e');
    final totals = await r.monthTotals('2026-11-22');
    expect(totals.month, '2026-11');
    expect(totals.income, 2500000);
    expect(totals.expense, 10000.3);
  });

  test('con la demo «sin conexión» falla por red', () async {
    c.read(demoControlsProvider.notifier).setOffline(true);
    await expectLater(
      repo('demo-nuevo').create(_input(), localId: 'm-1'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
    );
  });
}
