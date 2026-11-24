import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/demo_home_repository.dart';
import '../../home/data/home_models.dart' show readList, readMap, readMoney;
import '../../onboarding/data/demo_onboarding_repository.dart';

/// Un pago con Apple Pay que llegó desde Atajos del iPhone y espera aprobación (FT-0047).
class IncomingPayment {
  const IncomingPayment({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.date,
    this.card,
    this.possibleDuplicate = false,
  });

  static IncomingPayment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final amount = readMoney(raw['amount']);
    final id = raw['id'], merchant = raw['merchant'], date = raw['date'];
    if (id is! String || merchant is! String || date is! String || amount == null) return null;
    return IncomingPayment(
      id: id,
      merchant: merchant,
      amount: amount,
      date: date,
      card: raw['card'] is String ? raw['card'] as String : null,
      possibleDuplicate: raw['possibleDuplicate'] == true,
    );
  }

  final String id;

  /// Comercio.
  final String merchant;
  final num amount;

  /// AAAA-MM-DD.
  final String date;

  /// Nombre de la tarjeta en Wallet (solo texto: no es una tarjeta de Rinde).
  final String? card;

  /// Ya hay un gasto igual entre un día antes y uno después.
  final bool possibleDuplicate;
}

/// Pagos por confirmar (pendingPaymentService.js de la web).
/// - [ApiToConfirmRepository]: la real.
/// - [DemoToConfirmRepository]: MODO DEMOSTRACIÓN, los pagos sintéticos del Inicio demo, sin red.
abstract interface class ToConfirmRepository {
  bool get isDemo;

  /// GET /pending-payments → `items` (solo los pendientes, del más nuevo al más viejo).
  Future<List<IncomingPayment>> list();

  /// POST /pending-payments/:id/confirm `{description, category?}`: crea el gasto. Sin categoría la
  /// elige la IA. El contrato no recibe tarjeta: el gasto queda como pagado en efectivo o débito.
  /// 409 `ALREADY_RESOLVED` si ya se confirmó o descartó (también el reintento de uno que sí llegó).
  Future<void> confirm(String id, {required String description, String? category});

  /// POST /pending-payments/:id/discard: no se anota nada. 409 `ALREADY_RESOLVED` como arriba.
  Future<void> discard(String id);
}

class ApiToConfirmRepository implements ToConfirmRepository {
  ApiToConfirmRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  String _path(String id, String action) => '/pending-payments/${Uri.encodeComponent(id)}/$action';

  @override
  Future<List<IncomingPayment>> list() async => [
    for (final item in readList(readMap(await _api.get('/pending-payments'))['items']))
      ?IncomingPayment.tryParse(item),
  ];

  @override
  Future<void> confirm(String id, {required String description, String? category}) =>
      _api.post(_path(id, 'confirm'), body: {'description': description, 'category': ?category}, auth: true);

  @override
  Future<void> discard(String id) => _api.post(_path(id, 'discard'), auth: true);
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Los pagos por confirmar solo existen en el escenario fijo `planListo` (los mismos que cuenta el
//  Inicio demo): confirmarlos o descartarlos no llega a ningún servidor (demoNoBackend).
// ─────────────────────────────────────────────────────────────────────────────

class DemoToConfirmRepository implements ToConfirmRepository {
  DemoToConfirmRepository({required this.home, required this.controls});
  final DemoHomeRepository home;
  final DemoControlsNotifier controls;

  static const _noBackend = ApiException(
    code: ApiCodes.demoNoBackend,
    serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
  );

  @override
  bool get isDemo => true;

  @override
  Future<List<IncomingPayment>> list() async => [
    for (final item in await home.demoPendingPayments()) ?IncomingPayment.tryParse(item),
  ];

  @override
  Future<void> confirm(String id, {required String description, String? category}) async {
    await controls.simulate();
    throw _noBackend;
  }

  @override
  Future<void> discard(String id) async {
    await controls.simulate();
    throw _noBackend;
  }
}

/// Una sesión demo nunca usa la API.
final toConfirmRepositoryProvider = Provider<ToConfirmRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) {
    return DemoToConfirmRepository(
      home: ref.watch(demoHomeRepositoryProvider(session.user.id)),
      controls: ref.read(demoControlsProvider.notifier),
    );
  }
  return ApiToConfirmRepository(ref.watch(apiClientProvider));
});
