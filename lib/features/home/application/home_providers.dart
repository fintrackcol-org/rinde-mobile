import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily, ProviderOrFamily;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/i18n/tr.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/home_models.dart';
import '../data/home_repository.dart';
import '../domain/home_dates.dart';
import '../domain/home_view.dart';

/// Reloj del dispositivo; las pruebas lo fijan.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Hoy (fecha local, sin hora). Cambia solo a medianoche y al volver a la app, para que el mes del
/// Inicio no se quede en el anterior si la app sigue abierta.
class Today extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = ref.watch(clockProvider)();
    final timer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now) + const Duration(seconds: 1),
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
    return DateTime(now.year, now.month, now.day);
  }

  /// Al volver a la app o al recargar: si ya es otro día, todo lo que depende de hoy se vuelve a pedir.
  void sync() {
    final now = ref.read(clockProvider)();
    if (DateTime(now.year, now.month, now.day) != state) ref.invalidateSelf();
  }
}

final todayProvider = NotifierProvider<Today, DateTime>(Today.new);

/// Un bloque del Inicio, de una cuenta.
FutureProviderFamily<T, Session?> _block<T>(Future<T> Function(Ref ref, HomeRepository repo) load) =>
    perAccount<T>((ref) => load(ref, ref.watch(homeRepositoryProvider)));

// El plan y las tarjetas cuentan días desde hoy: al cambiar el día se piden otra vez.
final homePlanProvider = _block<MoneyPlan>((ref, repo) {
  ref.watch(todayProvider);
  return repo.plan();
});

final homeTotalsProvider = _block<MonthTotals>(
  (ref, repo) => repo.monthTotals(isoDay(ref.watch(todayProvider))),
);

final homeBudgetsProvider = _block<List<BudgetStatus>>(
  (ref, repo) => repo.budgets(isoMonth(ref.watch(todayProvider))),
);

final homeCardsProvider = _block<List<CardSummary>>((ref, repo) {
  ref.watch(todayProvider);
  return repo.cards();
});

final homeToConfirmProvider = _block<int>((ref, repo) {
  // La marca de «actualizado» va en un bloque que no depende del día: si fuera en el plan, la
  // medianoche haría pasar por fresco lo que no se volvió a pedir.
  if (ref.read(accountProvider) case final account?) {
    ref.read(homeFreshnessProvider).mark(account, ref.read(clockProvider)());
  }
  return repo.toConfirm();
});

final homeUnreadProvider = _block<int>((ref, repo) => repo.unread());

/// Los nombres los traduce el servidor: se vuelven a pedir al cambiar de idioma.
final homeCategoryNamesProvider = _block<Map<String, String>>((ref, repo) {
  ref.watch(displayLanguageProvider);
  return repo.categoryNames();
});

/// Cuándo se pidió el Inicio por última vez. Vive fuera de la pantalla: cambiar de pestaña la
/// destruye y no por eso las cifras son más nuevas.
class HomeFreshness {
  final _at = <Session, DateTime>{};

  DateTime? of(Session account) => _at[account];
  void mark(Session account, DateTime at) => _at[account] = at;
}

final homeFreshnessProvider = Provider<HomeFreshness>((ref) => HomeFreshness());

/// Lo que se pasa a la función pura. Al volver a cargar por un cambio (de día, de sesión) el valor
/// anterior ya no responde a lo que se pide: se descarta. Al refrescar se conserva, para que las
/// cifras no parpadeen.
Block<T> blockOf<T>(AsyncValue<T> async) => async.isReloading
    ? Block<T>(loading: true)
    : Block<T>(value: async.value, loading: async.isLoading, error: async.error);

final homeViewProvider = Provider<HomeView>((ref) {
  final account = ref.watch(accountProvider);
  return buildHomeView(
    status: blockOf(ref.watch(welcomeStatusProvider(account))),
    plan: blockOf(ref.watch(homePlanProvider(account))),
    totals: blockOf(ref.watch(homeTotalsProvider(account))),
    budgets: blockOf(ref.watch(homeBudgetsProvider(account))),
    cards: blockOf(ref.watch(homeCardsProvider(account))),
    // Si falla, la fila no sale: nunca se inventa «0 pagos».
    toConfirm: switch (blockOf(ref.watch(homeToConfirmProvider(account)))) {
      final block when !block.failed => block.value ?? 0,
      _ => 0,
    },
    today: ref.watch(todayProvider),
  );
});

