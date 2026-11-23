import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/application/home_providers.dart' show clockProvider, invalidateHome;
import '../data/json_list_store.dart';
import '../data/movements_repository.dart';
import '../domain/movement.dart';
import 'movements_controller.dart';

/// Tope de la cola: más allá de esto, sin conexión no se guarda (se muestra el error de red).
const kMaxPendingMovements = 50;

/// Un movimiento nuevo que no llegó al servidor por falta de conexión. Se reintenta con el MISMO
/// localId: si el primer envío sí llegó, el servidor lo reconoce y no lo duplica.
class PendingMovement {
  const PendingMovement({required this.localId, required this.input, required this.queuedAt, this.rejected});

  factory PendingMovement.fromJson(Object? raw) {
    if (raw is! Map || raw['localId'] is! String || raw['queuedAt'] is! String) {
      throw const ContractException('Pendiente ilegible');
    }
    return PendingMovement(
      localId: raw['localId'] as String,
      input: MovementInput.fromJson(raw['input']),
      queuedAt: DateTime.parse(raw['queuedAt'] as String),
      rejected: raw['rejected'] is String ? raw['rejected'] as String : null,
    );
  }

  final String localId;
  final MovementInput input;
  final DateTime queuedAt;

  /// Mensaje del servidor si lo rechazó al reintentar. Se guarda hasta que la persona lo descarte.
  final String? rejected;

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'input': input.toJson(),
    'queuedAt': queuedAt.toUtc().toIso8601String(),
    'rejected': ?rejected,
  };

  /// Cómo se ve en la lista. La categoría final, el origen y el monto en otra moneda los decide el
  /// servidor: aquí van como los escribió la persona.
  Movement toMovement() => Movement(
    id: localId,
    localId: localId,
    type: input.type,
    amount: input.amount,
    description: input.description,
    category: input.category,
    source: '',
    date: input.date,
    createdAt: queuedAt,
    pending: true,
    installments: input.installments,
    emotion: input.emotion,
    kakeibo: input.kakeibo,
    original: input.original,
  );
}

/// Un pendiente que el servidor rechazó (4xx) al reintentar: sale de la cola y queda con el mensaje,
/// guardado en el teléfono, hasta que la persona lo descarte.
class RejectedMovement {
  const RejectedMovement({required this.movement, required this.message});

  final PendingMovement movement;
  final String message;
}

class PendingState {
  const PendingState({this.items = const [], this.rejected = const [], this.readable = true});

  /// Del más viejo al más nuevo.
  final List<PendingMovement> items;

  /// Rechazados por el servidor; se guardan junto a la cola hasta que se descartan.
  final List<RejectedMovement> rejected;

  /// false: no se pudo leer la cola guardada. No se escribe encima: se perdería.
  final bool readable;

  List<Movement> get movements => [for (final p in items.reversed) p.toMovement()];

  PendingState copyWith({List<PendingMovement>? items, List<RejectedMovement>? rejected}) =>
      PendingState(items: items ?? this.items, rejected: rejected ?? this.rejected, readable: readable);
}

/// Cola por usuario en `rinde.pendientes.<userId>`.
final pendingStoreProvider = Provider<JsonListStore>((ref) => const SecureJsonListStore('rinde.pendientes.'));

/// Cola de pendientes del ingreso vigente. Otra cuenta lee la suya.
class PendingMovements extends AsyncNotifier<PendingState> {
  Future<void> _lock = Future.value();
  Future<int>? _retrying;

  @override
  Future<PendingState> build() async {
    final account = ref.watch(accountProvider);
    if (account == null) return const PendingState();
    final raw = await ref.read(pendingStoreProvider).read(account.user.id);
    if (raw == null) return const PendingState(readable: false);
    final items = <PendingMovement>[];
    final rejected = <RejectedMovement>[];
    for (final item in raw) {
      try {
        final p = PendingMovement.fromJson(item);
        if (p.rejected case final message?) {
          rejected.add(RejectedMovement(movement: p, message: message));
        } else {
          items.add(p);
        }
      } on Object {
        // Uno dañado no tumba la cola entera.
      }
    }
    return PendingState(items: items, rejected: rejected);
  }

