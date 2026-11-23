// Escrituras de Mi plata con el ApiClient real contra un adaptador falso: un solo envío a la vez,
// «no salió» frente a «en duda», verificación leyendo, refresco del Inicio y aislamiento por cuenta.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/application/money_writer.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co'),
  accessToken: 'acceso',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co'),
  accessToken: 'acceso-b',
  refreshToken: 'r',
);

/// Sesión ya leída, que se puede cambiar por la de otra cuenta sin pasar por el login.
class _Sessions extends SessionController {
  @override
  Future<SessionState> build() async => const SessionState(session: _ana);

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

final _sources = [
  const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]).toApi(),
];

/// Lo que GET /income devuelve si el PUT de [_sources] sí se aplicó (con otros id).
Map<String, dynamic> _savedIncome([num amount = 2500000]) => {
  'sources': [
    {
      'id': 'nuevo',
      'name': 'Sueldo',
      'kind': 'sueldo',
      'frequency': 'mensual',
      'payDays': [15, 30],
      'amount': amount,
      'low': null,
      'high': null,
      'lastMonths': <num>[],
      'workDays': null,
    },
  ],
  'normal': amount,
  'lean': amount,
  'basis': 'declared',
};

Never _timeout(RequestOptions options) =>
    throw DioException.receiveTimeout(timeout: const Duration(seconds: 45), requestOptions: options);

