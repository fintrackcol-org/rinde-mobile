import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../account/data/demo_account_repository.dart' show demoAccountRepositoryProvider;
import '../../auth/application/session_controller.dart';
import '../../cards/data/demo_cards_store.dart' show demoCardsStoreProvider;
import '../../debts/data/demo_debts_store.dart' show demoDebtsStoreProvider;
import '../../plan/data/demo_budgets_repository.dart' show demoBudgetsStoreProvider;
import '../../home/application/tour_controller.dart' show tourSeenStoreProvider;
import '../../home/data/home_models.dart' show readMoney;
import 'onboarding_repository.dart';
import '../../movements/application/movement_saver.dart' show pendingStoreProvider;
import '../../movements/data/demo_movements_repository.dart'
    show demoHasMovements, demoMovementsStoreProvider;

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND
//  Solo para desarrollo y pruebas. Nada de esto llega a un servidor ni confirma nada real.
//  Se usa únicamente con una sesión demo, que solo existe en compilaciones de desarrollo
//  con DEMO_MODE=true (ver AppConfig.demoMode).
// ─────────────────────────────────────────────────────────────────────────────

/// Escenarios de prueba. Los montos son SINTÉTICOS (no son de nadie) y están en pesos colombianos.
enum DemoScenario {
  /// Cuenta recién creada: sin movimientos y sin bienvenida → bienvenida completa y, al terminarla,
  /// un Inicio armado con lo que la bienvenida mandó.
  nuevo('Usuario nuevo'),

  /// Ya tiene movimientos y no respondió → Mi plata con «te alcanza» e invitación a las preguntas.
  movimientos('Usuario con movimientos', income: 2500000, expense: 1850000),

  /// Plan del servidor listo y con de todo: libre para gastar, pagos, presupuesto, tarjeta y avisos.
  planListo('Plan listo: libre para gastar', income: 1300000, expense: 887700, money: 412300, welcomed: true),

  /// La plata no alcanza para los pagos que vienen.
  teFaltan(
    'Te faltan: no alcanza para los pagos',
    income: 900000,
    expense: 720000,
    money: 180000,
    welcomed: true,
  ),

  /// La plata misma está bajo cero.
  negativo('Estás en negativo', income: 600000, expense: 635000, money: -35000, welcomed: true),

  /// Omitió la bienvenida y tiene movimientos: no hay plan, solo el enlace para configurarlo. Lo que
  /// configure en Mi plata queda guardado, como en un recorrido.
  sinPlan('Sin plan: omitió la bienvenida', income: 700000, expense: 287700, welcomed: true);

  const DemoScenario(this.label, {this.income = 0, this.expense = 0, this.money, this.welcomed = false});

  final String label;

  /// Todo el historial (GET /money-profile → totals).
  final num income;
  final num expense;

  /// Plata actual cuando la persona ya dijo su saldo. null = sale de los movimientos o de lo que
  /// responda en la bienvenida.
  final num? money;

  /// La bienvenida ya está hecha (u omitida) desde el principio.
  final bool welcomed;

  static DemoScenario fromUserId(String userId) =>
      values.firstWhere((s) => userId.endsWith(s.name), orElse: () => nuevo);
}

/// Escrituras de la bienvenida y la lectura de su estado. Quedan en el registro de llamadas.
enum DemoOperation { status, region, welcome, sources }

/// Lecturas del Inicio. Van aparte de [DemoOperation] porque ese es el registro de lo que la
/// bienvenida "envió" (la pantalla final de la demostración lo lista operación por operación).
enum DemoHomeOperation {
  /// GET /money-profile/plan.
  plan,

  /// GET /transactions/summary.
  summary,

  /// Presupuestos, tarjetas, pagos por confirmar, notificaciones y categorías.
  secondary,
}

enum DemoFailure { network, server }

