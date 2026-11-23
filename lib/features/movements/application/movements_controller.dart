import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../data/movements_repository.dart';
import '../domain/movement.dart';
import 'movement_saver.dart';

class MovementsState {
  const MovementsState({
    this.query = const MovementQuery(),
    this.server = const [],
    this.pending = const [],
    this.loading = false,
    this.error,
    this.hasMore = false,
    this.total,
    this.loadedPage = 0,
  });

  final MovementQuery query;

  /// Lo que devolvió el servidor, página tras página.
  final List<Movement> server;

  /// La cola sin conexión completa (sin filtrar).
  final List<PendingMovement> pending;
  final bool loading;

  /// El último fallo (de la primera página o de «cargar más»). Lo cargado se conserva.
  final Object? error;
  final bool hasMore;

  /// null hasta que responda el servidor: no se sabe, no es cero.
  final int? total;
  final int loadedPage;

  /// Lo que se pinta: primero los pendientes que cumplen los filtros, luego los del servidor.
  List<Movement> get items => [
    for (final p in pending.reversed)
      if (query.matches(p.input)) p.toMovement(),
    ...server,
  ];

  MovementsState copyWith({
    MovementQuery? query,
    List<Movement>? server,
    List<PendingMovement>? pending,
    bool? loading,
    Object? error,
    bool clearError = false,
    bool? hasMore,
    int? total,
    int? loadedPage,
  }) => MovementsState(
    query: query ?? this.query,
    server: server ?? this.server,
    pending: pending ?? this.pending,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
    loadedPage: loadedPage ?? this.loadedPage,
  );
}

/// La lista de Movimientos del ingreso vigente. Al cambiar de cuenta vuelve a empezar: la otra
/// cuenta nunca ve estos movimientos, ni recibe una respuesta que venía en camino.
class MovementsController extends Notifier<MovementsState> {
  /// Sube con cada carga nueva: una respuesta vieja (otros filtros, recarga) se descarta.
  int _run = 0;

  @override
  MovementsState build() {
    ref.watch(accountProvider);
    ref.watch(movementsRepositoryProvider);
    ref.listen(pendingMovementsProvider, (_, next) {
      if (next.value case final p?) state = state.copyWith(pending: p.items);
    });
    const query = MovementQuery();
    Future.microtask(() => _load(query, page: query.page));
    return MovementsState(
      pending: ref.read(pendingMovementsProvider).value?.items ?? const [],
      loading: true,
    );
  }

  /// Filtros nuevos: empieza desde su página (normalmente la 1).
  Future<void> setQuery(MovementQuery query) {
    state = MovementsState(query: query, pending: state.pending, loading: true);
    return _load(query, page: query.page);
  }

  /// Vuelve a pedir la primera página sin borrar lo que se ve mientras tanto.
  Future<void> refresh() {
    state = state.copyWith(loading: true, clearError: true);
    return _load(state.query, page: state.query.page);
  }

  /// La página siguiente. No hace nada si ya está cargando o no hay más.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, clearError: true);
    await _load(state.query, page: state.loadedPage + 1, append: true);
  }

  Future<void> _load(MovementQuery query, {required int page, bool append = false}) async {
    final run = ++_run;
    final owner = ref;
    final repo = ref.read(movementsRepositoryProvider);
    try {
      final result = await repo.list(
        MovementQuery(
          type: query.type,
          category: query.category,
          from: query.from,
          to: query.to,
          search: query.search,
          page: page,
          pageSize: query.pageSize,
        ),
      );
      if (!owner.mounted || run != _run) return;
      // Si entró uno nuevo entre páginas, el corrimiento repite filas: se quitan por id.
      final seen = append ? {for (final m in state.server) m.id} : <String>{};
      state = state.copyWith(
        server: [if (append) ...state.server, ...result.items.where((m) => seen.add(m.id))],
        loading: false,
        clearError: true,
        hasMore: result.hasMore,
        total: result.total,
        loadedPage: page,
      );
    } catch (e) {
      if (!owner.mounted || run != _run) return;
      state = state.copyWith(loading: false, error: e);
    }
  }
}

final movementsControllerProvider = NotifierProvider<MovementsController, MovementsState>(
  MovementsController.new,
);

/// Un movimiento por id, de una cuenta: `ref.watch(movementDetailProvider((account, id)))`. La copia
/// de quien salió no pide nada.
final movementDetailProvider = FutureProvider.family<Movement, (Session?, String)>((ref, key) {
  if (ref.watch(accountProvider) != key.$1) return Completer<Movement>().future;
  return ref.watch(movementsRepositoryProvider).get(key.$2);
});

/// Categorías de gasto e ingreso. Los nombres los traduce el servidor: se piden otra vez al cambiar
/// de idioma.
final movementCategoriesProvider = perAccount<CategoryLists>((ref) {
  ref.watch(displayLanguageProvider);
  return ref.watch(movementsRepositoryProvider).categories();
});
