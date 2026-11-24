// Tarjetas con el ApiClient real contra un adaptador falso que responde con las formas EXACTAS de
// QA (23-nov-2026): los 9 endpoints, los cuerpos, 404 = hecho al borrar, errores por campo, doble
// envío (un toque a la vez, en duda se relee y nunca se reintenta solo), refrescos de Mi plata y
// aislamiento por cuenta.
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
import 'package:rinde_mobile/features/cards/application/cards_providers.dart';
import 'package:rinde_mobile/features/cards/application/cards_writer.dart';
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/data/cards_repository.dart';
import 'package:rinde_mobile/features/cards/domain/card_rules.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart'
    show movementDetailProvider;
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

import '../../support/card_fixtures.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';
import '../../support/fake_movements_repository.dart';

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

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() async => const SessionState(session: _ana);

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

const _id = '41ced642-66c1-4615-85a6-8d38152f9d44';
const _card = '/cards/$_id';

/// Respuestas reales de QA.
final _payment = {
  'kind': 'payment',
  'id': '0cf8b4d3-3a64-4b94-9395-dfe89ca90147',
  'date': '2026-11-23',
  'amount': 100000,
};
final _charge = {
  'kind': 'purchase',
  'id': '2a6e04e3-d120-4528-b149-03a1ba5e68b5',
  'date': '2026-11-23',
  'amount': 200000,
  'description': 'Cargos del banco · Visa Clásica ••4242',
  'installments': 1,
};

/// La lectura del borrador (bienvenida pendiente) espera hasta que se abra [gate].
class _SlowDrafts extends MemoryDraftStore {
  final gate = Completer<void>();

  @override
  Future<Object?> read(String userId) async {
    await gate.future;
    return super.read(userId);
  }
}

Never _timeout(RequestOptions options) =>
    throw DioException.receiveTimeout(timeout: const Duration(seconds: 45), requestOptions: options);

