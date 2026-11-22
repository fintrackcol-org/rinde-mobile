import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/fake_http.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _user = AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana');
const _session = Session(user: _user, accessToken: 'acceso', refreshToken: 'refresh');

Future<ApiException> _failure(Future<dynamic> request) async {
  try {
    await request;
  } on ApiException catch (e) {
    return e;
  }
  fail('se esperaba ApiException');
}

void main() {
  group('ApiOnboardingRepository', () {
    late SessionHolder holder;

    setUp(() async {
      holder = SessionHolder(MemorySessionStorage(_session));
      await holder.load();
    });

    tearDown(() => holder.dispose());

    ApiOnboardingRepository repo(FakeHttpAdapter adapter) =>
        ApiOnboardingRepository(ApiClient(config: _qa, session: holder, adapter: adapter));

    FakeHttpAdapter statusServer({Object? profile, Object? list}) => FakeHttpAdapter(
      (o) => switch (o.path) {
        '/money-profile' => jsonBody(200, profile),
        '/transactions' => jsonBody(200, list),
        _ => jsonBody(404, {}),
      },
    );

    test('status: GET /money-profile y GET /transactions?page=1&pageSize=1 con token', () async {
      final adapter = statusServer(
        profile: {
          'welcomeDone': false,
          'tutorialDone': true,
          'totals': {'income': 2500000.4, 'expense': 1850000},
        },
        list: {'items': [], 'total': 3},
      );
      final status = await repo(adapter).status();

      expect(
        adapter.requests.map((r) => '${r.method} ${r.uri}'),
        unorderedEquals([
          'GET https://api-qa.ejemplo.test/api/v1/money-profile',
          'GET https://api-qa.ejemplo.test/api/v1/transactions?page=1&pageSize=1',
        ]),
      );
      expect(adapter.requests.map((r) => r.headers['Authorization']), everyElement('Bearer acceso'));
      expect(status.welcomeDone, isFalse);
      expect(status.tutorialDone, isTrue);
      expect(status.hasTransactions, isTrue);
      expect(status.income, 2500000.4);
      expect(status.balanceProposal, 650000);
    });

    test('status: total 0 → sin movimientos; propuesta solo si ingresos − gastos > 0', () async {
      Future<WelcomeStatus> read(Object? totals, {Object? total = 0}) =>
          repo(statusServer(profile: {'welcomeDone': true, 'totals': totals}, list: {'total': total}))
              .status();

      final none = await read({'income': 100, 'expense': 300});
      expect(none.hasTransactions, isFalse);
      expect(none.welcomeDone, isTrue);
      expect(none.balanceProposal, isNull);
      expect((await read({'income': 100, 'expense': 100})).balanceProposal, isNull);
      // round como Math.round de la web.
      expect((await read({'income': 100.5, 'expense': 0})).balanceProposal, 101);
      // Totales ausentes o con otra forma cuentan como 0.
      expect((await read(null, total: 'x')).balanceProposal, isNull);
      expect((await read(null, total: 'x')).hasTransactions, isFalse);
    });

    test('status: una respuesta que no es objeto es un error de contrato', () async {
      final adapter = statusServer(profile: [1, 2], list: {'total': 0});
      expect((await _failure(repo(adapter).status())).code, ApiCodes.unknown);
    });

    test('saveRegion: PATCH /users/me con country, language y currency', () async {
      final adapter = FakeHttpAdapter(
        (o) => jsonBody(200, {'id': 'u1', 'country': 'BR', 'currency': 'BRL', 'language': 'pt'}),
      );
      final region = await repo(adapter).saveRegion(country: 'BR', language: 'pt');

      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/users/me');
      expect(request.data, {'country': 'BR', 'language': 'pt', 'currency': 'BRL'});
      expect(region, const Region(country: 'BR', currency: 'BRL', language: 'pt'));
    });

    test('saveRegion: ante 409 CURRENCY_LOCKED repite sin currency y conserva la moneda', () async {
      final adapter = FakeHttpAdapter((o) {
        if ((o.data as Map).containsKey('currency')) {
          return errorBody(409, 'CURRENCY_LOCKED', 'Ya tienes movimientos en COP');
        }
        return jsonBody(200, {'country': 'BR', 'currency': 'COP', 'language': 'pt'});
      });
      final region = await repo(adapter).saveRegion(country: 'BR', language: 'pt');

      expect(adapter.requests.map((r) => r.data), [
        {'country': 'BR', 'language': 'pt', 'currency': 'BRL'},
        {'country': 'BR', 'language': 'pt'},
      ]);
      expect(region, const Region(country: 'BR', currency: 'COP', language: 'pt'));
    });

    test('saveRegion: cualquier otro error se relanza sin repetir', () async {
      final adapter = FakeHttpAdapter(
        (_) => errorBody(
          422,
          ApiCodes.validation,
          'Datos inválidos',
          details: [
            {'field': 'language', 'problem': 'Debe ser uno de: es, en, pt, zh'},
          ],
        ),
      );
      final e = await _failure(repo(adapter).saveRegion(country: 'BR', language: 'pt'));
      expect(e.code, ApiCodes.validation);
      expect(adapter.requests, hasLength(1));
    });

    test('saveRegion sin red: ApiException de red', () async {
      final adapter = FakeHttpAdapter(networkFailure);
      expect((await _failure(repo(adapter).saveRegion(country: 'CO', language: 'es'))).isNetwork, isTrue);
    });

    test('finishWelcome: POST /money-profile/welcome con el cuerpo tal cual (también {})', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {'welcomeDone': true}));
      final body = {
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
      };
      await repo(adapter).finishWelcome(body);
      await repo(adapter).finishWelcome(const {});

      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /money-profile/welcome',
        'POST /money-profile/welcome',
      ]);
      expect(adapter.requests.first.data, body);
      expect(adapter.requests.last.data, <String, dynamic>{});
      expect(adapter.requests.first.headers['Authorization'], 'Bearer acceso');
    });

    test('saveSources: PUT /money-profile/sources {sources}', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {'sources': []}));
      final sources = [
        {
          'kind': 'sueldo',
          'frequency': 'mensual',
          'payDays': [15, 30],
          'amount': 2500000,
        },
      ];
      await repo(adapter).saveSources(sources);

      final request = adapter.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/money-profile/sources');
      expect(request.data, {'sources': sources});
      expect(request.headers['Authorization'], 'Bearer acceso');
    });

    test('con una sesión demo nada sale a la red (DEMO_NO_BACKEND)', () async {
      await holder.save(Session.demo('nuevo'));
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {}));
      final api = repo(adapter);

      for (final call in <Future<dynamic> Function()>[
        api.status,
        () => api.saveRegion(country: 'BR', language: 'pt'),
        () => api.finishWelcome(const {}),
        () => api.saveSources(const []),
      ]) {
        expect((await _failure(call())).code, ApiCodes.demoNoBackend);
      }
      expect(adapter.requests, isEmpty);
    });
  });

  group('onboardingRepositoryProvider', () {
    Future<ProviderContainer> boot(Session session) async {
      final c = ProviderContainer.test(
        overrides: [
          sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
          ),
          demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        ],
      );
      await c.read(sessionControllerProvider.future);
      return c;
    }

    test('sesión normal → API; sesión demo → demostración', () async {
      final api = await boot(_session);
      expect(api.read(onboardingRepositoryProvider), isA<ApiOnboardingRepository>());
      expect(api.read(onboardingRepositoryProvider).isDemo, isFalse);

      final demo = await boot(Session.demo('movimientos'));
      final repo = demo.read(onboardingRepositoryProvider);
      expect(repo, isA<DemoOnboardingRepository>());
      expect(repo.isDemo, isTrue);
      expect((repo as DemoOnboardingRepository).scenario, DemoScenario.movimientos);
    });
  });

  group('DemoOnboardingRepository (MODO DEMOSTRACIÓN)', () {
    late ProviderContainer c;
    late DemoControlsNotifier controls;
    late MemoryDemoStateStore store;

    setUp(() {
      c = ProviderContainer.test();
      controls = c.read(demoControlsProvider.notifier)..setLatency(Duration.zero);
      store = MemoryDemoStateStore();
    });

    DemoOnboardingRepository demo(String scenario) =>
        DemoOnboardingRepository(userId: 'demo-$scenario', store: store, controls: controls);

    test('escenarios: nuevo sin movimientos; movimientos con propuesta sintética', () async {
      expect(DemoScenario.fromUserId('demo-nuevo'), DemoScenario.nuevo);
      expect(DemoScenario.fromUserId('demo-movimientos'), DemoScenario.movimientos);
      expect(DemoScenario.fromUserId('cualquiera'), DemoScenario.nuevo);

      final nuevo = await demo('nuevo').status();
      expect(nuevo.hasTransactions, isFalse);
      expect(nuevo.welcomeDone, isFalse);
      expect(nuevo.balanceProposal, isNull);

      final movimientos = await demo('movimientos').status();
      expect(movimientos.hasTransactions, isTrue);
      expect(movimientos.balanceProposal, 650000);
    });

    test(
      'saveRegion: nuevo toma la moneda del país; movimientos queda en COP (como CURRENCY_LOCKED)',
      () async {
        expect(
          await demo('nuevo').saveRegion(country: 'BR', language: 'en'),
          const Region(country: 'BR', currency: 'BRL', language: 'en'),
        );
        expect(
          await demo('movimientos').saveRegion(country: 'BR', language: 'pt'),
          const Region(country: 'BR', currency: 'COP', language: 'pt'),
        );
      },
    );

    test('anota cada llamada con su cuerpo y marca la bienvenida hecha', () async {
      final repo = demo('nuevo');
      await repo.finishWelcome(const {'balance': 1});
      await repo.saveSources(const [
        {'kind': 'sueldo'},
      ]);
      expect(repo.calls.map((call) => call.operation), [DemoOperation.welcome, DemoOperation.sources]);
      expect(repo.calls.first.body, {'balance': 1});
      expect((await repo.status()).welcomeDone, isTrue);
    });

    test('latencia configurable', () async {
      controls.setLatency(const Duration(milliseconds: 60));
      final watch = Stopwatch()..start();
      await demo('nuevo').saveSources(const []);
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 50)));
    });

    test('failNext falla una sola vez; red y servidor', () async {
      final repo = demo('nuevo');
      controls.failNext(DemoOperation.welcome, DemoFailure.network);
      expect((await _failure(repo.finishWelcome(const {}))).isNetwork, isTrue);
      // La falla no marcó la bienvenida.
      expect(await store.welcomeDone('demo-nuevo'), isFalse);
      await repo.finishWelcome(const {});
      expect(await store.welcomeDone('demo-nuevo'), isTrue);

      controls.failNext(DemoOperation.sources, DemoFailure.server);
      final e = await _failure(repo.saveSources(const []));
      expect(e.code, 'INTERNAL_ERROR');
      expect(e.status, 500);
      await repo.saveSources(const []);

      // Programar y luego quitar.
      controls.failNext(DemoOperation.status, DemoFailure.network);
      controls.failNext(DemoOperation.status, null);
      await repo.status();
      expect(c.read(demoControlsProvider).failures, isEmpty);
    });

    test('reset borra las llamadas y vuelve a "sin bienvenida"', () async {
      final repo = demo('nuevo');
      await repo.finishWelcome(const {});
      await repo.reset();
      expect(repo.calls, isEmpty);
      expect((await repo.status()).welcomeDone, isFalse);
    });
  });
}
