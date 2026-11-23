import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';

import '../../support/fake_home_repository.dart';

const _user = AuthUser(id: 'u1', email: 'ana.maria@rinde.co', name: 'Ana María');
const _session = Session(user: _user, accessToken: 'acceso', refreshToken: 'refresh');
const _offline =
    'Estás sin conexión. Tus respuestas quedaron guardadas en este dispositivo: inténtalo de nuevo cuando vuelva.';
const _serverDown = ApiException(
  code: 'INTERNAL_ERROR',
  serverMessage: 'Error interno del servidor',
  status: 500,
);
const _noStatus = WelcomeStatus(welcomeDone: false, tutorialDone: false, hasTransactions: false);

/// Doble del repositorio: anota cada llamada (sin contar status), falla a demanda y puede quedarse
/// esperando en [gate] para simular una petición en curso.
/// El servidor ya tiene lo que envían estas pruebas: el saldo y el pago de Arriendo.
const _landedStatus = WelcomeStatus(
  welcomeDone: true,
  tutorialDone: false,
  hasTransactions: false,
  balanceSet: true,
  balance: 650000,
  commitmentNames: ['Arriendo'],
);

/// El llavero guarda, pero esta vez no deja leer (teléfono bloqueado).
class _UnreadableDrafts extends MemoryDraftStore {
  @override
  Future<Object?> read(String userId) async => draftUnreadable;
}

class _FakeRepo implements OnboardingRepository {
  WelcomeStatus statusValue = _noStatus;

  /// GET /money-profile no responde.
  bool statusDown = false;

  /// Se cae justo al enviar la bienvenida: antes de enviarla sí respondió.
  bool downOnWelcome = false;
  int statusCalls = 0;
  final calls = <(String, Object?)>[];
  final _failures = <String, Object>{};
  Completer<void>? gate;

  /// Detiene solo la próxima llamada a esa operación.
  final gates = <String, Completer<void>>{};

  List<String> get ops => [for (final c in calls) c.$1];
  List<Object?> bodies(String op) => [
    for (final c in calls)
      if (c.$1 == op) c.$2,
  ];

  void failNext(String op, Object error) => _failures[op] = error;

  Future<void> _call(String op, Object? body) async {
    calls.add((op, body));
    if (op == 'welcome' && downOnWelcome) {
      statusDown = true;
      downOnWelcome = false;
    }
    if (gates.remove(op) case final g?) await g.future;
    if (gate case final g?) await g.future;
    if (_failures.remove(op) case final e?) throw e;
  }

  @override
  bool get isDemo => false;

  @override
  Future<WelcomeStatus> status() async {
    statusCalls++;
    if (statusDown) throw const ApiException(code: ApiCodes.timeout);
    return statusValue;
  }

  @override
  Future<Region> saveRegion({required String country, required String language}) async {
    await _call('region', {'country': country, 'language': language});
    return Region(country: country, currency: regionForCountry(country).currency, language: language);
  }

  @override
  Future<void> finishWelcome(Map<String, dynamic> body) => _call('welcome', body);

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) => _call('sources', sources);
}

class _MemoryRegionStore extends RegionStore {
  Region? saved;
  @override
  Future<Region?> read() async => saved;
  @override
  Future<void> write(Region region) async => saved = region;
}

Future<void> _settle() => pumpEventQueue();

Map<String, dynamic> _draftJson({
  int position = OnboardingSteps.hello,
  String country = 'CO',
  String language = 'es',
  Map<IncomeKind, IncomeSourceForm> sources = const {},
  String balance = '',
  List<CommitmentItem> items = const [],
}) => OnboardingDraft(
  position: position,
  country: country,
  language: language,
  sources: sources,
  balance: balance,
  items: items,
).toJson();

const _sueldo = IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]);
const _arriendo = CommitmentItem(key: 'k1', name: 'Arriendo', amount: '800000', dayOfMonth: '5');

