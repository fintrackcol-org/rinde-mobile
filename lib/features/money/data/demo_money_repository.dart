import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/demo_home_repository.dart' show demoFixedPending, demoJourneyPending;
import '../../home/data/home_models.dart' show readMoney;
import '../../home/domain/home_dates.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../../plan/data/plan_models.dart';
import 'money_models.dart';
import 'money_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Solo para desarrollo y pruebas: Mi plata de una sesión demo. Cada lectura arma la RESPUESTA
//  SINTÉTICA del contrato real y la lee con los mismos modelos que la API. Sale del mismo DemoState
//  que la bienvenida y el Inicio, para que los tres digan lo mismo.
//  - Escenarios fijos (planListo, teFaltan, negativo): cifras literales; nada se escribe
//    (DEMO_NO_BACKEND), así el plan fijo del Inicio nunca contradice lo editado.
//  - Recorridos (nuevo, movimientos) y sinPlan: lo que se guarda queda en DemoState y el Inicio lo
//    refleja. sinPlan no tiene plan fijo que contradecir: es quien omitió la bienvenida y lo configura
//    después en Mi plata.
// ─────────────────────────────────────────────────────────────────────────────

/// Lecturas y escrituras de Mi plata que se pueden hacer fallar desde el panel «DEMO».
enum DemoMoneyOperation {
  /// GET /money-profile.
  profile,

  /// GET /money-profile/income.
  income,

  /// GET /money-profile/adjustments.
  adjustments,

  /// GET /money-profile/calendar.
  calendar,

  /// PUT /money-profile/sources, POST, PUT y DELETE /money-profile/commitments y PUT /money-profile.
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

