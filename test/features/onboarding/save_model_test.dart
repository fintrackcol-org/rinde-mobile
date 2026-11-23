import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';

// El guardado en dos etapas, contra un servidor con las reglas del real (DemoState las porta:
// «respondió o conserva», ON CONFLICT DO NOTHING, las fuentes reemplazan). Se recorren TODAS las
// secuencias cortas de acciones y fallas y se exige, en cada una:
//   1. «Guardado» es verdad: el saldo, los pagos y las fuentes están en el servidor.
//   2. Ningún pago queda dos veces.
//   3. Nada que pudo llegar queda sin retomar.
//   4. No se borra lo que otro camino guardó.
//   5. Siempre hay salida: con el servidor sano, «Ver mi plata» termina.

enum _Fault {
  /// Responde bien.
  none,

  /// No salió del teléfono.
  notSent,

  /// Se aplicó y la respuesta se perdió.
  lost,

  /// Se aplicó, se perdió la respuesta y tampoco se puede preguntar.
  lostBlind,

  /// Venció la espera y no se aplicó.
  timeout,

  /// El servidor falló y deshizo la operación.
  rollback,

  /// Lo rechazó.
  invalid,
}

class _Server implements OnboardingRepository {
  _Server(this.state);

  DemoState state;
  _Fault welcome = _Fault.none;
  _Fault sources = _Fault.none;
  bool blind = false;

  /// La app escribió la etapa 1 alguna vez.
  bool appWelcomed = false;

  /// Un PUT de fuentes de la app pudo llegar.
  bool appSourcesMaybe = false;
  List<Map<String, dynamic>>? lastSources;

  Future<void> _answer(_Fault fault, void Function() apply) async {
    switch (fault) {
      case _Fault.none:
        apply();
      case _Fault.notSent:
        throw const ApiException(code: ApiCodes.network);
      case _Fault.lost:
        apply();
        throw const ApiException(code: ApiCodes.timeout);
      case _Fault.lostBlind:
        apply();
        blind = true;
        throw const ApiException(code: ApiCodes.timeout);
      case _Fault.timeout:
        throw const ApiException(code: ApiCodes.timeout);
      case _Fault.rollback:
        throw const ApiException(code: 'INTERNAL_ERROR', status: 500);
      case _Fault.invalid:
        throw const ApiException(code: ApiCodes.validation, status: 422);
    }
  }

  @override
  bool get isDemo => false;

  @override
  Future<WelcomeStatus> status() async {
    if (blind) throw const ApiException(code: ApiCodes.timeout);
    return WelcomeStatus(
      welcomeDone: state.welcomeDone,
      tutorialDone: false,
      hasTransactions: true,
      money: state.balance,
      balance: state.balance,
      balanceSet: state.balance != null,
      incomeType: state.incomeType,
      payDays: state.payDays,
      commitmentNames: [for (final c in state.commitments) '${c['name']}'],
    );
  }

  @override
  Future<Region> saveRegion({required String country, required String language}) async => kDefaultRegion;

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) => _answer(welcome, () {
    state = state.withWelcome(body);
    appWelcomed = true;
  });

  @override
  Future<void> saveSources(List<Map<String, dynamic>> list) {
    if (sources != _Fault.notSent && sources != _Fault.invalid) appSourcesMaybe = true;
    return _answer(sources, () {
      state = state.withSources(list);
      lastSources = list;
    });
  }
}

class _NoRegionStore extends RegionStore {
  @override
  Future<Region?> read() async => null;
  @override
  Future<void> write(Region region) async {}
}

enum _Do { finish, skip, balance, dropSources, rename, reopen, inviteLater }

typedef _Step = ({_Do act, _Fault welcome, _Fault sources});

_Step _step(_Do act, [_Fault welcome = _Fault.none, _Fault sources = _Fault.none]) =>
    (act: act, welcome: welcome, sources: sources);

final _sends = [
  for (final act in [_Do.finish, _Do.skip]) ...[
    for (final fault in _Fault.values) _step(act, fault),
    for (final fault in [_Fault.notSent, _Fault.lost, _Fault.timeout, _Fault.invalid])
      _step(act, _Fault.none, fault),
  ],
];

final _all = [
  ..._sends,
  for (final act in [_Do.balance, _Do.dropSources, _Do.rename, _Do.reopen, _Do.inviteLater]) _step(act),
];

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

typedef _Start = ({String name, OnboardingMode mode, DemoState server, OnboardingDraft draft});

final List<_Start> _starts = [
  (
    name: 'cuenta nueva con fuentes y un pago',
    mode: OnboardingMode.full,
    server: const DemoState(),
    draft: const OnboardingDraft(
      position: OnboardingSteps.payments,
      country: 'CO',
      language: 'es',
      balance: '900000',
      sources: {
        IncomeKind.sueldo: IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]),
      },
      items: [CommitmentItem(key: 'k1', name: 'Arriendo', amount: '800000', dayOfMonth: '5')],
    ),
  ),
  (
    name: 'ya tenía saldo y tipo de ingreso, solo responde el saldo',
    mode: OnboardingMode.questions,
    server: const DemoState(balance: 500000, incomeType: 'fecha_fija', payDays: [15, 30]),
    draft: const OnboardingDraft(
      position: OnboardingSteps.payments,
      country: 'CO',
      language: 'es',
      balance: '900000',
    ),
  ),
  (
    name: 'ya tenía tipo de ingreso, responde saldo y un pago',
    mode: OnboardingMode.questions,
    server: const DemoState(balance: 500000, incomeType: 'fecha_fija', payDays: [15, 30]),
    draft: const OnboardingDraft(
      position: OnboardingSteps.payments,
      country: 'CO',
      language: 'es',
      balance: '900000',
      items: [CommitmentItem(key: 'k1', name: 'Arriendo', amount: '800000', dayOfMonth: '5')],
    ),
  ),
  (
    name: 'ya tenía tipo de ingreso y elige fuentes',
    mode: OnboardingMode.questions,
    server: const DemoState(incomeType: 'fecha_fija', payDays: [10]),
    draft: const OnboardingDraft(
      position: OnboardingSteps.payments,
      country: 'CO',
      language: 'es',
      balance: '900000',
      sources: {
        IncomeKind.sueldo: IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]),
      },
    ),
  ),
];