/// Perillas de la demostración (panel «DEMO»).
class DemoControls {
  const DemoControls({
    this.latency = const Duration(milliseconds: 700),
    this.offline = false,
    this.failures = const {},
  });

  final Duration latency;

  /// «Sin conexión»: todas las llamadas fallan por red hasta que se apague.
  final bool offline;

  /// Falla una sola vez la próxima llamada a esa operación ([DemoOperation] o [DemoHomeOperation]).
  final Map<Enum, DemoFailure> failures;

  DemoControls copyWith({Duration? latency, bool? offline, Map<Enum, DemoFailure>? failures}) => DemoControls(
    latency: latency ?? this.latency,
    offline: offline ?? this.offline,
    failures: failures ?? this.failures,
  );
}

class DemoControlsNotifier extends Notifier<DemoControls> {
  @override
  DemoControls build() => const DemoControls();

  void failNext(Enum op, DemoFailure? failure) {
    final next = Map<Enum, DemoFailure>.of(state.failures);
    failure == null ? next.remove(op) : next[op] = failure;
    state = state.copyWith(failures: next);
  }

  void setLatency(Duration latency) => state = state.copyWith(latency: latency);

  void setOffline(bool offline) => state = state.copyWith(offline: offline);

  /// Vuelve la conexión y se borran las fallas programadas. La latencia se queda.
  void reconnect() => state = state.copyWith(offline: false, failures: const {});

  /// Lo que le pasa a una llamada sintética: espera la latencia y falla si toca.
  Future<void> simulate([Enum? op]) async {
    // La falla programada se lee al salir la llamada: las que salen juntas (los bloques secundarios
    // del Inicio) fallan todas, y solo esa vez.
    final planned = op == null ? null : state.failures[op];
    await Future<void>.delayed(state.latency);
    if (planned != null) failNext(op!, null);
    switch (state.offline ? DemoFailure.network : planned) {
      case DemoFailure.network:
        throw const ApiException(code: ApiCodes.network);
      case DemoFailure.server:
        throw const ApiException(
          code: 'INTERNAL_ERROR',
          serverMessage: 'Error simulado del servidor (demostración).',
          status: 500,
        );
      case null:
        return;
    }
  }
}

final demoControlsProvider = NotifierProvider<DemoControlsNotifier, DemoControls>(DemoControlsNotifier.new);

/// Lo que la demo "recibió" (para mostrarlo al terminar y para las pruebas).
class DemoCall {
  const DemoCall(this.operation, this.body);
  final DemoOperation operation;
  final Object? body;
}

List<int> _ints(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is int) item,
];

/// La cuenta sintética de un usuario demo: UN solo estado del que salen la bienvenida y el Inicio.
/// Guarda lo que la bienvenida mandó con las reglas del servidor (money-profile.service.js e
/// income.logic.js de Rinde Web), para que el recorrido sea coherente de principio a fin.
class DemoState {
  const DemoState({
    this.welcomeDone = false,
    this.tutorialDone = false,
    this.region,
    this.balance,
    this.commitments = const [],
    this.incomeType,
    this.payDays = const [],
    this.sources = const [],
    this.adjustments = const [],
    this.lastId = 0,
  });

  factory DemoState.fromJson(Object? raw) {
    if (raw is! Map) return const DemoState();
    final region = raw['region'];
    final commitments = raw['commitments'];
    return DemoState(
      welcomeDone: raw['welcomeDone'] == true,
      tutorialDone: raw['tutorialDone'] == true,
      region: region is Map<String, dynamic> ? Region.fromJson(region) : null,
      balance: readMoney(raw['balance']),
      commitments: [
        if (commitments is List)
          for (final item in commitments)
            if (item is Map) Map<String, dynamic>.from(item),
      ],
      incomeType: raw['incomeType'] is String ? raw['incomeType'] as String : null,
      payDays: _ints(raw['payDays']),
      sources: [
        if (raw['sources'] case final List<dynamic> sources)
          for (final item in sources)
            if (item is Map) Map<String, dynamic>.from(item),
      ],
      adjustments: [
        if (raw['adjustments'] case final List<dynamic> adjustments)
          for (final item in adjustments)
            if (item is Map) Map<String, dynamic>.from(item),
      ],
      lastId: raw['lastId'] is int ? raw['lastId'] as int : 0,
    );
  }

