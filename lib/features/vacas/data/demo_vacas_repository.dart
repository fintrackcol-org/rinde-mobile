import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/domain/home_dates.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import 'vaca_models.dart';
import 'vacas_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Una meta y una vaca sintéticas solo en el escenario fijo `planListo`, con la forma exacta de
//  GET /vacas/:id y leídas con los mismos modelos que la API. Ninguna escritura llega a un servidor
//  (demoNoBackend), en ningún escenario: aportar crearía un gasto y movería Mi plata, que en la demo
//  sale de valores fijos, y las cuotas y estados los calcula solo el servidor.
//  shortcut: los recorridos (nuevo, movimientos, sinPlan) no guardan metas; si se quiere probar
//  crear y aportar en la demo, guardar como Cuentas (demo_debts_repository.dart).
// ─────────────────────────────────────────────────────────────────────────────

const _noBackend = ApiException(
  code: ApiCodes.demoNoBackend,
  serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
);

const _notFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Vaca no encontrada', status: 404);

class DemoVacasRepository implements VacasRepository {
  DemoVacasRepository({
    required this.userId,
    required this.stateStore,
    required this.controls,
    required this.clock,
  });

  final String userId;
  final DemoStateStore stateStore;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  @override
  bool get isDemo => true;

  Future<List<Map<String, dynamic>>> _seed() async {
    await controls.simulate();
    if (DemoScenario.fromUserId(userId) != DemoScenario.planListo) return const [];
    return demoPlanListoVacas(await stateStore.read(userId), clock());
  }

  @override
  Future<List<Vaca>> list() async => [for (final raw in await _seed()) Vaca.fromJson(raw)];

  @override
  Future<Vaca> get(String id) async {
    final raw = (await _seed()).where((v) => v['id'] == id).firstOrNull;
    if (raw == null) throw _notFound;
    return Vaca.fromJson(raw);
  }

  Future<Never> _write() async {
    await controls.simulate();
    throw _noBackend;
  }

  @override
  Future<Vaca> create(Map<String, dynamic> body) => _write();

  @override
  Future<Vaca> update(String id, Map<String, dynamic> body) => _write();

  @override
  Future<void> delete(String id) => _write();

  @override
  Future<InvitationPreview> preview(String code) => _write();

  @override
  Future<Vaca> join(String code) => _write();

  @override
  Future<void> regenerateCode(String id) => _write();

  @override
  Future<bool> invite(String id, String email) => _write();

  @override
  Future<void> cancelInvitation(String id, String email) => _write();

  @override
  Future<void> updateMember(String id, String userId, Map<String, dynamic> body) => _write();

  @override
  Future<void> removeMember(String id, String userId) => _write();

  @override
  Future<num> contribute(String id, Map<String, dynamic> body, {required String localId}) => _write();

  @override
  Future<void> deleteContribution(String id, String contributionId) => _write();

  // El consejo lo arma la IA del servidor: en la demo la tarjeta dice que no se pudo traer.
  @override
  Future<VacaAdvice> advice(String id) => _write();

  @override
  Future<({int reminded, int delivered})> remind(String id) => _write();

  @override
  Future<Vaca> makePersonal(String id) => _write();
}

