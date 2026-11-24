import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../application/home_providers.dart' show clockProvider;
import '../domain/home_dates.dart';
import 'home_models.dart';
import 'home_repository.dart';
import '../../cards/data/demo_cards_repository.dart' show demoCardsJson, demoPlanListoCardJson;
import '../../cards/data/demo_cards_store.dart' show demoCardsStoreProvider;
import '../../movements/data/demo_movements_repository.dart'
    show demoMovementTotals, demoMovementsStoreProvider;
import '../../movements/data/json_list_store.dart';
import '../../plan/data/demo_budgets_repository.dart' show demoBudgetsStoreProvider, demoJourneyBudgets;

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Solo para desarrollo y pruebas: el Inicio de una sesión demo. Cada lectura arma la RESPUESTA
//  SINTÉTICA del contrato real (el mismo JSON que mandaría el servidor) y la lee con los mismos
//  modelos que la API, así la demostración y la app real comparten la lectura.
//  Los montos de los escenarios fijos son literales en pesos colombianos y cuadran entre sí.
// ─────────────────────────────────────────────────────────────────────────────

/// Las 15 categorías del catálogo con el nombre que manda el servidor en cada idioma: es, en, pt
/// (backend/src/i18n/locales/*/catalogo.json de Rinde Web).
const _categories = <String, List<String>>{
  'alimentacion': ['Alimentación', 'Food', 'Alimentação'],
  'transporte': ['Transporte', 'Transportation', 'Transporte'],
  'vivienda': ['Vivienda', 'Housing', 'Moradia'],
  'servicios_publicos': ['Servicios públicos', 'Utilities', 'Contas da casa'],
  'salud': ['Salud', 'Health', 'Saúde'],
  'educacion': ['Educación', 'Education', 'Educação'],
  'entretenimiento': ['Entretenimiento', 'Entertainment', 'Entretenimento'],
  'ropa_accesorios': ['Ropa y accesorios', 'Clothing and accessories', 'Roupas e acessórios'],
  'tecnologia': ['Tecnología', 'Technology', 'Tecnologia'],
  'ahorro_inversion': ['Ahorro/Inversión', 'Savings/Investment', 'Poupança/Investimento'],
  'otros': ['Otros', 'Other', 'Outros'],
  'salario': ['Salario', 'Salary', 'Salário'],
  'freelance': ['Freelance', 'Freelance', 'Freelance'],
  'inversion_rendimientos': [
    'Inversión y rendimientos',
    'Investments and returns',
    'Investimentos e rendimentos',
  ],
  'otros_ingresos': ['Otros ingresos', 'Other income', 'Outras receitas'],
};

const _incomeCategories = {'salario', 'freelance', 'inversion_rendimientos', 'otros_ingresos'};

/// Los pagos que faltan en el plan de cada escenario fijo. Mi plata lee de aquí los compromisos del
/// perfil y el calendario del mes: los tres dicen lo mismo. [day] da la fecha a tantos días de hoy;
/// a fin de mes no pasa del último día (el calendario del mes no trae fechas de otro).
/// shortcut: como las fechas se corren con hoy, un aviso cerrado en la demo vuelve al día siguiente.
List<Map<String, dynamic>> demoFixedPending(
  DemoScenario scenario,
  DemoState state,
  String Function(int) day,
) {
  final m = state.fixed;
  final month = day(0).substring(0, 7);
  String inMonth(int offset) {
    var o = offset;
    while (o > 0 && !day(o).startsWith(month)) {
      o--;
    }
    return day(o);
  }

  Map<String, dynamic> item(String id, String name, num amount, int offset) => {
    'id': id,
    'name': name,
    'amount': m(amount),
    'date': inMonth(offset),
  };
  return switch (scenario) {
    DemoScenario.planListo => [
      item('demo-celular', 'Plan celular', 45000, 3),
      item('demo-pila', 'PILA', 228000, 6),
      item('demo-internet', 'Internet', 65000, 10),
    ],
    DemoScenario.teFaltan => [
      item('demo-celular', 'Plan celular', 45000, 2),
      item('demo-pila', 'PILA', 228000, 5),
    ],
    DemoScenario.negativo => [item('demo-celular', 'Plan celular', 45000, 4)],
    _ => const [],
  };
}

/// Los pagos de un recorrido que tocan el mes de [now], por fecha: los anuales solo en su mes y un día
/// 31 en un mes de 30 cae el 30. El plan y el calendario de la demo salen de aquí (dicen lo mismo).
List<Map<String, dynamic>> demoJourneyPending(DemoState state, DateTime now) {
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  return [
    for (final c in state.commitmentsWithIds)
      if (readMoney(c['amount']) != null &&
          c['dayOfMonth'] is int &&
          (c['frequency'] != 'yearly' || c['month'] == now.month))
        {
          'id': c['id'],
          'name': '${c['name']}',
          'amount': readMoney(c['amount']),
          'date': isoDay(DateTime(now.year, now.month, math.min(c['dayOfMonth'] as int, lastDay))),
          'subscription': c['kind'] == 'subscription',
        },
  ]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
}