  final bool welcomeDone;
  final bool tutorialDone;

  /// null = nadie la ha guardado: la de una cuenta nueva.
  final Region? region;

  /// El saldo que la persona dijo. null = no lo ha dicho.
  final num? balance;

  /// Pagos fijos: `{name, amount, dayOfMonth}` (los de Mi plata traen además `id`, `kind`, `frequency` y
  /// `month`; ver [commitmentsWithIds]).
  final List<Map<String, dynamic>> commitments;

  /// `fecha_fija`, `sin_fecha` o null (sin fuentes de ingreso).
  final String? incomeType;
  final List<int> payDays;

  /// Las fuentes de ingreso tal como las recibió PUT /money-profile/sources.
  final List<Map<String, dynamic>> sources;

  /// Correcciones de saldo `{id, before, after, date, createdAt}`, de la más vieja a la más nueva.
  final List<Map<String, dynamic>> adjustments;

  /// El mayor `demo-c<n>` que se ha dado: el id de un pago borrado (y su aviso cerrado) no se repite.
  final int lastId;

  Map<String, dynamic> toJson() => {
    'welcomeDone': welcomeDone,
    'tutorialDone': tutorialDone,
    'region': region?.toJson(),
    'balance': balance,
    'commitments': commitments,
    'incomeType': incomeType,
    'payDays': payDays,
    'sources': sources,
    'adjustments': adjustments,
    'lastId': lastId,
  };

  /// Los montos fijos de los escenarios están pensados en pesos colombianos. Con otra moneda se
  /// dividen entre 1.000 (412.300 → 412,3) para que se vean cifras creíbles y con decimales. Lo que
  /// escribe la persona nunca se escala.
  num fixed(num cop) => (region?.currency ?? 'COP') == 'COP' ? cop : readMoney(cop / 1000)!;

  /// PATCH /users/me.
  DemoState withRegion(Region region) => DemoState(
    welcomeDone: welcomeDone,
    tutorialDone: tutorialDone,
    region: region,
    balance: balance,
    commitments: commitments,
    incomeType: incomeType,
    payDays: payDays,
    sources: sources,
    adjustments: adjustments,
    lastId: lastId,
  );

  /// POST /money-profile/tutorial.
  DemoState withTutorial() => DemoState(
    welcomeDone: welcomeDone,
    tutorialDone: true,
    region: region,
    balance: balance,
    commitments: commitments,
    incomeType: incomeType,
    payDays: payDays,
    sources: sources,
    adjustments: adjustments,
    lastId: lastId,
  );

  /// POST /money-profile/welcome.
  DemoState withWelcome(Map<String, dynamic> body) {
    final sent = readMoney(body['balance']);
    // Sin saldo ni tipo de ingreso no «respondió»: el servidor conserva lo que había y solo suma
    // pagos. Si respondió, lo sobrescribe todo (el tipo de ingreso vuelve hasta que lleguen las fuentes).
    final answered = body['incomeType'] != null || sent != null;
    final names = {for (final c in commitments) '${c['name']}'.toLowerCase()};
    final added = body['commitments'];
    return DemoState(
      welcomeDone: true,
      tutorialDone: tutorialDone,
      region: region,
      balance: answered ? sent : balance,
      incomeType: answered ? body['incomeType'] as String? : incomeType,
      payDays: answered ? _ints(body['payDays']) : payDays,
      sources: sources,
      adjustments: adjustments,
      lastId: lastId,
      commitments: [
        ...commitments,
        // ON CONFLICT (lower(nombre)) DO NOTHING: un nombre que ya está no cambia de monto ni se repite.
        // Solo quedan nombre, monto y día, como en el servidor.
        if (added is List)
          for (final c in added)
            if (c is Map && names.add('${c['name']}'.toLowerCase()))
              {'name': c['name'], 'amount': c['amount'], 'dayOfMonth': c['dayOfMonth']},
      ],
    );
  }