/// Vuelve a pedir TODO el Inicio (la web reintenta solo tres bloques). Termina cuando todos
/// respondieron, bien o mal: cada bloque muestra su propio estado.
Future<void> refreshHome(WidgetRef ref) {
  ref.read(todayProvider.notifier).sync();
  // Que el día nuevo llegue antes de refrescar: así se suelta lo del mes pasado.
  ref.read(todayProvider);
  final account = ref.read(accountProvider);
  Future<void> again<T>(FutureProviderFamily<T, Session?> provider) =>
      ref.refresh(provider(account).future).then<void>((_) {}, onError: (_) {});
  // Los nombres no se esperan: si el perfil cambia el idioma a mitad, se piden de nuevo y ese primer
  // pedido nunca termina (la rueda de recargar quedaría girando).
  ref.invalidate(homeCategoryNamesProvider(account));
  return Future.wait([
    // También el perfil: de él sale la moneda con que se pinta todo.
    again(profileProvider),
    again(welcomeStatusProvider),
    again(homePlanProvider),
    again(homeTotalsProvider),
    again(homeBudgetsProvider),
    again(homeCardsProvider),
    again(homeToConfirmProvider),
    again(homeUnreadProvider),
  ]);
}

/// Marca todo el Inicio para volver a pedirse (p. ej. desde el panel de demostración, que no tiene
/// un `WidgetRef` del Inicio).
void invalidateHome(void Function(ProviderOrFamily provider) invalidate) {
  for (final provider in <ProviderOrFamily>[
    welcomeStatusProvider,
    homePlanProvider,
    homeTotalsProvider,
    homeBudgetsProvider,
    homeCardsProvider,
    homeToConfirmProvider,
    homeUnreadProvider,
    homeCategoryNamesProvider,
  ]) {
    invalidate(provider);
  }
}

/// Alguien pidió ver el tutorial de primera vez otra vez (desde «Yo», como `?tutorial=1` en la web).
/// El Inicio lo abre cuando está listo y apaga la petición.
class TourRequested extends Notifier<bool> {
  @override
  bool build() {
    // Lo pidió quien estaba dentro: no le toca a la cuenta que entre después.
    ref.watch(accountProvider);
    return false;
  }

  void request() => state = true;
  void clear() => state = false;
}

final tourRequestedProvider = NotifierProvider<TourRequested, bool>(TourRequested.new);

// ── Ocultar montos ───────────────────────────────────────────────────────────

/// Preferencia «ocultar montos» (useHiddenAmounts de la web): una por dispositivo y se conserva al
/// cerrar la app. Solo cambia lo que se VE: no cifra ni protege los datos.
class HiddenAmountsStore {
  const HiddenAmountsStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'rinde.ocultar-montos';
  final FlutterSecureStorage _storage;

  /// Si no se puede leer, arranca oculto: es preferible tapar de más que mostrar sin querer.
  Future<bool> read() async {
    try {
      return await _storage.read(key: _key) == '1';
    } catch (_) {
      return true;
    }
  }

  Future<void> write(bool hidden) async {
    try {
      await _storage.write(key: _key, value: hidden ? '1' : '0');
    } catch (_) {
      // Sin almacenamiento dura hasta cerrar la app, como en la web.
    }
  }
}

final hiddenAmountsStoreProvider = Provider<HiddenAmountsStore>((ref) => const HiddenAmountsStore());

/// Valor con el que abre la app. Se lee en main ANTES de dibujar, para que ninguna cifra alcance a
/// verse si la persona las tenía ocultas.
final initialHiddenAmountsProvider = Provider<bool>((ref) => false);

class HiddenAmounts extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialHiddenAmountsProvider);

  void toggle() {
    state = !state;
    unawaited(ref.read(hiddenAmountsStoreProvider).write(state));
  }
}

final hiddenAmountsProvider = NotifierProvider<HiddenAmounts, bool>(HiddenAmounts.new);
