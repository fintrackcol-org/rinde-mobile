import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/fake_http.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _base = 'https://api-qa.ejemplo.test/api/v1';
const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);

// Los ejemplos del contrato (auditoría de contratos, secciones 1 a 9), tal como llegan de la red.
const _newProfile =
    '{"incomeType":null,"payDays":[],"balance":null,"balanceAt":null,"money":null,'
    '"totals":{"income":0,"expense":0},"welcomeDone":false,"tutorialDone":false,"commitments":[],'
    '"subscriptions":{"count":0,"monthly":0}}';
const _plan =
    '{"ready":true,"money":1850000,"ledger":650000,"pendingTotal":950000,"free":900000,"shortfall":0,'
    '"pace":42000,"hasCommitments":true,"pending":[{"id":"7c1e","name":"Arriendo","amount":900000,'
    '"date":"2026-12-05"},{"id":"9a2b","name":"Internet","amount":50000,"date":"2026-11-28"}],'
    '"saveAdvice":0,"mode":"daily","nextPay":"2026-11-30","days":9,"perDay":100000,"spentToday":35000,'
    '"leftToday":65000,"overBy":0,"dayStatus":"ok"}';
const _summary =
    '{"period":"month","from":"2026-11-01","to":"2026-11-30",'
    '"income":{"total":2500000,"byCategory":[{"category":"salario","total":2500000,"percentage":100}]},'
    '"expense":{"total":1203400.5,"byCategory":[{"category":"alimentacion","total":600000,"percentage":49.9},'
    '{"category":null,"total":3400.5,"percentage":0.3}]},'
    '"savings":{"total":200000},"timeSeries":[{"date":"2026-11-02","income":0,"expense":45000}]}';
const _budgets =
    '[{"id":"uuid","category":"alimentacion","month":"2026-11","amount":800000,"consumed":650000,'
    '"percentage":81.25,"alert":{"level":"warning_80","percentage":81.25}}]';
const _cards =
    '[{"id":"uuid","name":"Visa Gold ••4821","network":"visa","tier":"gold","last4":"4821","limit":5000000,'
    '"used":1200000,"available":3800000,"paymentDay":15,"cutoffDay":null,"statementTotal":null,'
    '"statementDueDate":null,"nextPaymentDate":"2026-12-15","daysToPayment":24,"paidThisCycle":true,'
    '"paidDueDate":"2026-11-15","paidAmount":400000,"reminderSentFor":null,"expiryMonth":3,"expiryYear":2027,'
    '"expiry":{"label":"03/27","expired":false,"soon":false},"expiryNotified":[]}]';
const _pendingPayments =
    '{"items":[{"id":"uuid","merchant":"Starbucks","amount":14500,"date":"2026-11-21","card":null,'
    '"status":"pending","transactionId":null,"createdAt":"2026-11-21T14:03:11.123Z","possibleDuplicate":false}]}';
const _notifications =
    '{"items":[{"id":"uuid","title":"Presupuesto de Alimentación","body":"Ya llevas el 81 %",'
    '"url":"/app/presupuestos","read":false,"createdAt":"2026-11-21T14:03:11.123Z"}],"unread":3}';
const _categories =
    '{"expense":[{"key":"alimentacion","name":"Alimentación","icon":null,"color":null,"custom":false},'
    '{"key":"c_mascotas","name":"Mascotas","icon":"paw-print","color":"amber","custom":true}],'
    '"income":[{"key":"salario","name":"Salario","icon":null,"color":null,"custom":false}]}';

