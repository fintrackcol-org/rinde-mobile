// Por confirmar (etapa 8): el contrato (lo que se manda al confirmar, con o sin tarjeta), el writer (un envío
// a la vez por pago, en duda se relee y nunca se reintenta solo, 409 = ya resuelto, bienvenida pendiente
// bloquea, tras confirmar se recarga lo que depende de la plata) y la demo (sin servidor).
import 'dart:convert';

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
import 'package:rinde_mobile/features/home/data/demo_home_repository.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/to_confirm/application/to_confirm_writer.dart';
import 'package:rinde_mobile/features/to_confirm/data/to_confirm_repository.dart';

import '../../support/card_fixtures.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() async => const SessionState(session: _ana);
}

const _taxi = IncomingPayment(id: 'p1', merchant: 'Taxi', amount: 12400, date: '2026-11-21', card: 'Mi Visa');
const _timeout = ApiException(code: ApiCodes.timeout, serverMessage: 'Se venció la espera');
const _resolved = ApiException(
  code: 'ALREADY_RESOLVED',
  status: 409,
  serverMessage: 'Este pago ya se confirmó o se descartó',
);

/// Pagos por confirmar a la medida; guarda cada envío.
class _FakeToConfirm implements ToConfirmRepository {
  final sent = <String>[];
  Future<void> Function() onSend = () async {};
  Future<List<IncomingPayment>> Function() onList = () async => const [_taxi];
  int lists = 0;

  @override
  bool get isDemo => false;

  @override
  Future<List<IncomingPayment>> list() {
    lists++;
    return onList();
  }

  @override
  Future<void> confirm(String id, {required String description, String? category, String? card}) {
    sent.add('confirm $id $description $category${card == null ? '' : ' $card'}');
    return onSend();
  }

  @override
  Future<void> discard(String id) {
    sent.add('discard $id');
    return onSend();
  }
}

