// Tarjetas de la demostración: un almacén por usuario aparte de DemoState; la semilla de planListo es
// la misma del aviso del Inicio; los recorridos guardan (crear, editar, pagar, ajustar, borrar) y el
// aviso, el detalle y Movimientos dicen lo mismo; los escenarios fijos no escriben (demoNoBackend).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/data/demo_cards_repository.dart';
import 'package:rinde_mobile/features/cards/data/demo_cards_store.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/demo_home_repository.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';

const _newCard = {
  'network': 'mastercard',
  'tier': 'gold',
  'last4': '5555',
  'limit': 1000000,
  'available': 800000,
  'paymentDay': 25,
};

MovementInput _purchase(String card, {num amount = 50000, int? installments}) => MovementInput(
  type: MovementType.expense,
  amount: amount,
  description: 'Mercado',
  date: '2026-11-22',
  card: card,
  installments: installments,
);

void main() {
  late MemoryJsonListStore cardsStore;
  late MemoryJsonListStore movementsStore;
  late ProviderContainer c;

  setUp(() {
    cardsStore = MemoryJsonListStore();
    movementsStore = MemoryJsonListStore();
    c = ProviderContainer.test(
      overrides: [
        demoCardsStoreProvider.overrideWithValue(cardsStore),
        demoMovementsStoreProvider.overrideWithValue(movementsStore),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
    );
    c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
  });

  DemoCardsRepository cards(String userId) => c.read(demoCardsRepositoryProvider(userId));
  DemoHomeRepository home(String userId) => c.read(demoHomeRepositoryProvider(userId));
  DemoMovementsRepository movements(String userId) => c.read(demoMovementsRepositoryProvider(userId));

  group('escenario fijo planListo', () {
    test('la semilla «Mi Visa» es la misma del aviso del Inicio; su historial no inventa compras', () async {
      final list = await cards('demo-planListo').list();
      expect(list.single.name, 'Mi Visa');
      expect(list.single.used, 320000);
      final notice = (await home('demo-planListo').cards()).single;
      expect((notice.id, notice.used, notice.daysToPayment), (list.single.id, 320000, 2));
      expect(await cards('demo-planListo').movements(list.single.id), isEmpty);
    });

    test('las escrituras no llegan a ningún servidor: demoNoBackend', () async {
      final repo = cards('demo-planListo');
      final noBackend = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend));
      await expectLater(repo.create(_newCard), noBackend);
      await expectLater(repo.update('demo-tarjeta', {'limit': 2000000}), noBackend);
      await expectLater(repo.pay('demo-tarjeta', amount: 1, date: '2026-11-22'), noBackend);
      await expectLater(repo.syncWithBank('demo-tarjeta', {'available': 1}), noBackend);
      await expectLater(repo.delete('demo-tarjeta'), noBackend);
      expect(cardsStore.data, isEmpty);
    });

    test('una compra anotada con la semilla suma en su deuda, su historial y el aviso', () async {
      await movements('demo-planListo').create(_purchase('demo-tarjeta', installments: 3), localId: 'm-1');
      final card = (await cards('demo-planListo').list()).single;
      expect(card.used, 370000);
      expect(card.available, 1130000);
      final history = await cards('demo-planListo').movements('demo-tarjeta');
      expect((history.single.kind, history.single.installments), (CardMovementKind.purchase, 3));
      expect((await home('demo-planListo').cards()).single.used, 370000);
      final saved = (await movements('demo-planListo').list(const MovementQuery())).items.single;
      expect((saved.card?.name, saved.card?.last4, saved.installments), ('Mi Visa', '4242', 3));
    });

    test('sin tarjetas (otro escenario fijo): lista vacía y anotar con tarjeta es 422 en «card»', () async {
      expect(await cards('demo-teFaltan').list(), isEmpty);
      await expectLater(
        movements('demo-teFaltan').create(_purchase('demo-tarjeta'), localId: 'm-1'),
        throwsA(isA<ApiException>().having((e) => e.fields['card'], 'card', 'No es una de tus tarjetas')),
      );
    });
  });

  group('recorrido movimientos', () {
    const user = 'demo-movimientos';

    test('crear guarda en su almacén (no en DemoState) y el aviso del Inicio la ve', () async {
      final created = await cards(user).create(_newCard);
      expect(created.used, 200000, reason: 'cupo − disponible');
      expect(created.name, 'Mastercard Gold ••5555', reason: 'el nombre por defecto del servidor');
      expect(cardsStore.data.keys, [user]);
      expect((await home(user).cards()).single.id, created.id);
      await expectLater(
        cards(user).create(_newCard),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CARD_EXISTS')),
      );
    });

    test('comprar no cambia el pago; pagar baja lo usado, marca el ciclo y cambia el aviso', () async {
      final created = await cards(user).create(_newCard);
      await movements(user).create(_purchase(created.id), localId: 'm-1');
      expect((await cards(user).get(created.id)).used, 250000);

      await cards(user).pay(created.id, amount: 250000, date: '2026-11-22');
      final paid = await cards(user).get(created.id);
      expect((paid.used, paid.paidThisCycle), (0, true));
      expect((await home(user).cards()).single.paidThisCycle, isTrue);
      final history = await cards(user).movements(created.id);
      expect([
        for (final m in history) m.kind,
      ], containsAll([CardMovementKind.purchase, CardMovementKind.payment]));

      final payment = history.firstWhere((m) => m.kind == CardMovementKind.payment);
      await cards(user).deletePayment(created.id, payment.id);
      expect((await cards(user).get(created.id)).used, 250000);
    });

    test('editar: el cupo no baja de lo usado y available se rechaza', () async {
      final created = await cards(user).create(_newCard);
      await expectLater(
        cards(user).update(created.id, {'limit': 100000}),
        throwsA(isA<ApiException>().having((e) => e.fields.keys, 'campo', ['limit'])),
      );
      await expectLater(
        cards(user).update(created.id, {'available': 1}),
        throwsA(isA<ApiException>().having((e) => e.fields.keys, 'campo', ['available'])),
      );
      final edited = await cards(user).update(created.id, {'name': 'Mi Master', 'limit': 2000000});
      expect((edited.name, edited.limit, edited.used), ('Mi Master', 2000000, 200000));
    });

    test('ajustar con el banco de más crea «Cargos del banco · {nombre}» en Movimientos', () async {
      final created = await cards(user).create(_newCard);
      final charge = await cards(user)
          .syncWithBank(created.id, {'available': 750000, 'statementTotal': 250000});
      expect(charge, 50000);
      final card = await cards(user).get(created.id);
      expect((card.used, card.statementTotal), (250000, 250000));
      final charges = (await movements(user).list(const MovementQuery())).items;
      expect(charges.single.description, 'Cargos del banco · Mastercard Gold ••5555');
      expect(charges.single.card?.id, created.id);
      // Repetirlo con el mismo disponible no crea nada (diferencia 0).
      expect(await cards(user).syncWithBank(created.id, {'available': 750000}), isNull);
    });

    test('borrar: sus compras quedan con «Tarjeta eliminada»', () async {
      final created = await cards(user).create(_newCard);
      await movements(user).create(_purchase(created.id), localId: 'm-1');
      await cards(user).delete(created.id);
      expect(await cards(user).list(), isEmpty);
      final saved = (await movements(user).list(const MovementQuery())).items.single;
      expect(saved.card?.deleted, isTrue);
    });

    test('el panel puede hacer fallar las lecturas y las escrituras de tarjetas', () async {
      final controls = c.read(demoControlsProvider.notifier);
      controls.failNext(DemoCardsOperation.list, DemoFailure.server);
      await expectLater(cards(user).list(), throwsA(isA<ApiException>()));
      expect(await cards(user).list(), isEmpty, reason: 'falla una sola vez');
      controls.failNext(DemoCardsOperation.write, DemoFailure.network);
      await expectLater(
        cards(user).create(_newCard),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
      );
      expect(cardsStore.data[user], isNull);
    });

    test('cada usuario demo tiene sus tarjetas', () async {
      await cards(user).create(_newCard);
      expect(await cards('demo-nuevo').list(), isEmpty);
    });

    test('el extracto se va como en el servidor: vencido antes del próximo pago o ya pagado', () async {
      final created = await cards(user).create(_newCard);
      // Vence el 20 y el próximo pago es el 25: el servidor no lo muestra.
      await cards(user).syncWithBank(created.id, {
        'available': 800000,
        'statementTotal': 200000,
        'statementDueDate': '2026-11-20',
      });
      var card = await cards(user).get(created.id);
      expect((card.statementTotal, card.statementDueDate), (null, null));

      await cards(user).syncWithBank(created.id, {
        'available': 800000,
        'statementTotal': 200000,
        'statementDueDate': '2026-12-30',
      });
      await cards(user).pay(created.id, amount: 100000, date: '2026-11-22');
      expect((await cards(user).get(created.id)).statementTotal, 200000, reason: 'falta pagar parte');
      await cards(user).pay(created.id, amount: 100000, date: '2026-11-22');
      card = await cards(user).get(created.id);
      // «Lo que debes $0» junto a un extracto de 200 000 invitaba a pagarlo dos veces.
      expect((card.used, card.statementTotal), (0, null));
    });

    test('editar la tarjeta cambia la que muestran sus compras (nombre y últimos 4)', () async {
      final created = await cards(user).create(_newCard);
      await movements(user).create(_purchase(created.id), localId: 'm-1');
      await cards(user).update(created.id, {'last4': '6666'});
      final saved = (await movements(user).list(const MovementQuery())).items.single;
      expect((saved.card?.name, saved.card?.last4), ('Mastercard Gold ••6666', '6666'));
    });

    test('editar una compra con su tarjeta ya borrada la conserva sin validarla, como el servidor', () async {
      final created = await cards(user).create(_newCard);
      final bought = await movements(user).create(_purchase(created.id, installments: 3), localId: 'm-1');
      await cards(user).delete(created.id);
      // Una pantalla vieja manda la tarjeta guardada (transactions.service.js:296-297 no la revalida).
      final edited = await movements(user).update(
        bought.id,
        MovementInput(
          type: MovementType.expense,
          amount: 60000,
          description: 'Mercado',
          date: '2026-11-22',
          card: created.id,
          installments: 3,
        ),
      );
      expect(
        (edited.amount, edited.card?.id, edited.card?.deleted, edited.installments),
        (60000, created.id, true, 3),
      );
    });
  });
}
