import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

import '../../../app/app.dart' show themeModeProvider;
import '../../../core/config/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/session_holder.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

class SessionState {
  const SessionState({this.session, this.expired = false});

  final Session? session;

  /// La sesión terminó porque el servidor rechazó la renovación (no porque la persona salió).
  /// El login lo usa para explicar por qué volvió ahí, cosa que la web no hace.
  final bool expired;

  bool get signedIn => session != null;
}

/// Quién está dentro. Arranca leyendo el almacenamiento seguro.
class SessionController extends AsyncNotifier<SessionState> {
  SessionHolder get _holder => ref.read(sessionHolderProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<SessionState> build() async {
    final sub = _holder.onExpired.listen((_) {
      final demo = state.value?.session?.demo ?? false;
      state = const AsyncData(SessionState(expired: true));
      _forget(demo: demo);
    });
    ref.onDispose(sub.cancel);
    return SessionState(session: await _holder.load());
  }

  /// Al salir o vencer la sesión no queda en pantalla nada de la cuenta anterior. Va después de
  /// cambiar el estado: un perfil de demostración que venía en camino ya no vuelve a poner su región.
  void _forget({required bool demo}) {
    // El idioma de vista previa de la bienvenida no pasa a la próxima cuenta.
    ref.invalidate(displayLanguageProvider);
    if (!demo) return;
    // La demostración no deja su región ni su tema: vuelven los del dispositivo.
    ref.invalidate(appRegionProvider);
    ref.invalidate(themeModeProvider);
    unawaited(_restoreRegion());
  }

  /// La guardada puede haber cambiado desde que abrió la app: la de arranque no basta.
  Future<void> _restoreRegion() async {
    final saved = await ref.read(regionStoreProvider).read();
    if (saved == null || !ref.mounted || state.value?.session != null) return;
    await ref.read(appRegionProvider.notifier).set(saved, persist: false);
  }

  /// Lanza ApiException si el servidor rechaza; la pantalla decide el mensaje.
  Future<void> signIn({required String email, required String password}) async {
    final session = await _repo.login(email: email, password: password);
    await _holder.save(session);
    state = AsyncData(SessionState(session: session));
  }

  /// MODO DEMOSTRACIÓN: entra con una cuenta sintética que no sale a la red. Solo existe en
  /// compilaciones de desarrollo con DEMO_MODE=true; en cualquier otra lanza error.
  Future<void> signInDemo(String scenario) async {
    if (!ref.read(appConfigProvider).demoMode) throw StateError('El modo demostración está apagado');
    final session = Session.demo(scenario);
    // Cada entrada estrena repositorio: el registro de llamadas no se hereda de la anterior.
    ref.invalidate(demoOnboardingRepositoryProvider);
    await _holder.save(session);
    state = AsyncData(SessionState(session: session));
  }

  /// Cierra la sesión en el servidor si se puede; en el dispositivo, siempre.
  Future<void> signOut() => _leaving ??= _signOut().whenComplete(() => _leaving = null);

  /// Una sola salida en curso: una segunda, al terminar tarde, borraría el ingreso que se hizo entre medias.
  Future<void>? _leaving;

  Future<void> _signOut() async {
    final current = _holder.current;
    if (current != null && !current.demo) {
      try {
        // Tope corto: cerrar sesión en el dispositivo no puede esperar a un servidor dormido.
        await _repo.logout(current.refreshToken).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Sin red o token vencido: igual se borra aquí. El refresh caduca solo en 30 días.
      }
    }
    await _holder.clear();
    state = const AsyncData(SessionState());
    _forget(demo: current?.demo ?? false);
  }
}

final sessionControllerProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Perfil del usuario dentro (términos y región). Se vuelve a pedir al cambiar de usuario.
/// El ingreso vigente (null sin sesión). Es la sesión misma y no su id: salir y volver a entrar
/// empieza de cero. Renovar el token no la cambia.
final accountProvider = Provider<Session?>(
  (ref) => ref.watch(sessionControllerProvider.select((s) => s.value?.session)),
);

/// Datos de una cuenta: una copia por ingreso. Un FutureProvider único no sirve,
/// porque conserva el último valor también si la carga siguiente falla: sin conexión, la cuenta que
/// entra veía la plata de la que salió.
FutureProviderFamily<T, Session?> perAccount<T>(FutureOr<T> Function(Ref ref) load) =>
    FutureProvider.family<T, Session?>((ref, account) {
      // La copia de quien salió no pide nada: se llenaría con la sesión de quien entró.
      if (ref.watch(accountProvider) != account) return Completer<T>().future;
      return load(ref);
    });

final profileProvider = perAccount<UserProfile>((ref) async {
  final session = ref.watch(sessionControllerProvider.select((s) => s.value?.session));
  if (session != null && session.demo) {
    // Perfil sintético de la demostración: no viene de ningún servidor. La región es la que guardó
    // la demostración (o la de una cuenta nueva), así al reabrir la app siguen el país, el idioma y
    // la moneda. No se guarda en el dispositivo: la próxima cuenta real no la hereda.
    final store = ref.watch(demoStateStoreProvider);
    final region = (await store.read(session.user.id)).region ?? kDefaultRegion;
    if (ref.mounted && ref.read(accountProvider) == session && region != ref.read(appRegionProvider)) {
      unawaited(ref.read(appRegionProvider.notifier).set(region, persist: false));
    }
    return UserProfile(
      id: session.user.id,
      email: session.user.email,
      name: session.user.name,
      termsAccepted: true,
      country: region.country,
      currency: region.currency,
      language: region.language,
    );
  }
  return ref.read(authRepositoryProvider).me().then((profile) {
    // useSyncProfile de la web: el formato y el idioma siguen a la cuenta (puede haber cambiado en
    // otro dispositivo, o el teléfono está en otro idioma).
    final region = Region.fromJson({
      'country': profile.country,
      'currency': profile.currency,
      'language': profile.language,
    });
    // Una respuesta tardía de quien salió no le cambia la moneda a quien entró.
    if (ref.mounted && ref.read(accountProvider) == session && region != ref.read(appRegionProvider)) {
      unawaited(ref.read(appRegionProvider.notifier).set(region));
    }
    return profile;
  });
});