void main() {
  group('contrato', () {
    late SessionHolder holder;

    setUp(() async {
      holder = SessionHolder(MemorySessionStorage(_session));
      await holder.load();
    });
    tearDown(() => holder.dispose());

    ApiToConfirmRepository repo(FakeHttpAdapter http) => ApiToConfirmRepository(
      ApiClient(
        config: const AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa'),
        session: holder,
        adapter: http,
      ),
    );

    test('lista los pendientes con el comercio, el monto del servidor y la tarjeta de Wallet', () async {
      final http = FakeHttpAdapter(
        (_) => jsonBody(200, {
          'items': [
            {
              'id': 'p1',
              'merchant': 'Taxi',
              'amount': 12400.5,
              'date': '2026-11-21',
              'card': 'Mi Visa',
              'status': 'pending',
              'possibleDuplicate': true,
            },
            {'id': 'roto'},
          ],
        }),
      );
      final [p] = await repo(http).list();
      expect(
        (p.id, p.merchant, p.amount, p.card, p.possibleDuplicate),
        ('p1', 'Taxi', 12400.5, 'Mi Visa', true),
      );
      expect(http.requests.single.path, '/pending-payments');
    });

    test('confirmar con tarjeta manda `card` (no resta de Mi plata: sin doble conteo al pagar la tarjeta); '
        'sin tarjeta, solo descripción y categoría (efectivo o débito)', () async {
      final http = FakeHttpAdapter((_) => jsonBody(200, {'payment': {}, 'transaction': {}}));
      await repo(http).confirm('p1', description: 'Taxi al trabajo');
      await repo(http).confirm('p1', description: 'Taxi', category: 'transporte');
      await repo(http).confirm('p1', description: 'Taxi', card: 'k1');
      await repo(http).discard('p1');
      expect(
        [for (final r in http.requests) '${r.method} ${r.path}'],
        [
          'POST /pending-payments/p1/confirm',
          'POST /pending-payments/p1/confirm',
          'POST /pending-payments/p1/confirm',
          'POST /pending-payments/p1/discard',
        ],
      );
      expect(jsonDecode(jsonEncode(http.requests[0].data)), {'description': 'Taxi al trabajo'});
      expect(jsonDecode(jsonEncode(http.requests[1].data)), {
        'description': 'Taxi',
        'category': 'transporte',
      });
      expect(jsonDecode(jsonEncode(http.requests[2].data)), {'description': 'Taxi', 'card': 'k1'});
    });
  });

  group('walletCardMatch', () {
    final visa = cardOfJson(cardJson(id: 'visa', last4: '4242'));
    final master = cardOfJson(cardJson(id: 'master', network: 'mastercard', last4: '1111'));

    test('la tarjeta de Wallet con los mismos últimos 4 queda elegida', () {
      expect(walletCardMatch('Visa Bancolombia 4242', [visa, master]), 'visa');
      expect(walletCardMatch('•••• 1111', [visa, master]), 'master');
    });

    test('si no es inequívoco, «Efectivo o débito» (null)', () {
      expect(walletCardMatch(null, [visa]), isNull);
      expect(walletCardMatch('Mi Visa', [visa]), isNull, reason: 'sin cifras no se adivina');
      expect(walletCardMatch('Visa 9999', [visa, master]), isNull, reason: 'ninguna termina así');
      expect(walletCardMatch('4242 o 1111', [visa, master]), isNull, reason: 'dos grupos de cifras');
      expect(walletCardMatch('Visa 424242', [visa]), isNull, reason: 'no son 4 cifras sueltas');
      final twin = cardOfJson(cardJson(id: 'otra', last4: '4242'));
      expect(walletCardMatch('Visa 4242', [visa, twin]), isNull, reason: 'dos tarjetas con esos 4');
    });
  });

  group('ToConfirmWriter', () {
    late FakeHomeRepository home;
    late _FakeToConfirm repo;
    late MemoryDraftStore drafts;

    Future<ProviderContainer> open() async {
      final c = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          sessionControllerProvider.overrideWith(_Sessions.new),
          homeRepositoryProvider.overrideWithValue(home),
          moneyRepositoryProvider.overrideWithValue(FakeMoneyRepository()),
          toConfirmRepositoryProvider.overrideWithValue(repo),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      await c.read(sessionControllerProvider.future);
      return c;
    }

    setUp(() {
      home = FakeHomeRepository();
      repo = _FakeToConfirm();
      drafts = MemoryDraftStore();
    });

    test(
      'dos toques en «Anotar el gasto», un solo envío; después se recargan la lista y el Inicio',
      () async {
        final c = await open();
        c.listen(homeToConfirmProvider(_ana), (_, _) {});
        c.listen(toConfirmListProvider(_ana), (_, _) {});
        await c.read(homeToConfirmProvider(_ana).future);
        await c.read(toConfirmListProvider(_ana).future);
        final (homeBefore, listBefore) = (home.count('toConfirm'), repo.lists);
        final writer = c.read(toConfirmWriterProvider);
        await Future.wait([
          writer.confirm(_taxi, description: 'Taxi'),
          writer.confirm(_taxi, description: 'Taxi'),
        ]);
        expect(repo.sent, ['confirm p1 Taxi null']);
        await writer.confirm(_taxi, description: 'Taxi', category: 'transporte', card: 'k1');
        expect(repo.sent.last, 'confirm p1 Taxi transporte k1', reason: 'la tarjeta llega al repositorio');
        await c.read(homeToConfirmProvider(_ana).future);
        await c.read(toConfirmListProvider(_ana).future);
        expect(home.count('toConfirm'), greaterThan(homeBefore));
        expect(repo.lists, greaterThan(listBefore));
      },
    );

    test('confirmar y descartar el mismo pago a la vez: el segundo llega y el servidor dice 409', () async {
      final c = await open();
      var first = true;
      repo.onSend = () async {
        if (first) {
          first = false;
          return;
        }
        throw _resolved;
      };
      final writer = c.read(toConfirmWriterProvider);
      await writer.confirm(_taxi, description: 'Taxi');
      await expectLater(
        writer.discard(_taxi),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_RESOLVED')),
      );
      expect(repo.sent, ['confirm p1 Taxi null', 'discard p1']);
    });

    test('en duda: si al releer ya no está pendiente cuenta como hecho, sin volver a enviar', () async {
      final c = await open();
      repo.onSend = () async => throw _timeout;
      repo.onList = () async => const [];
      await c.read(toConfirmWriterProvider).confirm(_taxi, description: 'Taxi');
      expect(repo.sent, hasLength(1), reason: 'nunca se reintenta solo');
    });

    test('en duda: si sigue pendiente se informa el fallo; si no se pudo releer, UNCONFIRMED', () async {
      final c = await open();
      repo.onSend = () async => throw _timeout;
      await expectLater(
        c.read(toConfirmWriterProvider).confirm(_taxi, description: 'Taxi'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.timeout)),
      );
      repo.onList = () async => throw const ApiException(code: ApiCodes.network);
      await expectLater(
        c.read(toConfirmWriterProvider).confirm(_taxi, description: 'Taxi'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(repo.sent, hasLength(2), reason: 'cada toque, un envío; ninguno solo');
    });

    test('con la bienvenida a medias no se confirma ni se descarta nada', () async {
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      final c = await open();
      for (final write in [
        () => c.read(toConfirmWriterProvider).confirm(_taxi, description: 'Taxi'),
        () => c.read(toConfirmWriterProvider).discard(_taxi),
      ]) {
        await expectLater(
          write(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending)),
        );
      }
      expect(repo.sent, isEmpty);
    });
  });

  group('demo', () {
    late ProviderContainer c;

    setUp(() {
      c = ProviderContainer.test(
        overrides: [
          demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
          demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        ],
      );
      c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
    });

    DemoToConfirmRepository demo(String user) => DemoToConfirmRepository(
      home: c.read(demoHomeRepositoryProvider(user)),
      controls: c.read(demoControlsProvider.notifier),
    );

    test(
      '«Plan listo» trae los 2 pagos que cuenta el Inicio y no escribe; los recorridos, ninguno',
      () async {
        final list = await demo('demo-planListo').list();
        expect(list.map((p) => p.merchant), ['Panadería del barrio', 'Taxi']);
        expect(await c.read(demoHomeRepositoryProvider('demo-planListo')).toConfirm(), list.length);
        for (final write in [
          () => demo('demo-planListo').confirm('x', description: 'x'),
          () => demo('demo-planListo').discard('x'),
        ]) {
          await expectLater(
            write(),
            throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
          );
        }
        expect(await demo('demo-movimientos').list(), isEmpty);
      },
    );
  });
}

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);
