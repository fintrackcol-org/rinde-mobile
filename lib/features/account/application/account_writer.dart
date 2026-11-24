import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/application/tour_controller.dart' show tourSeenStoreProvider;
import '../../money/application/money_providers.dart' show dismissedStoreProvider;
import '../../money/application/money_writer.dart' show inDoubt;
import '../../movements/application/movement_saver.dart' show afterMovementChange, pendingStoreProvider;
import '../../movements/application/movements_controller.dart' show movementCategoriesProvider;
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../../onboarding/data/draft_store.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/account_models.dart';
import '../data/account_repository.dart';
import '../data/demo_account_repository.dart' show DemoAccountOperation;
import 'account_providers.dart';

/// Escrituras de «Yo», con el patrón de CardsWriter y DebtsWriter:
/// - un solo envío a la vez por operación y cuenta ([_once]);
/// - `_sameAccount` antes de enviar lo que se leyó, y una respuesta tardía de quien salió no cambia la
///   región de quien entró;
/// - todas se pueden repetir sin riesgo (PATCH y PUT: gana el último; crear una categoría repetida da
///   409 `CATEGORY_EXISTS`; borrar una que ya no está da 404, que cuenta como hecho).
///
/// Eliminar la cuenta además borra todo lo de esa cuenta en el teléfono ([forgetAccountOnDevice]).
class AccountWriter {
  AccountWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<Object?>>{};

  /// Cuentas cuyo DELETE quedó en duda sin poder comprobarse: si el siguiente da un 401 auténtico, es
  /// que el primero sí la borró.
  final _unresolved = <String>{};

  AccountRepository get _repo => _ref.read(accountRepositoryProvider);

  Future<T> _once<T>(String operation, Future<T> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Un segundo toque espera el resultado del primero, sin un segundo envío.
    return (_running[key] ??= send().whenComplete(() {
          _running.remove(key);
        }))
        as Future<T>;
  }

  /// Otra cuenta entró mientras se leía: lo que se iba a mandar no es de ella.
  void _sameAccount(Session? account) {
    if (_ref.read(accountProvider)?.user.id != account?.user.id) {
      throw StateError('Cambió la cuenta antes de enviar');
    }
  }

  bool _current(Session? account) => _ref.read(accountProvider) == account;

  /// PATCH /users/me {name}. null lo borra. Devuelve el que quedó.
  Future<String?> saveName(String? name) => _once('name', () async {
    final account = _ref.read(accountProvider);
    final saved = await _repo.saveName(name);
    if (_current(account)) _ref.invalidate(profileProvider(account));
    return saved;
  });

  /// CountrySettings.jsx: el país, con la moneda del país solo mientras no haya movimientos
  /// (`CURRENCY_LOCKED`, lo resuelve `saveRegion`). El idioma no cambia.
  Future<Region> saveCountry(String country) => _once('country', () async {
    final account = _ref.read(accountProvider);
    final before = _ref.read(appRegionProvider);
    final saved = await _ref
        .read(onboardingRepositoryProvider)
        .saveRegion(country: country, language: before.language);
    _apply(account, saved, before);
    return saved;
  });

  /// LanguageSettings.jsx: solo el idioma. La app cambia los textos en el acto (la web recarga).
  Future<Region> saveLanguage(String language) => _once('language', () async {
    final account = _ref.read(accountProvider);
    final before = _ref.read(appRegionProvider);
    final saved = await _repo.saveLanguage(language);
    _apply(account, saved, before);
    return saved;
  });

  void _apply(Session? account, Region saved, Region before) {
    if (!_current(account)) return;
    // La demostración no deja su región en el dispositivo.
    unawaited(_ref.read(appRegionProvider.notifier).set(saved, persist: !(account?.demo ?? false)));
    _ref.invalidate(profileProvider(account));
    // Sin movimientos, la moneda siguió al país: todo se vuelve a pedir en la nueva (la web recarga).
    if (saved.currency != before.currency) afterMovementChange(_ref.container);
  }

  /// «Pago de tarjetas»: cambia solo el aviso, con las horas y la zona que el servidor ya tiene.
  Future<ReminderSettings> setCardReminders(bool on) => _once('reminders', () async {
    final account = _ref.read(accountProvider);
    final current = await _ref.read(reminderSettingsProvider(account).future);
    _sameAccount(account);
    final saved = await _repo.saveReminderSettings(current.withCardReminders(on));
    if (_current(account)) _ref.invalidate(reminderSettingsProvider(account), asReload: true);
    return saved;
  });

  /// POST /whatsapp/link: un código nuevo.
  Future<WhatsappCode> createWhatsappCode() => _once('whatsapp-code', () => _repo.createWhatsappCode());

