// Cuentas con el ApiClient real contra un adaptador falso que responde con las formas EXACTAS de QA
// (23-nov-2026): los 7 endpoints y sus cuerpos (sin reminder, PUT sin kind, saldar sin fecha, montos
// como números), los errores (409, 404 = hecho al borrar, 404 del abono que se relee), el doble envío
// (un toque a la vez; en duda se relee y nunca se reintenta solo), los refrescos de Mi plata y
// Movimientos, y el aislamiento por cuenta.
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
import 'package:rinde_mobile/features/debts/application/debts_providers.dart';
import 'package:rinde_mobile/features/debts/application/debts_writer.dart';
import 'package:rinde_mobile/features/debts/data/debts_repository.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_store.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart'
    show movementDetailProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

import '../../support/debt_fixtures.dart';
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

const _id = '85d2a84f-a7fe-45c3-b46e-84d16a8e83b6';
const _debt = '/debts/$_id';
const _pid = 'b4ed7bf7-78f4-4264-87b0-e92d109905f8';

/// Respuestas reales de QA: la cuenta recién creada (3 cuotas, sin abonos) y la de después del abono.
final _created = debtJson(
  dueDate: '2026-12-01',
  paid: 0,
  paidInstallments: 0,
  nextInstallment: const {'number': 1, 'date': '2026-12-01', 'amount': 100000},
  payments: const [],
);
final _afterPayment = debtJson();
final _settledQa = debtJson(
  settledAt: '2026-11-23T22:44:27.165Z',
  transactionId: 'ebd47b17-496b-476c-9a53-aa31fe4045d0',
);

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

