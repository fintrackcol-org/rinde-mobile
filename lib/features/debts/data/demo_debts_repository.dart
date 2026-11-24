import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/data/home_models.dart' show readMoney;
import '../../home/domain/home_dates.dart';
import '../../movements/data/demo_movements_repository.dart' show demoMovementsStoreProvider;
import '../../movements/data/json_list_store.dart';
import '../../onboarding/data/demo_onboarding_repository.dart';
import '../domain/debt_schedule.dart';
import 'debt_models.dart';
import 'debts_repository.dart';
import 'demo_debts_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Cuentas sintéticas con la forma exacta de GET /debts, leídas con los mismos modelos que la API.
//  Lo pagado, lo pendiente y la próxima cuota se recalculan con debt_schedule.dart (la copia del
//  servidor). Con la casilla marcada, abonar o saldar agrega el movimiento al almacén de movimientos
//  de la demo, como el servidor; Mi plata de la demo NO cambia (sale de valores fijos desde la
//  etapa 4: limitación declarada, igual que pagar una tarjeta en 5A).
// ─────────────────────────────────────────────────────────────────────────────

/// Operaciones del panel «DEMO» que se pueden hacer fallar.
enum DemoDebtsOperation {
  /// GET /debts.
  list,

  /// POST, PUT y DELETE de cuentas, saldar y abonos.
  write,
}

/// Los escenarios fijos no escriben: su semilla no debe contradecir lo editado.
const _journeys = {DemoScenario.nuevo, DemoScenario.movimientos, DemoScenario.sinPlan};

const _noBackend = ApiException(
  code: ApiCodes.demoNoBackend,
  serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
);

const _notFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Cuenta no encontrada', status: 404);
const _paymentNotFound = ApiException(code: 'NOT_FOUND', serverMessage: 'Abono no encontrado', status: 404);
const _alreadySettled = ApiException(
  code: 'ALREADY_SETTLED',
  serverMessage: 'Esta cuenta ya está saldada',
  status: 409,
);

ApiException _invalid(Map<String, String> fields) =>
    ApiException(code: ApiCodes.validation, serverMessage: 'Datos inválidos', status: 422, fields: fields);

int _cents(Object? value) => ((readMoney(value) ?? 0) * 100).round();

num _fromCents(int cents) => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Las dos cuentas de `planListo`: «Laura» me debe 60.000 en 3 cuotas mensuales y ya abonó 20.000;
/// a «Tío Jorge» le debo 120.000 de una vez, con fecha. El abono de la semilla no trae movimiento
/// (`transactionId: null`): ningún movimiento de la demo dice venir de él.
List<Map<String, dynamic>> demoPlanListoDebts(DemoState state, DateTime now) {
  final m = state.fixed;
  String day(int offset) => isoDay(DateTime(now.year, now.month, now.day + offset));
  final created = DateTime(now.year, now.month, now.day - 30).toUtc().toIso8601String();
  return [
    {
      'id': 'demo-cuenta-laura',
      'kind': 'receivable',
      'person': 'Laura',
      'amount': m(60000),
      'loanDate': day(-30),
      'dueDate': day(-15),
      'installments': 3,
      'frequency': 'monthly',
      'note': null,
      'settledAt': null,
      'transactionId': null,
      'createdAt': created,
      'updatedAt': created,
      'payments': [
        {
          'id': 'demo-abono-laura',
          'amount': m(20000),
          'date': day(-15),
          'transactionId': null,
          'createdAt': created,
        },
      ],
    },
    {
      'id': 'demo-cuenta-jorge',
      'kind': 'payable',
      'person': 'Tío Jorge',
      'amount': m(120000),
      'loanDate': day(-20),
      'dueDate': day(10),
      'installments': null,
      'frequency': null,
      'note': null,
      'settledAt': null,
      'transactionId': null,
      'createdAt': created,
      'updatedAt': created,
      'payments': const <Object>[],
    },
  ];
}

List<Map<String, dynamic>> _payments(Map<String, dynamic> raw) => [
  if (raw['payments'] is List)
    for (final p in raw['payments'] as List)
      if (p is Map) Map<String, dynamic>.from(p),
];

/// Lo pagado y la próxima cuota de lo guardado, como el servidor.
({num paid, num pending, int paidInstallments, Installment? next}) _progress(Map<String, dynamic> raw) {
  final installments = raw['installments'] is int ? raw['installments'] as int : null;
  return progress(
    amount: readMoney(raw['amount']) ?? 0,
    paid: _fromCents(_payments(raw).fold<int>(0, (sum, p) => sum + _cents(p['amount']))),
    installments: installments,
    frequency: DebtFrequency.fromWire(raw['frequency']),
    firstDueDate: installments == null ? null : raw['dueDate'] as String?,
    dueDate: raw['dueDate'] as String?,
  );
}