class DemoHomeRepository implements HomeRepository {
  DemoHomeRepository({
    required this.userId,
    required this.store,
    required this.controls,
    required this.clock,
    required this.language,
    this.movements,
    this.cardsStore,
    this.budgetsStore,
  });

  /// Movimientos anotados en la demo (suman en «Este mes»). El plan y el saldo no se recalculan:
  /// son del servidor, y la demostración no los imita.
  final JsonListStore? movements;

  /// Tarjetas de la demo: el aviso del Inicio lee del MISMO almacén que la pantalla de Tarjetas,
  /// así los dos dicen lo mismo. Sin él, solo la semilla fija de `planListo`.
  final JsonListStore? cardsStore;

  /// Presupuestos que los recorridos crearon en la demo (Planear → Presupuestos).
  final JsonListStore? budgetsStore;

  final String userId;
  final DemoStateStore store;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  /// Idioma en que se ve la app (el servidor traduce las categorías según Accept-Language).
  final String Function() language;

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  @override
  bool get isDemo => true;

  Future<DemoState> _read(DemoHomeOperation op) async {
    await controls.simulate(op);
    return store.read(userId);
  }

  /// Fechas relativas a hoy: lo que viene siempre está en el futuro, se abra cuando se abra.
  String _day(int offset) {
    final now = clock();
    return isoDay(DateTime(now.year, now.month, now.day + offset));
  }

  @override
  Future<MoneyPlan> plan() async => MoneyPlan.fromJson(_plan(await _read(DemoHomeOperation.plan)));

  @override
  Future<MonthTotals> monthTotals(String date) async {
    final scenario = MonthTotals.fromJson(_summary(date, await _read(DemoHomeOperation.summary)));
    final store = movements;
    if (store == null) return scenario;
    final noted = await demoMovementTotals(store, userId, date);
    return MonthTotals(
      month: scenario.month,
      income: readMoney(scenario.income + noted.income)!,
      expense: readMoney(scenario.expense + noted.expense)!,
    );
  }

  @override
  Future<List<BudgetStatus>> budgets(String month) async => [
    for (final item in await _budgets(month, await _read(DemoHomeOperation.secondary)))
      ?BudgetStatus.tryParse(item),
  ];

  @override
  Future<List<CardSummary>> cards() async => [
    for (final item in await _cardsJson(await _read(DemoHomeOperation.secondary)))
      ?CardSummary.tryParse(item),
  ];

  /// La misma fuente que la pantalla de Tarjetas (demoCardsJson): la semilla fija de `planListo` o
  /// lo guardado del recorrido. Agregar o pagar una tarjeta cambia el aviso del Inicio.
  Future<List<Map<String, dynamic>>> _cardsJson(DemoState state) {
    final store = cardsStore;
    if (store == null) {
      return Future.value(
        scenario == DemoScenario.planListo ? _cards(state).whereType<Map<String, dynamic>>().toList() : [],
      );
    }
    return demoCardsJson(
      userId: userId,
      state: state,
      cardsStore: store,
      movementsStore: movements ?? MemoryJsonListStore(),
      clock: clock,
    );
  }

  /// Las tarjetas como las da GET /cards, sin simular fallas: Anotar de la demo valida con ellas.
  Future<List<Map<String, dynamic>>> demoCards() async => _cardsJson(await store.read(userId));

  @override
  Future<int> toConfirm() async =>
      readList(_pendingPayments(await _read(DemoHomeOperation.secondary))['items']).length;

  @override
  Future<int> unread() async {
    await _read(DemoHomeOperation.secondary);
    return _notifications()['unread'] as int;
  }

  @override
  Future<Map<String, String>> categoryNames() async {
    await _read(DemoHomeOperation.secondary);
    final json = _categoryList();
    return {
      for (final list in json.values)
        for (final c in list) c['key'] as String: c['name'] as String,
    };
  }

  @override
  Future<void> finishTutorial() async {
    await controls.simulate();
    await store.update(userId, (state) => state.withTutorial());
  }

  // ── GET /money-profile/plan ────────────────────────────────────────────────