void main() {
  late SessionHolder holder;
  late FakeHomeRepository home;
  late FakeMoneyRepository money;
  late FakeMovementsRepository movementsRepo;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_ana));
    await holder.load();
    home = FakeHomeRepository();
    money = FakeMoneyRepository();
    movementsRepo = FakeMovementsRepository();
  });

  tearDown(() => holder.dispose());

  Future<(ProviderContainer, FakeHttpAdapter)> open(FakeHandler handler, {DraftStore? drafts}) async {
    final adapter = FakeHttpAdapter(handler);
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        cardsRepositoryProvider.overrideWithValue(
          ApiCardsRepository(ApiClient(config: _qa, session: holder, adapter: adapter)),
        ),
        moneyRepositoryProvider.overrideWithValue(money),
        homeRepositoryProvider.overrideWithValue(home),
        movementsRepositoryProvider.overrideWithValue(movementsRepo),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
      ],
    );
    await c.read(sessionControllerProvider.future);
    return (c, adapter);
  }

  List<String> sent(FakeHttpAdapter a) => [for (final r in a.requests) '${r.method} ${r.path}'];

  group('contrato (formas de QA)', () {
    test('GET /cards, /cards/:id y /movements con el orden del servidor', () async {
      final (c, adapter) = await open(
        (o) => switch (o.path) {
          '/cards' => jsonBody(200, [cardJson()]),
          _card => jsonBody(200, cardJson()),
          '$_card/movements' => jsonBody(200, [_charge, _payment]),
          _ => jsonBody(404, {}),
        },
      );
      final account = c.read(accountProvider);
      final list = await c.read(cardsProvider(account).future);
      expect(list.single.last4, '4242');
      final detail = await c.read(cardDetailProvider((account, _id)).future);
      expect(detail.card.used, 500000);
      expect(
        [for (final m in detail.movements) m.kind],
        [CardMovementKind.purchase, CardMovementKind.payment],
      );
      expect(sent(adapter), containsAll(['GET /cards', 'GET $_card', 'GET $_card/movements']));
      expect(adapter.requests.first.headers['Authorization'], 'Bearer acceso');
    });

    test('una tarjeta ilegible falla la lista entera (no se esconde)', () async {
      final (c, _) = await open(
        (o) => jsonBody(200, [
          cardJson(),
          {...cardJson(id: 'x')}..remove('used'),
        ]),
      );
      await expectLater(
        c.read(cardsProvider(c.read(accountProvider)).future),
        throwsA(isA<ContractException>()),
      );
    });

    test('POST /cards: montos y días como números; 201 refresca la lista', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'POST' ? jsonBody(201, cardJson()) : jsonBody(200, const <Object>[]),
      );
      final body = cardBody(
        null,
        network: 'visa',
        tier: 'clasica',
        last4: '4242',
        limit: '2000000',
        available: '1500000',
        paymentDay: '15',
        name: '',
        cutoffDay: '30',
        expiry: '',
      )!;
      await c.read(cardsWriterProvider).createCard(body);
      final post = adapter.to('/cards').where((r) => r.method == 'POST').single;
      expect(post.data, {
        'network': 'visa',
        'tier': 'clasica',
        'last4': '4242',
        'limit': 2000000,
        'available': 1500000,
        'paymentDay': 15,
        'cutoffDay': 30,
      });
    });

    test('PUT /cards/:id solo con lo que cambió y SIN available', () async {
      final (c, adapter) = await open((o) => jsonBody(200, cardJson(limit: 2500000)));
      final body = cardBody(
        cardOfJson(),
        network: 'visa',
        tier: 'clasica',
        last4: '4242',
        limit: '2500000',
        available: '999',
        paymentDay: '15',
        name: 'Visa Clásica ••4242',
        cutoffDay: '30',
        expiry: '',
      )!;
      await c.read(cardsWriterProvider).updateCard(_id, body);
      final put = adapter.requests.single;
      expect((put.method, put.path), ('PUT', _card));
      expect(put.data, {'limit': 2500000});
      expect((put.data as Map).containsKey('available'), isFalse);
    });

    test('POST /payments con {amount, date AAAA-MM-DD}', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'POST'
            ? jsonBody(201, {'payment': _payment, 'card': cardJson(used: 400000, paidThisCycle: true)})
            : jsonBody(200, const <Object>[]),
      );
      await c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23');
      final post = adapter.requests.where((r) => r.method == 'POST').single;
      expect(post.path, '$_card/payments');
      expect(post.data, {'amount': 100000, 'date': '2026-11-23'});
    });

    test('sync-with-bank: los opcionales vacíos se omiten y devuelve el cargo del banco', () async {
      final (c, adapter) = await open(
        (o) => jsonBody(200, {
          'card': cardJson(used: 700000),
          'chargeTransaction': {
            'id': 'tx',
            'amount': 200000,
            'description': 'Cargos del banco · Visa Clásica ••4242',
          },
        }),
      );
      final charge = await c
          .read(cardsWriterProvider)
          .syncWithBank(cardOfJson(), bankSyncBody(available: '1300000', statementTotal: ''));
      expect(charge, 200000);
      final post = adapter.requests.where((r) => r.method == 'POST').single;
      expect(post.path, '$_card/sync-with-bank');
      expect(post.data, {'available': 1300000});
    });

    test('sync-with-bank sin cargo: null', () async {
      final (c, _) = await open((o) => jsonBody(200, {'card': cardJson(), 'chargeTransaction': null}));
      expect(await c.read(cardsWriterProvider).syncWithBank(cardOfJson(), {'available': 1500000}), isNull);
    });

    test('DELETE de tarjeta y de pago: 204 o 404 cuentan como hechos', () async {
      for (final status in [204, 404]) {
        final (c, adapter) = await open(
          (o) => o.method == 'GET'
              ? jsonBody(200, cardJson())
              : status == 204
              ? ResponseBody.fromString('', 204)
              : errorBody(404, 'NOT_FOUND', 'Pago no encontrado'),
        );
        final writer = c.read(cardsWriterProvider);
        await writer.deletePayment(_id, 'p1');
        await writer.deleteCard(_id);
        expect(sent(adapter), [
          'DELETE $_card/payments/p1',
          // Con 404 se mira que la tarjeta siga en pie: entonces el pago ya no estaba.
          if (status == 404) 'GET $_card',
          'DELETE $_card',
        ], reason: '$status');
      }
    });

    test(
      'borrar un pago de una tarjeta que ya no existe: el 404 de la tarjeta, no «Pago eliminado.»',
      () async {
        final (c, _) = await open((o) => errorBody(404, 'NOT_FOUND', 'Tarjeta no encontrada'));
        await expectLater(
          c.read(cardsWriterProvider).deletePayment(_id, 'p1'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', 404)
                .having((e) => e.serverMessage, 'texto', 'Tarjeta no encontrada'),
          ),
        );
      },
    );
  });

  group('errores', () {
    test('422 llega por campo y 409 CARD_EXISTS con su código', () async {
      final (c, _) = await open(
        (o) => switch (o.method) {
          'PUT' => errorBody(
            422,
            'VALIDATION_ERROR',
            'Datos inválidos',
            details: [
              {'field': 'limit', 'problem': 'No puede ser menor que lo que ya usas'},
            ],
          ),
          'POST' => errorBody(409, 'CARD_EXISTS', 'Ya tienes una tarjeta con esos últimos 4 dígitos'),
          _ => jsonBody(200, const <Object>[]),
        },
      );
      final writer = c.read(cardsWriterProvider);
      await expectLater(
        writer.updateCard(_id, {'limit': 1}),
        throwsA(
          isA<ApiException>().having((e) => e.status, 'status', 422).having((e) => e.fields, 'fields', {
            'limit': 'No puede ser menor que lo que ya usas',
          }),
        ),
      );
      await expectLater(
        writer.createCard({'last4': '4242'}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CARD_EXISTS')),
      );
    });

    test('404 en el detalle es el error de la tarjeta', () async {
      final (c, _) = await open((o) => errorBody(404, 'NOT_FOUND', 'Tarjeta no encontrada'));
      await expectLater(
        c.read(cardDetailProvider((c.read(accountProvider), 'otra')).future),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });
  });

  group('doble envío', () {
    test('dos toques en «Registrar pago»: un solo POST y los dos reciben el resultado', () async {
      final answer = Completer<void>();
      final (c, adapter) = await open((o) async {
        if (o.method == 'GET') return jsonBody(200, const <Object>[]);
        await answer.future;
        return jsonBody(201, {'payment': _payment, 'card': cardJson()});
      });
      final writer = c.read(cardsWriterProvider);
      final first = writer.pay(_id, amount: 100000, date: '2026-11-23');
      final second = writer.pay(_id, amount: 100000, date: '2026-11-23');
      await pumpEventQueue();
      answer.complete();
      await Future.wait([first, second]);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test(
      'pago en duda: relee los ids; un pago NUEVO con ese monto y fecha = hecho, sin segundo POST',
      () async {
        var posted = false;
        final (c, adapter) = await open((o) {
          if (o.method == 'POST') {
            posted = true;
            return _timeout(o);
          }
          // Antes del envío no había pagos; después sí (la respuesta se perdió, pero llegó).
          return jsonBody(200, posted ? [_payment] : const <Object>[]);
        });
        await c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23');
        expect(sent(adapter), ['GET $_card/movements', 'POST $_card/payments', 'GET $_card/movements']);
      },
    );

    test('pago en duda y el pago que aparece YA estaba: no es este; UNCONFIRMED sin reintentar', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? _timeout(o) : jsonBody(200, [_payment]));
      await expectLater(
        c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiCodes.unconfirmed)
              .having(
                (e) => e.serverMessage,
                'texto',
                'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.',
              ),
        ),
      );
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('pago en duda y tampoco se puede leer: UNCONFIRMED, un solo POST', () async {
      var posted = false;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return errorBody(502, 'BAD_GATEWAY', 'x');
        }
        return posted ? networkFailure(o) : jsonBody(200, const <Object>[]);
      });
      await expectLater(
        c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('sin conexión no salió: el error de red, sin releer ni reintentar', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'POST' ? networkFailure(o) : jsonBody(200, const <Object>[]),
      );
      await expectLater(
        c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
      );
      expect(sent(adapter), ['GET $_card/movements', 'POST $_card/payments']);
    });

    test('dos toques en «Actualizar»: un solo POST (dos a la vez duplicarían el cargo)', () async {
      final answer = Completer<void>();
      final (c, adapter) = await open((o) async {
        await answer.future;
        return jsonBody(200, {'card': cardJson(), 'chargeTransaction': null});
      });
      final writer = c.read(cardsWriterProvider);
      final first = writer.syncWithBank(cardOfJson(), {'available': 1300000});
      final second = writer.syncWithBank(cardOfJson(), {'available': 1300000});
      await pumpEventQueue();
      answer.complete();
      await Future.wait([first, second]);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test(
      'ajuste en duda: si el disponible leído es el enviado, hecho, con el cargo de la vista previa',
      () async {
        var posted = false;
        final (c, adapter) = await open((o) {
          if (o.method == 'POST') {
            posted = true;
            return _timeout(o);
          }
          return jsonBody(200, posted ? cardJson(used: 700000, available: 1300000) : cardJson());
        });
        final charge = await c.read(cardsWriterProvider).syncWithBank(cardOfJson(), {'available': 1300000});
        expect(charge, 200000);
        expect(sent(adapter), ['GET $_card', 'POST $_card/sync-with-bank', 'GET $_card']);
      },
    );

    test(
      'ajuste en duda con el detalle viejo: la diferencia sale de la foto previa, no del detalle',
      () async {
        // El servidor ya tiene usado 500.000 (disponible 1.500.000); el detalle quedó en 400.000 porque
        // falló su recarga. El ajuste no llegó: ni el cargo ni el extracto existen.
        final (c, _) = await open((o) => o.method == 'POST' ? _timeout(o) : jsonBody(200, cardJson()));
        await expectLater(
          c.read(cardsWriterProvider).syncWithBank(cardOfJson(cardJson(used: 400000)), {
            'available': 1500000,
            'statementTotal': 480000,
            'statementDueDate': '2026-12-15',
          }),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
        );
      },
    );

    test('ajuste en duda sin foto previa: UNCONFIRMED aunque el disponible coincida', () async {
      var posted = false;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return _timeout(o);
        }
        return posted ? jsonBody(200, cardJson(used: 700000, available: 1300000)) : networkFailure(o);
      });
      await expectLater(
        c.read(cardsWriterProvider).syncWithBank(cardOfJson(), {'available': 1300000}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('ajuste en duda sin confirmar: UNCONFIRMED y un solo POST', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? _timeout(o) : jsonBody(200, cardJson()));
      await expectLater(
        c.read(cardsWriterProvider).syncWithBank(cardOfJson(), {'available': 1300000}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test(
      'ajuste en duda con diferencia 0: el disponible no prueba nada; decide el extracto enviado',
      () async {
        final body = {'available': 1500000, 'statementTotal': 480000, 'statementDueDate': '2026-12-15'};
        // No llegó: el disponible leído es el mismo de hoy, pero el extracto no está.
        final (lost, _) = await open((o) => o.method == 'POST' ? _timeout(o) : jsonBody(200, cardJson()));
        await expectLater(
          lost.read(cardsWriterProvider).syncWithBank(cardOfJson(), body),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
        );
        // Llegó: el extracto leído es el enviado.
        final (saved, _) = await open(
          (o) => o.method == 'POST'
              ? _timeout(o)
              : jsonBody(200, cardJson(statementTotal: 480000, statementDueDate: '2026-12-15')),
        );
        expect(await saved.read(cardsWriterProvider).syncWithBank(cardOfJson(), body), isNull);
      },
    );
  });

  group('consistencia con Mi plata', () {
    test('pagar refresca Mi plata y el Inicio con money: true; no hay movimiento nuevo', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'POST'
            ? jsonBody(201, {'payment': _payment, 'card': cardJson()})
            : jsonBody(200, const <Object>[]),
      );
      final account = c.read(accountProvider);
      c.listen(moneyProfileProvider(account), (_, _) {});
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(moneyProfileProvider(account).future);
      await c.read(homePlanProvider(account).future);
      expect((money.count('profile'), home.count('plan')), (1, 1));

      await c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23');
      await pumpEventQueue();
      expect((money.count('profile'), home.count('plan')), (2, 2));
      expect(sent(adapter).where((r) => r.contains('/transactions')), isEmpty);
    });

    test('tras pagar, la tarjeta no muestra la deuda de antes mientras recarga (como Mi plata)', () async {
      final gate = Completer<void>();
      var posted = false;
      final (c, _) = await open((o) async {
        if (o.method == 'POST') {
          posted = true;
          return jsonBody(201, {'payment': _payment, 'card': cardJson(used: 0)});
        }
        if (posted && o.path != '$_card/movements') await gate.future;
        return switch (o.path) {
          '/cards' => jsonBody(200, [cardJson(used: posted ? 0 : 500000)]),
          _card => jsonBody(200, cardJson(used: posted ? 0 : 500000)),
          _ => jsonBody(200, const <Object>[]),
        };
      });
      final account = c.read(accountProvider);
      final key = (account, _id);
      c.listen(cardDetailProvider(key), (_, _) {});
      c.listen(cardsProvider(account), (_, _) {});
      await c.read(cardDetailProvider(key).future);
      await c.read(cardsProvider(account).future);
      await c.read(cardsWriterProvider).pay(_id, amount: 500000, date: '2026-11-23');
      expect(c.read(cardDetailProvider(key)).isReloading, isTrue, reason: 'no la deuda de antes');
      expect(c.read(cardsProvider(account)).isReloading, isTrue, reason: 'ni «Debes en total» de antes');
      gate.complete();
      expect((await c.read(cardDetailProvider(key).future)).card.used, 0);
    });

    test('borrar un pago en duda: sin esqueleto, para que el aviso de la fila no se pierda', () async {
      final (c, _) = await open(
        (o) => switch (o.method) {
          'DELETE' => _timeout(o),
          _ when o.path == '$_card/movements' && o.method == 'GET' => jsonBody(200, [_payment]),
          _ => jsonBody(200, cardJson()),
        },
      );
      final key = (c.read(accountProvider), _id);
      c.listen(cardDetailProvider(key), (_, _) {});
      await c.read(cardDetailProvider(key).future);
      await expectLater(
        c.read(cardsWriterProvider).deletePayment(_id, _payment['id']! as String),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(cardDetailProvider(key)).isReloading, isFalse);
    });

    test('borrar un pago también refresca Mi plata', () async {
      final (c, _) = await open((o) => ResponseBody.fromString('', 204));
      final account = c.read(accountProvider);
      c.listen(moneyProfileProvider(account), (_, _) {});
      await c.read(moneyProfileProvider(account).future);
      await c.read(cardsWriterProvider).deletePayment(_id, 'p1');
      await pumpEventQueue();
      expect(money.count('profile'), 2);
    });

    test('si el pago falla (no salió), no se refresca nada', () async {
      final (c, _) = await open(
        (o) => o.method == 'POST' ? networkFailure(o) : jsonBody(200, const <Object>[]),
      );
      final account = c.read(accountProvider);
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(homePlanProvider(account).future);
      await expectLater(
        c.read(cardsWriterProvider).pay(_id, amount: 1, date: '2026-11-23'),
        throwsA(anything),
      );
      await pumpEventQueue();
      expect(home.count('plan'), 1);
    });

    test('editar o borrar la tarjeta refresca el detalle de sus compras («Tarjeta eliminada»)', () async {
      final (c, _) = await open(
        (o) => o.method == 'DELETE' ? ResponseBody.fromString('', 204) : jsonBody(200, cardJson()),
      );
      final account = c.read(accountProvider);
      c.listen(movementDetailProvider((account, 'm1')), (_, _) {});
      await c.read(movementDetailProvider((account, 'm1')).future);
      await c.read(cardsWriterProvider).updateCard(_id, {'last4': '4242'});
      await c.read(movementDetailProvider((account, 'm1')).future);
      await c.read(cardsWriterProvider).deleteCard(_id);
      await c.read(movementDetailProvider((account, 'm1')).future);
      expect(movementsRepo.calls.where((call) => call == 'get m1'), hasLength(3));
    });
  });

  group('aislamiento', () {
    test('B no ve las tarjetas de A, ni mientras carga las suyas', () async {
      var answer = Completer<ResponseBody>()..complete(jsonBody(200, [cardJson()]));
      final (c, _) = await open((o) => answer.future);
      c.listen(cardsProvider(c.read(accountProvider)), (_, _) {});
      expect(await c.read(cardsProvider(c.read(accountProvider)).future), hasLength(1));

      answer = Completer<ResponseBody>();
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      final beto = c.read(accountProvider);
      c.listen(cardsProvider(beto), (_, _) {});
      await pumpEventQueue();
      final shown = c.read(cardsProvider(beto));
      expect((shown.isLoading, shown.value), (true, null));
    });

    test('si otra cuenta entra mientras se toma la foto previa, el pago de A no se envía', () async {
      final before = Completer<ResponseBody>();
      final (c, adapter) = await open((o) => o.method == 'GET' ? before.future : jsonBody(201, {}));
      final paying = c.read(cardsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23');
      await pumpEventQueue();
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      before.complete(jsonBody(200, const <Object>[]));
      await expectLater(paying, throwsA(isA<StateError>()));
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('si otra cuenta entra mientras se revisa la bienvenida, ninguna escritura de A sale', () async {
      final ops = <String, Future<Object?> Function(CardsWriter w)>{
        'crear': (w) => w.createCard({'last4': '4242'}),
        'editar': (w) => w.updateCard(_id, {'limit': 1}),
        'borrar': (w) => w.deleteCard(_id),
        'pagar': (w) => w.pay(_id, amount: 1, date: '2026-11-23'),
        'borrar pago': (w) => w.deletePayment(_id, 'p1'),
        'ajustar': (w) => w.syncWithBank(cardOfJson(), {'available': 1}),
      };
      for (final MapEntry(key: name, value: write) in ops.entries) {
        final drafts = _SlowDrafts();
        final (c, adapter) = await open((o) => jsonBody(200, const <Object>[]), drafts: drafts);
        final writing = write(c.read(cardsWriterProvider));
        await pumpEventQueue();
        (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
        drafts.gate.complete();
        await expectLater(writing, throwsA(isA<StateError>()), reason: name);
        expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty, reason: name);
      }
    });
  });

  test('con una bienvenida a medias no se escribe nada: al retomarla pisaría la plata del pago', () async {
    final drafts = MemoryDraftStore();
    await drafts.write(
      'a',
      const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
    );
    final (c, adapter) = await open((o) => jsonBody(200, const <Object>[]), drafts: drafts);
    final writer = c.read(cardsWriterProvider);
    final pending = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending));
    await expectLater(writer.pay(_id, amount: 1, date: '2026-11-23'), pending);
    await expectLater(writer.createCard({'last4': '4242'}), pending);
    await expectLater(writer.updateCard(_id, {'limit': 1}), pending);
    await expectLater(writer.deleteCard(_id), pending);
    await expectLater(writer.deletePayment(_id, 'p1'), pending);
    await expectLater(writer.syncWithBank(cardOfJson(), {'available': 1}), pending);
    expect(adapter.requests, isEmpty);
  });
}