void main() {
  late MemoryDraftStore store;
  late _FakeRepo repo;
  late _MemoryRegionStore regions;

  setUp(() {
    store = MemoryDraftStore();
    repo = _FakeRepo();
    regions = _MemoryRegionStore();
  });

  /// Contenedor con la sesión ya cargada (el controlador la lee al construirse).
  ///
  /// Estricto por defecto: cualquier error al desechar el contenedor hace fallar la prueba.
  Future<ProviderContainer> boot({
    Session session = _session,
    List<Override> overrides = const [],
    bool strict = true,
    List<Locale> locales = const [Locale('es', 'CO')],
  }) async {
    final all = [
      sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
      draftStoreProvider.overrideWithValue(store),
      systemLocalesProvider.overrideWithValue(locales),
      regionStoreProvider.overrideWithValue(regions),
      ...overrides,
    ];
    final ProviderContainer c;
    if (strict) {
      c = ProviderContainer.test(retry: (_, _) => null, overrides: all);
    } else {
      final unexpected = <Object>[];
      // El contenedor reporta sus errores a la zona donde se creó.
      c = runZonedGuarded(() => ProviderContainer(retry: (_, _) => null, overrides: all), (e, _) {
        if (!(e is AssertionError && '$e'.contains('inside life-cycles'))) unexpected.add(e);
      })!;
      addTearDown(() {
        c.dispose();
        expect(unexpected, isEmpty);
      });
    }
    await c.read(sessionControllerProvider.future);
    return c;
  }

  /// [en] = traducciones al inglés (para probar que las sugerencias se renombran).
  Future<ProviderContainer> bootFake({
    bool strict = false,
    Map<String, String>? en,
    List<Locale> locales = const [Locale('es', 'CO')],
  }) => boot(
    strict: strict,
    locales: locales,
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(repo),
      if (en != null) translationsProvider.overrideWithValue(Translations({'en': en})),
    ],
  );

  /// Abre la bienvenida y espera a que lea el borrador y el estado del servidor.
  Future<OnboardingController> open(ProviderContainer c, [OnboardingMode mode = OnboardingMode.full]) async {
    final provider = onboardingControllerProvider(mode);
    c.listen(provider, (_, _) {});
    final controller = c.read(provider.notifier);
    await _settle();
    expect(c.read(provider).ready, isTrue);
    return controller;
  }

  OnboardingState stateOf(ProviderContainer c, [OnboardingMode mode = OnboardingMode.full]) =>
      c.read(onboardingControllerProvider(mode));

  Map<String, dynamic>? saved(String userId) =>
      store.data[userId] == null ? null : jsonDecode(store.data[userId]!) as Map<String, dynamic>;

  group('carga', () {
    test('lee el borrador del usuario y el primer nombre para el saludo', () async {
      await store.write('u1', _draftJson(position: 8, country: 'BR', language: 'pt', balance: '5000'));
      await store.write('otro', _draftJson(position: 9, balance: '1'));
      final c = await bootFake();
      await open(c);

      final s = stateOf(c);
      expect(s.position, 8);
      expect(s.draft.country, 'BR');
      expect(s.draft.balance, '5000');
      expect(s.userName, 'Ana');
      expect(s.isDemo, isFalse);
      expect(c.read(displayLanguageProvider), 'pt');
      expect(repo.statusCalls, 1);
    });

    test('sin borrador: saludo con el país de los idiomas del sistema', () async {
      final c = await bootFake();
      await open(c);
      final s = stateOf(c);
      expect(s.position, OnboardingSteps.hello);
      expect(s.draft.country, 'CO');
      expect(s.step, 0);
      expect(s.total, 9);
    });

    test('modo preguntas arranca en Ingresos (1 de 3) aunque el borrador esté antes', () async {
      await store.write('u1', _draftJson(position: 3));
      final c = await bootFake();
      await open(c, OnboardingMode.questions);
      final s = stateOf(c, OnboardingMode.questions);
      expect(s.position, OnboardingSteps.income);
      expect(s.step, 1);
      expect(s.total, 3);
    });

    test('modo preguntas respeta un borrador ya en Pagos', () async {
      await store.write('u1', _draftJson(position: 9));
      final c = await bootFake();
      await open(c, OnboardingMode.questions);
      expect(stateOf(c, OnboardingMode.questions).position, 9);
    });

    test('alreadyDone cuando el servidor dice welcomeDone', () async {
      repo.statusValue = const WelcomeStatus(welcomeDone: true, tutorialDone: false, hasTransactions: true);
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).alreadyDone, isTrue);
    });

    test('«solo las preguntas» sin borrador: la interfaz sigue en el idioma de la cuenta', () async {
      const account = Region(country: 'BR', currency: 'BRL', language: 'pt');
      final c = await boot(
        strict: false,
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(repo),
          initialRegionProvider.overrideWithValue(account),
        ],
      );
      await open(c, OnboardingMode.questions);
      final s = stateOf(c, OnboardingMode.questions);
      expect(s.position, OnboardingSteps.income);
      expect(s.draft.language, 'pt');
      expect(c.read(displayLanguageProvider), 'pt');
    });

    test('borrador nuevo: empieza en el idioma en que ya se ve la app, no en el del país sugerido', () async {
      final c = await bootFake(locales: const [Locale('en', 'US')]);
      final n = await open(c);
      expect(stateOf(c).draft.country, 'US');
      expect(stateOf(c).draft.language, 'es');
      expect(stateOf(c).draft.languagePicked, isFalse);
      expect(c.read(displayLanguageProvider), 'es');
      // Elegir un país sí propone su idioma.
      n.pickCountry('BR');
      expect(stateOf(c).draft.language, 'pt');
      expect(c.read(displayLanguageProvider), 'pt');
    });

    test(
      '«solo las preguntas» con un borrador en otro idioma: las sugerencias pasan al de la cuenta',
      () async {
        await store.write(
          'u1',
          _draftJson(
            position: 9,
            language: 'en',
            items: const [
              CommitmentItem(key: 'k1', name: 'Rent', amount: '800000', dayOfMonth: '5'),
              CommitmentItem(key: 'k2', name: 'Rent', custom: true),
            ],
          ),
        );
        final c = await bootFake(en: const {'Arriendo': 'Rent'});
        final n = await open(c, OnboardingMode.questions);
        const m = OnboardingMode.questions;
        expect(stateOf(c, m).draft.language, 'es');
        expect(stateOf(c, m).draft.items.map((i) => i.name), ['Arriendo', 'Rent']);
        // La pastilla «Arriendo» ya está marcada: tocarla la quita en vez de crear un segundo pago.
        n.toggleSuggestion('Arriendo');
        expect(stateOf(c, m).draft.items.map((i) => i.name), ['Rent']);
      },
    );

    test('la propuesta de saldo rellena solo si está vacío', () async {
      repo.statusValue = const WelcomeStatus(
        welcomeDone: false,
        tutorialDone: false,
        hasTransactions: true,
        income: 2500000,
        expense: 1850000,
      );
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).draft.balance, '650000');
    });

    test('la propuesta no pisa un saldo ya escrito', () async {
      repo.statusValue = const WelcomeStatus(
        welcomeDone: false,
        tutorialDone: false,
        hasTransactions: true,
        income: 2500000,
        expense: 1850000,
      );
      await store.write('u1', _draftJson(balance: '100'));
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).draft.balance, '100');
    });

    test('un saldo omitido no lo rellena la propuesta: viajaría sin que nadie la viera', () async {
      repo.statusValue = const WelcomeStatus(
        welcomeDone: false,
        tutorialDone: false,
        hasTransactions: true,
        income: 2500000,
        expense: 1850000,
      );
      await store.write('u1', _draftJson(position: 9));
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).draft.balance, '');
    });

    test('sin propuesta si gastó más de lo que entró', () async {
      repo.statusValue = const WelcomeStatus(
        welcomeDone: false,
        tutorialDone: false,
        hasTransactions: true,
        income: 100,
        expense: 300,
      );
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).draft.balance, '');
    });
  });

  group('navegación (Welcome.jsx: go, back, skip)', () {
    test('Empezar, Siguiente hasta Pagos, sin pasar de 9', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      expect(stateOf(c).position, OnboardingSteps.country);
      expect(stateOf(c).step, 1);
      for (var p = 2; p <= 9; p++) {
        n.next();
        expect(stateOf(c).position, p);
        expect(stateOf(c).direction, 1);
      }
      n.next();
      expect(stateOf(c).position, 9);
    });

    test('Atrás en cada posición; desde País vuelve al saludo y en el saludo devuelve false', () async {
      final c = await bootFake();
      final n = await open(c);
      n.go(OnboardingSteps.payments);
      for (var p = 8; p >= 0; p--) {
        expect(n.back(), isTrue);
        expect(stateOf(c).position, p);
        expect(stateOf(c).direction, -1);
      }
      expect(n.back(), isFalse);
      expect(stateOf(c).position, OnboardingSteps.hello);
    });

    test('Atrás en Ingresos del modo preguntas devuelve false y no se mueve', () async {
      final c = await bootFake();
      final n = await open(c, OnboardingMode.questions);
      const m = OnboardingMode.questions;
      expect(n.back(), isFalse);
      expect(stateOf(c, m).position, OnboardingSteps.income);
      n.next();
      expect(stateOf(c, m).step, 2);
      expect(n.back(), isTrue);
      expect(stateOf(c, m).position, OnboardingSteps.income);
    });

    test('Omitir en País va al recorrido sin guardar la región', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      n.pickLanguage('en');
      await n.skip();
      expect(stateOf(c).position, OnboardingSteps.tour);
      expect(repo.ops, isEmpty);
      expect(c.read(appRegionProvider), kDefaultRegion);
      expect(regions.saved, isNull);
      // El idioma tocado se sigue viendo (como loadMessages de la web).
      expect(c.read(displayLanguageProvider), 'en');
    });

    test('Omitir en cualquier escena del recorrido salta a Ingresos', () async {
      final c = await bootFake();
      final n = await open(c);
      for (var p = 2; p <= 6; p++) {
        n.go(p);
        await n.skip();
        expect(stateOf(c).position, OnboardingSteps.income, reason: 'desde $p');
      }
    });

    test('Omitir en Ingresos borra las fuentes', () async {
      final c = await bootFake();
      final n = await open(c);
      n.go(OnboardingSteps.income);
      n.toggleSource(IncomeKind.sueldo);
      n.toggleSource(IncomeKind.mesada);
      expect(stateOf(c).draft.sources, hasLength(2));
      await n.skip();
      expect(stateOf(c).draft.sources, isEmpty);
      expect(stateOf(c).position, OnboardingSteps.balance);
    });

    test('Omitir en Saldo borra el saldo', () async {
      final c = await bootFake();
      final n = await open(c);
      n.go(OnboardingSteps.balance);
      n.setBalance('5000');
      await n.skip();
      expect(stateOf(c).draft.balance, '');
      expect(stateOf(c).position, OnboardingSteps.payments);
    });

    test('Omitir en Pagos guarda sin commitments (aunque haya pagos inválidos) y con las fuentes', () async {
      await store.write(
        'u1',
        _draftJson(
          position: 9,
          balance: '5000',
          sources: {IncomeKind.sueldo: _sueldo},
          items: const [CommitmentItem(key: 'x', name: '')],
        ),
      );
      final c = await bootFake();
      final n = await open(c);
      await n.skip();
      expect(repo.ops, ['welcome', 'sources']);
      expect(repo.bodies('welcome').single, {'incomeType': null, 'payDays': <int>[], 'balance': 5000});
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });
  });

  group('país e idioma', () {
    test(
      'al cambiar de idioma, las sugerencias marcadas se renombran (siguen marcadas, sin duplicar)',
      () async {
        await store.write('u1', _draftJson(position: OnboardingSteps.country, items: const [_arriendo]));
        final c = await boot(
          strict: false,
          overrides: [
            onboardingRepositoryProvider.overrideWithValue(repo),
            translationsProvider.overrideWithValue(
              const Translations({
                'en': {'Arriendo': 'Rent'},
              }),
            ),
          ],
        );
        final n = await open(c);
        n.pickLanguage('en');
        expect(stateOf(c).draft.items.single.name, 'Rent');
        expect(stateOf(c).draft.items.single.amount, '800000');
        n.pickLanguage('es');
        expect(stateOf(c).draft.items.single.name, 'Arriendo');
      },
    );

    test('pickCountry cambia el idioma si no se eligió a mano', () async {
      final c = await bootFake();
      final n = await open(c);
      n.pickCountry('BR');
      expect(stateOf(c).draft.country, 'BR');
      expect(stateOf(c).draft.language, 'pt');
      expect(c.read(displayLanguageProvider), 'pt');
    });

    test('pickCountry NO cambia el idioma elegido a mano', () async {
      final c = await bootFake();
      final n = await open(c);
      n.pickLanguage('en');
      expect(stateOf(c).draft.languagePicked, isTrue);
      n.pickCountry('BR');
      expect(stateOf(c).draft.country, 'BR');
      expect(stateOf(c).draft.language, 'en');
      expect(c.read(displayLanguageProvider), 'en');
    });

    test('país o idioma desconocidos se ignoran (zh está pausado)', () async {
      final c = await bootFake();
      final n = await open(c);
      n.pickCountry('XX');
      n.pickLanguage('zh');
      expect(stateOf(c).draft.country, 'CO');
      expect(stateOf(c).draft.language, 'es');
      expect(stateOf(c).draft.languagePicked, isFalse);
    });

    test('saveRegion con éxito: la región queda en la app y en el dispositivo, y va al recorrido', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      n.pickCountry('BR');
      await n.saveRegion();
      const expected = Region(country: 'BR', currency: 'BRL', language: 'pt');
      expect(repo.bodies('region').single, {'country': 'BR', 'language': 'pt'});
      expect(c.read(appRegionProvider), expected);
      expect(regions.saved, expected);
      expect(stateOf(c).position, OnboardingSteps.tour);
      expect(stateOf(c).busy, isNull);
      expect(stateOf(c).error, isNull);
    });

    test('saveRegion sin red: mensaje de sin conexión y sigue en País', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      n.pickCountry('BR');
      repo.failNext('region', const ApiException(code: ApiCodes.network));
      await n.saveRegion();
      final s = stateOf(c);
      expect(s.position, OnboardingSteps.country);
      expect(s.busy, isNull);
      expect(s.error?.text, _offline);
      expect(c.read(appRegionProvider), kDefaultRegion);
      expect(regions.saved, isNull);
    });

    test('saveRegion con error del servidor muestra su mensaje (t() lo deja igual si no es clave)', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      repo.failNext('region', _serverDown);
      await n.saveRegion();
      expect(stateOf(c).error?.text, 'Error interno del servidor');
    });

    test('mientras guarda la región, Atrás, Omitir y Siguiente no hacen nada', () async {
      final c = await bootFake();
      final n = await open(c);
      n.start();
      repo.gate = Completer();
      final pending = n.saveRegion();
      expect(stateOf(c).busy, OnboardingBusy.region);
      n.back();
      await n.skip();
      n.next();
      expect(stateOf(c).position, OnboardingSteps.country);
      repo.gate!.complete();
      await pending;
      expect(stateOf(c).position, OnboardingSteps.tour);
      expect(repo.ops, ['region']);
    });
  });

  group('terminar (dos etapas: welcome y luego sources)', () {
    Future<(ProviderContainer, OnboardingController)> atPayments({
      Map<IncomeKind, IncomeSourceForm> sources = const {IncomeKind.sueldo: _sueldo},
      List<CommitmentItem> items = const [_arriendo],
      String balance = '650000',
    }) async {
      await store.write('u1', _draftJson(position: 9, sources: sources, balance: balance, items: items));
      final c = await bootFake();
      return (c, await open(c));
    }

    test('válido: welcome y después sources; borra el borrador y queda saved', () async {
      final (c, n) = await atPayments();
      await n.finish();
      expect(repo.ops, ['welcome', 'sources']);
      expect(repo.bodies('welcome').single, {
        'incomeType': null,
        'payDays': <int>[],
        'balance': 650000,
        'commitments': [
          {
            'name': 'Arriendo',
            'amount': 800000,
            'dayOfMonth': 5,
            'kind': 'fixed',
            'frequency': 'monthly',
            'month': null,
          },
        ],
      });
      expect(repo.bodies('sources').single, [_sueldo.toApi()]);
      expect(store.data.containsKey('u1'), isFalse);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
      expect(stateOf(c).busy, isNull);
    });

    test('sin fuentes no llama sources', () async {
      final (c, n) = await atPayments(sources: const {});
      await n.finish();
      expect(repo.ops, ['welcome']);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('un pago inválido no llama al servidor y señala el pago', () async {
      final (c, n) = await atPayments(
        items: const [CommitmentItem(key: 'k9', name: 'Internet', amount: '90000', dayOfMonth: '32')],
      );
      await n.finish();
      expect(repo.ops, isEmpty);
      expect(stateOf(c).error?.text, 'Escribe un día entre 1 y 31 para {cleanName}.');
      expect(stateOf(c).error?.vars, {'cleanName': 'Internet'});
      expect(stateOf(c).errorItemKey, 'k9');
      // Editar el pago limpia el error.
      n.updateItem('k9', dayOfMonth: '3');
      expect(stateOf(c).error, isNull);
      expect(stateOf(c).errorItemKey, isNull);
    });

    test('welcome falla: no llama sources, conserva el borrador, sin outcome y con mensaje', () async {
      final (c, n) = await atPayments();
      repo.failNext('welcome', _serverDown);
      await n.finish();
      expect(repo.ops, ['welcome']);
      final s = stateOf(c);
      expect(s.outcome, isNull);
      expect(s.busy, isNull);
      expect(s.error?.text, 'Error interno del servidor');
      expect(saved('u1')?['position'], 9);
      expect(saved('u1')?['balance'], '650000');
      // Un 500 no dice si quedó guardada: se le pregunta al servidor y, si dice que no, la marca se
      // quita y los pagos siguen editables.
      expect(s.draft.sentWelcome, isNull);
      expect(saved('u1')!.containsKey('sentWelcome'), isFalse);
      // Al abrir, antes de enviar un saldo (el tipo de ingreso que hay) y tras el fallo.
      expect(repo.statusCalls, 3);
      expect(s.paymentsLocked, isFalse);
    });

    test('welcome rechazada por el servidor (4xx): seguro no quedó, la marca se quita', () async {
      final (c, n) = await atPayments();
      repo.failNext(
        'welcome',
        const ApiException(code: ApiCodes.validation, serverMessage: 'Datos inválidos', status: 422),
      );
      await n.finish();
      expect(stateOf(c).error?.text, 'Datos inválidos');
      expect(stateOf(c).draft.sentWelcome, isNull);
      expect(saved('u1')!.containsKey('sentWelcome'), isFalse);
      expect(repo.statusCalls, 2, reason: 'al abrir y antes de enviar: tras un 4xx no hace falta preguntar');
    });

    test('la etapa 1 se anota en el dispositivo ANTES de enviarla y se confirma al responder', () async {
      final (c, n) = await atPayments();
      final welcome = repo.gates['welcome'] = Completer();
      final pending = n.finish();
      await _settle();
      expect(repo.ops, ['welcome']);
      expect(saved('u1')?['sentWelcome'], isNotNull);
      expect(saved('u1')!.containsKey('welcomeConfirmed'), isFalse);
      // Desde que sale no se editan, pero no se dice que quedaron guardados.
      expect((stateOf(c).paymentsLocked, stateOf(c).paymentsSaved), (true, false));

      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      welcome.complete();
      await pending;
      expect(saved('u1')?['welcomeConfirmed'], isTrue);
      expect(stateOf(c).paymentsLocked, isTrue);
    });

    test('espera vencida pero el servidor sí la guardó: bloquea los pagos y el reintento manda solo '
        'las fuentes', () async {
      final (c, n) = await atPayments();
      repo.failNext('welcome', const ApiException(code: ApiCodes.timeout));
      repo.statusValue = _landedStatus;
      await n.finish();
      expect(stateOf(c).outcome, isNull);
      expect(stateOf(c).error?.text, ApiMessages.network);
      expect(stateOf(c).paymentsLocked, isTrue);
      expect(saved('u1')?['welcomeConfirmed'], isTrue);
      // Ya no se puede corregir un pago que el servidor no cambiaría.
      n.updateItem('k1', amount: '1');
      expect(stateOf(c).draft.items.single.amount, '800000');

      await n.finish();
      expect(repo.ops, ['welcome', 'sources']);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('la app se cerró mientras enviaba la etapa 1: al reabrir (welcomeDone) no borra el borrador y '
        'manda las fuentes', () async {
      final (first, n) = await atPayments();
      // La respuesta nunca llega: el proceso murió en «Guardando…».
      repo.gates['welcome'] = Completer();
      unawaited(n.finish());
      await _settle();
      first.dispose();

      repo.statusValue = _landedStatus;
      final again = await bootFake();
      // La entrada sabe que hay una bienvenida a medias en este dispositivo.
      expect(await again.read(pendingSourcesProvider(again.read(accountProvider)).future), isTrue);
      final reopened = await open(again);
      expect(stateOf(again).alreadyDone, isFalse);
      expect(stateOf(again).position, OnboardingSteps.payments);
      expect(stateOf(again).paymentsLocked, isTrue);
      expect(stateOf(again).draft.sources.keys, [IncomeKind.sueldo]);

      await reopened.finish();
      expect(repo.ops, ['welcome', 'sources']);
      expect(repo.bodies('sources').single, [_sueldo.toApi()]);
      expect(stateOf(again).outcome, OnboardingOutcome.saved);
      expect(store.data['u1'], isNull);
    });

    test(
      'la app se cerró enviando la etapa 1 y el servidor NO la tiene: se reenvía idéntica, sin editar',
      () async {
        final (first, n) = await atPayments();
        repo.gates['welcome'] = Completer();
        unawaited(n.finish());
        await _settle();
        first.dispose();

        final again = await bootFake();
        final reopened = await open(again);
        // Puede llegar tarde: editar y reenviar duplicaría los pagos en el servidor.
        expect((stateOf(again).paymentsLocked, stateOf(again).paymentsSaved), (true, false));
        reopened.updateItem('k1', amount: '900000');
        await reopened.finish();
        expect(repo.ops, ['welcome', 'welcome', 'sources']);
        expect(repo.bodies('welcome').last, repo.bodies('welcome').first);
        expect(stateOf(again).outcome, OnboardingOutcome.saved);
      },
    );

    test('bienvenida hecha por otro camino: no prueba que lo enviado quedó, se reenvía igual', () async {
      final (first, n) = await atPayments();
      repo.gates['welcome'] = Completer();
      unawaited(n.finish());
      await _settle();
      first.dispose();

      // «Ahora no» en otro dispositivo: welcomeDone, sin el saldo ni los pagos de este borrador.
      repo.statusValue = const WelcomeStatus(welcomeDone: true, tutorialDone: false, hasTransactions: false);
      final again = await bootFake();
      final reopened = await open(again);
      expect((stateOf(again).paymentsLocked, stateOf(again).paymentsSaved), (true, false));
      await reopened.finish();
      expect(repo.ops, ['welcome', 'welcome', 'sources']);
    });

    test('sin conexión la etapa 1 no salió: los pagos se pueden corregir', () async {
      final (c, n) = await atPayments();
      repo.failNext('welcome', const ApiException(code: ApiCodes.network));
      await n.finish();
      expect((stateOf(c).paymentsLocked, stateOf(c).draft.sentWelcome), (false, null));
    });

    test('al terminar, el Inicio vuelve a pedir el plan que tenía guardado', () async {
      final home = FakeHomeRepository();
      await store.write('u1', _draftJson(position: 9, balance: '650000', items: const [_arriendo]));
      final c = await boot(
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(repo),
          homeRepositoryProvider.overrideWithValue(home),
        ],
      );
      final n = await open(c);
      final account = c.read(accountProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(homePlanProvider(account).future);
      expect(home.count('plan'), 1);

      await n.finish();
      await c.read(homePlanProvider(account).future);
      expect(home.count('plan'), greaterThan(1));
    });

    test(
      'saldo editado con la etapa 1 en duda: la prueba del intento anterior no lo da por guardado',
      () async {
        final (c, n) = await atPayments();
        repo
          ..failNext('welcome', const ApiException(code: ApiCodes.timeout))
          ..downOnWelcome = true;
        await n.finish();

        n.setBalance('900000');
        repo
          ..failNext('welcome', const ApiException(code: 'INTERNAL_ERROR', status: 500))
          ..statusDown = false
          ..statusValue = _landedStatus;
        await n.finish();
        expect(stateOf(c).outcome, isNull);

        await n.finish();
        expect(repo.ops, ['welcome', 'welcome', 'welcome', 'sources']);
        expect((repo.bodies('welcome').last! as Map)['balance'], 900000);
        expect(stateOf(c).outcome, OnboardingOutcome.saved);
      },
    );

    test('con los pagos guardados, reenviar el saldo no revive pagos borrados en Mi plata', () async {
      final (_, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.timeout));
      await n.finish();
      n.setBalance('900000');
      await n.finish();
      final resent = repo.bodies('welcome').last! as Map;
      expect((resent['balance'], resent.containsKey('commitments')), (900000, false));
    });

    test('Omitir en Pagos no bloquea ni dice guardados unos pagos que no salieron', () async {
      final (c, n) = await atPayments(items: [_arriendo.copyWith(amount: '')]);
      repo.failNext('sources', const ApiException(code: ApiCodes.timeout));
      await n.skip();
      expect((stateOf(c).paymentsLocked, stateOf(c).paymentsSaved), (false, false));
      n.updateItem('k1', amount: '700000');
      expect(stateOf(c).draft.items.single.amount, '700000');
    });

    test('Omitir con pagos en duda no los repite (pudo cambiarlos en la web)', () async {
      final (_, n) = await atPayments();
      repo.failNext('welcome', const ApiException(code: ApiCodes.timeout));
      await n.finish();
      await n.skip();
      expect((repo.bodies('welcome').last! as Map).containsKey('commitments'), isFalse);
    });

    test('un corte después de enviar deja la marca', () async {
      final (c, n) = await atPayments();
      repo
        ..failNext('welcome', const ApiException(code: ApiCodes.timeout))
        ..downOnWelcome = true;
      await n.finish();
      expect((stateOf(c).paymentsLocked, saved('u1')?['sentWelcome'] != null), (true, true));
    });

    test('en duda sin fuentes también se retoma: faltan su saldo y sus pagos', () async {
      final (first, n) = await atPayments(sources: const {});
      repo.gates['welcome'] = Completer();
      unawaited(n.finish());
      await _settle();
      first.dispose();
      final again = await bootFake();
      expect(await again.read(pendingSourcesProvider(again.read(accountProvider)).future), isTrue);
    });

    test('quitar todas las fuentes tras enviarlas las borra en el servidor', () async {
      final (c, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.timeout));
      await n.finish();
      n.toggleSource(IncomeKind.sueldo);
      await n.finish();
      expect(repo.bodies('sources').last, isEmpty);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('si el llavero no dejó leer el borrador, no se borra ni se vuelve aquí en bucle', () async {
      store = _UnreadableDrafts();
      await store.write('u1', _draftJson(position: 9, items: const [_arriendo]));
      final kept = store.data['u1'];
      repo.statusValue = _landedStatus;
      final c = await bootFake();
      c.listen(onboardingControllerProvider(OnboardingMode.full), (_, _) {});
      await _settle();
      expect(store.data['u1'], kept);
      expect(c.read(resumeDeferredProvider), isTrue);
    });

    test('el saldo que ya guardó no se reenvía: pisaría el corregido después', () async {
      final (c, n) = await atPayments(items: const []);
      repo.failNext('sources', const ApiException(code: ApiCodes.timeout));
      await n.finish();
      final key = n.addCustom();
      n.updateItem(key!, name: 'Gimnasio', amount: '90000', dayOfMonth: '3');
      await n.finish();
      expect((repo.bodies('welcome').last! as Map)['balance'], isNull);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('en la misma sesión, reintentar no pisa un saldo corregido en la web sin mostrarlo', () async {
      final (c, n) = await atPayments();
      repo
        ..failNext('welcome', const ApiException(code: ApiCodes.timeout))
        ..downOnWelcome = true;
      await n.finish();
      repo
        ..statusDown = false
        ..statusValue = const WelcomeStatus(
          welcomeDone: true,
          tutorialDone: false,
          hasTransactions: false,
          balanceSet: true,
          balance: 700000,
          commitmentNames: ['Arriendo'],
        );
      await n.skip();
      expect(repo.ops, ['welcome']);
      expect((stateOf(c).position, stateOf(c).busy), (OnboardingSteps.balance, null));
      n.next();
      await n.finish();
      expect((repo.bodies('welcome').last! as Map)['balance'], 650000, reason: 'ya lo vio y eligió seguir');
    });

    test('al retomar con otro saldo guardado, lo muestra en Saldo antes de pisarlo', () async {
      final (first, n) = await atPayments();
      repo.gates['welcome'] = Completer();
      unawaited(n.finish());
      await _settle();
      first.dispose();
      repo.statusValue = const WelcomeStatus(
        welcomeDone: true,
        tutorialDone: false,
        hasTransactions: false,
        balanceSet: true,
        balance: 700000,
        commitmentNames: ['Arriendo'],
      );
      final again = await bootFake();
      await open(again);
      expect((stateOf(again).position, stateOf(again).paymentsSaved), (OnboardingSteps.balance, true));
    });

    test('si no se puede leer el tipo de ingreso antes de enviar el saldo, no se envía', () async {
      final (c, n) = await atPayments(sources: const {});
      repo.statusDown = true;
      await n.finish();
      expect(repo.ops, isEmpty);
      expect(stateOf(c).paymentsLocked, isFalse);
    });

    test('un 500 deshecho con la bienvenida ya hecha deja corregir el pago nuevo', () async {
      final (c, n) = await atPayments(items: const []);
      repo.failNext('sources', const ApiException(code: ApiCodes.timeout));
      await n.finish();
      repo.statusValue = const WelcomeStatus(
        welcomeDone: true,
        tutorialDone: false,
        hasTransactions: false,
        balance: 650000,
      );
      final key = n.addCustom();
      n.updateItem(key!, name: 'Gimnasio', amount: '90000', dayOfMonth: '3');
      repo.failNext('welcome', const ApiException(code: 'INTERNAL_ERROR', status: 500));
      await n.finish();
      expect(stateOf(c).paymentsLocked, isFalse);
    });

    test('welcome sin red: mensaje de sin conexión', () async {
      final (c, n) = await atPayments();
      repo.failNext('welcome', const ApiException(code: ApiCodes.network));
      await n.finish();
      expect(stateOf(c).error?.text, _offline);
    });

    test('sources falla tras welcome OK: el reintento NO repite welcome y sí sources', () async {
      final (c, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      await n.finish();
      expect(repo.ops, ['welcome', 'sources']);
      expect(stateOf(c).outcome, isNull);
      expect(stateOf(c).error?.text, _offline);
      expect(stateOf(c).draft.sentWelcome, isNotNull);
      // La etapa 1 confirmada queda anotada también en el dispositivo.
      expect(saved('u1')?['sentWelcome'], stateOf(c).draft.sentWelcome);

      await n.finish();
      expect(repo.ops, ['welcome', 'sources', 'sources']);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('tras ese fallo, si cambia el saldo el reintento SÍ reenvía welcome', () async {
      final (c, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      await n.finish();
      n.setBalance('700000');
      await n.finish();
      expect(repo.ops, ['welcome', 'sources', 'welcome', 'sources']);
      expect((repo.bodies('welcome').last! as Map)['balance'], 700000);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('la marca de welcome sobrevive a cerrar y reabrir: no se repite', () async {
      final (first, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      await n.finish();
      first.dispose();

      final again = await bootFake();
      final reopened = await open(again);
      expect(stateOf(again).draft.sentWelcome, isNotNull);
      await reopened.finish();
      expect(repo.ops, ['welcome', 'sources', 'sources']);
      expect(stateOf(again).outcome, OnboardingOutcome.saved);
    });

    test('doble toque en Ver mi plata: una sola llamada', () async {
      final (c, n) = await atPayments();
      repo.gate = Completer();
      final a = n.finish();
      final b = n.finish();
      expect(stateOf(c).busy, OnboardingBusy.finishing);
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.ops, ['welcome', 'sources']);
    });

    test(
      'etapa 1 hecha y la app se cerró: al reabrir (welcomeDone) vuelve a Pagos y manda solo sources',
      () async {
        final (first, n) = await atPayments();
        repo.failNext('sources', const ApiException(code: ApiCodes.network));
        await n.finish();
        first.dispose();

        repo.statusValue = const WelcomeStatus(
          welcomeDone: true,
          tutorialDone: false,
          hasTransactions: false,
        );
        final again = await bootFake();
        final reopened = await open(again);
        expect(stateOf(again).alreadyDone, isFalse);
        expect(stateOf(again).position, OnboardingSteps.payments);
        await reopened.finish();
        expect(repo.ops, ['welcome', 'sources', 'sources']);
        expect(stateOf(again).outcome, OnboardingOutcome.saved);
        expect(store.data['u1'], isNull);
      },
    );

    test('welcomeDone sin etapa 1 en este dispositivo: borra el borrador viejo y no repite', () async {
      await store.write('u1', _draftJson(position: 8, balance: '5000'));
      repo.statusValue = const WelcomeStatus(welcomeDone: true, tutorialDone: false, hasTransactions: true);
      final c = await bootFake();
      await open(c);
      expect(stateOf(c).alreadyDone, isTrue);
      expect(store.data['u1'], isNull);
    });

    test('con la etapa 1 confirmada, cambiar de idioma no renombra ni reenvía los pagos', () async {
      await store.write(
        'u1',
        _draftJson(position: 9, sources: {IncomeKind.sueldo: _sueldo}, items: const [_arriendo]),
      );
      final c = await bootFake(en: const {'Arriendo': 'Rent'});
      final n = await open(c);
      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      await n.finish();

      // Atrás hasta País, otro idioma (a mano o por el país) y de vuelta a Pagos.
      n.go(OnboardingSteps.country);
      n.pickLanguage('en');
      expect(stateOf(c).draft.language, 'en');
      expect(stateOf(c).draft.items.single.name, 'Arriendo');
      n.pickCountry('US');
      expect(stateOf(c).draft.items.single.name, 'Arriendo');
      n.go(OnboardingSteps.payments);

      await n.finish();
      // Con «Rent» el servidor guardaría el pago otra vez y apartaría la plata dos veces.
      expect(repo.ops, ['welcome', 'sources', 'sources']);
      expect(stateOf(c).outcome, OnboardingOutcome.saved);
    });

    test('con la etapa 1 confirmada los pagos no se editan (el servidor no los cambiaría)', () async {
      final (c, n) = await atPayments();
      repo.failNext('sources', const ApiException(code: ApiCodes.network));
      await n.finish();
      expect(stateOf(c).paymentsLocked, isTrue);
      n.updateItem('k1', amount: '1');
      n.removeItem('k1');
      n.toggleSuggestion('Internet');
      expect(n.addCustom(), isNull);
      expect(stateOf(c).draft.items.single.amount, '800000');
    });
  });

  group('Ahora no (saludo)', () {
    test('manda welcome({}) sin fuentes, borra el borrador y queda skipped', () async {
      await store.write('u1', _draftJson(sources: {IncomeKind.sueldo: _sueldo}, balance: '5'));
      final c = await bootFake();
      final n = await open(c);
      await n.later();
      expect(repo.ops, ['welcome']);
      expect(repo.bodies('welcome').single, <String, dynamic>{});
      expect(store.data.containsKey('u1'), isFalse);
      expect(stateOf(c).outcome, OnboardingOutcome.skipped);
    });

    test('doble toque: una sola llamada', () async {
      final c = await bootFake();
      final n = await open(c);
      repo.gate = Completer();
      final a = n.later();
      final b = n.later();
      expect(stateOf(c).busy, OnboardingBusy.later);
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.ops, ['welcome']);
    });

    test('si falla, el borrador queda y se ve el mensaje', () async {
      await store.write('u1', _draftJson(balance: '5'));
      final c = await bootFake();
      final n = await open(c);
      repo.failNext('welcome', const ApiException(code: ApiCodes.network));
      await n.later();
      expect(stateOf(c).outcome, isNull);
      expect(stateOf(c).error?.text, _offline);
      expect(saved('u1')?['balance'], '5');
    });
  });

  group('escritura del borrador', () {
    test('se escribe tras draftWriteDelay, una vez por ráfaga de cambios', () async {
      final c = await bootFake();
      final n = await open(c);
      final before = store.writes;
      n.setBalance('1');
      n.setBalance('12');
      n.setBalance('123');
      await Future<void>.delayed(draftWriteDelay ~/ 2);
      expect(store.writes, before);
      await Future<void>.delayed(draftWriteDelay);
      expect(store.writes, before + 1);
      expect(saved('u1')?['balance'], '123');
      expect(stateOf(c).ready, isTrue);
    });

    test('flush escribe de inmediato y cancela la escritura pendiente', () async {
      final c = await bootFake();
      final n = await open(c);
      final before = store.writes;
      n.setBalance('9');
      await n.flush();
      expect(store.writes, before + 1);
      expect(saved('u1')?['balance'], '9');
      await Future<void>.delayed(draftWriteDelay + const Duration(milliseconds: 50));
      expect(store.writes, before + 1);
    });

    test('cerrar la pantalla escribe lo pendiente sin errores', () async {
      final c = await bootFake(strict: true);
      final n = await open(c);
      n.setBalance('77');
      c.dispose();
      await _settle();
      expect(saved('u1')?['balance'], '77');
    });

    test(
      'si la pantalla se cierra mientras guarda las fuentes, la confirmación igual borra el borrador',
      () async {
        await store.write('u1', _draftJson(position: 9, balance: '5', sources: {IncomeKind.sueldo: _sueldo}));
        final c = await bootFake();
        final n = await open(c);
        final sources = repo.gates['sources'] = Completer();
        final pending = n.finish();
        await _settle();
        expect(repo.ops, ['welcome', 'sources']);
        c.dispose();
        sources.complete();
        await pending;
        expect(store.data.containsKey('u1'), isFalse);
      },
    );
  });

  test(
    'la confirmación llega con la pantalla ya cerrada: la entrada igual vuelve a preguntar el estado',
    () async {
      await store.write('u1', _draftJson(position: 9, balance: '5', sources: {IncomeKind.sueldo: _sueldo}));
      final c = await bootFake();
      final provider = onboardingControllerProvider(OnboardingMode.full);
      final screen = c.listen(provider, (_, _) {});
      final n = c.read(provider.notifier);
      await _settle();
      expect(repo.statusCalls, 1);

      final sources = repo.gates['sources'] = Completer();
      final pending = n.finish();
      await _settle();
      // Se cierra solo la pantalla; la app (el contenedor) sigue.
      screen.close();
      await _settle();
      sources.complete();
      await pending;

      expect(store.data.containsKey('u1'), isFalse);
      // Con el dato viejo en caché (bienvenida pendiente), la entrada devolvería a la bienvenida.
      await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
      expect(repo.statusCalls, 3);
    },
  );

  group('MODO DEMOSTRACIÓN', () {
    Future<ProviderContainer> bootDemo(MemoryDemoStateStore demoStore, {String scenario = 'nuevo'}) async {
      final c = await boot(
        session: Session.demo(scenario),
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
          ),
          demoStateStoreProvider.overrideWithValue(demoStore),
        ],
      );
      c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
      return c;
    }

    test('usa el repositorio de demostración y termina como demoSaved', () async {
      final demoStore = MemoryDemoStateStore();
      await store.write('demo-nuevo', _draftJson(position: 9, balance: '10', items: const [_arriendo]));
      final c = await bootDemo(demoStore);
      final n = await open(c);
      final demo = c.read(onboardingRepositoryProvider) as DemoOnboardingRepository;
      expect(stateOf(c).isDemo, isTrue);
      expect(stateOf(c).userName, 'Ana');

      await n.finish();
      expect(demo.calls.map((call) => call.operation), [
        DemoOperation.status,
        // Con saldo, antes de enviar se lee el tipo de ingreso que hay.
        DemoOperation.status,
        DemoOperation.welcome,
      ]);
      expect(stateOf(c).outcome, OnboardingOutcome.demoSaved);
      expect(await demoStore.welcomeDone('demo-nuevo'), isTrue);
      expect(store.data.containsKey('demo-nuevo'), isFalse);
    });

    test('Ahora no en demostración: demoSkipped', () async {
      final c = await bootDemo(MemoryDemoStateStore());
      final n = await open(c);
      await n.later();
      expect(stateOf(c).outcome, OnboardingOutcome.demoSkipped);
    });

    test('reiniciar vuelve a leer el estado: la propuesta de saldo del escenario reaparece', () async {
      final c = await bootDemo(MemoryDemoStateStore(), scenario: 'movimientos');
      final n = await open(c);
      expect(stateOf(c).draft.balance, '650000');
      n.setBalance('1');
      await n.restartDemo();
      await _settle();
      expect(stateOf(c).position, OnboardingSteps.hello);
      expect(stateOf(c).draft.balance, '650000');
    });

    test(
      'reiniciar mientras guarda no hace nada (la respuesta en camino reescribiría el borrador)',
      () async {
        final c = await bootDemo(MemoryDemoStateStore());
        final n = await open(c);
        n.go(OnboardingSteps.payments);
        c.read(demoControlsProvider.notifier).setLatency(const Duration(milliseconds: 20));
        final pending = n.finish();
        await n.restartDemo();
        expect(stateOf(c).busy, OnboardingBusy.finishing);
        expect(stateOf(c).position, OnboardingSteps.payments);
        await pending;
        expect(stateOf(c).outcome, OnboardingOutcome.demoSaved);
      },
    );

    test('una falla programada se muestra como la real', () async {
      final c = await bootDemo(MemoryDemoStateStore());
      final n = await open(c);
      n.go(OnboardingSteps.payments);
      c.read(demoControlsProvider.notifier).failNext(DemoOperation.welcome, DemoFailure.network);
      await n.finish();
      expect(stateOf(c).error?.text, _offline);
      expect(stateOf(c).outcome, isNull);
    });
  });
}