  Map<String, dynamic> _plan(DemoState state) {
    final m = state.fixed;
    return switch (scenario) {
      // sinPlan: sin tipo de ingreso no hay plan; si lo configura en Mi plata, sale como en un recorrido.
      DemoScenario.nuevo || DemoScenario.movimientos || DemoScenario.sinPlan => _journeyPlan(state),
      DemoScenario.planListo => {
        'ready': true,
        'money': m(412300),
        'ledger': m(412300),
        'pendingTotal': m(338000),
        'free': m(74300),
        'shortfall': 0,
        'pace': m(13700),
        'hasCommitments': true,
        'pending': demoFixedPending(scenario, state, _day),
        'saveAdvice': 0,
        ..._daily(days: 12, perDay: m(6500), spentToday: m(3700), leftToday: m(2800)),
      },
      DemoScenario.teFaltan => {
        'ready': true,
        'money': m(180000),
        'ledger': m(180000),
        'pendingTotal': m(273000),
        'free': m(-93000),
        'shortfall': m(93000),
        'pace': m(24800),
        'hasCommitments': true,
        'pending': demoFixedPending(scenario, state, _day),
        'saveAdvice': 0,
        ..._daily(days: 8),
      },
      DemoScenario.negativo => {
        'ready': true,
        'money': m(-35000),
        'ledger': m(-35000),
        'pendingTotal': m(45000),
        'free': m(-80000),
        'shortfall': m(80000),
        'pace': m(30200),
        'hasCommitments': true,
        'pending': demoFixedPending(scenario, state, _day),
        'saveAdvice': 0,
        ..._daily(days: 6),
      },
    };
  }

  /// Campos del modo `daily`. Sin plata libre el servidor manda 0 al día.
  Map<String, dynamic> _daily({required int days, num perDay = 0, num spentToday = 0, num leftToday = 0}) => {
    'mode': 'daily',
    'nextPay': _day(days),
    'days': days,
    'perDay': perDay,
    'spentToday': spentToday,
    'leftToday': leftToday,
    'overBy': 0,
    'dayStatus': 'ok',
  };

  /// Plan de los recorridos «nuevo» y «movimientos» (y de «sinPlan» cuando ya configuró Mi plata),
  /// armado SOLO con lo que la bienvenida o Mi plata mandaron: una
  /// suma y una resta simples, para que lo que la persona escribió se vea en el Inicio. NO es el
  /// algoritmo del servidor (que mira fechas de pago, lo ya pagado y el ritmo de gasto; además
  /// redondea a enteros) y nunca corre para una cuenta real. Por eso sale en modo `runway` y sin
  /// días: el modo diario solo lo muestra el escenario fijo. No inventa ingresos ni gastos y no da
  /// ningún pago por hecho.
  Map<String, dynamic> _journeyPlan(DemoState state) {
    final status = demoWelcomeStatus(scenario, state);
    final money = status.money;
    // Como el servidor: sin saber cómo le entra la plata o cuánta tiene, no hay plan.
    if (state.incomeType == null || money == null) return {'ready': false};
    int cents(num value) => (value * 100).round();
    final pending = demoJourneyPending(state, clock());
    final pendingCents = pending.fold<int>(0, (sum, p) => sum + cents(p['amount'] as num));
    final freeCents = cents(money) - pendingCents;
    return {
      'ready': true,
      'money': money,
      'ledger': readMoney(status.income - status.expense),
      'pendingTotal': pendingCents / 100,
      'free': freeCents / 100,
      'shortfall': math.max(0, -freeCents) / 100,
      'pace': null,
      'hasCommitments': pending.isNotEmpty,
      'pending': pending,
      'saveAdvice': 0,
      'mode': 'runway',
      'runwayDays': null,
    };
  }

  // ── GET /transactions/summary?period=month ─────────────────────────────────

  /// Ingresos y gastos del mes por categoría, de mayor a menor. Nunca pasan de los totales del
  /// historial del escenario ([DemoScenario.income] y [DemoScenario.expense]).
  (Map<String, num> income, Map<String, num> expense) get _month => switch (scenario) {
    DemoScenario.nuevo => const ({}, {}),
    DemoScenario.movimientos => const (
      {'salario': 2500000},
      {'vivienda': 900000, 'alimentacion': 520000, 'transporte': 250000, 'entretenimiento': 180000},
    ),
    DemoScenario.planListo || DemoScenario.sinPlan => const (
      {'freelance': 700000},
      {'alimentacion': 172000, 'transporte': 70700, 'entretenimiento': 45000},
    ),
    DemoScenario.teFaltan => const (
      {'freelance': 400000},
      {'alimentacion': 214000, 'entretenimiento': 186000, 'transporte': 120000},
    ),
    DemoScenario.negativo => const (
      {'freelance': 600000},
      {'vivienda': 380000, 'alimentacion': 165000, 'transporte': 90000},
    ),
  };

