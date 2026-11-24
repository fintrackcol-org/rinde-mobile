import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/home_models.dart' show readMoney;
import '../../home/domain/home_dates.dart';
import '../../movements/data/demo_movements_repository.dart' show demoMovementsStoreProvider;
import '../../movements/data/json_list_store.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import 'card_models.dart';
import 'cards_repository.dart';
import 'demo_cards_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Tarjetas sintéticas con la forma exacta de GET /cards, leídas con los mismos modelos que la API.
//  El ciclo se calcula de forma SIMPLE (limitación declarada en el plan): el próximo día de pago
//  hacia adelante (el 31 cae en el último día del mes), «pagada este ciclo» si hubo un pago desde el
//  vencimiento anterior, y `used = max(0, base + compras de la demo con esa tarjeta − pagos)`.
//  Pagar una tarjeta en la demo NO baja Mi plata: la demo no recalcula la plata (etapa 3).
// ─────────────────────────────────────────────────────────────────────────────

/// Operaciones del panel «DEMO» que se pueden hacer fallar.
enum DemoCardsOperation {
  /// GET /cards.
  list,

  /// GET /cards/:id y /cards/:id/movements.
  detail,

  /// POST, PUT y DELETE de tarjetas, pagos y sync-with-bank.
  write,
}

/// Los escenarios fijos no escriben: su semilla no debe contradecir lo editado.
const _journeys = {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan};

const _noBackend = ApiException(
  code: ApiCodes.demoNoBackend,
  serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
);

const _notFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Tarjeta no encontrada', status: 404);

const _cardExists = ApiException(
  code: 'CARD_EXISTS',
  serverMessage: 'Ya tienes una tarjeta con esos últimos 4 dígitos',
  status: 409,
);

ApiException _invalid(Map<String, String> fields) =>
    ApiException(code: ApiCodes.validation, serverMessage: 'Datos inválidos', status: 422, fields: fields);

/// La única tarjeta de los escenarios fijos (`planListo`): la misma semilla «Mi Visa» de siempre
/// (demo_home_repository). Su historial está vacío: la deuda viene de la base, no de compras.
Map<String, dynamic> demoPlanListoCardJson(DemoState state, DateTime Function() clock) {
  final m = state.fixed;
  final now = clock();
  String day(int offset) => isoDay(DateTime(now.year, now.month, now.day + offset));
  return {
    'id': 'demo-tarjeta',
    'name': 'Mi Visa',
    'network': 'visa',
    'tier': 'gold',
    'last4': '4242',
    'limit': m(1500000),
    'used': m(320000),
    'available': m(1180000),
    'paymentDay': DateTime(now.year, now.month, now.day + 2).day,
    'cutoffDay': null,
    'statementTotal': null,
    'statementDueDate': null,
    'nextPaymentDate': day(2),
    'daysToPayment': 2,
    'paidThisCycle': false,
    'paidDueDate': null,
    'paidAmount': 0,
    'reminderSentFor': null,
    'expiryMonth': 3,
    'expiryYear': now.year + 2,
    'expiry': {'label': '03/${(now.year + 2) % 100}', 'expired': false, 'soon': false},
    'expiryNotified': const <Object>[],
  };
}

/// Lo que respondería GET /cards para este usuario demo: la semilla fija o lo guardado del
/// recorrido. El Inicio (aviso) y la pantalla de Tarjetas leen de aquí: dicen lo mismo.
Future<List<Map<String, dynamic>>> demoCardsJson({
  required String userId,
  required DemoState state,
  required JsonListStore cardsStore,
  required JsonListStore movementsStore,
  required DateTime Function() clock,
}) async {
  final scenario = DemoScenario.fromUserId(userId);
  final purchases = scenario == DemoScenario.planListo || _journeys.contains(scenario)
      ? await _readPurchases(movementsStore, userId)
      : const <Map<String, dynamic>>[];
  if (scenario == DemoScenario.planListo) {
    // Lo que se anote con la semilla suma en su deuda, como en el servidor: el detalle, Movimientos y
    // el aviso del Inicio dicen lo mismo.
    final seed = demoPlanListoCardJson(state, clock);
    final usedCents =
        _cents(seed['used']) +
        purchases
            .where((p) => (p['card'] as Map)['id'] == seed['id'])
            .fold<int>(0, (sum, p) => sum + _cents(p['amount']));
    return [
      {...seed, 'used': _fromCents(usedCents), 'available': _fromCents(_cents(seed['limit']) - usedCents)},
    ];
  }
  if (!_journeys.contains(scenario)) return const [];
  // Solo lectura: un llavero ilegible se lee como «sin tarjetas» (las ESCRITURAS sí fallan, para no
  // pisar lo guardado; ver readDemoCards).
  final raw = await cardsStore.read(userId) ?? const <Object?>[];
  return [
    for (final item in raw)
      if (item is Map) _cardJson(Map<String, dynamic>.from(item), purchases, clock()),
  ];
}