  /// Cambia la cola de a una operación a la vez y la guarda. Lo hace sobre el usuario con que
  /// empezó: si la cuenta cambió entre medias, no toca la de la nueva.
  Future<bool> _change(PendingState Function(PendingState state) change) {
    final owner = ref;
    final account = ref.read(accountProvider);
    final run = _lock.then((_) async {
      if (account == null) return false;
      final current = await future;
      if (!owner.mounted || !current.readable) return false;
      final next = change(current);
      if (!identical(next.items, current.items) || !identical(next.rejected, current.rejected)) {
        await ref.read(pendingStoreProvider).write(account.user.id, [
          for (final p in next.items) p.toJson(),
          for (final r in next.rejected) {...r.movement.toJson(), 'rejected': r.message},
        ]);
      }
      if (owner.mounted) state = AsyncData(next);
      return true;
    });
    _lock = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// false si no cabe (tope o cola ilegible): quien llama muestra el error de red.
  Future<bool> enqueue(String localId, MovementInput input) async {
    var added = false;
    final ok = await _change((s) {
      final others = s.items.where((p) => p.localId != localId).toList();
      if (others.length >= kMaxPendingMovements) return s;
      added = true;
      return s.copyWith(
        items: [
          ...others,
          PendingMovement(localId: localId, input: input, queuedAt: ref.read(clockProvider)()),
        ],
      );
    });
    return ok && added;
  }

  Future<void> remove(String localId) => _change((s) {
    if (!s.items.any((p) => p.localId == localId)) return s;
    return s.copyWith(items: s.items.where((p) => p.localId != localId).toList());
  });

  /// La pantalla ya mostró los rechazos.
  Future<void> clearRejected() => _change((s) => s.copyWith(rejected: const []));

  /// Reintenta la cola en orden con el mismo localId de cada uno. Se detiene en el primer error
  /// de red, del servidor (5xx), 401, 408 o 429; otro 4xx lo saca de la cola y guarda el mensaje. Devuelve cuántos
  /// confirmó el servidor. Una sola pasada a la vez.
  Future<int> retryPending() => _retrying ??= _retry().whenComplete(() => _retrying = null);

  Future<int> _retry() async {
    final owner = ref;
    final repo = ref.read(movementsRepositoryProvider);
    var done = 0;
    for (final pending in (await future).items) {
      if (!owner.mounted) break;
      try {
        await repo.create(pending.input, localId: pending.localId);
        await remove(pending.localId);
        done++;
      } on ApiException catch (e) {
        // Sesión vencida, espera o demasiados intentos no son un rechazo del movimiento: se queda.
        final status = e.status ?? 0;
        if (status < 400 || status >= 500 || const {401, 408, 429}.contains(status)) break;
        await _change(
          (s) => s.copyWith(
            items: s.items.where((p) => p.localId != pending.localId).toList(),
            rejected: [
              ...s.rejected,
              RejectedMovement(
                movement: pending,
                message: e.messageFor(fallback: ApiMessages.generic),
              ),
            ],
          ),
        );
      } on ContractException {
        // Respuesta ilegible: pudo guardarse. Se queda y el próximo reintento lo confirma sin duplicar.
        break;
      }
    }
    if (done > 0 && owner.mounted) afterMovementChange(ref.container);
    return done;
  }
}

final pendingMovementsProvider = AsyncNotifierProvider<PendingMovements, PendingState>(PendingMovements.new);

/// Lo que cambia tras guardar, editar o borrar: la lista, el detalle y todo el Inicio.
void afterMovementChange(ProviderContainer container) {
  if (container.read(movementsControllerProvider.exists)) {
    unawaited(container.read(movementsControllerProvider.notifier).refresh());
  }
  container.invalidate(movementDetailProvider);
  invalidateHome(container.invalidate);
}

/// Guarda, edita y borra movimientos.
class MovementSaver {
  MovementSaver(this._ref);
  final Ref _ref;

  static final _random = math.Random.secure();

  /// 'm-' + 128 bits al azar en hexadecimal. Uno por movimiento nuevo: el formulario lo genera al
  /// abrirse y lo reusa en cada reintento del mismo borrador.
  static String newLocalId() =>
      'm-${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  MovementsRepository get _repo => _ref.read(movementsRepositoryProvider);

  /// Crea con el localId que el formulario guarda ([newLocalId]). Sin conexión (o si se venció la
  /// espera) queda en la cola y devuelve el movimiento con `pending: true`. Si la cola no lo acepta,
  /// o el servidor lo rechaza, lanza el error.
  Future<Movement> create(MovementInput input, {required String localId}) async {
    final owner = _ref.read(accountProvider)?.user.id;
    final Movement created;
    try {
      created = await _repo.create(input, localId: localId);
    } on ApiException catch (e) {
      // Si la cuenta cambió mientras iba el envío, no se mete en la cola de la otra persona.
      if (!e.isNetwork || _ref.read(accountProvider)?.user.id != owner) rethrow;
      final pending = _ref.read(pendingMovementsProvider.notifier);
      if (!await pending.enqueue(localId, input)) rethrow;
      return PendingMovement(
        localId: localId,
        input: input,
        queuedAt: _ref.read(clockProvider)(),
      ).toMovement();
    }
    // Si este borrador estaba en la cola, ya llegó.
    await _ref.read(pendingMovementsProvider.notifier).remove(localId);
    afterMovementChange(_ref.container);
    return created;
  }

  /// Necesita conexión: sin ella lanza el error de red (no hay edición sin conexión).
  Future<Movement> update(String id, MovementInput input, {Movement? from}) async {
    final updated = await _repo.update(id, input, from: from);
    afterMovementChange(_ref.container);
    return updated;
  }

  /// Necesita conexión, como [update].
  /// Un 404 cuenta como borrado: el borrado del servidor es lógico y un reintento, tras perder la
  /// respuesta del primero, recibe 404 aunque sí se borró.
  Future<void> delete(String id) async {
    try {
      await _repo.delete(id);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    afterMovementChange(_ref.container);
  }
}

final movementSaverProvider = Provider<MovementSaver>(MovementSaver.new);
