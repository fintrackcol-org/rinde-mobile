import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import 'onboarding_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Solo para desarrollo y pruebas. Nada de esto llega a un servidor ni confirma nada real.
//  Se usa únicamente con una sesión demo, que solo existe en compilaciones de desarrollo
//  con DEMO_MODE=true (ver AppConfig.demoMode).
// ─────────────────────────────────────────────────────────────────────────────

/// Escenarios de prueba.
enum DemoScenario {
  /// Cuenta recién creada: sin movimientos y sin bienvenida → bienvenida completa.
  nuevo('Usuario nuevo'),

  /// Ya tiene movimientos y no respondió → invitación y recorrido abreviado.
  movimientos('Usuario con movimientos');

  const DemoScenario(this.label);
  final String label;

  static DemoScenario fromUserId(String userId) => userId.endsWith(movimientos.name) ? movimientos : nuevo;
}

/// Operaciones que se pueden hacer fallar a propósito.
enum DemoOperation { status, region, welcome, sources }

enum DemoFailure { network, server }

/// Perillas de la demostración (panel «DEMO»).
class DemoControls {
  const DemoControls({this.latency = const Duration(milliseconds: 700), this.failures = const {}});

  final Duration latency;

  /// Falla una sola vez la próxima llamada a esa operación.
  final Map<DemoOperation, DemoFailure> failures;

  DemoControls copyWith({Duration? latency, Map<DemoOperation, DemoFailure>? failures}) =>
      DemoControls(latency: latency ?? this.latency, failures: failures ?? this.failures);
}

class DemoControlsNotifier extends Notifier<DemoControls> {
  @override
  DemoControls build() => const DemoControls();

  void failNext(DemoOperation op, DemoFailure? failure) {
    final next = Map<DemoOperation, DemoFailure>.of(state.failures);
    failure == null ? next.remove(op) : next[op] = failure;
    state = state.copyWith(failures: next);
  }

  void setLatency(Duration latency) => state = state.copyWith(latency: latency);

  /// Valor actual, para el repositorio de demostración.
  DemoControls get current => state;

  /// Consume la falla programada (una sola vez).
  DemoFailure? take(DemoOperation op) {
    final failure = state.failures[op];
    if (failure != null) failNext(op, null);
    return failure;
  }
}

final demoControlsProvider = NotifierProvider<DemoControlsNotifier, DemoControls>(DemoControlsNotifier.new);

/// Lo que la demo "recibió" (para mostrarlo al terminar y para las pruebas).
class DemoCall {
  const DemoCall(this.operation, this.body);
  final DemoOperation operation;
  final Object? body;
}

/// Estado simulado que sobrevive a cerrar la app (para probar «ya la terminó»).
abstract class DemoStateStore {
  Future<bool> welcomeDone(String userId);
  Future<void> setWelcomeDone(String userId, bool done);
}

class SecureDemoStateStore implements DemoStateStore {
  const SecureDemoStateStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<bool> welcomeDone(String userId) async {
    try {
      final raw = await _storage.read(key: 'rinde.demo.$userId');
      return raw != null && (jsonDecode(raw) as Map)['welcomeDone'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setWelcomeDone(String userId, bool done) async {
    try {
      done
          ? await _storage.write(key: 'rinde.demo.$userId', value: jsonEncode({'welcomeDone': true}))
          : await _storage.delete(key: 'rinde.demo.$userId');
    } catch (_) {}
  }
}

class MemoryDemoStateStore implements DemoStateStore {
  final _done = <String, bool>{};
  @override
  Future<bool> welcomeDone(String userId) async => _done[userId] ?? false;
  @override
  Future<void> setWelcomeDone(String userId, bool done) async => _done[userId] = done;
}

final demoStateStoreProvider = Provider<DemoStateStore>((ref) => const SecureDemoStateStore());

class DemoOnboardingRepository implements OnboardingRepository {
  DemoOnboardingRepository({required this.userId, required this.store, required this.controls});

  final String userId;
  final DemoStateStore store;
  final DemoControlsNotifier controls;
  final calls = <DemoCall>[];

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  @override
  bool get isDemo => true;

  Future<void> _simulate(DemoOperation op, Object? body) async {
    calls.add(DemoCall(op, body));
    await Future<void>.delayed(controls.current.latency);
    switch (controls.take(op)) {
      case DemoFailure.network:
        throw const ApiException(code: ApiCodes.network);
      case DemoFailure.server:
        throw const ApiException(
          code: 'INTERNAL_ERROR',
          serverMessage: 'Error simulado del servidor (demostración).',
          status: 500,
        );
      case null:
        return;
    }
  }

  @override
  Future<WelcomeStatus> status() async {
    await _simulate(DemoOperation.status, null);
    final done = await store.welcomeDone(userId);
    return switch (scenario) {
      DemoScenario.nuevo => WelcomeStatus(welcomeDone: done, tutorialDone: false, hasTransactions: false),
      // Totales SINTÉTICOS para probar la propuesta de saldo: no son de nadie.
      DemoScenario.movimientos => WelcomeStatus(
        welcomeDone: done,
        tutorialDone: false,
        hasTransactions: true,
        income: 2500000,
        expense: 1850000,
      ),
    };
  }

  @override
  Future<Region> saveRegion({required String country, required String language}) async {
    await _simulate(DemoOperation.region, {'country': country, 'language': language});
    final region = regionForCountry(country);
    // Escenario con movimientos: la moneda ya no se puede cambiar (como CURRENCY_LOCKED en el servidor).
    final currency = scenario == DemoScenario.movimientos ? 'COP' : region.currency;
    return Region(country: region.country, currency: currency, language: language);
  }

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) async {
    await _simulate(DemoOperation.welcome, body);
    await store.setWelcomeDone(userId, true);
  }

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) async {
    await _simulate(DemoOperation.sources, sources);
  }

  /// «Reiniciar demostración»: la cuenta sintética vuelve a no haber hecho la bienvenida.
  Future<void> reset() async {
    calls.clear();
    await store.setWelcomeDone(userId, false);
  }
}

final demoOnboardingRepositoryProvider = Provider.family<DemoOnboardingRepository, String>(
  (ref, userId) => DemoOnboardingRepository(
    userId: userId,
    store: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
  ),
);
