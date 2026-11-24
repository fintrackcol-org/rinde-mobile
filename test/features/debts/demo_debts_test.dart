// Cuentas de la demostración: un almacén por usuario aparte de DemoState; la semilla de planListo
// («Laura» y «Tío Jorge», con state.fixed y abonos sin movimiento); los escenarios fijos no escriben
// (demoNoBackend); los recorridos guardan y recalculan con debt_schedule, y con la casilla agregan el
// movimiento al almacén de Movimientos de la demo (borrar el abono lo borra).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/debts/data/debt_models.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_repository.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_store.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart' show MovementQuery;
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';

const _journey = 'demo-movimientos';

Map<String, dynamic> _body({
  String kind = 'receivable',
  String person = 'Ana',
  num amount = 90000,
  int? installments,
  String? frequency,
  String? dueDate,
}) => {
  'kind': kind,
  'person': person,
  'amount': amount,
  'loanDate': '2026-11-01',
  'dueDate': dueDate,
  'installments': installments,
  'frequency': frequency,
  'note': null,
};

void main() {
  late MemoryJsonListStore debtsStore;
  late MemoryJsonListStore movementsStore;
  late ProviderContainer c;

  setUp(() {
    debtsStore = MemoryJsonListStore();
    movementsStore = MemoryJsonListStore();
    c = ProviderContainer.test(
      overrides: [
        demoDebtsStoreProvider.overrideWithValue(debtsStore),
        demoMovementsStoreProvider.overrideWithValue(movementsStore),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
    );
    c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
  });

  DemoDebtsRepository debts(String userId) => c.read(demoDebtsRepositoryProvider(userId));
  Future<List<Map<String, dynamic>>> movements(String userId) async => [
    for (final m in await movementsStore.read(userId) ?? const <Object?>[])
      Map<String, dynamic>.from(m! as Map),
  ];

  group('escenario fijo planListo', () {
    test('Laura me debe 60.000 en 3 cuotas con un abono de 20.000; a Tío Jorge le debo 120.000', () async {
      final list = await debts('demo-planListo').list();
      // Orden del servidor: pendientes por fecha (Tío Jorge vence antes que la próxima cuota de Laura).
      final [jorge, laura] = list.items;
      expect((laura.person, laura.kind, laura.amount), ('Laura', DebtKind.receivable, 60000));
      expect((laura.installments, laura.frequency), (3, DebtFrequency.monthly));
      expect((laura.paid, laura.pending, laura.paidInstallments), (20000, 40000, 1));
      expect((laura.nextInstallment!.number, laura.nextInstallment!.amount), (2, 20000));
      expect(laura.dueDate, laura.nextInstallment!.date, reason: 'al leer, dueDate es la próxima cuota');
      expect(laura.firstDueDate, '2026-11-07');
      expect(laura.payments.single.transactionId, isNull, reason: 'ningún movimiento dice venir de él');
      expect(
        (jorge.person, jorge.kind, jorge.amount, jorge.installments),
        ('Tío Jorge', DebtKind.payable, 120000, null),
      );
      expect(jorge.dueDate, '2026-12-02');
      expect((list.receivable, list.payable), (40000, 120000));
      expect(await movements('demo-planListo'), isEmpty);
    });

    test('los montos pasan por state.fixed (USD: miles de pesos → dólares)', () async {
      final store = MemoryDemoStateStore();
      c = ProviderContainer.test(
        overrides: [
          demoDebtsStoreProvider.overrideWithValue(debtsStore),
          demoMovementsStoreProvider.overrideWithValue(movementsStore),
          demoStateStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        ],
      );
      c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
      await c
          .read(demoOnboardingRepositoryProvider('demo-planListo'))
          .saveRegion(country: 'US', language: 'en');
      final laura = (await debts('demo-planListo').list()).items.firstWhere((d) => d.person == 'Laura');
      expect((laura.amount, laura.paid), (60, 20));
    });

    test('las escrituras no llegan a ningún servidor: demoNoBackend', () async {
      final repo = debts('demo-planListo');
      final noBackend = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend));
      await expectLater(repo.create(_body()), noBackend);
      await expectLater(repo.update('demo-cuenta-laura', {'amount': 1}), noBackend);
      await expectLater(
        repo.pay('demo-cuenta-laura', amount: 1, date: '2026-11-22', createTransaction: true),
        noBackend,
      );
      await expectLater(repo.settle('demo-cuenta-laura', createTransaction: true), noBackend);
      await expectLater(repo.deletePayment('demo-cuenta-laura', 'demo-abono-laura'), noBackend);
      await expectLater(repo.delete('demo-cuenta-jorge'), noBackend);
      expect(debtsStore.data, isEmpty);
      expect(await movements('demo-planListo'), isEmpty);
    });

    test('los otros escenarios fijos no tienen cuentas', () async {
      expect((await debts('demo-teFaltan').list()).items, isEmpty);
      expect((await debts('demo-negativo').list()).items, isEmpty);
    });
  });

  group('recorridos', () {
    test('crear en cuotas: lo recalcula con debt_schedule y lo guarda por usuario', () async {
      await debts(_journey)
          .create(_body(person: '  Ana ', installments: 3, frequency: 'monthly', dueDate: '2027-01-31'));
      final ana = (await debts(_journey).list()).items.single;
      expect((ana.person, ana.amount, ana.pending, ana.paidInstallments), ('Ana', 90000, 90000, 0));
      expect((ana.nextInstallment!.date, ana.nextInstallment!.amount), ('2027-01-31', 30000));
      expect(ana.firstDueDate, '2027-01-31');
      expect((await debts('demo-sinPlan').list()).items, isEmpty, reason: 'otro usuario no la ve');
    });

    test('las validaciones del servidor que se ven: cuotas, frecuencia y fecha', () async {
      await expectLater(
        debts(_journey).create(_body(installments: 1, dueDate: '2026-12-01')),
        throwsA(
          isA<ApiException>().having(
            (e) => e.fields.keys,
            'campos',
            containsAll(['installments', 'frequency']),
          ),
        ),
      );
      await expectLater(
        debts(_journey).create(_body(dueDate: '2026-10-01')),
        throwsA(isA<ApiException>().having((e) => e.fields['loanDate'], 'loanDate', isNotNull)),
      );
    });

    test('abonar con la casilla: «Abono de X» en Movimientos y la cuota siguiente', () async {
      await debts(_journey).create(_body(installments: 3, frequency: 'monthly', dueDate: '2026-12-01'));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 30000, date: '2026-11-22', createTransaction: true);
      final ana = (await debts(_journey).list()).items.single;
      expect(
        (ana.paid, ana.pending, ana.paidInstallments, ana.nextInstallment!.number),
        (30000, 60000, 1, 2),
      );
      expect(ana.dueDate, '2027-01-01', reason: 'el dueDate leído pasa a la próxima cuota');
      final [movement] = await movements(_journey);
      expect(
        (movement['type'], movement['description'], movement['category'], movement['amount']),
        ('ingreso', 'Abono de Ana', 'otros_ingresos', 30000),
      );
      expect(ana.payments.single.transactionId, movement['id']);
      // Y se ve en Movimientos de la demo.
      final page = await c.read(demoMovementsRepositoryProvider(_journey)).list(const MovementQuery());
      expect(page.items.single.description, 'Abono de Ana');
    });

    test('abonar SIN la casilla no anota nada; «Abono a X» si es lo que debo', () async {
      await debts(_journey).create(_body(kind: 'payable', person: 'Beto', dueDate: '2026-12-01'));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 1000, date: '2026-11-22', createTransaction: false);
      expect(await movements(_journey), isEmpty);
      await debts(_journey).pay(id, amount: 1000, date: '2026-11-22', createTransaction: true);
      final [movement] = await movements(_journey);
      expect((movement['type'], movement['description']), ('gasto', 'Abono a Beto'));
    });

    test('el abono que completa la cuenta la salda con UN solo movimiento (y sin enlace)', () async {
      await debts(_journey).create(_body(amount: 50000));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 50000, date: '2026-11-22', createTransaction: true);
      final ana = (await debts(_journey).list()).items.single;
      expect((ana.settled, ana.pending, ana.transactionId), (true, 0, null));
      expect(await movements(_journey), hasLength(1));
      await expectLater(
        debts(_journey).settle(id, createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
      );
      expect(await movements(_journey), hasLength(1), reason: 'saldar otra vez no crea otro');
    });

    test('saldar después de abonos: el movimiento va solo por lo que faltaba', () async {
      await debts(_journey).create(_body(kind: 'payable', person: 'Beto', amount: 100000));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 30000, date: '2026-11-22', createTransaction: false);
      await debts(_journey).settle(id, createTransaction: true);
      final beto = (await debts(_journey).list()).items.single;
      final [movement] = await movements(_journey);
      expect(
        (movement['description'], movement['amount'], movement['type']),
        ('Le pagué a Beto', 70000, 'gasto'),
      );
      expect((beto.settled, beto.transactionId), (true, movement['id']));
    });

    test('borrar un abono borra su movimiento; en una cuenta saldada da 404', () async {
      await debts(_journey).create(_body(person: 'Ana', amount: 90000));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 10000, date: '2026-11-22', createTransaction: true);
      final payment = (await debts(_journey).list()).items.single.payments.single;
      final updated = await debts(_journey).deletePayment(id, payment.id);
      expect(updated.payments, isEmpty);
      expect(updated.paid, 0);
      expect(await movements(_journey), isEmpty);

      await debts(_journey).pay(id, amount: 90000, date: '2026-11-22', createTransaction: false);
      final last = (await debts(_journey).list()).items.single.payments.single;
      await expectLater(
        debts(_journey).deletePayment(id, last.id),
        throwsA(isA<ApiException>().having((e) => e.serverMessage, 'mensaje', 'Abono no encontrado')),
      );
    });

    test('no pasa de lo pendiente, no acepta fechas futuras y una saldada no se edita', () async {
      await debts(_journey).create(_body(amount: 1000));
      final id = (await debts(_journey).list()).items.single.id;
      await expectLater(
        debts(_journey).pay(id, amount: 1001, date: '2026-11-22', createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 422)),
      );
      await expectLater(
        debts(_journey).pay(id, amount: 1, date: '2026-11-23', createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.fields['date'], 'date', 'No puede ser una fecha futura')),
      );
      await expectLater(
        debts(_journey).update(id, {'kind': 'payable'}),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 422)),
      );
      await debts(_journey).settle(id, createTransaction: false);
      await expectLater(
        debts(_journey).update(id, {'amount': 5000}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_SETTLED')),
      );
    });

    test('editar: de una vez a cuotas recalcula; borrar deja los movimientos', () async {
      await debts(_journey).create(_body(amount: 90000));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 30000, date: '2026-11-22', createTransaction: true);
      await debts(_journey).update(
        id,
        {..._body(amount: 90000), 'installments': 3, 'frequency': 'biweekly', 'dueDate': '2026-11-15'}
          ..remove('kind'),
      );
      final ana = (await debts(_journey).list()).items.single;
      expect((ana.paidInstallments, ana.nextInstallment!.date), (1, '2026-11-30'));
      await debts(_journey).delete(id);
      expect((await debts(_journey).list()).items, isEmpty);
      expect(await movements(_journey), hasLength(1), reason: 'como el servidor: los movimientos quedan');
    });

    test('el panel puede hacer fallar la lectura y las escrituras', () async {
      final controls = c.read(demoControlsProvider.notifier);
      controls.failNext(DemoDebtsOperation.list, DemoFailure.network);
      await expectLater(debts(_journey).list(), throwsA(isA<ApiException>()));
      controls.failNext(DemoDebtsOperation.write, DemoFailure.server);
      await expectLater(
        debts(_journey).create(_body()),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(await debts(_journey).list(), isA<DebtsList>());
    });

    test('un llavero ilegible: la lista se ve vacía pero NO se escribe encima', () async {
      await debts(_journey).create(_body());
      debtsStore.failReads = true;
      expect((await debts(_journey).list()).items, isEmpty);
      await expectLater(debts(_journey).create(_body()), throwsA(isA<StateError>()));
      debtsStore.failReads = false;
      expect((await debts(_journey).list()).items, hasLength(1));
    });

    test('un llavero de MOVIMIENTOS ilegible: abonar, saldar y borrar un abono fallan sin pisarlo', () async {
      await debts(_journey).create(_body(person: 'Ana', amount: 90000));
      final id = (await debts(_journey).list()).items.single.id;
      await debts(_journey).pay(id, amount: 10000, date: '2026-11-22', createTransaction: true);
      final before = await movements(_journey);
      final payment = (await debts(_journey).list()).items.single.payments.single;
      movementsStore.failReads = true;
      await expectLater(
        debts(_journey).pay(id, amount: 1000, date: '2026-11-22', createTransaction: true),
        throwsA(isA<StateError>()),
      );
      await expectLater(debts(_journey).settle(id, createTransaction: true), throwsA(isA<StateError>()));
      await expectLater(debts(_journey).deletePayment(id, payment.id), throwsA(isA<StateError>()));
      movementsStore.failReads = false;
      expect(await movements(_journey), before);
      final ana = (await debts(_journey).list()).items.single;
      expect(
        (ana.payments.single.id, ana.settled),
        (payment.id, false),
        reason: 'la cuenta no quedó a medias',
      );
    });

    test('con la misma fecha (o las dos sin fecha) va primero la más nueva, como el servidor', () async {
      for (final (person, dueDate) in [
        ('Vieja', null),
        ('Nueva', null),
        ('Vieja con fecha', '2026-12-01'),
        ('Nueva con fecha', '2026-12-01'),
      ]) {
        await debts(_journey).create(_body(person: person, dueDate: dueDate));
      }
      final raw = [for (final d in (await debtsStore.read(_journey))!) Map<String, dynamic>.from(d! as Map)];
      for (final (i, d) in raw.indexed) {
        d['createdAt'] = '2026-11-0${i + 1}T10:00:00.000Z';
      }
      await debtsStore.write(_journey, raw);
      expect(
        [for (final d in (await debts(_journey).list()).items) d.person],
        ['Nueva con fecha', 'Vieja con fecha', 'Nueva', 'Vieja'],
      );
    });
  });
}