  /// PUT /money-profile/sources: las fuentes reemplazan a las anteriores y de ellas sale el tipo de
  /// ingreso (`legacyIncomeType`). No toca el saldo ni la bienvenida.
  DemoState withSources(List<Map<String, dynamic>> sources) {
    final days = {
      for (final s in sources)
        if (const ['sueldo', 'mesada', 'comisiones'].contains(s['kind'])) ..._ints(s['payDays']),
    }.toList()..sort();
    return DemoState(
      welcomeDone: welcomeDone,
      tutorialDone: tutorialDone,
      region: region,
      balance: balance,
      commitments: commitments,
      incomeType: sources.isEmpty
          ? null
          : days.isEmpty
          ? 'sin_fecha'
          : 'fecha_fija',
      payDays: days.take(4).toList(),
      sources: sources,
      adjustments: adjustments,
      lastId: lastId,
    );
  }

  /// PUT /money-profile con `resetBalance` (Corregir saldo): el saldo nuevo y, si cambió, su ajuste.
  DemoState withBalance(num balance, {Map<String, dynamic>? adjustment}) => DemoState(
    welcomeDone: welcomeDone,
    tutorialDone: tutorialDone,
    region: region,
    balance: balance,
    commitments: commitments,
    incomeType: incomeType,
    payDays: payDays,
    sources: sources,
    adjustments: [...adjustments, ?adjustment],
    lastId: lastId,
  );

  /// PUT /money-profile: el tipo de ingreso y los días (solo con fecha fija), como los mandó.
  DemoState withIncomeType(String? type, List<int> days) => DemoState(
    welcomeDone: welcomeDone,
    tutorialDone: tutorialDone,
    region: region,
    balance: balance,
    commitments: commitments,
    incomeType: type,
    payDays: type == 'fecha_fija' ? days : const [],
    sources: sources,
    adjustments: adjustments,
    lastId: lastId,
  );

  /// Los pagos con su id fijo (`demo-c<n>`). El que no lo tiene (los de la bienvenida o un estado de
  /// antes) lo recibe al leerlo, después del mayor que ya se haya dado: así no cambia al renombrar ni al
  /// borrar otro, y Mi plata y el Inicio dicen el mismo id.
  List<Map<String, dynamic>> get commitmentsWithIds => withDemoIds(commitments, after: lastId);

  /// POST, PUT y DELETE /money-profile/commitments desde Mi plata: la lista completa, ya con ids (los
  /// nombres repetidos ya los descartó quien llama).
  DemoState withCommitments(List<Map<String, dynamic>> list) {
    // Cuenta también el id del que se borra (aunque solo lo tuviera al leerlo).
    final used = _maxDemoId(commitmentsWithIds, lastId);
    final next = withDemoIds(list, after: used);
    return DemoState(
      welcomeDone: welcomeDone,
      tutorialDone: tutorialDone,
      region: region,
      balance: balance,
      commitments: next,
      incomeType: incomeType,
      payDays: payDays,
      sources: sources,
      adjustments: adjustments,
      lastId: _maxDemoId(next, used),
    );
  }
}

/// El mayor n de los `demo-c<n>` de [list], o [floor] si es mayor.
int _maxDemoId(List<Map<String, dynamic>> list, int floor) => list.fold(floor, (max, c) {
  final n = int.tryParse('${c['id']}'.replaceFirst('demo-c', '')) ?? 0;
  return n > max ? n : max;
});

