import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/demo_home_repository.dart' show demoFixedPending;
import '../../home/data/home_models.dart' show readMoney;
import '../../home/domain/home_dates.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import 'money_models.dart';
import 'money_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Solo para desarrollo y pruebas: Mi plata de una sesión demo. Cada lectura arma la RESPUESTA
//  SINTÉTICA del contrato real y la lee con los mismos modelos que la API. Sale del mismo DemoState
//  que la bienvenida y el Inicio, para que los tres digan lo mismo.
//  - Escenarios fijos (planListo, teFaltan, negativo, sinPlan): cifras literales; nada se escribe
//    (DEMO_NO_BACKEND), así el plan fijo del Inicio nunca contradice lo editado.
//  - Recorridos (nuevo, movimientos): lo que se guarda queda en DemoState y el Inicio lo refleja.
// ─────────────────────────────────────────────────────────────────────────────

/// Lecturas y escrituras de Mi plata que se pueden hacer fallar desde el panel «DEMO».
enum DemoMoneyOperation {
  /// GET /money-profile.
  profile,

  /// GET /money-profile/income.
  income,

  /// GET /money-profile/adjustments.
  adjustments,

  /// PUT /money-profile/sources, POST /money-profile/commitments y PUT /money-profile.
  write,
}

/// Nombre que pone el servidor a cada fuente cuando no trae uno (validator.js).
const _sourceNames = {
  'sueldo': 'Sueldo',
  'comisiones': 'Sueldo y comisiones',
  'proyectos': 'Proyectos',
  'diario': 'Trabajo por días',
  'mesada': 'Mesada',
};

class DemoMoneyRepository implements MoneyRepository {
  DemoMoneyRepository({
    required this.userId,
    required this.store,
    required this.controls,
    required this.clock,
  });

  final String userId;
  final DemoStateStore store;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  /// Recorrido: lo que se escribe queda guardado.
  bool get _journey => scenario == DemoScenario.nuevo || scenario == DemoScenario.movimientos;

  @override
  bool get isDemo => true;

  Future<DemoState> _read(DemoMoneyOperation op) async {
    await controls.simulate(op);
    return store.read(userId);
  }

  Future<void> _write() async {
    await controls.simulate(DemoMoneyOperation.write);
    if (_journey) return;
    // El mismo texto con que ApiClient rechaza una sesión demo.
    throw const ApiException(
      code: ApiCodes.demoNoBackend,
      serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
    );
  }

  String _day(int offset) {
    final now = clock();
    return isoDay(DateTime(now.year, now.month, now.day + offset));
  }

  @override
  Future<MoneyProfile> profile() async {
    final state = await _read(DemoMoneyOperation.profile);
    final status = demoWelcomeStatus(scenario, state);
    final List<Map<String, dynamic>> commitments = _journey
        ? [
            // shortcut: el id sale de la posición (como en el plan del recorrido); al editar o borrar
            // pagos (4C) tiene que ser fijo.
            for (final (i, c) in state.commitments.indexed)
              {
                'id': 'demo-pago-$i',
                'kind': 'fixed',
                'frequency': 'monthly',
                'month': null,
                ...c,
                'reminder': null,
              },
          ]
        : [
            for (final p in demoFixedPending(scenario, state, _day))
              {
                'id': p['id'],
                'name': p['name'],
                'amount': p['amount'],
                'dayOfMonth': int.parse((p['date'] as String).substring(8)),
                'kind': 'fixed',
                'frequency': 'monthly',
                'month': null,
                'reminder': null,
              },
          ];
    final subscriptions = [
      for (final c in commitments)
        if (c['kind'] == 'subscription') readMoney(c['amount']) ?? 0,
    ];
    final now = clock();
    return MoneyProfile.fromJson({
      'incomeType': status.incomeType,
      'payDays': status.payDays,
      'balance': status.balance,
      // La de la última corrección; si no, fija en el mes: no cambia en cada lectura.
      'balanceAt': status.balance == null
          ? null
          : state.adjustments.lastOrNull?['createdAt'] ?? DateTime.utc(now.year, now.month).toIso8601String(),
      'money': status.money,
      'totals': {'income': status.income, 'expense': status.expense},
      'welcomeDone': status.welcomeDone,
      'tutorialDone': status.tutorialDone,
      'commitments': commitments,
      'subscriptions': {
        'count': subscriptions.length,
        'monthly': readMoney(subscriptions.fold<num>(0, (sum, v) => sum + v)),
      },
    });
  }

  @override
  Future<IncomeOverview> income() async {
    final state = await _read(DemoMoneyOperation.income);
    return IncomeOverview.fromJson(_journey ? _journeyIncome(state) : _fixedIncome(state));
  }

