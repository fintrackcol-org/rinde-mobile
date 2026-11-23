import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';

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

/// 45 movimientos del servidor, de a `pageSize` por página.
MovementPage _page(MovementQuery q, {String prefix = 'm', int total = 45}) {
  final start = (q.page - 1) * q.pageSize;
  return MovementPage(
    items: [for (var i = start; i < total && i < start + q.pageSize; i++) movementOf('$prefix$i')],
    page: q.page,
    pageSize: q.pageSize,
    total: total,
  );
}

void main() {
  late FakeMovementsRepository repo;
  late ProviderContainer c;

  setUp(() {
    repo = FakeMovementsRepository()..onList = (q) async => _page(q);
    c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        movementsRepositoryProvider.overrideWithValue(repo),
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
      ],
    );
    c.listen(movementsControllerProvider, (_, _) {});
  });

  MovementsState state() => c.read(movementsControllerProvider);
  MovementsController ctrl() => c.read(movementsControllerProvider.notifier);
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  void enter(Session? session) => (c.read(sessionControllerProvider.notifier) as _Sessions).enter(session);

  test('arranca cargando, sin total inventado, y luego trae la primera página', () async {
    expect(state().loading, isTrue);
    expect(state().total, isNull);
    await settle();
    expect(state().items, hasLength(20));
    expect(state().total, 45);
    expect(state().hasMore, isTrue);
  });

  test('loadMore pide la siguiente página hasta el final y no repite', () async {
    await settle();
    await ctrl().loadMore();
    await ctrl().loadMore();
    expect(state().items, hasLength(45));
    expect(state().hasMore, isFalse);
    await ctrl().loadMore();
    expect(repo.calls, ['list 1', 'list 2', 'list 3']);
  });

  test('una fila repetida por el corrimiento entre páginas no se duplica', () async {
    await settle();
    repo.onList = (q) async => _page(
      MovementQuery(page: q.page, pageSize: q.pageSize),
      prefix: 'm',
    )..items.insert(0, movementOf('m19'));
    await ctrl().loadMore();
    expect(state().items.where((m) => m.id == 'm19'), hasLength(1));
  });

  test('si falla «cargar más» se conserva lo cargado y queda el error', () async {
    await settle();
    repo.onList = (_) async => throw const ApiException(code: ApiCodes.network);
    await ctrl().loadMore();
    expect(state().items, hasLength(20));
    expect(state().error, isA<ApiException>());
    expect(state().loading, isFalse);
  });

  test('refresh vuelve a la página 1 sin vaciar lo que se ve', () async {
    await settle();
    await ctrl().loadMore();
    final done = Completer<MovementPage>();
    repo.onList = (_) => done.future;
    final refreshing = ctrl().refresh();
    expect(state().items, hasLength(40));
    expect(state().loading, isTrue);
    done.complete(_page(const MovementQuery(), total: 3));
    await refreshing;
    expect(state().items, hasLength(3));
    expect(state().hasMore, isFalse);
  });

  test('setQuery manda los filtros y una respuesta vieja no pisa la nueva', () async {
    await settle();
    final slow = Completer<MovementPage>();
    repo.onList = (_) => slow.future;
    final first = ctrl().setQuery(const MovementQuery(search: 'viejo'));
    repo.onList = (q) async => _page(q, prefix: 'nuevo', total: 1);
    await ctrl().setQuery(const MovementQuery(type: MovementType.income));
    slow.complete(_page(const MovementQuery(), prefix: 'viejo'));
    await first;
    expect(state().query, const MovementQuery(type: MovementType.income));
    expect([for (final m in state().items) m.id], ['nuevo0']);
    expect(repo.queries.last.type, MovementType.income);
  });

  test('otra cuenta empieza de cero y no recibe la respuesta que venía para la anterior', () async {
    await settle();
    final late = Completer<MovementPage>();
    repo.onList = (_) => late.future;
    unawaited(ctrl().refresh());
    repo.onList = (q) async => _page(q, prefix: 'beto', total: 2);
    enter(_beto);
    expect(state().items, isEmpty);
    await settle();
    late.complete(_page(const MovementQuery(), prefix: 'ana'));
    await settle();
    expect([for (final m in state().items) m.id], ['beto0', 'beto1']);
  });

  test('el detalle de quien salió no se pide', () async {
    c.listen(movementDetailProvider((_ana, 'x')), (_, _) {});
    await c.read(movementDetailProvider((_ana, 'x')).future);
    enter(_beto);
    c.listen(movementDetailProvider((_ana, 'y')), (_, _) {});
    await settle();
    expect(repo.calls.where((call) => call.startsWith('get')), ['get x']);
  });

  test('categorías por cuenta', () async {
    repo.onCategories = () async => const CategoryLists(
      expense: [CategoryOption(key: 'alimentacion', name: 'Alimentación')],
      income: [],
    );
    final lists = await c.read(movementCategoriesProvider(_ana).future);
    expect(lists.expense.single.key, 'alimentacion');
  });
}