  /// «Ya lo envié» y al cerrar la hoja: vuelve a leer si quedó conectado.
  void reloadWhatsapp() => _ref.invalidate(whatsappLinkProvider(_ref.read(accountProvider)), asReload: true);

  Future<void> unlinkWhatsapp() => _once('whatsapp-unlink', () async {
    await _repo.unlinkWhatsapp();
    reloadWhatsapp();
  });

  Future<void> requestWhatsappAccess() => _once('whatsapp-access', () async {
    await _repo.requestWhatsappAccess();
    reloadWhatsapp();
  });

  void _categoriesChanged({bool movements = false}) {
    _ref.invalidate(movementCategoriesProvider, asReload: true);
    if (movements) afterMovementChange(_ref.container);
  }

  /// [type]: `gasto` o `ingreso`.
  Future<void> createCategory({required String name, required String type}) =>
      _once('category-create', () async {
        await _repo.createCategory(name: name, type: type);
        _categoriesChanged();
      });

  Future<void> renameCategory(String key, String name) => _once('category-edit $key', () async {
    try {
      await _repo.renameCategory(key, name);
    } finally {
      // También con 404: ya no existe y la lista lo muestra.
      _categoriesChanged();
    }
  });

  /// Devuelve cuántos movimientos pasaron a «Otros». Un 404 (el de un reintento) cuenta como borrada.
  Future<int> deleteCategory(String key) => _once('category-delete $key', () async {
    var moved = 0;
    try {
      moved = await _repo.deleteCategory(key);
    } on ApiException catch (e) {
      if (e.status != 404) {
        // En duda pudo borrarse: la lista y los movimientos se vuelven a pedir.
        _categoriesChanged(movements: inDoubt(e));
        rethrow;
      }
    }
    // Aunque no moviera nada, el servidor borró sus presupuestos: Planear y el Inicio se vuelven a pedir.
    _categoriesChanged(movements: true);
    return moved;
  });

  /// DeleteAccount.jsx (FT-0017): DELETE /users/me con la contraseña; al terminar sale y no deja nada
  /// de la cuenta en el teléfono. En duda (se venció la espera o 5xx) se comprueba leyendo el perfil:
  /// si la cuenta ya no existe, cuenta como eliminada; si sigue o no se sabe, el error llega a la hoja.
  /// Si no se supo, el reintento que da un 401 auténtico (la cuenta ya no está) también cuenta.
  /// En la demostración solo la reinicia y sale.
  Future<void> deleteAccount(String password) => _once('delete-account', () async {
    final account = _ref.read(accountProvider);
    if (account == null) return;
    if (account.demo) {
      await _ref.read(demoControlsProvider.notifier).simulate(DemoAccountOperation.write);
      await _ref.read(demoOnboardingRepositoryProvider(account.user.id)).reset();
    } else {
      final auth = _ref.read(authRepositoryProvider);
      try {
        await auth.deleteAccount(password);
      } on ApiException catch (e, stack) {
        final id = account.user.id;
        final gone = inDoubt(e) ? await _gone(auth) : _unresolved.contains(id) && _authGone(e);
        if (gone != true) {
          if (gone == null) _unresolved.add(id);
          Error.throwWithStackTrace(e, stack);
        }
      }
    }
    await _ref.read(sessionControllerProvider.notifier).leaveDeleted();
    await forgetAccountOnDevice(_ref, account.user.id);
  });

  /// Un 401 del servidor, no el sintético del interceptor cuando renovar falló por red
  /// (NETWORK, TIMEOUT o REFRESH_FAILED, también con status 401).
  static bool _authGone(ApiException e) =>
      e.status == 401 && (e.code == ApiCodes.unauthorized || e.code == ApiCodes.tokenExpired);

  /// ¿La cuenta ya no existe? true: un «no autorizado» o «no existe»; false: sigue; null: no se sabe.
  static Future<bool?> _gone(AuthRepository auth) async {
    try {
      await auth.me();
      return false;
    } on ApiException catch (e) {
      return _authGone(e) || e.status == 404 ? true : null;
    } on Object {
      return null;
    }
  }
}

/// Lo que la app guarda de una cuenta en el teléfono: la cola sin conexión (con sus rechazados), el
/// borrador de la bienvenida, la marca del tutorial y los avisos de pago cerrados. Lo de la demostración
/// lo borra su reinicio.
/// El tema, la región y «ocultar montos» son del dispositivo, no de la cuenta.
Future<void> forgetAccountOnDevice(Ref ref, String userId) async {
  await Future.wait([
    ref.read(pendingStoreProvider).clear(userId),
    ref.read(draftStoreProvider).clear(userId),
    ref.read(tourSeenStoreProvider).clear(userId),
    ref.read(dismissedStoreProvider).clear(userId),
  ]);
}

final accountWriterProvider = Provider<AccountWriter>(AccountWriter.new);