/// La forma de una cuenta de GET /debts a partir de lo guardado.
Map<String, dynamic> _served(Map<String, dynamic> raw) {
  final p = _progress(raw);
  final settled = raw['settledAt'] != null;
  final inInstallments = raw['installments'] is int;
  final next = settled ? null : p.next;
  return {
    'id': raw['id'],
    'kind': raw['kind'],
    'person': raw['person'],
    'amount': readMoney(raw['amount']),
    // Al leer, con cuotas, es la PRÓXIMA cuota (el servidor la corre sola); la primera va aparte.
    'dueDate': inInstallments ? (next?.date ?? raw['dueDate']) : raw['dueDate'],
    'note': raw['note'],
    'settledAt': raw['settledAt'],
    'transactionId': raw['transactionId'],
    'createdAt': raw['createdAt'],
    'updatedAt': raw['updatedAt'],
    'loanDate': raw['loanDate'],
    'installments': raw['installments'],
    'frequency': raw['frequency'],
    'firstDueDate': inInstallments ? raw['dueDate'] : null,
    'paid': p.paid,
    'pending': settled ? 0 : p.pending,
    'paidInstallments': p.paidInstallments,
    'nextInstallment': next == null
        ? null
        : {'number': next.number, 'date': next.date, 'amount': next.amount},
    'payments': [
      for (final payment
          in _payments(raw)..sort((a, b) {
            final byDate = '${b['date']}'.compareTo('${a['date']}');
            return byDate != 0 ? byDate : '${b['createdAt']}'.compareTo('${a['createdAt']}');
          }))
        {
          'id': payment['id'],
          'amount': readMoney(payment['amount']),
          'date': payment['date'],
          'transactionId': payment['transactionId'],
          'createdAt': payment['createdAt'],
        },
    ],
    'reminder': const {
      'daysBefore': [1],
      'time': null,
      'channel': 'push',
    },
  };
}

/// GET /debts: pendientes por fecha (sin fecha al final; con la misma, la más nueva) y luego saldadas de la más reciente a la más
/// vieja (debts.repository.js:83-90); los totales, lo pendiente de cada lado en centavos.
Map<String, dynamic> _listJson(List<Map<String, dynamic>> raw) {
  final served = [for (final r in raw) _served(r)];
  final pending = served.where((d) => d['settledAt'] == null).toList()
    ..sort((a, b) {
      final x = a['dueDate'] as String?, y = b['dueDate'] as String?;
      // Misma fecha (o las dos sin fecha): la más nueva primero (created_at DESC).
      if (x == y) return '${b['createdAt']}'.compareTo('${a['createdAt']}');
      if (x == null || y == null) return x == null ? 1 : -1;
      return x.compareTo(y);
    });
  final settled = served.where((d) => d['settledAt'] != null).toList()
    ..sort((a, b) => '${b['settledAt']}'.compareTo('${a['settledAt']}'));
  int total(String kind) =>
      pending.where((d) => d['kind'] == kind).fold(0, (s, d) => s + _cents(d['pending']));
  return {
    'items': [...pending, ...settled],
    'totals': {'receivable': _fromCents(total('receivable')), 'payable': _fromCents(total('payable'))},
  };
}