int _cents(Object? value) => ((readMoney(value) ?? 0) * 100).round();

num _fromCents(int cents) => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

/// Gastos de la demo pagados con tarjeta: `{card: {id}, date, amount, …}` del almacén de movimientos.
Future<List<Map<String, dynamic>>> _readPurchases(JsonListStore store, String userId) async {
  final raw = await store.read(userId) ?? const <Object?>[];
  return [
    for (final item in raw)
      if (item is Map && item['type'] == 'gasto' && item['card'] is Map) Map<String, dynamic>.from(item),
  ];
}

DateTime _due(int year, int month, int paymentDay) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(paymentDay, last));
}

/// Ids de los gastos «Cargos del banco» de sus ajustes: ya van dentro de la base nueva.
Set<Object?> _charges(Map<String, dynamic> raw) => {for (final a in _adjustments(raw)) ?a['transactionId']};

/// Como purchasesSince del servidor: lo creado desde la base y con fecha desde ese día. Los cargos del
/// banco no cuentan (se crean junto con la base); sí salen en el historial.
bool _sinceBase(Map<String, dynamic> m, Map<String, dynamic> raw) =>
    '${m['date']}'.compareTo('${raw['baseDay'] ?? ''}') >= 0 &&
    '${m['createdAt'] ?? ''}'.compareTo('${raw['baseAt'] ?? ''}') >= 0 &&
    !_charges(raw).contains(m['id']);

/// Días de calendario como el servidor (en UTC): el cambio de hora no resta uno.
int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// La forma de `Card` del servidor a partir de lo guardado, con el ciclo simplificado.
Map<String, dynamic> _cardJson(Map<String, dynamic> raw, List<Map<String, dynamic>> purchases, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final payments = _payments(raw);
  final limitCents = _cents(raw['limit']);
  var usedCents = _cents(raw['base']);
  final cardId = raw['id'];
  for (final p in purchases) {
    if ((p['card'] as Map)['id'] == cardId && _sinceBase(p, raw)) usedCents += _cents(p['amount']);
  }
  var paidSinceBaseCents = 0;
  for (final p in payments) {
    if (_sinceBase(p, raw)) paidSinceBaseCents += _cents(p['amount']);
  }
  usedCents -= paidSinceBaseCents;
  if (usedCents < 0) usedCents = 0;

  final paymentDay = raw['paymentDay'] is int ? raw['paymentDay'] as int : 1;
  final thisMonth = _due(today.year, today.month, paymentDay);
  final next = thisMonth.isBefore(today) ? _due(today.year, today.month + 1, paymentDay) : thisMonth;
  final prev = _due(next.year, next.month - 1, paymentDay);
  final prevIso = isoDay(prev);
  var paidCents = 0;
  for (final p in payments) {
    if ('${p['date']}'.compareTo(prevIso) > 0) paidCents += _cents(p['amount']);
  }
  final paid = paidCents > 0;
  final nextPayment = paid ? _due(next.year, next.month + 1, paymentDay) : next;
  // statementGone del servidor (cards.logic.js:80-82): un extracto vencido o ya pagado no se muestra.
  final statementTotal = readMoney(raw['statementTotal']);
  final statementDue = raw['statementDueDate'] is String ? raw['statementDueDate'] as String : null;
  final statementGone =
      (statementDue != null && statementDue.compareTo(isoDay(nextPayment)) < 0) ||
      (statementTotal != null && paidSinceBaseCents >= _cents(statementTotal));

  final expiryMonth = raw['expiryMonth'] is int ? raw['expiryMonth'] as int : null;
  final expiryYear = raw['expiryYear'] is int ? raw['expiryYear'] as int : null;
  Map<String, dynamic>? expiry;
  if (expiryMonth != null && expiryYear != null) {
    final first = DateTime(expiryYear, expiryMonth);
    final last = DateTime(expiryYear, expiryMonth + 1, 0);
    expiry = {
      'label': '${expiryMonth.toString().padLeft(2, '0')}/${(expiryYear % 100).toString().padLeft(2, '0')}',
      'expired': today.isAfter(last),
      'soon': !today.isAfter(last) && _daysBetween(today, first) <= 60,
    };
  }

  return {
    'id': cardId,
    'name': demoCardDisplayName(raw),
    'network': raw['network'],
    'tier': raw['tier'],
    'last4': raw['last4'],
    'limit': _fromCents(limitCents),
    'used': _fromCents(usedCents),
    'available': _fromCents(limitCents - usedCents),
    'paymentDay': paymentDay,
    'cutoffDay': raw['cutoffDay'],
    'statementTotal': statementGone ? null : statementTotal,
    'statementDueDate': statementGone ? null : statementDue,
    'nextPaymentDate': isoDay(nextPayment),
    'daysToPayment': _daysBetween(today, nextPayment),
    'paidThisCycle': paid,
    'paidDueDate': paid ? isoDay(next) : null,
    'paidAmount': _fromCents(paidCents),
    'reminderSentFor': null,
    'expiryMonth': expiryMonth,
    'expiryYear': expiryYear,
    'expiry': expiry,
    'expiryNotified': const <Object>[],
  };
}