ResponseBody _list(List<Map<String, dynamic>> items) => jsonBody(200, debtsJson(items));

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

  late MemoryJsonListStore disk;

  Future<(ProviderContainer, FakeHttpAdapter)> open(FakeHandler handler, {DraftStore? drafts}) async {
    final adapter = FakeHttpAdapter(handler);
    disk = MemoryJsonListStore();
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        debtsRepositoryProvider.overrideWithValue(
          ApiDebtsRepository(ApiClient(config: _qa, session: holder, adapter: adapter)),
        ),
        moneyRepositoryProvider.overrideWithValue(money),
        homeRepositoryProvider.overrideWithValue(home),
        movementsRepositoryProvider.overrideWithValue(movementsRepo),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
        // Si algo de cuentas fuera a parar al teléfono, quedaría aquí.
        demoDebtsStoreProvider.overrideWithValue(disk),
        demoMovementsStoreProvider.overrideWithValue(disk),
      ],
    );
    await c.read(sessionControllerProvider.future);
    return (c, adapter);
  }

  List<String> sent(FakeHttpAdapter a) => [for (final r in a.requests) '${r.method} ${r.path}'];
  List<RequestOptions> posts(FakeHttpAdapter a, String path) =>
      a.requests.where((r) => r.method == 'POST' && r.path == path).toList();

  /// Que Mi plata, el plan y Movimientos tengan quien los escuche, para contar sus recargas.
  Future<void> watchMoney(ProviderContainer c) async {
    final account = c.read(accountProvider);
    c.listen(moneyProfileProvider(account), (_, _) {});
    c.listen(homePlanProvider(account), (_, _) {});
    c.listen(movementDetailProvider((account, 'm1')), (_, _) {});
    await c.read(moneyProfileProvider(account).future);
    await c.read(homePlanProvider(account).future);
    await c.read(movementDetailProvider((account, 'm1')).future);
  }

  ({int money, int plan, int movement}) refreshes() => (
    money: money.count('profile'),
    plan: home.count('plan'),
    movement: movementsRepo.calls.where((call) => call == 'get m1').length,
  );

  group('contrato (formas de QA)', () {
    test('GET /debts: las cuentas en el orden del servidor y los totales', () async {
      final (c, adapter) = await open((o) => _list([_afterPayment, onceJson()]));
      final list = await c.read(debtsProvider(c.read(accountProvider)).future);
      expect([for (final d in list.items) d.person], ['Prueba QA', 'Laura']);
      expect((list.payable, list.receivable), (200000, 60000));
      expect(sent(adapter), ['GET /debts']);
      expect(adapter.requests.single.headers['Authorization'], 'Bearer acceso');
    });

    test('POST /debts: lado, montos y cuotas como números y SIN reminder', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? jsonBody(201, _created) : _list([]));
      await c.read(debtsWriterProvider).create({
        'kind': 'payable',
        'person': 'Prueba QA',
        'amount': 300000,
        'loanDate': null,
        'dueDate': '2026-12-01',
        'installments': 3,
        'frequency': 'monthly',
        'note': 'sintética',
      });
      final post = posts(adapter, '/debts').single;
      expect(post.data, {
        'kind': 'payable',
        'person': 'Prueba QA',
        'amount': 300000,
        'loanDate': null,
        'dueDate': '2026-12-01',
        'installments': 3,
        'frequency': 'monthly',
        'note': 'sintética',
      });
      expect((post.data as Map).containsKey('reminder'), isFalse);
    });

    test('PUT /debts/:id llega tal cual (sin kind ni reminder)', () async {
      final (c, adapter) = await open((o) => o.method == 'PUT' ? jsonBody(200, _afterPayment) : _list([]));
      final body = {'person': 'Prueba QA', 'amount': 300000, 'dueDate': '2026-12-01', 'installments': 3};
      await c.read(debtsWriterProvider).update(_id, body);
      final put = adapter.requests.singleWhere((r) => r.method == 'PUT');
      expect((put.path, put.data), (_debt, body));
    });

    test('saldar: {createTransaction} y SIN date; abonar: {amount, date, createTransaction}', () async {
      final (c, adapter) = await open(
        (o) => switch (o.path) {
          '$_debt/settle' => jsonBody(200, {'debt': _settledQa, 'transaction': null}),
          '$_debt/payments' => jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': null}),
          _ => _list([_created]),
        },
      );
      final writer = c.read(debtsWriterProvider);
      await writer.pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true);
      await writer.settle(_id, createTransaction: false);
      expect(posts(adapter, '$_debt/payments').single.data, {
        'amount': 100000,
        'date': '2026-11-23',
        'createTransaction': true,
      });
      expect(posts(adapter, '$_debt/settle').single.data, {'createTransaction': false});
    });

    test('borrar la cuenta: 204 o 404 cuentan como hechos', () async {
      for (final status in [204, 404]) {
        final (c, _) = await open(
          (o) => o.method == 'DELETE'
              ? (status == 204
                    ? ResponseBody.fromString('', 204)
                    : errorBody(404, 'NOT_FOUND', 'Cuenta no encontrada'))
              : _list([]),
        );
        await c.read(debtsWriterProvider).delete(_id);
      }
    });

    test('borrar un abono devuelve la cuenta como quedó', () async {
      final (c, adapter) = await open((o) => jsonBody(200, _created));
      final updated = await c
          .read(debtsWriterProvider)
          .deletePayment(debtOf(_afterPayment), debtOf().payments.single);
      expect(updated.payments, isEmpty);
      expect(sent(adapter).first, 'DELETE $_debt/payments/$_pid');
    });
  });

  group('errores', () {
    test('422 llega por campo', () async {
      final (c, _) = await open(
        (o) => o.method == 'POST'
            ? errorBody(
                422,
                'VALIDATION_ERROR',
                'Datos inválidos',
                details: [
                  {'field': 'dueDate', 'problem': 'Con cuotas es la fecha de la primera cuota'},
                ],
              )
            : _list([]),
      );
      await expectLater(
        c.read(debtsWriterProvider).create({'kind': 'payable', 'person': 'x', 'amount': 1}),
        throwsA(
          isA<ApiException>().having((e) => e.fields, 'fields', {
            'dueDate': 'Con cuotas es la fecha de la primera cuota',
          }),
        ),
      );
    });

    for (final (name, write) in [
      ('editar', (DebtsWriter w) => w.update(_id, {'amount': 1})),
      ('abonar', (DebtsWriter w) => w.pay(_id, amount: 1, date: '2026-11-23', createTransaction: true)),
      // Sin una duda antes: la saldaron en otro lado y la casilla no anotó el movimiento.
      ('saldar', (DebtsWriter w) => w.settle(_id, createTransaction: true)),
    ]) {
      test('409 ALREADY_SETTLED al $name: llega con su código y la lista se recarga', () async {
        final (c, _) = await open(
          (o) => o.method == 'GET'
              ? _list([_settledQa])
              : errorBody(409, 'ALREADY_SETTLED', 'Esta cuenta ya está saldada'),
        );
        final account = c.read(accountProvider);
        c.listen(debtsProvider(account), (_, _) {});
        await c.read(debtsProvider(account).future);
        await expectLater(
          write(c.read(debtsWriterProvider)),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_SETTLED')),
        );
        expect(c.read(debtsProvider(account)).isReloading, isTrue);
      });
    }

    test('404 de un abono en una cuenta YA saldada: se relee y NO se da por borrado', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'DELETE'
            ? errorBody(404, 'NOT_FOUND', 'Abono no encontrado')
            // Aunque la lectura no traiga el abono (como la respuesta de saldar), saldada no es «borrado».
            : _list([debtJson(settledAt: '2026-11-23T22:44:27.165Z', payments: const [])]),
      );
      await expectLater(
        c.read(debtsWriterProvider).deletePayment(debtOf(_afterPayment), debtOf().payments.single),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      expect(sent(adapter), ['DELETE $_debt/payments/$_pid', 'GET /debts']);
    });

    test('404 de un abono que ya no está y la cuenta sigue pendiente: hecho (un reintento)', () async {
      final (c, _) = await open(
        (o) => o.method == 'DELETE' ? errorBody(404, 'NOT_FOUND', 'Abono no encontrado') : _list([_created]),
      );
      final updated = await c
          .read(debtsWriterProvider)
          .deletePayment(debtOf(_afterPayment), debtOf().payments.single);
      expect(updated.payments, isEmpty);
    });
  });

  group('doble envío', () {
    test('dos toques en «Registrar abono»: un solo POST y los dos reciben el resultado', () async {
      final answer = Completer<ResponseBody>();
      final (c, adapter) = await open((o) => o.method == 'POST' ? answer.future : _list([_created]));
      final writer = c.read(debtsWriterProvider);
      final first = writer.pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true);
      final second = writer.pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true);
      await pumpEventQueue();
      answer.complete(jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': null}));
      await Future.wait([first, second]);
      expect(posts(adapter, '$_debt/payments'), hasLength(1));
    });

    test('abono en duda y aparece un abono NUEVO igual: hecho, sin segundo POST', () async {
      var posted = false;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return _timeout(o);
        }
        return _list([posted ? _afterPayment : _created]);
      });
      await c.read(debtsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true);
      expect(posts(adapter, '$_debt/payments'), hasLength(1));
    });

    test('abono en duda y el abono que se ve YA estaba: no es este; UNCONFIRMED sin reintentar', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? _timeout(o) : _list([_afterPayment]));
      await expectLater(
        c.read(debtsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiCodes.unconfirmed)
              .having((e) => e.serverMessage, 'mensaje', DebtsWriter.unconfirmedText),
        ),
      );
      expect(posts(adapter, '$_debt/payments'), hasLength(1));
    });

    test('abono en duda con otro monto o fecha: UNCONFIRMED', () async {
      var posted = false;
      final (c, _) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return jsonBody(503, {});
        }
        return _list([posted ? _afterPayment : _created]);
      });
      await expectLater(
        c.read(debtsWriterProvider).pay(_id, amount: 90000, date: '2026-11-23', createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
    });

    test('abono en duda y tampoco se puede leer: UNCONFIRMED, un solo POST', () async {
      var posted = false;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return _timeout(o);
        }
        return posted ? networkFailure(o) : _list([_created]);
      });
      await expectLater(
        c.read(debtsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(posts(adapter, '$_debt/payments'), hasLength(1));
    });

    test('sin conexión no salió: el error de red, sin releer ni reintentar', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? networkFailure(o) : _list([_created]));
      await expectLater(
        c.read(debtsWriterProvider).pay(_id, amount: 1, date: '2026-11-23', createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
      );
      expect(sent(adapter), ['GET /debts', 'POST $_debt/payments']);
    });

    test('saldar en duda y su reintento a mano da 409: hecho, sin un segundo movimiento', () async {
      var tries = 0;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          tries++;
          return tries == 1 ? _timeout(o) : errorBody(409, 'ALREADY_SETTLED', 'Esta cuenta ya está saldada');
        }
        // La lectura de la duda aún no lo ve saldado (o no responde): queda en la hoja para repetir.
        return networkFailure(o);
      });
      final writer = c.read(debtsWriterProvider);
      await expectLater(writer.settle(_id, createTransaction: true), throwsA(isA<ApiException>()));
      await writer.settle(_id, createTransaction: true);
      expect(posts(adapter, '$_debt/settle'), hasLength(2));
    });

    // La hoja vuelve a habilitar la casilla tras el error: el reintento puede pedir otra cosa.
    for (final (first, retry) in [(false, true), (true, false)]) {
      test('saldar en duda con casilla $first y reintento con $retry da 409: llega a la hoja', () async {
        var tries = 0;
        final (c, adapter) = await open((o) {
          if (o.method == 'POST') {
            tries++;
            return tries == 1
                ? _timeout(o)
                : errorBody(409, 'ALREADY_SETTLED', 'Esta cuenta ya está saldada');
          }
          return networkFailure(o);
        });
        await watchMoney(c);
        final writer = c.read(debtsWriterProvider);
        await expectLater(writer.settle(_id, createTransaction: first), throwsA(isA<ApiException>()));
        await pumpEventQueue();
        final before = refreshes().money;
        await expectLater(
          writer.settle(_id, createTransaction: retry),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        await pumpEventQueue();
        // El envío en duda pudo anotar un movimiento: Mi plata se vuelve a pedir.
        expect(refreshes().money, before + 1);
        expect(
          [for (final r in posts(adapter, '$_debt/settle')) r.data],
          [
            {'createTransaction': first},
            {'createTransaction': retry},
          ],
        );
      });
    }

    test(
      'saldar: tras la duda la saldaron SIN movimiento en otro lado; el 409 con casilla no es hecho',
      () async {
        var tries = 0;
        var reads = 0;
        final (c, _) = await open((o) {
          if (o.method == 'POST') {
            tries++;
            return tries == 1
                ? _timeout(o)
                : errorBody(409, 'ALREADY_SETTLED', 'Esta cuenta ya está saldada');
          }
          reads++;
          // La lectura de la duda no responde; la del 409 la ve saldada sin movimiento.
          return reads == 1 ? networkFailure(o) : _list([debtJson(settledAt: '2026-11-23T22:44:27.165Z')]);
        });
        final writer = c.read(debtsWriterProvider);
        await expectLater(writer.settle(_id, createTransaction: true), throwsA(isA<ApiException>()));
        await expectLater(
          writer.settle(_id, createTransaction: true),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
      },
    );

    test('saldar en duda y la lectura la ve saldada con OTRA casilla: sigue en duda', () async {
      var tries = 0;
      final (c, _) = await open((o) {
        if (o.method == 'POST') {
          tries++;
          return _timeout(o);
        }
        // La primera duda no se pudo leer; en la segunda ya está saldada, sin movimiento.
        return tries == 1 ? networkFailure(o) : _list([debtJson(settledAt: '2026-11-23T22:44:27.165Z')]);
      });
      final writer = c.read(debtsWriterProvider);
      await expectLater(writer.settle(_id, createTransaction: false), throwsA(isA<ApiException>()));
      await expectLater(
        writer.settle(_id, createTransaction: true),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.timeout)),
      );
    });

    test('saldar en duda y la lectura ya la ve saldada: hecho', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? _timeout(o) : _list([_settledQa]));
      await c.read(debtsWriterProvider).settle(_id, createTransaction: true);
      expect(posts(adapter, '$_debt/settle'), hasLength(1));
    });

    test('POST /debts en duda: una cuenta NUEVA igual (persona sin espacios) es la nuestra', () async {
      var posted = false;
      final (c, adapter) = await open((o) {
        if (o.method == 'POST') {
          posted = true;
          return _timeout(o);
        }
        return _list([onceJson(), if (posted) _created]);
      });
      await c.read(debtsWriterProvider).create({
        'kind': 'payable',
        'person': '  Prueba QA ',
        'amount': 300000,
      });
      expect(posts(adapter, '/debts'), hasLength(1));
    });

    test('POST /debts en duda sin una cuenta nueva igual: UNCONFIRMED, un solo POST', () async {
      final (c, adapter) = await open((o) => o.method == 'POST' ? _timeout(o) : _list([_created]));
      await expectLater(
        c.read(debtsWriterProvider).create({'kind': 'payable', 'person': 'Prueba QA', 'amount': 300000}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(posts(adapter, '/debts'), hasLength(1));
    });

    test('dos toques en «Guardar cuenta»: un solo POST', () async {
      final answer = Completer<ResponseBody>();
      final (c, adapter) = await open((o) => o.method == 'POST' ? answer.future : _list([]));
      final writer = c.read(debtsWriterProvider);
      final body = {'kind': 'payable', 'person': 'x', 'amount': 1};
      final both = Future.wait([writer.create(body), writer.create(body)]);
      await pumpEventQueue();
      answer.complete(jsonBody(201, _created));
      await both;
      expect(posts(adapter, '/debts'), hasLength(1));
    });
  });

  group('consistencia con Mi plata', () {
    test('abonar con la casilla: Movimientos, Mi plata y el Inicio se vuelven a pedir', () async {
      final (c, _) = await open(
        (o) => o.method == 'POST'
            ? jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': {}})
            : _list([_created]),
      );
      await watchMoney(c);
      expect(refreshes(), (money: 1, plan: 1, movement: 1));
      await c.read(debtsWriterProvider).pay(_id, amount: 100000, date: '2026-11-23', createTransaction: true);
      await pumpEventQueue();
      expect(refreshes(), (money: 2, plan: 2, movement: 2));
    });

    test('abonar SIN la casilla, crear, editar y borrar la cuenta: Mi plata no se toca', () async {
      final (c, _) = await open(
        (o) => switch (o.method) {
          'POST' when o.path == '/debts' => jsonBody(201, _created),
          'POST' => jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': null}),
          'PUT' => jsonBody(200, _afterPayment),
          'DELETE' => ResponseBody.fromString('', 204),
          _ => _list([_created]),
        },
      );
      await watchMoney(c);
      final writer = c.read(debtsWriterProvider);
      await writer.pay(_id, amount: 100000, date: '2026-11-23', createTransaction: false);
      await writer.create({'kind': 'payable', 'person': 'x', 'amount': 1});
      await writer.update(_id, {'amount': 2});
      await writer.delete(_id);
      await writer.settle(_id, createTransaction: false);
      await pumpEventQueue();
      expect(refreshes(), (money: 1, plan: 1, movement: 1));
    });

    test('saldar con la casilla refresca Mi plata; borrar un abono con movimiento también', () async {
      final (c, _) = await open(
        (o) => switch (o.method) {
          'POST' => jsonBody(200, {'debt': _settledQa, 'transaction': {}}),
          'DELETE' => jsonBody(200, _created),
          _ => _list([_afterPayment]),
        },
      );
      await watchMoney(c);
      final writer = c.read(debtsWriterProvider);
      await writer.settle(_id, createTransaction: true);
      await pumpEventQueue();
      expect(refreshes(), (money: 2, plan: 2, movement: 2));
      await writer.deletePayment(debtOf(_afterPayment), debtOf().payments.single);
      await pumpEventQueue();
      expect(refreshes(), (money: 3, plan: 3, movement: 3));
    });

    test('tras abonar, la lista muestra la carga y no lo pendiente de antes', () async {
      final gate = Completer<void>();
      var posted = false;
      final (c, _) = await open((o) async {
        if (o.method == 'POST') {
          posted = true;
          return jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': null});
        }
        if (posted) await gate.future;
        return _list([posted ? _afterPayment : _created]);
      });
      final account = c.read(accountProvider);
      c.listen(debtsProvider(account), (_, _) {});
      expect((await c.read(debtsProvider(account).future)).items.single.pending, 300000);
      // La foto previa se pide antes del POST: se deja pasar.
      final paying = c
          .read(debtsWriterProvider)
          .pay(_id, amount: 100000, date: '2026-11-23', createTransaction: false);
      await pumpEventQueue();
      await paying;
      expect(c.read(debtsProvider(account)).isReloading, isTrue, reason: 'no los 300.000 de antes');
      gate.complete();
      expect((await c.read(debtsProvider(account).future)).items.single.pending, 200000);
    });

    test('si el abono falla (no salió), no se refresca nada', () async {
      final (c, _) = await open((o) => o.method == 'POST' ? networkFailure(o) : _list([_created]));
      await watchMoney(c);
      await expectLater(
        c.read(debtsWriterProvider).pay(_id, amount: 1, date: '2026-11-23', createTransaction: true),
        throwsA(anything),
      );
      await pumpEventQueue();
      expect(refreshes(), (money: 1, plan: 1, movement: 1));
    });
  });

  group('aislamiento', () {
    test('B no ve las cuentas de A, ni mientras carga las suyas', () async {
      var answer = Completer<ResponseBody>()..complete(_list([_created]));
      final (c, _) = await open((o) => answer.future);
      c.listen(debtsProvider(c.read(accountProvider)), (_, _) {});
      expect((await c.read(debtsProvider(c.read(accountProvider)).future)).items, hasLength(1));

      answer = Completer<ResponseBody>();
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      final beto = c.read(accountProvider);
      c.listen(debtsProvider(beto), (_, _) {});
      await pumpEventQueue();
      final shown = c.read(debtsProvider(beto));
      expect((shown.isLoading, shown.value), (true, null));
    });

    test('si otra cuenta entra mientras se toma la foto previa, el abono de A no se envía', () async {
      final before = Completer<ResponseBody>();
      final (c, adapter) = await open((o) => o.method == 'GET' ? before.future : jsonBody(201, {}));
      final paying = c
          .read(debtsWriterProvider)
          .pay(_id, amount: 1, date: '2026-11-23', createTransaction: true);
      await pumpEventQueue();
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      before.complete(_list([_created]));
      await expectLater(paying, throwsA(isA<StateError>()));
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('si otra cuenta entra mientras se revisa la bienvenida, ninguna escritura de A sale', () async {
      final ops = <String, Future<Object?> Function(DebtsWriter w)>{
        'crear': (w) => w.create({'kind': 'payable', 'person': 'x', 'amount': 1}),
        'editar': (w) => w.update(_id, {'amount': 1}),
        'borrar': (w) => w.delete(_id),
        'abonar': (w) => w.pay(_id, amount: 1, date: '2026-11-23', createTransaction: true),
        'saldar': (w) => w.settle(_id, createTransaction: true),
        'borrar abono': (w) => w.deletePayment(debtOf(_afterPayment), debtOf().payments.single),
      };
      for (final MapEntry(key: name, value: write) in ops.entries) {
        final drafts = _SlowDrafts();
        final (c, adapter) = await open((o) => _list([]), drafts: drafts);
        final writing = write(c.read(debtsWriterProvider));
        await pumpEventQueue();
        (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
        drafts.gate.complete();
        await expectLater(writing, throwsA(isA<StateError>()), reason: name);
        expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty, reason: name);
      }
    });
  });

  test('en una cuenta real no se guarda nada de cuentas en el teléfono (solo en memoria)', () async {
    final (c, _) = await open(
      (o) => switch (o.method) {
        'POST' when o.path == '/debts' => jsonBody(201, _created),
        'POST' => jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': {}}),
        _ => _list([_created]),
      },
    );
    await c.read(debtsProvider(c.read(accountProvider)).future);
    await c.read(debtsWriterProvider).create({'kind': 'payable', 'person': 'x', 'amount': 1});
    await c.read(debtsWriterProvider).pay(_id, amount: 1, date: '2026-11-23', createTransaction: true);
    expect(disk.data, isEmpty);
  });

  test('con una bienvenida a medias no se escribe nada: al retomarla pisaría la plata del abono', () async {
    final drafts = MemoryDraftStore();
    await drafts.write(
      'a',
      const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
    );
    final (c, adapter) = await open((o) => _list([]), drafts: drafts);
    final writer = c.read(debtsWriterProvider);
    final pending = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending));
    await expectLater(writer.pay(_id, amount: 1, date: '2026-11-23', createTransaction: true), pending);
    await expectLater(writer.create({'kind': 'payable', 'person': 'x', 'amount': 1}), pending);
    await expectLater(writer.update(_id, {'amount': 1}), pending);
    await expectLater(writer.delete(_id), pending);
    await expectLater(writer.settle(_id, createTransaction: true), pending);
    await expectLater(writer.deletePayment(debtOf(_afterPayment), debtOf().payments.single), pending);
    expect(adapter.requests, isEmpty);
  });

  group('Idempotency-Key del abono', () {
    test('el mismo abono tras una duda reusa la llave; un abono nuevo saca otra', () async {
      var timeout = true;
      final (c, adapter) = await open((o) {
        if (o.method != 'POST') return _list([_created]);
        return timeout
            ? _timeout(o)
            : jsonBody(201, {'debt': _afterPayment, 'payment': {}, 'transaction': null});
      });
      final writer = c.read(debtsWriterProvider);
      Future<void> pay({bool record = true}) =>
          writer.pay(_id, amount: 100000, date: '2026-11-23', createTransaction: record);

      // En duda y la relectura no muestra el abono: UNCONFIRMED.
      await expectLater(
        pay(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      timeout = false;
      // Reintento a mano, aunque cambie la casilla: misma llave (el servidor responde 409 y no abona dos veces).
      await pay(record: false);
      await pay(); // un abono nuevo, con el anterior ya hecho: otra llave
      final keys = [for (final r in posts(adapter, '$_debt/payments')) r.headers['Idempotency-Key']];
      expect(keys, hasLength(3));
      expect(keys[0], isA<String>());
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
    });
  });
}