  Map<String, dynamic> _summary(String date, DemoState state) {
    final day = DateTime.parse(date);
    final (income, expense) = _month;
    Map<String, dynamic> side(Map<String, num> byCategory) {
      final total = byCategory.values.fold<num>(0, (sum, value) => sum + value);
      return {
        'total': state.fixed(total),
        'byCategory': [
          for (final MapEntry(:key, :value) in byCategory.entries)
            {'category': key, 'total': state.fixed(value), 'percentage': (value * 1000 / total).round() / 10},
        ],
      };
    }

    return {
      'period': 'month',
      'from': isoDay(DateTime(day.year, day.month)),
      'to': isoDay(DateTime(day.year, day.month + 1, 0)),
      'income': side(income),
      'expense': side(expense),
      'savings': {'total': 0},
      // Los escenarios no detallan el día a día: el Inicio no lo muestra.
      'timeSeries': const <Object>[],
    };
  }

  // ── GET /budgets, /cards, /pending-payments, /notifications, /categories ───

  /// Lo consumido es lo gastado este mes en esa categoría ([_month]). Los escenarios fijos traen su
  /// presupuesto sembrado solo en el mes en curso; los recorridos, lo que crearon en Presupuestos.
  Future<List<Object?>> _budgets(String month, DemoState state) async {
    final current = month == isoMonth(clock());
    final budgetsStore = this.budgetsStore;
    if (budgetsStore != null &&
        const {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan}.contains(scenario)) {
      return demoJourneyBudgets(
        store: budgetsStore,
        movements: movements ?? MemoryJsonListStore(),
        userId: userId,
        month: month,
        spentCents: {
          if (current)
            for (final MapEntry(:key, :value) in _month.$2.entries) key: (state.fixed(value) * 100).round(),
        },
      );
    }
    if (!current) return const [];
    Map<String, dynamic> budget(String category, num amount, num consumed, num percentage, String level) => {
      'id': 'demo-presupuesto',
      'category': category,
      'month': month,
      'amount': state.fixed(amount),
      'consumed': state.fixed(consumed),
      'percentage': percentage,
      'alert': {'level': level, 'percentage': percentage},
    };
    return switch (scenario) {
      DemoScenario.planListo => [budget('alimentacion', 200000, 172000, 86, 'warning_80')],
      DemoScenario.teFaltan => [budget('entretenimiento', 150000, 186000, 124, 'exceeded_100')],
      _ => const [],
    };
  }

  /// La tarjeta de la semilla vive en demoPlanListoCardJson (cards/data): una sola fuente.
  List<Object?> _cards(DemoState state) =>
      scenario != DemoScenario.planListo ? const [] : [demoPlanListoCardJson(state, clock)];

  Map<String, dynamic> _pendingPayments(DemoState state) {
    final m = state.fixed;
    Map<String, dynamic> item(int n, String merchant, num amount, int day, String? card) => {
      'id': 'demo-por-confirmar-$n',
      'merchant': merchant,
      'amount': m(amount),
      'date': _day(day),
      'card': card,
      'status': 'pending',
      'transactionId': null,
      'createdAt': clock().toUtc().toIso8601String(),
      'possibleDuplicate': false,
    };
    return {
      'items': [
        if (scenario == DemoScenario.planListo) ...[
          item(1, 'Panadería del barrio', 8900, 0, null),
          item(2, 'Taxi', 12400, -1, 'Mi Visa ••4242'),
        ],
      ],
    };
  }

  Map<String, dynamic> _notifications() {
    final unread = switch (scenario) {
      DemoScenario.planListo => 3,
      DemoScenario.teFaltan => 1,
      _ => 0,
    };
    return {
      'items': [
        for (var n = 1; n <= unread; n++)
          {
            'id': 'demo-aviso-$n',
            'title': 'Aviso de demostración $n',
            'body': 'Este aviso es sintético: no viene de ningún servidor.',
            'url': null,
            'read': false,
            'createdAt': clock().toUtc().toIso8601String(),
          },
      ],
      'unread': unread,
    };
  }

  Map<String, List<Map<String, dynamic>>> _categoryList() {
    final index = math.max(0, const ['es', 'en', 'pt'].indexOf(language()));
    List<Map<String, dynamic>> list({required bool income}) => [
      for (final MapEntry(:key, :value) in _categories.entries)
        if (_incomeCategories.contains(key) == income)
          {'key': key, 'name': value[index], 'icon': null, 'color': null, 'custom': false},
    ];
    return {'expense': list(income: false), 'income': list(income: true)};
  }
}

/// Uno por usuario demo. Comparte el estado guardado con la bienvenida de demostración.
final demoHomeRepositoryProvider = Provider.family<DemoHomeRepository, String>(
  (ref, userId) => DemoHomeRepository(
    userId: userId,
    store: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
    language: () => ref.read(displayLanguageProvider),
    movements: ref.watch(demoMovementsStoreProvider),
    cardsStore: ref.watch(demoCardsStoreProvider),
    budgetsStore: ref.watch(demoBudgetsStoreProvider),
  ),
);