  /// Cifras de cada escenario fijo, calculadas a mano con income.logic.js e income.service.js de
  /// Rinde Web (la tabla está en demo_money_repository_test.dart).
  Map<String, dynamic> _fixedIncome(DemoState state) {
    final m = state.fixed;
    Map<String, dynamic> source(
      String kind, {
      num? amount,
      List<int> payDays = const [],
      List<num> months = const [],
    }) => {
      'id': 'demo-fuente-$kind',
      'name': _sourceNames[kind],
      'kind': kind,
      'frequency': kind == 'proyectos' ? 'irregular' : 'mensual',
      'payDays': payDays,
      'amount': amount == null ? null : m(amount),
      'low': null,
      'high': null,
      'lastMonths': [for (final v in months) m(v)],
      'workDays': null,
    };
    Map<String, dynamic> cushion(num goal) => {
      'goal': m(goal),
      'suggestedGoal': m(goal),
      'saved': 0,
      'metaId': null,
    };
    // SMMLV 2026: con lo que les entra, el aporte sale sobre el mínimo (40 % < 1 SMMLV).
    final pila = {
      'ibc': m(1750905),
      'health': m(218863),
      'pension': m(280145),
      'total': m(499008),
      'smmlv': m(1750905),
    };
    final none = {
      'sources': const <Object>[],
      'normal': 0,
      'lean': 0,
      'fixed': 0,
      'basis': 'none',
      'estimated': false,
      'variable': false,
      'independent': false,
      'ownSalary': null,
      'cushion': cushion(0),
      'socialSecurity': null,
      'workDay': null,
    };
    return switch (scenario) {
      DemoScenario.planListo => {
        ...none,
        'sources': [
          source('proyectos', months: [700000, 650000, 800000]),
        ],
        'normal': m(700000),
        'lean': m(650000),
        'basis': 'declared',
        'variable': true,
        'independent': true,
        'ownSalary': m(600000),
        'cushion': cushion(2250000),
        'socialSecurity': pila,
      },
      DemoScenario.teFaltan => {
        ...none,
        'sources': [
          source('proyectos', months: [400000]),
        ],
        'normal': m(400000),
        'lean': m(320000),
        'basis': 'declared',
        'estimated': true,
        'variable': true,
        'independent': true,
        'ownSalary': m(300000),
        'cushion': cushion(3050000),
        'socialSecurity': pila,
      },
      DemoScenario.negativo => {
        ...none,
        'sources': [
          source('sueldo', amount: 600000, payDays: [15, 30]),
        ],
        'normal': m(600000),
        'lean': m(600000),
        'fixed': m(600000),
        'basis': 'declared',
        'cushion': cushion(950000),
      },
      _ => none,
    };
  }

  /// Cuánto deja una fuente al mes según lo que dijo el usuario: `declaredMonth` de
  /// `income.logic.js`, para que la tarjeta y la hoja digan lo mismo que diría el servidor.
  static ({num fixed, num normal, num lean, bool estimated}) _declared(Map<String, dynamic> s) {
    final amount = readMoney(s['amount']) ?? 0;
    switch (s['kind']) {
      case 'sueldo':
        return (fixed: amount, normal: amount, lean: amount, estimated: false);
      case 'mesada':
        const perMonth = {'quincenal': 2, 'semanal': 52 / 12, 'diario': 30};
        final monthly = amount * (perMonth[s['frequency']] ?? 1);
        return (fixed: monthly, normal: monthly, lean: monthly, estimated: false);
      case 'comisiones':
        final low = readMoney(s['low']) ?? 0;
        final high = readMoney(s['high']) ?? low;
        return (fixed: amount, normal: amount + (low + high) / 2, lean: amount + low, estimated: false);
      case 'proyectos':
        final months = [
          for (final v in s['lastMonths'] as List? ?? const []) ?readMoney(v),
        ].where((v) => v > 0).toList()..sort();
        if (months.isEmpty) return (fixed: 0, normal: 0, lean: 0, estimated: false);
        if (months.length == 1) {
          return (fixed: 0, normal: months.first, lean: months.first * 0.8, estimated: true);
        }
        final mid = months.length ~/ 2;
        final median = months.length.isOdd ? months[mid] : (months[mid - 1] + months[mid]) / 2;
        return (fixed: 0, normal: median, lean: months.first, estimated: false);
      case 'diario':
        final normal = amount * (readMoney(s['workDays']) ?? 0) * 52 / 12;
        return (fixed: 0, normal: normal, lean: normal * 0.8, estimated: true);
      default:
        return (fixed: 0, normal: 0, lean: 0, estimated: false);
    }
  }