/// Corre una secuencia y devuelve lo que no se cumplió, o null.
Future<String?> _run(_Start start, List<_Step> steps) async {
  final server = _Server(start.server);
  final store = MemoryDraftStore();
  await store.write('u1', start.draft.toJson());
  final provider = onboardingControllerProvider(start.mode);

  late ProviderContainer c;
  late OnboardingController n;
  Future<void> open() async {
    server.blind = false;
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(_session)),
        draftStoreProvider.overrideWithValue(store),
        regionStoreProvider.overrideWithValue(_NoRegionStore()),
        systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
        onboardingRepositoryProvider.overrideWithValue(server),
      ],
    );
    await c.read(sessionControllerProvider.future);
    c.listen(provider, (_, _) {});
    n = c.read(provider.notifier);
    await pumpEventQueue(times: 8);
  }

  OnboardingState now() => c.read(provider);

  Future<String?> send(_Step step) async {
    server
      ..blind = false
      ..welcome = step.welcome
      ..sources = step.sources;
    final draft = now().draft;
    // Antes de este envío: un borrado que no debía salir no puede justificarse a sí mismo.
    final sourcesMaybe = server.appSourcesMaybe;
    await (step.act == _Do.finish ? n.finish() : n.skip());
    final after = now();
    if (after.outcome != OnboardingOutcome.saved) return null;

    final balance = draft.balance.isEmpty ? null : num.parse(draft.balance);
    if (balance != null && server.state.balance != balance) return 'dijo guardado y el saldo no está';
    final names = {for (final c in server.state.commitments) c['name']};
    if (step.act == _Do.finish && !draft.items.every((i) => names.contains(i.name))) {
      return 'dijo guardado y faltan pagos';
    }
    if (draft.sources.isNotEmpty) {
      if (server.lastSources?.length != draft.sources.length) return 'dijo guardado y las fuentes no están';
      if (server.state.incomeType != 'fecha_fija' || server.state.payDays.join(',') != '15,30') {
        return 'las fuentes no fijaron el tipo de ingreso';
      }
    } else if (!sourcesMaybe) {
      if (server.state.incomeType != start.server.incomeType ||
          server.state.payDays.join() != start.server.payDays.join()) {
        return 'borró el tipo de ingreso que otro camino guardó';
      }
    } else if (server.lastSources?.isNotEmpty ?? false) {
      return 'dijo guardado y las fuentes quitadas siguen';
    }
    return null;
  }

  String? invariants() {
    if (server.state.commitments.length > 1) return 'pago duplicado';
    if (now().paymentsSaved && server.state.commitments.isEmpty) return 'dice pagos guardados y no están';
    final done = now().outcome != null || now().alreadyDone;
    if (server.appWelcomed && !done && now().draft.sentWelcome == null) {
      return 'llegó y no quedó marca para retomar';
    }
    return null;
  }

  await open();
  try {
    for (final step in steps) {
      if (now().outcome != null || now().alreadyDone) return null;
      switch (step.act) {
        case _Do.finish || _Do.skip:
          if (await send(step) case final problem?) return problem;
        case _Do.balance:
          n.setBalance('750000');
        case _Do.dropSources:
          for (final kind in now().draft.sources.keys.toList()) {
            n.toggleSource(kind);
          }
        case _Do.rename:
          if (now().draft.items.isNotEmpty) n.updateItem('k1', name: 'Apartamento');
        case _Do.reopen:
          await n.flush();
          c.dispose();
          await open();
        case _Do.inviteLater:
          // «Ahora no» de la invitación: marca la bienvenida y conserva un borrador que ya salió.
          if (server.state.welcomeDone) continue;
          await n.flush();
          server.state = server.state.withWelcome(const {});
          final saved = await store.read('u1');
          if (saved is Map && saved['sentWelcome'] is! String) await store.clear('u1');
          c.dispose();
          await open();
      }
      if (invariants() case final problem?) return problem;
    }

    if (now().outcome != null || now().alreadyDone) return null;
    if (now().draft.sentWelcome != null && server.state.welcomeDone) {
      c.invalidate(pendingSourcesProvider);
      if (!await c.read(pendingSourcesProvider(c.read(accountProvider)).future)) {
        return 'queda trabajo y al reabrir no se retoma';
      }
    }
    if (await send(_step(_Do.finish)) case final problem?) return problem;
    if (now().outcome != OnboardingOutcome.saved) return 'sin salida: ${now().error?.text}';
    return invariants();
  } finally {
    c.dispose();
  }
}

void main() {
  for (final start in _starts) {
    test('guardado en dos etapas, todas las secuencias: ${start.name}', () async {
      final failures = <String, String>{};
      for (final a in _sends) {
        for (final b in _all) {
          for (final d in _all) {
            final problem = await _run(start, [a, b, d]);
            if (problem == null || failures.containsKey(problem)) continue;
            failures[problem] = [
              for (final s in [a, b, d]) '${s.act.name}(${s.welcome.name},${s.sources.name})',
            ].join(' → ');
          }
        }
      }
      expect(failures, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