  /// Recorrido (o sinPlan): lo que se escribe queda guardado.
  bool get _journey =>
      const {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan}.contains(scenario);

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
            // El id es fijo (el mismo del plan del recorrido): no cambia al renombrar.
            for (final c in state.commitmentsWithIds)
              {'kind': 'fixed', 'frequency': 'monthly', 'month': null, ...c, 'reminder': null},
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
    // Como subscriptionsSummary del servidor: las anuales cuentan su doceava parte.
    final subscriptions = [
      for (final c in commitments)
        if (c['kind'] == 'subscription')
          (readMoney(c['amount']) ?? 0) / (c['frequency'] == 'yearly' ? 12 : 1),
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
        'monthly': subscriptions.fold<num>(0, (sum, v) => sum + v).round(),
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
  Future<void> saveSources(List<Map<String, dynamic>> sources, {int? expectedVersion}) async {
    await _write();
    await store.update(userId, (state) => state.withSources(sources));
  }

  /// Como el servidor: el saldo dicho reemplaza al anterior y, si la plata cambió (en pesos
  /// enteros), queda un ajuste con la de antes. Los fijos no escriben (DEMO_NO_BACKEND).
  @override
  Future<void> saveProfile(Map<String, dynamic> body) async {
    await _write();
    final balance = readMoney(body['balance']);
    final now = clock();
    await store.update(userId, (before) {
      // Reemplazo total: el tipo de ingreso y los días también («Tu sueldo»).
      final state = before.withIncomeType(body['incomeType'] as String?, [
        for (final d in body['payDays'] as List? ?? const []) d as int,
      ]);
      if (balance == null) return state;
      final money = demoWelcomeStatus(scenario, state).money;
      final changed = body['resetBalance'] == true && money != null && money.round() != balance.round();
      return state.withBalance(
        balance,
        adjustment: changed
            ? {
                'id': 'demo-ajuste-${state.adjustments.length + 1}',
                'before': money,
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

  /// Escenarios fijos: las mismas ocurrencias (y fechas) del `pending` del plan, por pagar: «Falta por
  /// pagar» da `pendingTotal`. Recorridos: los pagos de este mes, atrasados si su día ya pasó. La demo
  /// nunca marca un pago como hecho (no imita la regla del nombre en los gastos).
  @override
  Future<List<CalendarPayment>> calendar(String month) async => (await monthCalendar(month)).payments;

  /// Los mismos pagos del plan del Inicio, solo en el mes en curso (los demás meses salen vacíos). Lo
  /// que queda después de cada pago es la plata menos lo pagado hasta ese día: la demo no proyecta el
  /// gasto diario (`pace: null`) ni días de pago, y no suma tarjetas ni cuentas (no las tiene en su
  /// plan fijo: el «libre» del Inicio seguiría diciendo otra cosa).
  @override
  Future<PaymentCalendar> monthCalendar(String month) async {
    final state = await _read(DemoMoneyOperation.calendar);
    final today = _day(0);
    final money = _planMoney(state);
    var left = money == null ? null : _cents(money);
    final events = <Map<String, dynamic>>[];
    var pending = 0;
    for (final p in month == today.substring(0, 7) ? _pending(state) : const <Map<String, dynamic>>[]) {
      pending += _cents(p['amount']);
      if (left != null) left -= _cents(p['amount']);
      events.add({
        'subscription': false,
        ...p,
        'kind': 'compromiso',
        'status': (p['date'] as String).compareTo(today) < 0 ? 'atrasado' : 'pendiente',
        'balanceAfter': left == null ? null : _fromCents(left),
        'risk': left == null ? null : (left < 0 ? 'negativo' : 'ok'),
      });
    }
    return PaymentCalendar.fromJson({
      'month': month,
      'today': today,
      'money': money,
      'projectedUntil': null,
      'events': events,
      'cardDates': const <Object>[],
      'totals': {'pending': _fromCents(pending), 'paid': 0},
    });
  }

  /// GET /liquidity sintético: del hoy al fin de mes, la plata menos los pagos del plan (lo atrasado se
  /// paga hoy, como el servidor). Sin gasto diario ni ingresos esperados (ver [monthCalendar]).
  @override
  Future<Liquidity> liquidity() async {
    final state = await _read(DemoMoneyOperation.calendar);
    final today = _day(0);
    final money = _planMoney(state);
    if (money == null) return Liquidity.fromJson({'ready': false, 'today': today});
    final now = clock();
    final pending = _pending(state);
    var left = _cents(money);
    final days = <Map<String, dynamic>>[];
    for (var d = now.day; d <= DateTime(now.year, now.month + 1, 0).day; d++) {
      final date = isoDay(DateTime(now.year, now.month, d));
      final flows = [
        for (final p in pending)
          if ((p['date'] as String).compareTo(today) <= 0 ? date == today : p['date'] == date)
            {
              'kind': 'compromiso',
              'id': p['id'],
              'name': p['name'],
              'amount': p['amount'],
              'date': p['date'],
            },
      ];
      final start = left;
      for (final f in flows) {
        left -= _cents(f['amount']);
      }
      days.add({
        'date': date,
        'start': _fromCents(start),
        'out': _fromCents(start - left),
        'in': 0,
        'end': _fromCents(left),
        'events': flows,
      });
    }
    final index = days.indexWhere((d) => (d['end'] as num) < 0);
    Map<String, dynamic>? shortfall;
    if (index >= 0) {
      var causes = days[index]['events'] as List<Map<String, dynamic>>;
      if (causes.isEmpty) {
        causes = [for (final d in days.take(index)) ...d['events'] as List<Map<String, dynamic>>]
          ..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));
        causes = causes.take(3).toList();
      }
      shortfall = {'date': days[index]['date'], 'missing': -(days[index]['end'] as num), 'causes': causes};
    }
    final low = days.reduce((a, b) => (b['end'] as num) < (a['end'] as num) ? b : a);
    // El tope diario del servidor sin gasto normal: lo que queda tras los pagos de cada día ÷ los días.
    var safe = double.infinity;
    for (var k = 1; k <= (index >= 0 ? index : days.length - 1); k++) {
      safe = math.min(safe, (days[k]['end'] as num) / k);
    }
    return Liquidity.fromJson({
      'ready': true,
      'today': today,
      'money': money,
      'pace': null,
      'until': days.last['date'],
      'days': days,
      'firstShortfall': shortfall,
      'lowest': {'date': low['date'], 'amount': low['end']},
      'risk': shortfall == null ? 'ok' : 'falta',
      'safeDailySpend': safe.isFinite ? math.max(0, (safe / 100).floor() * 100) : 0,
      'receivable': 0,
      'assumptions': const ['No contamos ingresos futuros: solo la plata que ya tienes.'],
    });
  }

  List<Map<String, dynamic>> _pending(DemoState state) =>
      _journey ? demoJourneyPending(state, clock()) : demoFixedPending(scenario, state, _day);

  /// La plata del plan de la demo (la del Inicio); null sin plan, como el servidor.
  num? _planMoney(DemoState state) {
    if (_journey && state.incomeType == null) return null;
    return demoWelcomeStatus(scenario, state).money;
  }

  static int _cents(Object? value) => ((readMoney(value) ?? 0) * 100).round();
  static num _fromCents(int cents) => readMoney(cents / 100)!;

  static const _exists = ApiException(
    code: 'COMMITMENT_EXISTS',
    status: 409,
    serverMessage: 'Ya tienes un compromiso con ese nombre',
  );

  static const _notFound = ApiException(
    code: 'NOT_FOUND',
    status: 404,
    serverMessage: 'Compromiso no encontrado',
  );

  /// Lo que guarda el servidor: sin `kind` ni `frequency` es un pago fijo de cada mes.
  static Map<String, dynamic> _commitment(Map<String, dynamic> body) => {
    'name': '${body['name']}'.trim(),
    'amount': body['amount'],
    'dayOfMonth': body['dayOfMonth'],
    'kind': body['kind'] ?? 'fixed',
    'frequency': body['frequency'] ?? 'monthly',
    'month': body['frequency'] == 'yearly' ? body['month'] : null,
  };

  /// Como el servidor: el nombre no se repite (sin distinguir mayúsculas).
  static bool _taken(List<Map<String, dynamic>> list, Object? name, {String? except}) =>
      list.any((c) => c['id'] != except && '${c['name']}'.toLowerCase() == '$name'.trim().toLowerCase());

  @override
  Future<void> createCommitment(Map<String, dynamic> body) async {
    await _write();
    final state = await store.read(userId);
    final list = state.commitmentsWithIds;
    if (_taken(list, body['name'])) throw _exists;
    // Tope del servidor (MAX_COMMITMENTS).
    if (list.length >= 30) {
      throw const ApiException(
        code: 'COMMITMENT_LIMIT',
        status: 409,
        serverMessage: 'Puedes tener hasta 30 compromisos',
      );
    }
    await store.write(userId, state.withCommitments([...list, _commitment(body)]));
  }

  @override
  Future<void> updateCommitment(String id, Map<String, dynamic> body) async {
    await _write();
    final state = await store.read(userId);
    final list = state.commitmentsWithIds;
    final i = list.indexWhere((c) => c['id'] == id);
    if (i < 0) throw _notFound;
    if (_taken(list, body['name'], except: id)) throw _exists;
    await store.write(userId, state.withCommitments([...list]..[i] = {'id': id, ..._commitment(body)}));
  }

  @override
  Future<void> deleteCommitment(String id) async {
    await _write();
    final state = await store.read(userId);
    final list = state.commitmentsWithIds;
    if (!list.any((c) => c['id'] == id)) throw _notFound;
    await store.write(userId, state.withCommitments([...list.where((c) => c['id'] != id)]));
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