/// Pone `demo-c<n>` a los pagos que no tienen id, después del mayor que exista o de [after].
List<Map<String, dynamic>> withDemoIds(List<Map<String, dynamic>> list, {int after = 0}) {
  var next = _maxDemoId(list, after) + 1;
  return [
    for (final c in list) c['id'] is String ? c : {...c, 'id': 'demo-c${next++}'},
  ];
}

/// Estado simulado que sobrevive a cerrar la app (para probar «ya la terminó» y el Inicio).
abstract class DemoStateStore {
  const DemoStateStore();

  Future<DemoState> read(String userId);
  Future<void> write(String userId, DemoState state);
  Future<void> clear(String userId);

  Future<void> update(String userId, DemoState Function(DemoState state) change) async =>
      write(userId, change(await read(userId)));

  Future<bool> welcomeDone(String userId) async => (await read(userId)).welcomeDone;
}

class SecureDemoStateStore extends DemoStateStore {
  const SecureDemoStateStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  String _key(String userId) => 'rinde.demo.$userId';

  @override
  Future<DemoState> read(String userId) async {
    try {
      final raw = await _storage.read(key: _key(userId));
      return raw == null ? const DemoState() : DemoState.fromJson(jsonDecode(raw));
    } catch (_) {
      return const DemoState();
    }
  }

