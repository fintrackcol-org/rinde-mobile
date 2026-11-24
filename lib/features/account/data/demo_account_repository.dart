import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import 'account_models.dart';
import 'account_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Ajustes de «Yo» de la cuenta sintética, en memoria (no se guardan en el teléfono). Los recorridos
//  escriben; los escenarios fijos dan demoNoBackend, como Tarjetas y Cuentas. El idioma se guarda en la
//  región de la demo, igual que el país de la bienvenida. El nombre y las categorías no se cambian en
//  ninguna demo: el nombre sale de la sesión sintética y las categorías de la demo son las 15 de todos.
// ─────────────────────────────────────────────────────────────────────────────

/// Operaciones del panel «DEMO» que se pueden hacer fallar.
enum DemoAccountOperation {
  /// Lecturas de avisos y WhatsApp.
  read,

  /// Todas las escrituras.
  write,
}

const _journeys = {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan};

const _noBackend = ApiException(
  code: ApiCodes.demoNoBackend,
  serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
);

class DemoAccountRepository implements AccountRepository {
  DemoAccountRepository({required this.userId, required this.stateStore, required this.controls});

  final String userId;
  final DemoStateStore stateStore;
  final DemoControlsNotifier controls;

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  var _reminders = const ReminderSettings(times: [], timezone: 'America/Bogota', cardReminders: true);
  var _whatsapp = const WhatsappLink(available: true, access: WhatsappAccess.approved, linked: false);

  @override
  bool get isDemo => true;

  Future<void> _read() => controls.simulate(DemoAccountOperation.read);

  Future<void> _write({bool always = false}) async {
    await controls.simulate(DemoAccountOperation.write);
    if (!always && !_journeys.contains(scenario)) throw _noBackend;
  }

  @override
  Future<String?> saveName(String? name) async {
    await controls.simulate(DemoAccountOperation.write);
    throw _noBackend;
  }

  @override
  Future<Region> saveLanguage(String language) async {
    // Como el país en la bienvenida: cualquier demo lo guarda en su región.
    await _write(always: true);
    final current = (await stateStore.read(userId)).region ?? kDefaultRegion;
    final saved = current.copyLanguage(language);
    await stateStore.update(userId, (state) => state.withRegion(saved));
    return saved;
  }

  @override
  Future<ReminderSettings> reminderSettings() async {
    await _read();
    return _reminders;
  }

  @override
  Future<ReminderSettings> saveReminderSettings(ReminderSettings settings) async {
    await _write();
    return _reminders = settings;
  }

  @override
  Future<WhatsappLink> whatsapp() async {
    await _read();
    return _whatsapp;
  }

  @override
  Future<WhatsappCode> createWhatsappCode() async {
    await _write();
    // Sin número del bot: no abre ningún chat real. El código nunca se vincula solo.
    return const WhatsappCode(code: 'RINDE-DEMO');
  }

  @override
  Future<void> unlinkWhatsapp() async {
    await _write();
    _whatsapp = const WhatsappLink(available: true, access: WhatsappAccess.approved, linked: false);
  }

  @override
  Future<void> requestWhatsappAccess() async {
    await _write();
    _whatsapp = const WhatsappLink(available: true, access: WhatsappAccess.pending, linked: false);
  }

  @override
  Future<void> createCategory({required String name, required String type}) async {
    await controls.simulate(DemoAccountOperation.write);
    throw _noBackend;
  }

  @override
  Future<void> renameCategory(String key, String name) async {
    await controls.simulate(DemoAccountOperation.write);
    throw _noBackend;
  }

  @override
  Future<int> deleteCategory(String key) async {
    await controls.simulate(DemoAccountOperation.write);
    throw _noBackend;
  }
}

final demoAccountRepositoryProvider = Provider.family<DemoAccountRepository, String>(
  (ref, userId) => DemoAccountRepository(
    userId: userId,
    stateStore: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
  ),
);
