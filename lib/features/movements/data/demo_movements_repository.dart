import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/demo_home_repository.dart';
import '../../home/data/home_models.dart' show MonthTotals, readMoney;
import '../../home/domain/home_dates.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../domain/movement.dart';
import 'json_list_store.dart';
import 'movements_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Movimientos sintéticos de un usuario demo, guardados en el teléfono con la forma del servidor y
//  leídos con los mismos modelos que la API. Imita las reglas del servidor que se ven en pantalla
//  (monto, descripción, fecha no futura, categoría del tipo, localId); no la IA ni las tarjetas.
// ─────────────────────────────────────────────────────────────────────────────

const _incomeCategories = {'salario', 'freelance', 'inversion_rendimientos', 'otros_ingresos'};

/// Plata apartada: el servidor no la cuenta como gasto del mes (SAVINGS_CATEGORY).
const _savings = 'ahorro_inversion';

class DemoMovementsRepository implements MovementsRepository {
  DemoMovementsRepository({
    required this.userId,
    required this.store,
    required this.controls,
    required this.clock,
    required this.home,
  });

  final String userId;
  final JsonListStore store;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  /// De aquí salen los nombres de las 15 categorías en el idioma que se ve.
  final DemoHomeRepository home;

  final _random = math.Random.secure();
  Future<void> _lock = Future.value();

  @override
  bool get isDemo => true;

  /// Un llavero ilegible falla en vez de leerse como vacío: escribir encima borraría lo anotado.
  Future<List<Movement>> _all() async => [
    for (final m in await _readDemo(store, userId)) Movement.fromJson(m),
  ];

