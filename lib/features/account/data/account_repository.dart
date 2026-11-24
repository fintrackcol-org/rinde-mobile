import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/region/region.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/home_models.dart' show readMap;
import 'account_models.dart';
import 'demo_account_repository.dart';

/// Ajustes de «Yo» en el servidor (userService.js, pushService.js, whatsappService.js y las categorías
/// de transactionService.js de Rinde Web). El país usa `OnboardingRepository.saveRegion` y eliminar la
/// cuenta, `AuthRepository.deleteAccount`: ya existían.
/// - [ApiAccountRepository]: la real.
/// - `DemoAccountRepository`: MODO DEMOSTRACIÓN, en memoria y sin red.
abstract interface class AccountRepository {
  bool get isDemo;

  /// PATCH /users/me {name}. null lo borra. Devuelve el nombre que quedó.
  Future<String?> saveName(String? name);

  /// PATCH /users/me {language}. Solo el idioma: viajar no lo cambia, ni cambiarlo toca la moneda.
  Future<Region> saveLanguage(String language);

  /// GET /users/me/reminder-settings.
  Future<ReminderSettings> reminderSettings();

  /// PUT /users/me/reminder-settings.
  Future<ReminderSettings> saveReminderSettings(ReminderSettings settings);

  /// GET /whatsapp/link.
  Future<WhatsappLink> whatsapp();

  /// POST /whatsapp/link.
  Future<WhatsappCode> createWhatsappCode();

  /// DELETE /whatsapp/link. Los movimientos no se borran.
  Future<void> unlinkWhatsapp();

  /// POST /whatsapp/link/request: el equipo aprueba el acceso.
  Future<void> requestWhatsappAccess();

  /// POST /categories {name, type, icon, color}.
  Future<void> createCategory({required String name, required String type});

  /// PATCH /categories/:key {name}.
  Future<void> renameCategory(String key, String name);

  /// DELETE /categories/:key: sus movimientos pasan a «Otros» (u «Otros ingresos») y sus
  /// presupuestos se borran. Devuelve cuántos movimientos cambiaron.
  Future<int> deleteCategory(String key);
}

/// Ícono y color con que la web abre «Nueva categoría» (ICON_OPTIONS[0] y COLOR_OPTIONS[0] de
/// lib/categoryStyles.js). La app no dibuja íconos de categoría: se cambian en la web.
const newCategoryIcon = 'paw-print';
const newCategoryColor = 'orange';

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _category(String key) => '/categories/${Uri.encodeComponent(key)}';

  @override
  Future<String?> saveName(String? name) async {
    final value = readMap(await _api.patch('/users/me', body: {'name': name}))['name'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  @override
  Future<Region> saveLanguage(String language) async =>
      Region.fromJson(readMap(await _api.patch('/users/me', body: {'language': language})));

  @override
  Future<ReminderSettings> reminderSettings() async =>
      ReminderSettings.fromJson(await _api.get('/users/me/reminder-settings'));

  @override
  Future<ReminderSettings> saveReminderSettings(ReminderSettings settings) async =>
      ReminderSettings.fromJson(await _api.put('/users/me/reminder-settings', body: settings.toJson()));

  @override
  Future<WhatsappLink> whatsapp() async => WhatsappLink.fromJson(await _api.get('/whatsapp/link'));

  @override
  Future<WhatsappCode> createWhatsappCode() async =>
      WhatsappCode.fromJson(await _api.post('/whatsapp/link', auth: true));

  @override
  Future<void> unlinkWhatsapp() => _api.delete('/whatsapp/link');

  @override
  Future<void> requestWhatsappAccess() => _api.post('/whatsapp/link/request', auth: true);

  @override
  Future<void> createCategory({required String name, required String type}) => _api.post(
    '/categories',
    body: {'name': name, 'type': type, 'icon': newCategoryIcon, 'color': newCategoryColor},
    auth: true,
  );

  @override
  Future<void> renameCategory(String key, String name) => _api.patch(_category(key), body: {'name': name});

  @override
  Future<int> deleteCategory(String key) async {
    final moved = readMap(await _api.delete(_category(key)))['moved'];
    return moved is int ? moved : 0;
  }
}

/// Elige la implementación según la sesión: una sesión demo nunca usa la API.
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) return ref.watch(demoAccountRepositoryProvider(session.user.id));
  return ApiAccountRepository(ref.watch(apiClientProvider));
});
