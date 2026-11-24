import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/cards/application/cards_providers.dart';
import 'package:rinde_mobile/features/cards/data/cards_repository.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';

import '../../support/fake_cards_repository.dart';
import '../../support/fake_movements_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co', name: 'Beto'),
  accessToken: 'b',
  refreshToken: 's',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _ana));

  void enter(Session? session) => state = AsyncData(SessionState(session: session));
}

const _offline = ApiException(code: ApiCodes.network);

void main() {
  late FakeMovementsRepository repo;
  late FakeCardsRepository cards;
  late MemoryJsonListStore store;
  late ProviderContainer c;

  setUp(() {
    repo = FakeMovementsRepository();
    cards = FakeCardsRepository();
    store = MemoryJsonListStore();
    c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        movementsRepositoryProvider.overrideWithValue(repo),
        cardsRepositoryProvider.overrideWithValue(cards),
        pendingStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
    );
  });

  void enter(Session? session) => (c.read(sessionControllerProvider.notifier) as _Sessions).enter(session);
  MovementSaver saver() => c.read(movementSaverProvider);
  Future<PendingState> pending() => c.read(pendingMovementsProvider.future);
  List<Object?> saved(String userId) => store.data[userId] == null ? [] : jsonDecode(store.data[userId]!);

  test('localId: m- y 128 bits en hexadecimal, distinto cada vez', () {
    final id = MovementSaver.newLocalId();
    expect(id, matches(RegExp(r'^m-[0-9a-f]{32}$')));
    expect(MovementSaver.newLocalId(), isNot(id));
  });

  test('create manda el localId y un reintento del mismo borrador manda el mismo', () async {
    repo.onCreate = (_, _) async => throw const ApiException(code: 'INTERNAL_ERROR', status: 500);
    final localId = MovementSaver.newLocalId();
    await expectLater(saver().create(inputOf, localId: localId), throwsA(isA<ApiException>()));
    repo.onCreate = (input, id) async => movementOf('srv-$id');
    final created = await saver().create(inputOf, localId: localId);
    expect(repo.localIds, [localId, localId]);
    expect(created.pending, isFalse);
    // Un 500 no entra a la cola.
    expect((await pending()).items, isEmpty);
  });

  for (final code in [ApiCodes.network, ApiCodes.timeout]) {
    test('sin conexión ($code): queda en la cola guardada y vuelve como pendiente', () async {
      repo.onCreate = (_, _) async => throw ApiException(code: code);
      final result = await saver().create(inputOf, localId: 'm-1');
      expect(result.pending, isTrue);
      expect(result.localId, 'm-1');
      expect(result.amount, 12500);
      expect((await pending()).movements.single.id, 'm-1');
      expect(saved('a'), hasLength(1));
      expect((saved('a').single as Map)['localId'], 'm-1');
    });
  }

  test('reintentar el mismo borrador sin conexión no lo duplica en la cola', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    await saver().create(inputOf, localId: 'm-1');
    expect((await pending()).items, hasLength(1));
  });

  test('tope de 50: el 51 no se guarda y sale el error de red', () async {
    repo.onCreate = (_, _) async => throw _offline;
    for (var i = 0; i < kMaxPendingMovements; i++) {
      await saver().create(inputOf, localId: 'm-$i');
    }
    await expectLater(
      saver().create(inputOf, localId: 'm-extra'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
    );
    expect(saved('a'), hasLength(kMaxPendingMovements));
  });

  test('si no se pudo leer la cola guardada no se escribe encima', () async {
    store.data['a'] = jsonEncode([
      {'localId': 'm-viejo', 'input': inputOf.toJson(), 'queuedAt': '2026-11-21T00:00:00.000Z'},
    ]);
    store.failReads = true;
    repo.onCreate = (_, _) async => throw _offline;
    await expectLater(saver().create(inputOf, localId: 'm-1'), throwsA(isA<ApiException>()));
    expect((saved('a').single as Map)['localId'], 'm-viejo');
  });

  test('la cola es de cada usuario y sobrevive a reabrir', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-ana');
    enter(_beto);
    expect((await pending()).items, isEmpty);
    await saver().create(inputOf, localId: 'm-beto');
    expect([for (final p in saved('b')) (p as Map)['localId']], ['m-beto']);
    enter(_ana);
    expect([for (final p in (await pending()).items) p.localId], ['m-ana']);
  });

  test('retryPending: confirma con el mismo localId y vacía la cola', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    await saver().create(inputOf, localId: 'm-2');
    repo.onCreate = (input, id) async => movementOf('srv-$id');
    repo.localIds.clear();
    expect(await c.read(pendingMovementsProvider.notifier).retryPending(), 2);
    expect(repo.localIds, ['m-1', 'm-2']);
    expect((await pending()).items, isEmpty);
    expect(saved('a'), isEmpty);
  });

  test('retryPending: un 4xx sale de la cola con el mensaje del servidor; un error de red detiene', () async {
    repo.onCreate = (_, _) async => throw _offline;
    for (final id in ['m-1', 'm-2', 'm-3']) {
      await saver().create(inputOf, localId: id);
    }
    repo.onCreate = (input, id) async => switch (id) {
      'm-1' => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        fields: {'date': 'La fecha no puede ser futura'},
      ),
      _ => throw _offline,
    };
    expect(await c.read(pendingMovementsProvider.notifier).retryPending(), 0);
    final state = await pending();
    expect([for (final p in state.items) p.localId], ['m-2', 'm-3']);
    expect(state.rejected.single.movement.localId, 'm-1');
    expect(state.rejected.single.message, 'La fecha no puede ser futura');
    expect(repo.localIds.where((id) => id == 'm-3'), hasLength(1)); // solo el envío original
  });

  test('un rechazado sigue guardado al reabrir, no se reenvía, y «Descartar» lo borra', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    repo.onCreate = (_, _) async => throw const ApiException(code: ApiCodes.validation, status: 422);
    await c.read(pendingMovementsProvider.notifier).retryPending();
    c.invalidate(pendingMovementsProvider); // como cerrar y reabrir la app
    final reopened = await pending();
    expect(reopened.items, isEmpty);
    expect(reopened.rejected.single.movement.localId, 'm-1');
    final sent = repo.localIds.length;
    await c.read(pendingMovementsProvider.notifier).retryPending();
    expect(repo.localIds, hasLength(sent));
    await c.read(pendingMovementsProvider.notifier).clearRejected();
    expect(saved('a'), isEmpty);
  });

  test('si la cuenta cambia mientras va el envío, el gasto no entra en la cola de la otra', () async {
    await pending();
    repo.onCreate = (_, _) async {
      enter(_beto);
      throw _offline;
    };
    await expectLater(saver().create(inputOf, localId: 'm-1'), throwsA(isA<ApiException>()));
    expect(saved('b'), isEmpty);
    expect(saved('a'), isEmpty);
  });

  test('retryPending: 401 y 429 no descartan el movimiento', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    for (final status in [401, 429]) {
      repo.onCreate = (_, _) async => throw ApiException(code: 'X', status: status);
      await c.read(pendingMovementsProvider.notifier).retryPending();
      expect((await pending()).items, hasLength(1));
    }
  });

  test('crear con éxito un borrador que estaba en la cola lo saca de ella', () async {
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    repo.onCreate = (input, id) async => movementOf('srv-$id');
    await saver().create(inputOf, localId: 'm-1');
    expect((await pending()).items, isEmpty);
  });

  test('editar y borrar necesitan conexión: no hay cola', () async {
    repo.onUpdate = (_, _) async => throw _offline;
    repo.onDelete = (_) async => throw _offline;
    await expectLater(saver().update('x', inputOf), throwsA(isA<ApiException>()));
    await expectLater(saver().delete('x'), throwsA(isA<ApiException>()));
    expect((await pending()).items, isEmpty);
  });

  test('borrar: un 404 (ya estaba borrado) cuenta como hecho; otro error no', () async {
    repo.onDelete = (_) async => throw const ApiException(code: 'NOT_FOUND', status: 404);
    await saver().delete('x');
    repo.onDelete = (_) async => throw const ApiException(code: 'INTERNAL_ERROR', status: 500);
    await expectLater(saver().delete('x'), throwsA(isA<ApiException>()));
  });

  test('tras guardar se recarga la lista y se invalida el detalle', () async {
    c.listen(movementsControllerProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    c.listen(movementDetailProvider((_ana, 'x')), (_, _) {});
    await c.read(movementDetailProvider((_ana, 'x')).future);
    repo.calls.clear();
    await saver().update('x', inputOf);
    await c.read(movementDetailProvider((_ana, 'x')).future);
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, containsAll(['update x', 'list 1', 'get x']));
  });

  test('los pendientes salen primero en la lista, si cumplen los filtros', () async {
    repo.onList = (q) async => MovementPage(items: [movementOf('s1')], page: 1, pageSize: 20, total: 1);
    c.listen(movementsControllerProvider, (_, _) {});
    repo.onCreate = (_, _) async => throw _offline;
    await saver().create(inputOf, localId: 'm-1');
    await Future<void>.delayed(Duration.zero);
    expect([for (final m in c.read(movementsControllerProvider).items) m.id], ['m-1', 's1']);
    expect(c.read(movementsControllerProvider).items.first.pending, isTrue);
    await c
        .read(movementsControllerProvider.notifier)
        .setQuery(const MovementQuery(type: MovementType.income));
    expect([for (final m in c.read(movementsControllerProvider).items) m.id], ['s1']);
  });

  group('tarjeta en la cola (regla cardDropped)', () {
    const withCard = MovementInput(
      type: MovementType.expense,
      amount: 12500,
      description: 'Almuerzo',
      date: '2026-11-21',
      card: 't1',
      installments: 3,
    );

    test(
      'anotar con tarjeta: la app no resta nada; vuelve a pedir las tarjetas (lo usado lo da el servidor)',
      () async {
        final account = c.read(accountProvider);
        c.listen(cardsProvider(account), (_, _) {});
        await c.read(cardsProvider(account).future);
        expect(cards.calls, ['list']);
        await saver().create(withCard, localId: 'm-1');
        await pumpEventQueue();
        expect(cards.calls, ['list', 'list']);
        expect(repo.calls.where((call) => call.startsWith('create')), hasLength(1));
      },
    );

    test(
      'la cola guarda en el disco el id de la tarjeta y las cuotas, nunca su nombre ni últimos 4',
      () async {
        repo.onCreate = (_, _) async => throw _offline;
        await saver().create(withCard, localId: 'm-1', cardName: 'Mi Visa', cardLast4: '4242');
        // Mientras la sesión sigue, la etiqueta vive en memoria.
        expect((await pending()).items.single.toMovement().card?.name, 'Mi Visa');
        final disk = store.data['a']!;
        expect(disk, isNot(contains('Mi Visa')));
        expect(disk, isNot(contains('4242')));
        expect(disk, isNot(contains('cardName')));
        c.invalidate(pendingMovementsProvider);
        final p = (await pending()).items.single;
        expect((p.input.card, p.input.installments), ('t1', 3), reason: 'al reabrir');
        expect(p.toMovement().card?.id, 't1');
      },
    );

    test(
      'la tarjeta ya no existe al reenviar: UNA vez sin tarjeta ni cuotas, mismo localId, y avisa',
      () async {
        repo.onCreate = (_, _) async => throw _offline;
        await saver().create(withCard, localId: 'm-1');
        final sent = <MovementInput>[];
        repo.onCreate = (input, id) async {
          sent.add(input);
          if (input.card != null) {
            throw const ApiException(
              code: ApiCodes.validation,
              status: 422,
              fields: {'card': 'No es una de tus tarjetas'},
            );
          }
          return movementOf('srv-$id');
        };
        expect(await c.read(pendingMovementsProvider.notifier).retryPending(), 1);
        expect(repo.localIds, ['m-1', 'm-1', 'm-1']);
        expect([for (final i in sent) (i.card, i.installments)], [('t1', 3), (null, null)]);
        final state = await pending();
        expect(state.items, isEmpty);
        final notice = state.rejected.single;
        expect(notice.cardDropped, isTrue, reason: 'no es un rechazo: el gasto quedó guardado');
        expect(
          notice.message,
          'Guardamos el gasto sin tarjeta: esa tarjeta ya no existe. Puedes asignarle una al editarlo.',
        );
        // Al reabrir sigue siendo el aviso, y no se reenvía nada.
        c.invalidate(pendingMovementsProvider);
        expect((await pending()).rejected.single.cardDropped, isTrue);
        await c.read(pendingMovementsProvider.notifier).retryPending();
        expect(repo.localIds, hasLength(3));
      },
    );

    test('si el reenvío sin tarjeta también se rechaza, queda como rechazo normal', () async {
      repo.onCreate = (_, _) async => throw _offline;
      await saver().create(withCard, localId: 'm-1');
      repo.onCreate = (input, id) async => throw ApiException(
        code: ApiCodes.validation,
        status: 422,
        fields: input.card != null ? const {'card': 'No es una de tus tarjetas'} : const {'date': 'Futura'},
      );
      await c.read(pendingMovementsProvider.notifier).retryPending();
      final rejected = (await pending()).rejected.single;
      expect((rejected.cardDropped, rejected.message), (false, 'Futura'));
    });
  });
}