  /// Recorrido: las fuentes guardadas con su mes normal y flaco, como `monthlyIncome` sin historial.
  /// shortcut: no imita la base «history» del servidor (2 meses completos con ingresos), ni el
  /// colchón ni la PILA, que dependen de pagos y ritmo; si la demo necesita mostrarlos, portarlos.
  Map<String, dynamic> _journeyIncome(DemoState state) {
    final kinds = {for (final s in state.sources) s['kind']};
    final declared = state.sources.map(_declared).toList();
    final normal = declared.fold<num>(0, (sum, d) => sum + d.normal);
    final lean = declared.fold<num>(0, (sum, d) => sum + d.lean);
    final some = normal > 0;
    final variable = kinds.any(const {'comisiones', 'proyectos', 'diario'}.contains);
    return {
      'sources': [
        for (final (i, s) in state.sources.indexed)
          {'id': 'demo-fuente-$i', 'name': _sourceNames[s['kind']] ?? 'Ingreso', ...s},
      ],
      'normal': some ? normal.round() : 0,
      'lean': some ? lean.round() : 0,
      'fixed': some ? declared.fold<num>(0, (sum, d) => sum + d.fixed).round() : 0,
      'basis': some ? 'declared' : 'none',
      'estimated': some && declared.any((d) => d.estimated),
      'variable': variable,
      'independent': kinds.any(const {'proyectos', 'diario'}.contains),
      // «Págate un sueldo» (ownSalary): el mes flaco menos el 10 %, a 50 000; no si ya tiene sueldo.
      'ownSalary': variable && !kinds.contains('sueldo') && lean > 0
          ? (lean * 0.9 / 50000).round() * 50000
          : null,
      'cushion': {'goal': 0, 'suggestedGoal': 0, 'saved': 0, 'metaId': null},
      'socialSecurity': null,
      'workDay': null,
    };
  }

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) async {
    await _write();
    await store.update(userId, (state) => state.withSources(sources));
  }

  /// Como el servidor: el saldo dicho reemplaza al anterior y, si la plata cambió (en pesos
  /// enteros), queda un ajuste con la de antes. Los fijos no escriben (DEMO_NO_BACKEND).
  @override
  Future<void> saveProfile(Map<String, dynamic> body) async {
    await _write();
    final balance = readMoney(body['balance']);
    if (balance == null) return;
    final now = clock();
    await store.update(userId, (state) {
      final before = demoWelcomeStatus(scenario, state).money;
      final changed = body['resetBalance'] == true && before != null && before.round() != balance.round();
      return state.withBalance(
        balance,
        adjustment: changed
            ? {
                'id': 'demo-ajuste-${state.adjustments.length + 1}',
                'before': before,
                'after': balance,
                'date': isoDay(now),
                'createdAt': now.toUtc().toIso8601String(),
              }
            : null,
      );
    });
  }

  @override
  Future<List<BalanceAdjustment>> adjustments({required String from, required String to}) async {
    final state = await _read(DemoMoneyOperation.adjustments);
    return BalanceAdjustment.listFromJson({
      'data': [
        for (final a in state.adjustments.reversed)
          if ('${a['date']}'.compareTo(from) >= 0 && '${a['date']}'.compareTo(to) <= 0) a,
      ],
    });
  }

  @override
  Future<void> createCommitment(Map<String, dynamic> body) async {
    await _write();
    final state = await store.read(userId);
    final name = '${body['name']}'.trim();
    // Como el servidor: el nombre no se repite (sin distinguir mayúsculas) y hay un tope de 30.
    if (state.commitments.any((c) => '${c['name']}'.toLowerCase() == name.toLowerCase())) {
      throw const ApiException(
        code: 'COMMITMENT_EXISTS',
        status: 409,
        serverMessage: 'Ya tienes un compromiso con ese nombre',
      );
    }
    if (state.commitments.length >= 30) {
      throw const ApiException(
        code: 'COMMITMENT_LIMIT',
        status: 409,
        serverMessage: 'Puedes tener hasta 30 compromisos',
      );
    }
    await store.write(
      userId,
      state.withCommitment({
        'name': name,
        'amount': body['amount'],
        'dayOfMonth': body['dayOfMonth'],
        'kind': body['kind'] ?? 'fixed',
        'frequency': body['frequency'] ?? 'monthly',
        'month': body['month'],
      }),
    );
  }
}

/// Uno por usuario demo. Comparte el estado guardado con la bienvenida y el Inicio de demostración.
final demoMoneyRepositoryProvider = Provider.family<DemoMoneyRepository, String>(
  (ref, userId) => DemoMoneyRepository(
    userId: userId,
    store: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
  ),
);
