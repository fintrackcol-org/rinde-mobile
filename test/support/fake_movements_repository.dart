import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';

/// Movimiento del contrato con lo mínimo, para armar respuestas.
Movement movementOf(
  String id, {
  String date = '2026-11-20',
  num amount = 1000,
  String description = 'Café',
}) => Movement(
  id: id,
  type: MovementType.expense,
  amount: amount,
  description: description,
  source: 'manual',
  date: date,
  category: 'alimentacion',
);

const inputOf = MovementInput(
  type: MovementType.expense,
  amount: 12500,
  description: 'Almuerzo',
  date: '2026-11-21',
);

/// Repositorio de movimientos con respuestas a la medida. Guarda cada llamada con sus argumentos.
class FakeMovementsRepository implements MovementsRepository {
  final calls = <String>[];
  final queries = <MovementQuery>[];
  final localIds = <String>[];

  /// Contra qué movimiento se calculó cada PUT (`from`).
  final froms = <Movement?>[];

  Future<MovementPage> Function(MovementQuery q) onList = (q) async =>
      MovementPage(items: const [], page: q.page, pageSize: q.pageSize, total: 0);
  Future<Movement> Function(String id) onGet = (id) async => movementOf(id);
  Future<Movement> Function(MovementInput input, String localId) onCreate = (input, localId) async =>
      movementOf('srv-$localId', amount: input.amount, description: input.description, date: input.date);
  Future<Movement> Function(String id, MovementInput input) onUpdate = (id, input) async =>
      movementOf(id, amount: input.amount, description: input.description, date: input.date);
  Future<void> Function(String id) onDelete = (id) async {};
  Future<CategoryLists> Function() onCategories = () async => const CategoryLists(expense: [], income: []);

  @override
  bool get isDemo => false;

  @override
  Future<MovementPage> list(MovementQuery q) {
    calls.add('list ${q.page}');
    queries.add(q);
    return onList(q);
  }

  @override
  Future<Movement> get(String id) {
    calls.add('get $id');
    return onGet(id);
  }

  @override
  Future<Movement> create(MovementInput input, {required String localId}) {
    calls.add('create $localId');
    localIds.add(localId);
    return onCreate(input, localId);
  }

  @override
  Future<Movement> update(String id, MovementInput input, {Movement? from}) {
    calls.add('update $id');
    froms.add(from);
    return onUpdate(id, input);
  }

  @override
  Future<void> delete(String id) {
    calls.add('delete $id');
    return onDelete(id);
  }

  @override
  Future<CategoryLists> categories() {
    calls.add('categories');
    return onCategories();
  }
}