  @override
  Future<void> write(String userId, DemoState state) async {
    try {
      await _storage.write(key: _key(userId), value: jsonEncode(state.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {}
  }
}

/// En memoria, para pruebas. Guarda el JSON, como el almacenamiento real.
class MemoryDemoStateStore extends DemoStateStore {
  final _data = <String, String>{};

  @override
  Future<DemoState> read(String userId) async =>
      _data[userId] == null ? const DemoState() : DemoState.fromJson(jsonDecode(_data[userId]!));
  @override
  Future<void> write(String userId, DemoState state) async => _data[userId] = jsonEncode(state.toJson());
  @override
  Future<void> clear(String userId) async => _data.remove(userId);
}

final demoStateStoreProvider = Provider<DemoStateStore>((ref) => const SecureDemoStateStore());

/// GET /money-profile (y si hay movimientos) de la cuenta sintética. La bienvenida y el Inicio leen
/// la plata de aquí, para que digan lo mismo.
WelcomeStatus demoWelcomeStatus(DemoScenario scenario, DemoState state) {
  final income = state.fixed(scenario.income);
  final expense = state.fixed(scenario.expense);
  final ledger = readMoney(income - expense)!;
  // `currentMoney` del servidor: manda el saldo que dijo la persona; si no, lo que dan los movimientos
  // y solo si es positivo. Sin ninguno de los dos no se sabe (null), nunca cero.
  // Los fijos con saldo lo traen literal; sinPlan (sin saldo fijo) y los recorridos, el que se guardó.
  final said = scenario.money == null ? state.balance : state.fixed(scenario.money!);
  return WelcomeStatus(
    welcomeDone: scenario.welcomed || state.welcomeDone,
    tutorialDone: state.tutorialDone,
    hasTransactions: scenario.income > 0 || scenario.expense > 0,
    income: income,
    expense: expense,
    money: said ?? (ledger > 0 ? ledger : null),
    balanceSet: said != null,
    balance: said,
    incomeType: state.incomeType,
    payDays: state.payDays,
    commitmentNames: [for (final c in state.commitments) '${c['name']}'],
  );
}

class DemoOnboardingRepository implements OnboardingRepository {
  DemoOnboardingRepository({
    required this.userId,
    required this.store,
    required this.controls,
    this.onReset,
    this.hasMovements,
  });

  /// La demo ya tiene movimientos anotados (una cuenta nueva deja de verse «sin movimientos»).
  final Future<bool> Function()? hasMovements;

  final String userId;
  final DemoStateStore store;
  final DemoControlsNotifier controls;

  /// Lo que hay que devolver fuera del estado guardado al reiniciar (la región que se ve y el tutorial).
  final void Function()? onReset;
  final calls = <DemoCall>[];

  DemoScenario get scenario => DemoScenario.fromUserId(userId);

  @override
  bool get isDemo => true;

  /// Sube al reiniciar: una respuesta que venía en camino ya no escribe sobre la cuenta recién creada.
  int _run = 0;

  Future<void> _simulate(DemoOperation op, Object? body) {
    calls.add(DemoCall(op, body));
    return controls.simulate(op);
  }

  @override
  Future<WelcomeStatus> status() async {
    await _simulate(DemoOperation.status, null);
    final status = demoWelcomeStatus(scenario, await store.read(userId));
    if (status.hasTransactions || !(await hasMovements?.call() ?? false)) return status;
    return WelcomeStatus(
      welcomeDone: status.welcomeDone,
      tutorialDone: status.tutorialDone,
      hasTransactions: true,
      income: status.income,
      expense: status.expense,
      money: status.money,
      balanceSet: status.balanceSet,
      balance: status.balance,
      incomeType: status.incomeType,
      payDays: status.payDays,
      commitmentNames: status.commitmentNames,
    );
  }

  @override
  Future<Region> saveRegion({required String country, required String language}) async {
    final run = _run;
    await _simulate(DemoOperation.region, {'country': country, 'language': language});
    final region = regionForCountry(country);
    // Escenario con movimientos: la moneda ya no se puede cambiar (como CURRENCY_LOCKED en el servidor).
    final currency = scenario == DemoScenario.movimientos ? 'COP' : region.currency;
    final saved = Region(country: region.country, currency: currency, language: language);
    if (run == _run) await store.update(userId, (state) => state.withRegion(saved));
    return saved;
  }

  @override
  Future<void> finishWelcome(Map<String, dynamic> body, {String? idempotencyKey}) async {
    final run = _run;
    await _simulate(DemoOperation.welcome, body);
    if (run != _run) return;
    await store.update(userId, (state) => state.withWelcome(body));
  }

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) async {
    final run = _run;
    await _simulate(DemoOperation.sources, sources);
    if (run != _run) return;
    await store.update(userId, (state) => state.withSources(sources));
  }

  /// «Reiniciar demostración»: la cuenta sintética vuelve a estar recién creada.
  Future<void> reset() async {
    _run++;
    // Con una falla puesta la lectura no volvería, y seguiría en pantalla la plata de la cuenta borrada.
    controls.reconnect();
    calls.clear();
    await store.clear(userId);
    onReset?.call();
  }
}

final demoOnboardingRepositoryProvider = Provider.family<DemoOnboardingRepository, String>(
  (ref, userId) => DemoOnboardingRepository(
    userId: userId,
    store: ref.watch(demoStateStoreProvider),
    controls: ref.read(demoControlsProvider.notifier),
    onReset: () {
      // La región que se ve también vuelve a la de una cuenta nueva (sin guardarla en el dispositivo).
      unawaited(ref.read(appRegionProvider.notifier).set(kDefaultRegion, persist: false));
      ref.invalidate(profileProvider);
      // La marca local del tutorial es de este usuario, que es el mismo en cada reinicio.
      unawaited(ref.read(tourSeenStoreProvider).clear(userId));
      // Lo anotado y lo pendiente de esta cuenta demo también se borran.
      unawaited(ref.read(demoMovementsStoreProvider).write(userId, const []));
      unawaited(ref.read(demoCardsStoreProvider).write(userId, const []));
      unawaited(ref.read(demoDebtsStoreProvider).write(userId, const []));
      unawaited(ref.read(demoBudgetsStoreProvider).write(userId, const []));
      unawaited(ref.read(pendingStoreProvider).write(userId, const []));
      // Los avisos y el WhatsApp de «Yo» (en memoria) también vuelven a los de una cuenta nueva.
      ref.invalidate(demoAccountRepositoryProvider(userId));
    },
    hasMovements: () => demoHasMovements(ref.read(demoMovementsStoreProvider), userId),
  ),
);
