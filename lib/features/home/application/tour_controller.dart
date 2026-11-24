import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/home_repository.dart';

/// Si el tutorial de primera vez se abre solo en cuentas reales. Apagado a propósito mientras faltaban
/// módulos que tour_steps.dart promete; desde la etapa 10 (Metas y Vacas) ya existen todos, pero
/// encenderlo es decisión aparte: cerrarlo lo marca como visto en el servidor, también para la web.
/// En una sesión de demostración sí se abre, y desde «Yo» siempre.
const kCoachTourForRealAccounts = false;

/// Marca local «el tutorial ya se vio aquí aunque el servidor aún no lo sepa» (TOUR_SEEN_KEY de la
/// web). Una por usuario: la de la web es del dispositivo y le esconde el tutorial a una segunda cuenta.
abstract class TourSeenStore {
  Future<bool> read(String userId);
  Future<void> write(String userId);

  /// Solo al reiniciar la demostración.
  Future<void> clear(String userId);
}

class SecureTourSeenStore implements TourSeenStore {
  const SecureTourSeenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  String _key(String userId) => 'rinde.tutorialVisto.$userId';

  @override
  Future<bool> read(String userId) async {
    try {
      return await _storage.read(key: _key(userId)) == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> write(String userId) async {
    try {
      await _storage.write(key: _key(userId), value: '1');
    } catch (_) {
      // Sin almacenamiento solo queda el servidor.
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {
      // Sin almacenamiento tampoco había marca que leer.
    }
  }
}

/// En memoria, para pruebas.
class MemoryTourSeenStore implements TourSeenStore {
  final seen = <String>{};

  @override
  Future<bool> read(String userId) async => seen.contains(userId);
  @override
  Future<void> write(String userId) async => seen.add(userId);
  @override
  Future<void> clear(String userId) async => seen.remove(userId);
}

final tourSeenStoreProvider = Provider<TourSeenStore>((ref) => const SecureTourSeenStore());

/// Cuándo se muestra el tutorial de primera vez (useFirstTimeTour de la web). El estado es true
/// mientras está abierto.
class TourController extends Notifier<bool> {
  bool _checking = false;

  /// El aviso callado al servidor se intenta una vez por cuenta y por apertura de la app: el Inicio
  /// puede llamar a [maybeStart] muchas veces y sin conexión cada una sería otra petición fallida.
  bool _retried = false;

  @override
  bool build() {
    // Al cambiar de cuenta, un tutorial abierto era de la anterior.
    ref.watch(sessionControllerProvider.select((s) => s.value?.session?.user.id));
    _retried = false;
    return false;
  }

  Session? get _session => ref.read(sessionControllerProvider).value?.session;

  /// Lo abre solo: después de la bienvenida, si ni el servidor ni este dispositivo lo dan por visto.
  /// El Inicio lo llama cuando ya cargó; llamarlo de más no hace daño.
  Future<void> maybeStart() async {
    final session = _session;
    final status = ref.read(welcomeStatusProvider(ref.read(accountProvider)));
    // Un dato viejo (recargando o con error) no decide nada.
    if (state || _checking || session == null || status.isLoading || status.hasError) return;
    final profile = status.value;
    if (profile == null || !profile.welcomeDone || profile.tutorialDone) return;
    if (!session.demo && !kCoachTourForRealAccounts) return;

    _checking = true;
    try {
      final seen = await ref.read(tourSeenStoreProvider).read(session.user.id);
      if (!ref.mounted || _session?.user.id != session.user.id) return;
      if (!seen) {
        state = true;
      } else if (!_retried) {
        // Se vio sin conexión: ahora sí se le cuenta al servidor.
        _retried = true;
        await _tellServer();
      }
    } finally {
      _checking = false;
    }
  }

  /// A pedido (desde «Yo» o el panel de demostración): no mira si ya se vio.
  void open() => state = true;

  /// Omitir, terminar, tocar fuera o «atrás»: todos lo dan por visto. Nunca avisa que se guardó.
  Future<void> close() async {
    if (!state) return;
    state = false;
    final userId = _session?.user.id;
    if (userId == null) return;
    await ref.read(tourSeenStoreProvider).write(userId);
    if (!ref.mounted || _session?.user.id != userId) return;
    if (ref.read(welcomeStatusProvider(ref.read(accountProvider))).value?.tutorialDone == false) {
      await _tellServer();
    }
  }

  /// Si falla se calla: queda la marca local y se reintenta la próxima vez.
  Future<void> _tellServer() async {
    try {
      await ref.read(homeRepositoryProvider).finishTutorial();
    } catch (_) {
      return;
    }
    if (ref.mounted) ref.invalidate(welcomeStatusProvider);
  }
}

final tourControllerProvider = NotifierProvider<TourController, bool>(TourController.new);