/// La meta «Moto» (personal, con fecha) y la vaca «Paseo de fin de año» (tres personas, partes
/// iguales, la usuaria administra). Fechas relativas a hoy; la proyección se arma como
/// buildProjection de vacas.service.js para que las cifras cuadren entre sí.
List<Map<String, dynamic>> demoPlanListoVacas(DemoState state, DateTime now) {
  final m = state.fixed;
  final today = DateTime(now.year, now.month, now.day);
  String day(int offset) => isoDay(today.add(Duration(days: offset)));
  final updated = now.toUtc().toIso8601String();

  Map<String, dynamic> projection({
    required num goal,
    required num total,
    required int age,
    required int left,
  }) {
    final remaining = goal - total;
    final days = age + 1;
    final estimated = remaining > 0 && total > 0 ? day((remaining * days / total).ceil()) : null;
    final perDay = remaining > 0 && left > 0 ? (remaining / left).ceil() : null;
    return {
      'remaining': remaining,
      'averagePerDay': (total / days).round(),
      'estimatedDate': estimated,
      'daysLeft': left,
      'neededPerDay': perDay,
      'neededPerWeek': perDay == null ? null : (remaining * 7 / left).ceil(),
      'onTrack': remaining == 0 || (estimated != null && estimated.compareTo(day(left)) <= 0),
    };
  }

  final motoGoal = m(3000000), motoTotal = m(750000);
  final paseoGoal = m(1200000), mine = m(250000), laura = m(400000);
  final quota = m(400000);
  return [
    {
      'id': 'demo-meta-moto',
      'name': 'Moto',
      'description': 'La cuota inicial de la moto',
      'goal': motoGoal,
      'deadline': day(120),
      'split': 'igual',
      'code': null,
      'personal': true,
      'role': 'admin',
      'total': motoTotal,
      'percentage': 25,
      'status': 'activa',
      'membersCount': 1,
      'myQuota': motoGoal,
      'myContributed': motoTotal,
      'myRemaining': motoGoal - motoTotal,
      'myStatus': 'al_dia',
      'projection': projection(goal: motoGoal, total: motoTotal, age: 45, left: 120),
      'members': [
        {
          'userId': 'demo-yo',
          'name': 'Tú',
          'isMe': true,
          'role': 'admin',
          'quota': motoGoal,
          'customQuota': null,
          'contributed': motoTotal,
          'remaining': motoGoal - motoTotal,
          'percentage': 25,
          'status': 'al_dia',
        },
      ],
      'contributions': [
        {
          'id': 'demo-aporte-moto-2',
          'name': 'Tú',
          'isMe': true,
          'amount': m(450000),
          'note': null,
          'date': day(-8),
        },
        {
          'id': 'demo-aporte-moto-1',
          'name': 'Tú',
          'isMe': true,
          'amount': m(300000),
          'note': null,
          'date': day(-40),
        },
      ],
      'invitations': const <Object>[],
      'updatedAt': updated,
    },
    {
      'id': 'demo-vaca-paseo',
      'name': 'Paseo de fin de año',
      'description': 'Hotel y transporte',
      'goal': paseoGoal,
      'deadline': day(40),
      'split': 'igual',
      'code': 'K7M2QX',
      'personal': false,
      'role': 'admin',
      'total': mine + laura,
      'percentage': 54.2,
      'status': 'activa',
      'membersCount': 3,
      'myQuota': quota,
      'myContributed': mine,
      'myRemaining': quota - mine,
      'myStatus': 'al_dia',
      'projection': projection(goal: paseoGoal, total: mine + laura, age: 20, left: 40),
      'members': [
        {
          'userId': 'demo-yo',
          'name': 'Tú',
          'isMe': true,
          'role': 'admin',
          'quota': quota,
          'customQuota': null,
          'contributed': mine,
          'remaining': quota - mine,
          'percentage': 62.5,
          'status': 'al_dia',
        },
        {
          'userId': 'demo-laura',
          'name': 'Laura',
          'isMe': false,
          'role': 'miembro',
          'quota': quota,
          'customQuota': null,
          'contributed': laura,
          'remaining': 0,
          'percentage': 100,
          'status': 'cumplido',
        },
        {
          'userId': 'demo-andres',
          'name': 'Andrés',
          'isMe': false,
          'role': 'miembro',
          'quota': quota,
          'customQuota': null,
          'contributed': 0,
          'remaining': quota,
          'percentage': 0,
          'status': 'atrasado',
        },
      ],
      'contributions': [
        {
          'id': 'demo-aporte-paseo-2',
          'name': 'Tú',
          'isMe': true,
          'amount': mine,
          'note': null,
          'date': day(-6),
        },
        {
          'id': 'demo-aporte-paseo-1',
          'name': 'Laura',
          'isMe': false,
          'amount': laura,
          'note': 'Mi parte',
          'date': day(-15),
        },
      ],
      'invitations': const <Object>[],
      'updatedAt': updated,
    },
  ];
}

/// Uno por usuario demo.
final demoVacasRepositoryProvider = Provider.family<DemoVacasRepository, String>(
  (ref, userId) => DemoVacasRepository(
    userId: userId,
    stateStore: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
  ),
);