  /// Las escrituras van de a una: dos guardados seguidos no se pisan.
  Future<T> _write<T>(Future<T> Function(List<Movement> all) change) {
    final run = _lock.then((_) => _all()).then(change);
    _lock = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _save(List<Movement> all) => store.write(userId, [for (final m in all) m.toJson()]);

  @override
  Future<MovementPage> list(MovementQuery q) async {
    await controls.simulate();
    final all = (await _all()).where((m) => q.matches(_inputOf(m))).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
    final start = (q.page - 1) * q.pageSize;
    return MovementPage(
      items: all.skip(start).take(q.pageSize).toList(),
      page: q.page,
      pageSize: q.pageSize,
      total: all.length,
    );
  }

  @override
  Future<Movement> get(String id) async {
    await controls.simulate();
    return (await _all()).where((m) => m.id == id).firstOrNull ?? (throw _notFound);
  }

  @override
  Future<Movement> create(MovementInput input, {required String localId}) async {
    await controls.simulate();
    final categories = await _categoryNames();
    return _write((all) async {
      // Como el servidor (FT-0009): el mismo localId devuelve el que ya existe.
      if (all.where((m) => m.localId == localId).firstOrNull case final existing?) return existing;
      final now = clock().toUtc();
      final created = _build(
        input,
        categories,
        id: 'demo-${List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
        localId: localId,
        createdAt: now,
        updatedAt: now,
      );
      await _save([...all, created]);
      return created;
    });
  }

  @override
  Future<Movement> update(String id, MovementInput input, {Movement? from}) async {
    await controls.simulate();
    final categories = await _categoryNames();
    return _write((all) async {
      final current = all.where((m) => m.id == id).firstOrNull ?? (throw _notFound);
      final updated = _build(
        input,
        categories,
        id: id,
        localId: current.localId,
        createdAt: current.createdAt,
        updatedAt: clock().toUtc(),
      );
      await _save([for (final m in all) m.id == id ? updated : m]);
      return updated;
    });
  }

  @override
  Future<void> delete(String id) async {
    await controls.simulate();
    await _write((all) async {
      if (!all.any((m) => m.id == id)) throw _notFound;
      await _save(all.where((m) => m.id != id).toList());
    });
  }

  @override
  Future<CategoryLists> categories() async {
    final names = await _categoryNames();
    List<Map<String, Object?>> of(bool income) => [
      for (final e in names.entries)
        if (_incomeCategories.contains(e.key) == income)
          {'key': e.key, 'name': e.value, 'icon': null, 'color': null, 'custom': false},
    ];
    return CategoryLists.fromJson({'expense': of(false), 'income': of(true)});
  }

  /// Ingresos y gastos del mes de `date` (AAAA-MM-DD), como GET /transactions/summary: lo apartado
  /// no cuenta como gasto. Suma en centavos. Para que el Inicio demo refleje lo anotado.
  Future<MonthTotals> monthTotals(String date) => demoMovementTotals(store, userId, date);

  Future<Map<String, String>> _categoryNames() => home.categoryNames();

  Movement _build(
    MovementInput input,
    Map<String, String> categories, {
    required String id,
    required String? localId,
    required DateTime? createdAt,
    required DateTime? updatedAt,
  }) {
    final fields = <String, String>{};
    final description = input.description.trim();
    final original = input.original;
    final amount = original == null ? readMoney(input.amount) : readMoney(original.amount * original.rate);
    if (amount == null || amount <= 0) fields['amount'] = 'Debe ser un número mayor que 0';
    if (description.isEmpty) fields['description'] = 'Es obligatoria';
    if (description.length > 200) fields['description'] = 'Máximo 200 caracteres';
    if (input.date.compareTo(isoDay(clock())) > 0) {
      fields['date'] = 'La fecha no puede ser futura';
    }
    final category = input.category;
    if (category != null &&
        (!categories.containsKey(category) ||
            _incomeCategories.contains(category) != (input.type == MovementType.income))) {
      fields['category'] = 'No es una categoría de ${input.type.wire} del catálogo';
    }
    if (fields.isNotEmpty) {
      throw ApiException(
        code: ApiCodes.validation,
        serverMessage: 'Datos inválidos',
        status: 422,
        fields: fields,
      );
    }
    final expense = input.type == MovementType.expense;
    return Movement(
      id: id,
      localId: localId,
      type: input.type,
      amount: amount!,
      description: description,
      category: category,
      source: category == null ? 'sin_clasificar' : 'manual',
      date: input.date,
      createdAt: createdAt,
      updatedAt: updatedAt,
      emotion: expense ? input.emotion : null,
      kakeibo: expense ? input.kakeibo : null,
      original: original,
    );
  }
}

MovementInput _inputOf(Movement m) => MovementInput(
  type: m.type,
  amount: m.amount,
  description: m.description,
  date: m.date,
  category: m.category,
);

const _notFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Transacción no encontrada', status: 404);

/// Movimientos de cada usuario demo en `rinde.demo.movimientos.<userId>`.
final demoMovementsStoreProvider = Provider<JsonListStore>(
  (ref) => const SecureJsonListStore('rinde.demo.movimientos.'),
);

/// El Inicio demo lee de aquí los totales del mes (`monthTotals`).
final demoMovementsRepositoryProvider = Provider.family<DemoMovementsRepository, String>(
  (ref, userId) => DemoMovementsRepository(
    userId: userId,
    store: ref.watch(demoMovementsStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
    home: ref.watch(demoHomeRepositoryProvider(userId)),
  ),
);

/// Lo anotado en la demo durante el mes de `date`. Función suelta: el Inicio demo la usa sin depender
/// del repositorio de movimientos (que ya depende del Inicio para los nombres de categoría).
Future<MonthTotals> demoMovementTotals(JsonListStore store, String userId, String date) async {
  final month = date.substring(0, 7);
  var income = 0, expense = 0;
  for (final raw in await _readDemo(store, userId)) {
    final m = Movement.fromJson(raw);
    if (!m.date.startsWith(month)) continue;
    final cents = (m.amount * 100).round();
    if (m.isIncome) {
      income += cents;
    } else if (m.category != _savings) {
      expense += cents;
    }
  }
  return MonthTotals(month: month, income: readMoney(income / 100)!, expense: readMoney(expense / 100)!);
}

/// ¿Ya anotó algo en la demo? (cuenta para «Todavía no has anotado nada» y la bienvenida).
Future<bool> demoHasMovements(JsonListStore store, String userId) async =>
    // Solo lectura: si el llavero no responde se toma como «nada anotado» (no se escribe nada).
    (await store.read(userId) ?? const <Object?>[]).isNotEmpty;

Future<List<Object?>> _readDemo(JsonListStore store, String userId) async =>
    await store.read(userId) ?? (throw StateError('No se pudieron leer los movimientos de la demostración'));