ResponseBody _raw(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// Responde lo mismo a todo: cada prueba hace una sola petición.
FakeHttpAdapter _answers(String body) => FakeHttpAdapter((_) => _raw(body));
FakeHttpAdapter _answersJson(Object? body) => FakeHttpAdapter((_) => jsonBody(200, body));

final _contract = throwsA(isA<ContractException>());

Matcher _apiError(String code, {int? status}) => throwsA(
  isA<ApiException>().having((e) => e.code, 'code', code).having((e) => e.status, 'status', status),
);

void main() {
  late SessionHolder holder;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_session));
    await holder.load();
  });

  tearDown(() => holder.dispose());

  ApiClient client(FakeHttpAdapter adapter) => ApiClient(config: _qa, session: holder, adapter: adapter);
  ApiHomeRepository repo(FakeHttpAdapter adapter) => ApiHomeRepository(client(adapter));

  /// Cada lectura del Inicio, para probar lo que es igual en todas.
  Map<String, Future<Object?> Function(HomeRepository)> reads() => {
    'plan': (r) => r.plan(),
    'monthTotals': (r) => r.monthTotals('2026-11-21'),
    'budgets': (r) => r.budgets('2026-11'),
    'cards': (r) => r.cards(),
    'toConfirm': (r) => r.toConfirm(),
    'unread': (r) => r.unread(),
    'categoryNames': (r) => r.categoryNames(),
  };

  group('ApiHomeRepository: a dónde pide', () {
    test('no es de demostración', () {
      expect(repo(_answers('{}')).isDemo, isFalse);
    });

    test('cada lectura es un GET con token a su ruta, con los mismos parámetros que la web', () async {
      const expected = {
        'plan': 'GET $_base/money-profile/plan',
        'monthTotals': 'GET $_base/transactions/summary?period=month&date=2026-11-21',
        'budgets': 'GET $_base/budgets?month=2026-11',
        'cards': 'GET $_base/cards',
        'toConfirm': 'GET $_base/pending-payments',
        'unread': 'GET $_base/notifications',
        // No /transactions/categories: esa ruta no existe (responde 404 «Transacción no encontrada»).
        'categoryNames': 'GET $_base/categories',
      };
      for (final MapEntry(key: name, value: read) in reads().entries) {
        final adapter = FakeHttpAdapter((_) => errorBody(500, 'INTERNAL_ERROR', 'x'));
        await expectLater(read(repo(adapter)), throwsA(anything), reason: name);
        final request = adapter.requests.single;
        expect('${request.method} ${request.uri}', expected[name], reason: name);
        expect(request.headers['Authorization'], 'Bearer acceso', reason: name);
      }
    });

    test(
      'el día y el mes van tal cual los manda la app (el día local del dispositivo), sin tocarlos',
      () async {
        final adapter = FakeHttpAdapter((o) => o.path == '/budgets' ? _raw('[]') : _raw(_summary));
        await repo(adapter).monthTotals('2026-11-30');
        await repo(adapter).monthTotals('2026-12-01');
        await repo(adapter).budgets('2026-12');
        expect(adapter.requests.map((r) => r.uri.query), [
          'period=month&date=2026-11-30',
          'period=month&date=2026-12-01',
          'month=2026-12',
        ]);
      },
    );

    test('finishTutorial: POST /money-profile/tutorial con token y sin cuerpo', () async {
      final adapter = _answers(_newProfile);
      await repo(adapter).finishTutorial();
      final request = adapter.requests.single;
      expect('${request.method} ${request.uri}', 'POST $_base/money-profile/tutorial');
      expect(request.headers['Authorization'], 'Bearer acceso');
      expect(request.data, isNull);
    });

    test('finishTutorial: si el servidor falla, lanza (quien llama decide callarlo)', () async {
      await expectLater(repo(FakeHttpAdapter(networkFailure)).finishTutorial(), _apiError(ApiCodes.network));
      await expectLater(
        repo(FakeHttpAdapter((_) => errorBody(500, 'INTERNAL_ERROR', 'x'))).finishTutorial(),
        _apiError('INTERNAL_ERROR', status: 500),
      );
    });
  });

  group('ApiHomeRepository: lee los ejemplos del contrato', () {
    test('plan listo (modo daily)', () async {
      final plan = await repo(_answers(_plan)).plan();
      expect(plan.ready, isTrue);
      expect(
        (plan.money, plan.pendingTotal, plan.free, plan.shortfall, plan.mode, plan.perDay, plan.nextPay),
        (1850000, 950000, 900000, 0, 'daily', 100000, '2026-11-30'),
      );
      expect(plan.pending.map((p) => '${p.name} ${p.amount} ${p.date}'), [
        'Arriendo 900000 2026-12-05',
        'Internet 50000 2026-11-28',
      ]);
    });

    test('plan sin configurar: {"ready": false}', () async {
      expect((await repo(_answers('{"ready":false}')).plan()).ready, isFalse);
    });

    test('ingresos y gastos del mes', () async {
      final totals = await repo(_answers(_summary)).monthTotals('2026-11-21');
      expect((totals.month, totals.income, totals.expense), ('2026-11', 2500000, 1203400.5));
    });

    test('presupuestos; sin ninguno es una lista vacía', () async {
      final budget = (await repo(_answers(_budgets)).budgets('2026-11')).single;
      expect(
        (budget.category, budget.amount, budget.consumed, budget.percentage, budget.level),
        ('alimentacion', 800000, 650000, 81.25, BudgetLevel.warning),
      );
      expect(await repo(_answers('[]')).budgets('2026-11'), isEmpty);
    });

    test('tarjetas; sin ninguna es una lista vacía', () async {
      final card = (await repo(_answers(_cards)).cards()).single;
      expect(
        (card.id, card.network, card.last4, card.used, card.daysToPayment, card.paidThisCycle),
        ('uuid', 'visa', '4821', 1200000, 24, true),
      );
      expect(await repo(_answers('[]')).cards(), isEmpty);
    });

    test('un presupuesto o una tarjeta mal formados se saltan; los buenos quedan', () async {
      final good = (jsonDecode(_budgets) as List).single as Map<String, dynamic>;
      final budgets = await repo(
        _answersJson([
          {...good, 'amount': '800000'},
          good,
          null,
          'alimentacion',
        ]),
      ).budgets('2026-11');
      expect(budgets.single.category, 'alimentacion');

      final card = (jsonDecode(_cards) as List).single as Map<String, dynamic>;
      final cards = await repo(
        _answersJson([
          // Sin días hasta el pago no hay nada cierto que avisar.
          {...card, 'id': 'sin-dias'}..remove('daysToPayment'),
          {...card, 'id': 'buena', 'daysToPayment': -2, 'paidThisCycle': false},
          42,
        ]),
      ).cards();
      expect(cards.map((c) => '${c.id} ${c.daysToPayment}'), ['buena -2']);
    });

    test('por confirmar: cuántos pagos esperan', () async {
      expect(await repo(_answers(_pendingPayments)).toConfirm(), 1);
      expect(await repo(_answers('{"items":[]}')).toConfirm(), 0);
      expect(
        await repo(
          _answersJson({
            'items': [
              {'id': 'a'},
              {'id': 'b'},
              {'id': 'c'},
            ],
          }),
        ).toConfirm(),
        3,
      );
    });

    test('notificaciones sin leer', () async {
      expect(await repo(_answers(_notifications)).unread(), 3);
      expect(await repo(_answers('{"items":[],"unread":0}')).unread(), 0);
    });

    test('notificaciones sin leer: sin un entero positivo no hay punto que mostrar', () async {
      for (final unread in <Object?>[null, -1, '3', 2.5]) {
        expect(
          await repo(_answersJson({'items': <Object?>[], 'unread': unread})).unread(),
          0,
          reason: '$unread',
        );
      }
      expect(await repo(_answers('{"items":[]}')).unread(), 0);
    });

    test('categorías: clave → nombre, de gastos e ingresos y con las propias', () async {
      expect(await repo(_answers(_categories)).categoryNames(), {
        'alimentacion': 'Alimentación',
        'c_mascotas': 'Mascotas',
        'salario': 'Salario',
      });
    });

    test('categorías: se salta lo mal formado y tolera que falte una lista', () async {
      final names = await repo(
        _answersJson({
          'expense': [
            {'key': 'vivienda', 'name': 'Vivienda'},
            {'key': 'sin-nombre'},
            {'key': 7, 'name': 'Clave rara'},
            'transporte',
            null,
          ],
          'income': 'ninguna',
        }),
      ).categoryNames();
      expect(names, {'vivienda': 'Vivienda'});
      expect(await repo(_answers('{}')).categoryNames(), isEmpty);
    });
  });

  group('ApiHomeRepository: errores', () {
    test('sin conexión: NETWORK en todas las lecturas', () async {
      for (final MapEntry(key: name, value: read) in reads().entries) {
        await expectLater(
          read(repo(FakeHttpAdapter(networkFailure))),
          _apiError(ApiCodes.network),
          reason: name,
        );
      }
    });

    test('un 500 llega con el código del servidor, no como «sin conexión»', () async {
      for (final MapEntry(key: name, value: read) in reads().entries) {
        final adapter = FakeHttpAdapter((_) => errorBody(500, 'INTERNAL_ERROR', 'Error interno'));
        await expectLater(read(repo(adapter)), _apiError('INTERNAL_ERROR', status: 500), reason: name);
      }
    });

    test('un error sin la forma del servidor (un proxy caído) es UNKNOWN con su estado', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(502, {'message': 'Bad Gateway'}));
      await expectLater(repo(adapter).plan(), _apiError(ApiCodes.unknown, status: 502));
    });

    test('la sesión vencida llega como tal (el Inicio no la trata como error de carga)', () async {
      // Sin sesión guardada la petición ni sale: UNAUTHORIZED.
      await holder.clear();
      final adapter = _answers(_plan);
      await expectLater(repo(adapter).plan(), _apiError(ApiCodes.unauthorized));
      expect(adapter.requests, isEmpty);
    });

    test(
      'un 200 con otra forma es un error de contrato: nunca un plan, un cero ni una lista vacía',
      () async {
        for (final body in ['[]', '"ok"', 'null', '42', '{}']) {
          await expectLater(repo(_answers(body)).plan(), _contract, reason: 'plan $body');
          await expectLater(
            repo(_answers(body)).monthTotals('2026-11-21'),
            _contract,
            reason: 'totales $body',
          );
          await expectLater(repo(_answers(body)).toConfirm(), _contract, reason: 'por confirmar $body');
        }
        for (final body in ['{}', '"ok"', 'null', '{"items":[]}']) {
          await expectLater(repo(_answers(body)).budgets('2026-11'), _contract, reason: 'presupuestos $body');
          await expectLater(repo(_answers(body)).cards(), _contract, reason: 'tarjetas $body');
        }
        for (final body in ['[]', '"ok"', 'null']) {
          await expectLater(repo(_answers(body)).unread(), _contract, reason: 'sin leer $body');
          await expectLater(repo(_answers(body)).categoryNames(), _contract, reason: 'categorías $body');
        }
      },
    );

    test('por confirmar: sin la lista de pagos es un error, no «0 pagos»', () async {
      await expectLater(repo(_answers('{"items":null}')).toConfirm(), _contract);
      await expectLater(repo(_answers('{"items":3}')).toConfirm(), _contract);
      await expectLater(repo(_answers('{"total":3}')).toConfirm(), _contract);
    });

    test('plan listo al que le falta una cifra: error de contrato, no un cero', () async {
      final plan = jsonDecode(_plan) as Map<String, dynamic>;
      for (final key in ['money', 'pendingTotal', 'free', 'shortfall']) {
        await expectLater(repo(_answersJson({...plan}..remove(key))).plan(), _contract, reason: 'sin $key');
        await expectLater(repo(_answersJson({...plan, key: '1000'})).plan(), _contract, reason: '$key texto');
      }
    });

    test('un cuerpo que no es JSON falla: nunca se lee como una respuesta vacía', () async {
      for (final MapEntry(key: name, value: read) in reads().entries) {
        final adapter = _answers('<html>Servicio en mantenimiento</html>');
        await expectLater(read(repo(adapter)), throwsA(anything), reason: name);
      }
      // Si ni siquiera dice ser JSON, llega como texto: error de contrato.
      final html = FakeHttpAdapter(
        (_) => ResponseBody.fromString(
          '<html>Servicio en mantenimiento</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      );
      await expectLater(repo(html).plan(), _contract);
      await expectLater(repo(html).toConfirm(), _contract);
    });
  });

  group('ApiOnboardingRepository.status (lo que el Inicio lee de la cuenta)', () {
    Future<WelcomeStatus> status({Object? profile, Object? list = const {'data': <Object?>[], 'total': 57}}) {
      final adapter = FakeHttpAdapter(
        (o) => switch (o.path) {
          '/money-profile' => jsonBody(200, profile),
          '/transactions' => jsonBody(200, list),
          _ => jsonBody(404, <String, Object?>{}),
        },
      );
      return ApiOnboardingRepository(client(adapter)).status();
    }

    Map<String, dynamic> profile([Map<String, dynamic> changes = const {}]) => {
      ...(jsonDecode(_newProfile) as Map<String, dynamic>),
      ...changes,
    };

    test(
      'cuenta nueva del contrato: la plata que el servidor no sabe sigue siendo null, no un cero',
      () async {
        final s = await status(
          profile: profile(),
          list: {'data': <Object?>[], 'page': 1, 'pageSize': 1, 'total': 0},
        );
        expect(s.money, isNull);
        expect(s.balanceSet, isFalse);
        expect((s.welcomeDone, s.tutorialDone, s.hasTransactions), (false, false, false));
      },
    );

    test('money ausente o que no es un número: null', () async {
      expect((await status(profile: profile()..remove('money'))).money, isNull);
      expect((await status(profile: profile({'money': '850000'}))).money, isNull);
    });

    test('money llega tal cual, al centavo y sin residuos de coma flotante', () async {
      expect((await status(profile: profile({'money': 1234567.5}))).money, 1234567.5);
      expect((await status(profile: profile({'money': -0.4}))).money, -0.4);
      // Un cero que SÍ llegó es un cero.
      final zero = (await status(profile: profile({'money': 0}))).money;
      expect(zero, 0);
      // El perfil no redondea: 100000.26 + 0.2 − 100000.46 llega como −1.455e-11.
      final residue = (await status(profile: profile({'money': 100000.26 + 0.2 - 100000.46}))).money!;
      expect((residue, residue.isNegative), (0, false));
    });

    test('balanceSet: la persona ya dijo cuánta plata tiene (balance es un número, también 0)', () async {
      expect((await status(profile: profile({'balance': 850000, 'money': 850000}))).balanceSet, isTrue);
      expect((await status(profile: profile({'balance': 0, 'money': 0}))).balanceSet, isTrue);
      expect((await status(profile: profile({'balance': null}))).balanceSet, isFalse);
      expect((await status(profile: profile()..remove('balance'))).balanceSet, isFalse);
      expect((await status(profile: profile({'balance': '850000'}))).balanceSet, isFalse);
    });

    test('balanceSet no depende de money: saldo dicho pero el servidor usa los movimientos', () async {
      final s = await status(profile: profile({'balance': 850000, 'money': null}));
      expect((s.balanceSet, s.money), (true, null));
    });

    test('un perfil mal formado lanza: no se lee como «cuenta nueva sin bienvenida»', () async {
      final broken = <String, Object?>{
        'sin welcomeDone': profile()..remove('welcomeDone'),
        'welcomeDone null': profile({'welcomeDone': null}),
        'welcomeDone texto': profile({'welcomeDone': 'false'}),
        'welcomeDone 0': profile({'welcomeDone': 0}),
        'objeto vacío': <String, Object?>{},
        'lista': <Object?>[],
        'texto': 'ok',
        'null': null,
      };
      for (final MapEntry(key: name, value: body) in broken.entries) {
        await expectLater(status(profile: body), _apiError(ApiCodes.unknown), reason: name);
      }
    });

    test('un total de movimientos mal formado lanza: no se lee como «sin movimientos»', () async {
      final done = profile({'welcomeDone': false});
      final broken = <String, Object?>{
        'sin total': {'data': <Object?>[]},
        'total null': {'data': <Object?>[], 'total': null},
        'total texto': {'data': <Object?>[], 'total': '0'},
        'objeto vacío': <String, Object?>{},
        'lista': <Object?>[],
        'null': null,
      };
      for (final MapEntry(key: name, value: body) in broken.entries) {
        await expectLater(
          status(profile: done, list: body),
          _apiError(ApiCodes.unknown),
          reason: name,
        );
      }
    });

    test('si una de las dos peticiones falla, falla todo (no hay estado a medias)', () async {
      final adapter = FakeHttpAdapter(
        (o) => o.path == '/money-profile' ? _raw(_newProfile) : errorBody(500, 'INTERNAL_ERROR', 'x'),
      );
      await expectLater(
        ApiOnboardingRepository(client(adapter)).status(),
        _apiError('INTERNAL_ERROR', status: 500),
      );
      await expectLater(
        ApiOnboardingRepository(client(FakeHttpAdapter(networkFailure))).status(),
        _apiError(ApiCodes.network),
      );
    });
  });
}