List<Map<String, dynamic>> _payments(Map<String, dynamic> raw) => [
  if (raw['payments'] is List)
    for (final p in raw['payments'] as List)
      if (p is Map) Map<String, dynamic>.from(p),
];

List<Map<String, dynamic>> _adjustments(Map<String, dynamic> raw) => [
  if (raw['adjustments'] is List)
    for (final a in raw['adjustments'] as List)
      if (a is Map) Map<String, dynamic>.from(a),
];

class DemoCardsRepository implements CardsRepository {
  DemoCardsRepository({
    required this.userId,
    required this.store,
    required this.movementsStore,
    required this.stateStore,
    required this.controls,
    required this.clock,
  });

  final String userId;
  final JsonListStore store;
  final JsonListStore movementsStore;
  final DemoStateStore stateStore;
  final DemoControlsNotifier controls;
  final DateTime Function() clock;

  final _random = math.Random.secure();
  Future<void> _lock = Future.value();

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  bool get _journey => _journeys.contains(scenario);

  @override
  bool get isDemo => true;

  String _rand(String prefix) =>
      '$prefix-${List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Future<List<Map<String, dynamic>>> _json(Enum op) async {
    await controls.simulate(op);
    return demoCardsJson(
      userId: userId,
      state: await stateStore.read(userId),
      cardsStore: store,
      movementsStore: movementsStore,
      clock: clock,
    );
  }

  @override
  Future<List<CreditCard>> list() async => [
    for (final json in await _json(DemoCardsOperation.list)) CreditCard.fromJson(json),
  ];

  @override
  Future<CreditCard> get(String id) async {
    final cards = await _json(DemoCardsOperation.detail);
    final json = cards.where((c) => c['id'] == id).firstOrNull ?? (throw _notFound);
    return CreditCard.fromJson(json);
  }

  @override
  Future<List<CardMovement>> movements(String id) async {
    await controls.simulate(DemoCardsOperation.detail);
    final Map<String, dynamic> raw;
    if (scenario == DemoScenario.planListo) {
      // La deuda de la semilla viene de la base: el historial solo trae lo anotado con ella.
      if (id != demoPlanListoCardJson(await stateStore.read(userId), clock)['id']) throw _notFound;
      raw = {'id': id};
    } else {
      if (!_journey) throw _notFound;
      final all = await store.read(userId) ?? const <Object?>[];
      raw =
          all.whereType<Map>().where((c) => c['id'] == id).map(Map<String, dynamic>.from).firstOrNull ??
          (throw _notFound);
    }
    final charges = _charges(raw);
    final rows =
        <Map<String, dynamic>>[
          for (final p in await _readPurchases(movementsStore, userId))
            if ((p['card'] as Map)['id'] == id && (_sinceBase(p, raw) || charges.contains(p['id'])))
              {
                'kind': 'purchase',
                'id': p['id'],
                'date': p['date'],
                'amount': readMoney(p['amount']),
                'description': p['description'],
                'installments': p['installments'] is int ? p['installments'] : 1,
                'createdAt': p['createdAt'],
              },
          for (final p in _payments(raw))
            {
              'kind': 'payment',
              'id': p['id'],
              'date': p['date'],
              'amount': readMoney(p['amount']),
              'createdAt': p['createdAt'],
            },
          // Como el servidor: solo los ajustes negativos.
          for (final a in _adjustments(raw))
            if ((readMoney(a['amount']) ?? 0) < 0)
              {
                'kind': 'adjustment',
                'id': a['id'],
                'date': a['date'],
                'amount': readMoney(a['amount']),
                'createdAt': a['createdAt'],
              },
        ]..sort((a, b) {
          final byDate = '${b['date']}'.compareTo('${a['date']}');
          return byDate != 0 ? byDate : '${b['createdAt']}'.compareTo('${a['createdAt']}');
        });
    return [for (final row in rows) CardMovement.fromJson(row)];
  }

  /// Las escrituras van de a una y solo en los recorridos; en los escenarios fijos la semilla no se
  /// puede contradecir.
  Future<T> _write<T>(Future<T> Function(List<Map<String, dynamic>> all) change) async {
    await controls.simulate(DemoCardsOperation.write);
    if (!_journey) throw _noBackend;
    final run = _lock.then((_) => readDemoCards(store, userId)).then(change);
    _lock = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _save(List<Map<String, dynamic>> all) => store.write(userId, all);

  Future<CreditCard> _served(String id) async {
    final json = (await demoCardsJson(
      userId: userId,
      state: await stateStore.read(userId),
      cardsStore: store,
      movementsStore: movementsStore,
      clock: clock,
    )).where((c) => c['id'] == id).firstOrNull;
    return CreditCard.fromJson(json ?? (throw _notFound));
  }

  @override
  Future<CreditCard> create(Map<String, dynamic> body) => _write((all) async {
    if (all.any((c) => c['last4'] == body['last4'])) throw _cardExists;
    final limit = _cents(body['limit']);
    final available = _cents(body['available']);
    if (available > limit) throw _invalid({'available': 'No puede ser mayor que el cupo'});
    final now = clock();
    final raw = <String, dynamic>{
      'id': _rand('demo-t'),
      'name': body['name'],
      'network': body['network'],
      'tier': body['tier'],
      'last4': body['last4'],
      'limit': _fromCents(limit),
      'base': _fromCents(limit - available),
      'baseAt': now.toUtc().toIso8601String(),
      'baseDay': isoDay(now),
      'createdAt': now.toUtc().toIso8601String(),
      'paymentDay': body['paymentDay'],
      'cutoffDay': body['cutoffDay'],
      'statementTotal': null,
      'statementDueDate': null,
      'expiryMonth': body['expiryMonth'],
      'expiryYear': body['expiryYear'],
      'payments': const <Object>[],
      'adjustments': const <Object>[],
    };
    await _save([...all, raw]);
    return _served(raw['id'] as String);
  });

  @override
  Future<CreditCard> update(String id, Map<String, dynamic> body) => _write((all) async {
    final raw = all.where((c) => c['id'] == id).firstOrNull ?? (throw _notFound);
    if (body.containsKey('available')) {
      throw _invalid({'available': 'No se edita aquí: usa sync-with-bank'});
    }
    if (body.containsKey('last4') && all.any((c) => c['id'] != id && c['last4'] == body['last4'])) {
      throw _cardExists;
    }
    final next = {...raw};
    for (final key in const ['network', 'tier', 'last4', 'paymentDay', 'cutoffDay', 'name']) {
      if (body.containsKey(key)) next[key] = body[key];
    }
    if (body.containsKey('expiryMonth') || body.containsKey('expiryYear')) {
      next['expiryMonth'] = body['expiryMonth'];
      next['expiryYear'] = body['expiryYear'];
    }
    if (body.containsKey('limit')) {
      final used = _cents(_cardJson(raw, await _readPurchases(movementsStore, userId), clock())['used']);
      if (_cents(body['limit']) < used) {
        throw _invalid({'limit': 'No puede ser menor que lo que ya usas'});
      }
      next['limit'] = readMoney(body['limit']);
    }
    await _save([for (final c in all) c['id'] == id ? next : c]);
    // El servidor arma la tarjeta de cada compra con sus datos de hoy (transactions.repository.js:28-36).
    await _retagPurchases(id, {'name': demoCardDisplayName(next), 'last4': next['last4']});
    return _served(id);
  });

  @override
  Future<void> delete(String id) => _write((all) async {
    if (!all.any((c) => c['id'] == id)) throw _notFound;
    await _save(all.where((c) => c['id'] != id).toList());
    // Como el borrado lógico del servidor: sus compras quedan, con «Tarjeta eliminada».
    await _retagPurchases(id, {'deleted': true});
  });

  /// Cambia la tarjeta que muestran las compras hechas con [id].
  Future<void> _retagPurchases(String id, Map<String, dynamic> card) async {
    final movements = await movementsStore.read(userId);
    if (movements == null) return;
    await movementsStore.write(userId, [
      for (final m in movements)
        if (m is Map && m['card'] is Map && (m['card'] as Map)['id'] == id)
          {
            ...m,
            'card': {...m['card'] as Map, ...card},
          }
        else
          m,
    ]);
  }

  @override
  Future<void> pay(String id, {required num amount, required String date, String? idempotencyKey}) =>
      _write((all) async {
        final raw = all.where((c) => c['id'] == id).firstOrNull ?? (throw _notFound);
        if (amount <= 0) throw _invalid({'amount': 'Debe ser un número mayor que 0'});
        if (date.compareTo(isoDay(clock())) > 0) {
          throw _invalid({'date': 'No puede ser una fecha futura'});
        }
        final next = {
          ...raw,
          'payments': [
            ..._payments(raw),
            {
              'id': _rand('demo-p'),
              'date': date,
              'amount': readMoney(amount),
              'createdAt': clock().toUtc().toIso8601String(),
            },
          ],
        };
        await _save([for (final c in all) c['id'] == id ? next : c]);
      });

  @override
  Future<void> deletePayment(String id, String paymentId) => _write((all) async {
    final raw = all.where((c) => c['id'] == id).firstOrNull ?? (throw _notFound);
    final payments = _payments(raw);
    if (!payments.any((p) => p['id'] == paymentId)) {
      throw const ApiException(code: 'NOT_FOUND', serverMessage: 'Pago no encontrado', status: 404);
    }
    final next = {...raw, 'payments': payments.where((p) => p['id'] != paymentId).toList()};
    await _save([for (final c in all) c['id'] == id ? next : c]);
  });

  @override
  Future<num?> syncWithBank(String id, Map<String, dynamic> body) => _write((all) async {
    final raw = all.where((c) => c['id'] == id).firstOrNull ?? (throw _notFound);
    final availableCents = _cents(body['available']);
    final limitCents = _cents(raw['limit']);
    if (availableCents < 0) throw _invalid({'available': 'Debe ser un número mayor o igual que 0'});
    if (availableCents > limitCents) throw _invalid({'available': 'No puede ser mayor que el cupo'});
    final usedCents = _cents(_cardJson(raw, await _readPurchases(movementsStore, userId), clock())['used']);
    final differenceCents = limitCents - availableCents - usedCents;
    final now = clock();
    final today = isoDay(now);
    final chargeId = differenceCents > 0 ? _rand('demo') : null;
    final next = {
      ...raw,
      'base': _fromCents(limitCents - availableCents),
      'baseAt': now.toUtc().toIso8601String(),
      'baseDay': today,
      if (body.containsKey('statementTotal')) 'statementTotal': readMoney(body['statementTotal']),
      if (body.containsKey('statementDueDate')) 'statementDueDate': body['statementDueDate'],
      // Como el servidor: se guarda si la diferencia no es 0; el historial solo muestra las negativas.
      if (differenceCents != 0)
        'adjustments': [
          ..._adjustments(raw),
          {
            'id': _rand('demo-a'),
            'date': today,
            'amount': _fromCents(differenceCents),
            'createdAt': now.toUtc().toIso8601String(),
            'transactionId': chargeId,
          },
        ],
    };
    await _save([for (final c in all) c['id'] == id ? next : c]);
    if (differenceCents <= 0) return null;
    // El gasto «Cargos del banco» va al almacén de movimientos de la demo, como lo haría el servidor.
    final amount = _fromCents(differenceCents);
    final movements = await movementsStore.read(userId) ?? const <Object?>[];
    await movementsStore.write(userId, [
      ...movements,
      {
        'id': chargeId,
        'localId': null,
        'type': 'gasto',
        'amount': amount,
        'description': 'Cargos del banco · ${demoCardDisplayName(raw)}',
        'category': 'otros',
        'source': 'manual',
        'date': today,
        'createdAt': now.toUtc().toIso8601String(),
        'updatedAt': now.toUtc().toIso8601String(),
        'deletedAt': null,
        'card': {'id': id, 'name': demoCardDisplayName(raw), 'last4': raw['last4'], 'deleted': false},
        'installments': 1,
        'emotion': null,
        'kakeibo': null,
        'original': null,
      },
    ]);
    return amount;
  });
}

/// Uno por usuario demo. Comparte los almacenes de la demostración.
final demoCardsRepositoryProvider = Provider.family<DemoCardsRepository, String>(
  (ref, userId) => DemoCardsRepository(
    userId: userId,
    store: ref.watch(demoCardsStoreProvider),
    movementsStore: ref.watch(demoMovementsStoreProvider),
    stateStore: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
  ),
);