void main() {
  late SessionHolder holder;
  late FakeHomeRepository home;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_ana));
    await holder.load();
    home = FakeHomeRepository();
  });

  tearDown(() => holder.dispose());

  Future<ProviderContainer> open(MoneyRepository repo, {DraftStore? drafts}) async {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        moneyRepositoryProvider.overrideWithValue(repo),
        homeRepositoryProvider.overrideWithValue(home),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
      ],
    );
    await c.read(sessionControllerProvider.future);
    return c;
  }

  Future<(ProviderContainer, FakeHttpAdapter)> openApi(FakeHandler handler) async {
    final adapter = FakeHttpAdapter(handler);
    final c = await open(ApiMoneyRepository(ApiClient(config: _qa, session: holder, adapter: adapter)));
    return (c, adapter);
  }

  group('PUT /money-profile/sources', () {
    test('dos toques mientras va el primero: una sola petición y los dos reciben el resultado', () async {
      final answer = Completer<void>();
      final (c, adapter) = await openApi((o) async {
        await answer.future;
        return jsonBody(200, _savedIncome());
      });
      final writer = c.read(moneyWriterProvider);
      final first = writer.saveSources(_sources);
      final second = writer.saveSources(_sources);
      await pumpEventQueue();
      expect(adapter.to('/money-profile/sources'), hasLength(1));
      answer.complete();
      await Future.wait([first, second]);
      expect(adapter.to('/money-profile/sources'), hasLength(1));

      // Terminado el primero, el siguiente sí sale.
      await writer.saveSources(_sources);
      expect(adapter.to('/money-profile/sources'), hasLength(2));
    });

    test('sin conexión no salió: el error de red, sin volver a leer ni reintentar', () async {
      final (c, adapter) = await openApi(networkFailure);
      await expectLater(
        c.read(moneyWriterProvider).saveSources(_sources),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
      );
      expect(adapter.requests.map((r) => r.path), ['/money-profile/sources']);
    });

    test('en duda (se venció la espera): vuelve a leer y, si ya quedó, no hay segundo PUT', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'PUT' ? _timeout(o) : jsonBody(200, _savedIncome()),
      );
      await c.read(moneyWriterProvider).saveSources(_sources);
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'PUT /money-profile/sources',
        'GET /money-profile/income',
      ]);
    });

    test('en duda (500) y lo leído no es lo enviado: el error del envío, sin segundo PUT', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'PUT'
            ? errorBody(500, 'INTERNAL_ERROR', 'Error interno del servidor')
            : jsonBody(200, _savedIncome(1000000)),
      );
      await expectLater(
        c.read(moneyWriterProvider).saveSources(_sources),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(adapter.to('/money-profile/sources'), hasLength(1));
      expect(adapter.to('/money-profile/income'), hasLength(1));
    });

    test('en duda y tampoco se puede leer: sigue el error del envío', () async {
      final (c, adapter) = await openApi((o) => o.method == 'PUT' ? _timeout(o) : networkFailure(o));
      await expectLater(
        c.read(moneyWriterProvider).saveSources(_sources),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.timeout)),
      );
      expect(adapter.to('/money-profile/sources'), hasLength(1));
    });

    test('un 422 no está en duda: llega tal cual, con sus campos', () async {
      final (c, adapter) = await openApi(
        (_) => errorBody(
          422,
          'VALIDATION_ERROR',
          'Datos inválidos',
          details: [
            {'field': 'sources[0].amount', 'problem': 'Debe ser un número desde 0'},
          ],
        ),
      );
      await expectLater(
        c.read(moneyWriterProvider).saveSources(_sources),
        throwsA(isA<ApiException>().having((e) => e.fields.keys, 'campos', ['sources[0].amount'])),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('después de guardar se vuelven a pedir Mi plata y el plan del Inicio', () async {
      final repo = FakeMoneyRepository();
      final c = await open(repo);
      final account = c.read(accountProvider);
      c.listen(incomeOverviewProvider(account), (_, _) {});
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(incomeOverviewProvider(account).future);
      await c.read(homePlanProvider(account).future);
      expect((repo.count('income'), home.count('plan')), (1, 1));

      await c.read(moneyWriterProvider).saveSources(_sources);
      await pumpEventQueue();
      expect((repo.count('income'), home.count('plan')), (2, 2));
    });

    test('en duda sin confirmar: el error, pero lo que se ve se vuelve a pedir (pudo aplicarse)', () async {
      final repo = FakeMoneyRepository()
        ..onSaveSources = (_) async => throw const ApiException(code: ApiCodes.timeout);
      final c = await open(repo);
      final account = c.read(accountProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(homePlanProvider(account).future);
      await expectLater(c.read(moneyWriterProvider).saveSources(_sources), throwsA(isA<ApiException>()));
      await pumpEventQueue();
      expect(home.count('plan'), 2);
    });

    test('si falla, no se refresca nada', () async {
      final repo = FakeMoneyRepository()
        ..onSaveSources = (_) async => throw const ApiException(code: ApiCodes.network);
      final c = await open(repo);
      final account = c.read(accountProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(homePlanProvider(account).future);
      await expectLater(c.read(moneyWriterProvider).saveSources(_sources), throwsA(isA<ApiException>()));
      await pumpEventQueue();
      expect(home.count('plan'), 1);
    });
  });

  group('POST /money-profile/commitments (PILA)', () {
    const pila = {'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 10};

    test('409 COMMITMENT_EXISTS no está en duda: llega con el mensaje del servidor', () async {
      final (c, adapter) = await openApi(
        (_) => errorBody(409, 'COMMITMENT_EXISTS', 'Ya tienes un compromiso con ese nombre'),
      );
      await expectLater(
        c.read(moneyWriterProvider).createCommitment(pila),
        throwsA(
          isA<ApiException>().having(
            (e) => e.serverMessage,
            'mensaje',
            'Ya tienes un compromiso con ese nombre',
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('en duda: busca el nombre en el perfil (sin distinguir mayúsculas) y no repite el POST', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'POST'
            ? errorBody(502, 'BAD_GATEWAY', 'x')
            : jsonBody(200, {
                'welcomeDone': true,
                'commitments': [
                  {'id': 'c9', 'name': 'SEGURIDAD SOCIAL (PILA)', 'amount': 499008, 'dayOfMonth': 10},
                ],
              }),
      );
      await c.read(moneyWriterProvider).createCommitment(pila);
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /money-profile/commitments',
        'GET /money-profile',
      ]);
    });

    test('en duda y ya había uno con ese nombre pero otro día: no se da por guardado', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'POST'
            ? errorBody(502, 'BAD_GATEWAY', 'x')
            : jsonBody(200, {
                'welcomeDone': true,
                'commitments': [
                  {'id': 'c1', 'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 5},
                ],
              }),
      );
      await expectLater(
        c.read(moneyWriterProvider).createCommitment(pila),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
      );
      expect(adapter.to('/money-profile/commitments'), hasLength(1));
    });

    test('dos pagos con distinto nombre a la vez: cada uno sale', () async {
      final answer = Completer<void>();
      final repo = FakeMoneyRepository()..onCreateCommitment = (_) => answer.future;
      final c = await open(repo);
      final writer = c.read(moneyWriterProvider);
      final both = Future.wait([
        writer.createCommitment(pila),
        writer.createCommitment({'name': 'Arriendo', 'amount': 900000, 'dayOfMonth': 1}),
      ]);
      await pumpEventQueue();
      expect(repo.sentCommitments.map((b) => b['name']), ['Seguridad social (PILA)', 'Arriendo']);
      answer.complete();
      await both;
    });

    test('en duda y no está en el perfil: el error del envío', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'POST'
            ? _timeout(o)
            : jsonBody(200, {'welcomeDone': true, 'commitments': const <Object>[]}),
      );
      await expectLater(c.read(moneyWriterProvider).createCommitment(pila), throwsA(isA<ApiException>()));
      expect(adapter.to('/money-profile/commitments'), hasLength(1));
    });
  });

  test('con una bienvenida a medias en este dispositivo no se envía nada: al retomarla pisaría', () async {
    final drafts = MemoryDraftStore();
    await drafts.write(
      'a',
      const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
    );
    final repo = FakeMoneyRepository();
    final c = await open(repo, drafts: drafts);
    final writer = c.read(moneyWriterProvider);
    final pending = isA<ApiException>()
        .having((e) => e.code, 'code', ApiCodes.welcomePending)
        .having((e) => e.serverMessage, 'mensaje', 'Primero terminemos de guardar tu bienvenida.');
    await expectLater(writer.saveSources(_sources), throwsA(pending));
    await expectLater(
      writer.createCommitment({'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 10}),
      throwsA(pending),
    );
    expect((repo.count('saveSources'), repo.count('createCommitment')), (0, 0));
  });

  test('aislamiento: la cuenta que entra no ve las fuentes de la que salió', () async {
    final repo = FakeMoneyRepository();
    final c = await open(repo);
    c.listen(incomeOverviewProvider(c.read(accountProvider)), (_, _) {});
    final ana = await c.read(incomeOverviewProvider(c.read(accountProvider)).future);
    expect(ana.sources, isNotEmpty);

    // Beto entra sin conexión: su carga no termina y no hereda nada de Ana.
    repo.onIncome = () => Completer<IncomeOverview>().future;
    (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
    final beto = c.read(accountProvider);
    expect(beto, _beto);
    c.listen(incomeOverviewProvider(beto), (_, _) {});
    await pumpEventQueue();
    final shown = c.read(incomeOverviewProvider(beto));
    expect((shown.isLoading, shown.value), (true, null));
  });

  test('aislamiento: un «Ya lo pagué» de A que no termina no deja ocupados los botones de B', () async {
    final c = await open(FakeMoneyRepository());
    c.listen(payingPaymentProvider, (_, _) {});
    final ana = c.read(payingPaymentProvider.notifier)..set('c1-2026-11-28');
    (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
    await pumpEventQueue();
    expect(c.read(payingPaymentProvider), isNull);

    // B guarda uno y el de A termina después: no le suelta el suyo.
    final beto = c.read(payingPaymentProvider.notifier)..set('c2-2026-11-28');
    ana.release('c1-2026-11-28');
    beto.release('c1-2026-11-28');
    expect(c.read(payingPaymentProvider), 'c2-2026-11-28');
    beto.release('c2-2026-11-28');
    expect(c.read(payingPaymentProvider), isNull);
  });
}
