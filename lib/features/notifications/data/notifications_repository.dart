import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/demo_home_repository.dart';
import '../../home/data/home_models.dart' show readList, readMap;
import '../../onboarding/data/demo_onboarding_repository.dart';

/// Un aviso de la bandeja (notificationService.js de la web, FT-0045).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.url,
  });

  static AppNotification? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], body = raw['body'], created = raw['createdAt'];
    final createdAt = created is String ? DateTime.tryParse(created) : null;
    if (id is! String || title is! String || body is! String || createdAt == null) return null;
    return AppNotification(
      id: id,
      title: title,
      body: body,
      read: raw['read'] == true,
      createdAt: createdAt,
      url: raw['url'] is String ? raw['url'] as String : null,
    );
  }

  final String id;
  final String title;
  final String body;

  /// Ruta de la app a la que lleva (p. ej. /app/tarjetas/{id}), o null.
  final String? url;
  final bool read;
  final DateTime createdAt;
}

/// Bandeja de avisos. No hay push en la app: solo se leen los que guarda el servidor.
/// - [ApiNotificationsRepository]: la real.
/// - [DemoNotificationsRepository]: MODO DEMOSTRACIÓN, los avisos sintéticos del Inicio demo, sin red.
abstract interface class NotificationsRepository {
  bool get isDemo;

  /// GET /notifications → `items`, los 30 más recientes (del más nuevo al más viejo).
  Future<List<AppNotification>> list();

  /// POST /notifications/read: todos quedan leídos.
  Future<void> markAllRead();
}

class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<List<AppNotification>> list() async => [
    for (final item in readList(readMap(await _api.get('/notifications'))['items']))
      ?AppNotification.tryParse(item),
  ];

  @override
  Future<void> markAllRead() => _api.post('/notifications/read', auth: true);
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Los avisos son los del escenario fijo (los que cuenta la campana del Inicio demo): marcarlos como
//  leídos no llega a ningún servidor (demoNoBackend) y la campana sigue con su número.
// ─────────────────────────────────────────────────────────────────────────────

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository({required this.home, required this.controls});
  final DemoHomeRepository home;
  final DemoControlsNotifier controls;

  @override
  bool get isDemo => true;

  @override
  Future<List<AppNotification>> list() async => [
    for (final item in readList((await home.demoNotifications())['items'])) ?AppNotification.tryParse(item),
  ];

  @override
  Future<void> markAllRead() async {
    await controls.simulate();
    throw const ApiException(
      code: ApiCodes.demoNoBackend,
      serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
    );
  }
}

/// Una sesión demo nunca usa la API.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) {
    return DemoNotificationsRepository(
      home: ref.watch(demoHomeRepositoryProvider(session.user.id)),
      controls: ref.read(demoControlsProvider.notifier),
    );
  }
  return ApiNotificationsRepository(ref.watch(apiClientProvider));
});