class DemoDebtsRepository implements DebtsRepository {
  DemoDebtsRepository({
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

  @override
  bool get isDemo => true;

  String _rand(String prefix) =>
      '$prefix-${List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  String get _now => clock().toUtc().toIso8601String();

  @override
  Future<DebtsList> list() async {
    await controls.simulate(DemoDebtsOperation.list);
    final List<Map<String, dynamic>> raw;
    if (scenario == DemoScenario.planListo) {
      raw = demoPlanListoDebts(await stateStore.read(userId), clock());
    } else if (_journeys.contains(scenario)) {
      // Solo lectura: un llavero ilegible se lee como «sin cuentas» (las escrituras sí fallan).
      raw = [
        for (final item in await store.read(userId) ?? const <Object?>[])
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } else {
      raw = const [];
    }
    return DebtsList.fromJson(_listJson(raw));
  }

  /// Las escrituras van de a una y solo en los recorridos. Un llavero ilegible falla en vez de
  /// leerse como vacío: escribir encima borraría lo guardado.
  Future<T> _write<T>(Future<T> Function(List<Map<String, dynamic>> all) change) async {
    await controls.simulate(DemoDebtsOperation.write);
    if (!_journeys.contains(scenario)) throw _noBackend;
    final run = _lock
        .then((_) async {
          final raw =
              await store.read(userId) ??
              (throw StateError('No se pudieron leer las cuentas de la demostración'));
          return [
            for (final item in raw)
              if (item is Map) Map<String, dynamic>.from(item),
          ];
        })
        .then(change);
    _lock = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _save(List<Map<String, dynamic>> all) => store.write(userId, all);

  Map<String, dynamic> _find(List<Map<String, dynamic>> all, String id, [ApiException missing = _notFound]) =>
      all.where((d) => d['id'] == id).firstOrNull ?? (throw missing);

  /// Las reglas de debts.validator.js que se ven en pantalla, sobre la cuenta ya combinada.
  static void _validate(Map<String, dynamic> d) {
    final fields = <String, String>{};
    final person = d['person'];
    if (DebtKind.fromWire(d['kind']) == null) fields['kind'] = 'Debe ser: receivable, payable';
    if (person is! String || person.trim().isEmpty || person.trim().length > 60) {
      fields['person'] = 'Debe tener entre 1 y 60 caracteres';
    }
    if (d['amount'] is! num || (d['amount'] as num) <= 0) fields['amount'] = 'Debe ser un número mayor que 0';
    for (final key in const ['loanDate', 'dueDate']) {
      if (d[key] != null && (d[key] is! String || !_isoDate.hasMatch(d[key] as String))) {
        fields[key] = 'Debe ser una fecha AAAA-MM-DD';
      }
    }
    if (d['note'] is String && (d['note'] as String).length > 200) fields['note'] = 'Máximo 200 caracteres';
    final n = d['installments'];
    if (n != null) {
      if (n is! int || n < 2 || n > 60) {
        fields['installments'] = 'Debe ser un entero entre 2 y 60, o null para fecha fija';
      }
      if (DebtFrequency.fromWire(d['frequency']) == null) fields['frequency'] = 'Es obligatoria con cuotas';
      if (d['dueDate'] == null) fields['dueDate'] = 'Con cuotas es la fecha de la primera cuota';
    }
    if (d['loanDate'] is String &&
        d['dueDate'] is String &&
        (d['loanDate'] as String).compareTo(d['dueDate'] as String) > 0) {
      fields['loanDate'] = 'No puede ser después de la fecha de pago';
    }
    if (fields.isNotEmpty) throw _invalid(fields);
  }

  static const _fields = ['person', 'amount', 'loanDate', 'dueDate', 'installments', 'frequency', 'note'];

  @override
  Future<void> create(Map<String, dynamic> body) => _write((all) async {
    final raw = <String, dynamic>{
      'id': _rand('demo-c'),
      'kind': body['kind'],
      for (final key in _fields) key: body[key],
      'settledAt': null,
      'transactionId': null,
      'createdAt': _now,
      'updatedAt': _now,
      'payments': const <Object>[],
    };
    if (raw['installments'] == null) raw['frequency'] = null;
    _validate(raw);
    raw['person'] = (raw['person'] as String).trim();
    raw['amount'] = readMoney(raw['amount']);
    await _save([...all, raw]);
  });

  @override
  Future<void> update(String id, Map<String, dynamic> body) => _write((all) async {
    final raw = _find(all, id);
    if (raw['settledAt'] != null) throw _alreadySettled;
    if (body.containsKey('kind')) throw _invalid({'kind': 'No se cambia: borra la cuenta y créala de nuevo'});
    final next = {
      ...raw,
      for (final key in _fields)
        if (body.containsKey(key)) key: body[key],
      'updatedAt': _now,
    };
    if (next['installments'] == null) next['frequency'] = null;
    _validate(next);
    next['person'] = (next['person'] as String).trim();
    next['amount'] = readMoney(next['amount']);
    await _save([for (final d in all) d['id'] == id ? next : d]);
  });

  @override
  Future<void> delete(String id) => _write((all) async {
    _find(all, id);
    // Como el servidor: los abonos se van con la cuenta; sus movimientos quedan.
    await _save(all.where((d) => d['id'] != id).toList());
  });

  @override
  Future<void> pay(
    String id, {
    required num amount,
    required String date,
    required bool createTransaction,
    String? idempotencyKey,
  }) => _write((all) async {
    final raw = _find(all, id);
    if (raw['settledAt'] != null) throw _alreadySettled;
    if (amount <= 0) throw _invalid({'amount': 'Debe ser un número mayor que 0'});
    if (date.compareTo(isoDay(clock())) > 0) throw _invalid({'date': 'No puede ser una fecha futura'});
    final pending = _progress(raw).pending;
    if (_cents(amount) > _cents(pending)) {
      throw _invalid({'amount': 'No puede pasar de lo pendiente ($pending)'});
    }
    final receivable = raw['kind'] == 'receivable';
    final transactionId = createTransaction
        ? await _addMovement(
            income: receivable,
            amount: amount,
            date: date,
            description: receivable ? 'Abono de ${raw['person']}' : 'Abono a ${raw['person']}',
          )
        : null;
    final next = {
      ...raw,
      'payments': [
        ..._payments(raw),
        {
          'id': _rand('demo-a'),
          'amount': readMoney(amount),
          'date': date,
          'transactionId': transactionId,
          'createdAt': _now,
        },
      ],
      'updatedAt': _now,
    };
    // El abono que completa la salda sin un segundo movimiento (markSettled, transactionId null).
    if (_cents(_progress(next).pending) == 0) next['settledAt'] = _now;
    await _save([for (final d in all) d['id'] == id ? next : d]);
  });

  @override
  Future<void> settle(String id, {required bool createTransaction}) => _write((all) async {
    final raw = _find(all, id);
    if (raw['settledAt'] != null) throw _alreadySettled;
    // Por lo que faltaba, no por el total (debts.service.js:190-191).
    final missing = _progress(raw).pending;
    final receivable = raw['kind'] == 'receivable';
    final transactionId = createTransaction && missing > 0
        ? await _addMovement(
            income: receivable,
            amount: missing,
            date: isoDay(clock()),
            description: receivable ? '${raw['person']} me pagó' : 'Le pagué a ${raw['person']}',
          )
        : null;
    final next = {...raw, 'settledAt': _now, 'transactionId': transactionId, 'updatedAt': _now};
    await _save([for (final d in all) d['id'] == id ? next : d]);
  });

  @override
  Future<Debt> deletePayment(String id, String paymentId) => _write((all) async {
    // Como el servidor: 404 «Abono no encontrado» también si la cuenta ya está saldada.
    final raw = _find(all, id, _paymentNotFound);
    final payments = _payments(raw);
    final payment = payments.where((p) => p['id'] == paymentId).firstOrNull;
    if (raw['settledAt'] != null || payment == null) throw _paymentNotFound;
    final next = {
      ...raw,
      'payments': payments.where((p) => p['id'] != paymentId).toList(),
      'updatedAt': _now,
    };
    // El servidor también borra el movimiento que se anotó con el abono. Se lee ANTES de guardar: si
    // no se puede, nada cambia (ni el abono ni su movimiento).
    final transactionId = payment['transactionId'];
    final movements = transactionId is String ? await _movements() : null;
    await _save([for (final d in all) d['id'] == id ? next : d]);
    if (movements != null) {
      await movementsStore.write(userId, [
        for (final m in movements)
          if (m is! Map || m['id'] != transactionId) m,
      ]);
    }
    return Debt.fromJson(_served(next));
  });

  /// Un llavero de movimientos ilegible falla en vez de leerse como vacío: escribir encima borraría
  /// los movimientos de la demo.
  Future<List<Object?>> _movements() async =>
      await movementsStore.read(userId) ??
      (throw StateError('No se pudieron leer los movimientos de la demostración'));

  /// Ingreso en «Otros ingresos» o gasto en «Otros», en el almacén de movimientos de la demo. Va antes
  /// de guardar la cuenta: si falla, la cuenta no cambia.
  Future<String> _addMovement({
    required bool income,
    required num amount,
    required String date,
    required String description,
  }) async {
    final id = _rand('demo');
    final movements = await _movements();
    await movementsStore.write(userId, [
      ...movements,
      {
        'id': id,
        'localId': null,
        'type': income ? 'ingreso' : 'gasto',
        'amount': readMoney(amount),
        'description': description,
        'category': income ? 'otros_ingresos' : 'otros',
        'source': 'manual',
        'date': date,
        'createdAt': _now,
        'updatedAt': _now,
        'deletedAt': null,
        'card': null,
        'installments': null,
        'emotion': null,
        'kakeibo': null,
        'original': null,
      },
    ]);
    return id;
  }
}

/// Uno por usuario demo. Comparte los almacenes de la demostración.
final demoDebtsRepositoryProvider = Provider.family<DemoDebtsRepository, String>(
  (ref, userId) => DemoDebtsRepository(
    userId: userId,
    store: ref.watch(demoDebtsStoreProvider),
    movementsStore: ref.watch(demoMovementsStoreProvider),
    stateStore: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    clock: ref.watch(clockProvider),
  ),
);
