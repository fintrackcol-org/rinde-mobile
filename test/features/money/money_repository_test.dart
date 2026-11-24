// Contrato de Mi plata contra el ApiClient real y un adaptador falso: a dónde pide, qué manda y
// cómo lee lo que llega. Los ejemplos son literales, con la forma de income.service.js y
// money-profile.service.js de Rinde Web.
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/domain/income_rules.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';

import '../../support/fake_http.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _base = 'https://api-qa.ejemplo.test/api/v1';
const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);

/// Un ejemplo de cada tipo de fuente, como lo devuelve GET /money-profile/income (y PUT /sources).
const _sources = [
  {
    'id': 'a1',
    'name': 'Sueldo',
    'kind': 'sueldo',
    'frequency': 'mensual',
    'payDays': [15, 30],
    'amount': 2500000,
    'low': null,
    'high': null,
    'lastMonths': <num>[],
    'workDays': null,
  },
  {
    'id': 'a2',
    'name': 'Sueldo y comisiones',
    'kind': 'comisiones',
    'frequency': 'mensual',
    'payDays': [30],
    'amount': 1200000,
    'low': 200000,
    'high': 600000,
    'lastMonths': <num>[],
    'workDays': null,
  },
  {
    'id': 'a3',
    'name': 'Proyectos',
    'kind': 'proyectos',
    'frequency': 'irregular',
    'payDays': <int>[],
    'amount': null,
    'low': null,
    'high': null,
    'lastMonths': [1500000, 800000.5, 2000000],
    'workDays': null,
  },
  {
    'id': 'a4',
    'name': 'Trabajo por días',
    'kind': 'diario',
    'frequency': 'diario',
    'payDays': <int>[],
    'amount': 90000,
    'low': null,
    'high': null,
    'lastMonths': <num>[],
    'workDays': 5,
  },
  {
    'id': 'a5',
    'name': 'Mesada',
    'kind': 'mesada',
    'frequency': 'quincenal',
    'payDays': <int>[],
    'amount': 150000,
    'low': null,
    'high': null,
    'lastMonths': <num>[],
    'workDays': null,
  },
];

const _income = {
  'sources': [
    ..._sources,
    // Mal formadas: un tipo que la app no conoce y algo que no es un objeto. Se descartan.
    {'id': 'a6', 'kind': 'criptos'},
    'basura',
  ],
  'normal': 5900000,
  'lean': 4100000,
  'fixed': 3850000,
  'basis': 'declared',
  'estimated': true,
  'variable': true,
  'independent': true,
  'ownSalary': null,
  'cushion': {'goal': 4500000, 'suggestedGoal': 4500000, 'saved': 1200000, 'metaId': 'meta-1'},
  'socialSecurity': {'ibc': 2360000, 'health': 295000, 'pension': 377600, 'total': 672600, 'smmlv': 1750905},
  'workDay': {'target': 3100000, 'earned': 1250000, 'daysLeft': 7, 'perDay': 264300, 'extraToday': 0},
};

const _profile = {
  'incomeType': 'fecha_fija',
  'payDays': [15, 30],
  'balance': null,
  'balanceAt': null,
  'money': null,
  'totals': {'income': 0, 'expense': 0},
  'welcomeDone': true,
  'tutorialDone': false,
  'commitments': [
    {
      'id': 'c1',
      'name': 'Arriendo',
      'amount': 900000,
      'dayOfMonth': 5,
      'kind': 'fixed',
      'frequency': 'monthly',
      'month': null,
      'reminder': {
        'daysBefore': [1],
        'time': null,
        'channel': 'push',
      },
    },
    {
      'id': 'c2',
      'name': 'Seguro',
      'amount': 1200000,
      'dayOfMonth': 20,
      'kind': 'subscription',
      'frequency': 'yearly',
      'month': 3,
      'reminder': null,
    },
    {'id': 'c3', 'name': 'Sin monto', 'dayOfMonth': 1},
  ],
  'subscriptions': {'count': 1, 'monthly': 100000},
};

void main() {
  late SessionHolder holder;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_session));
    await holder.load();
  });

  tearDown(() => holder.dispose());

  ApiMoneyRepository repo(FakeHttpAdapter adapter) =>
      ApiMoneyRepository(ApiClient(config: _qa, session: holder, adapter: adapter));

  group('GET /money-profile/income', () {
    test('pide con token y lee cada tipo de fuente; lo mal formado se descarta', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, _income));
      final income = await repo(adapter).income();
      final request = adapter.requests.single;
      expect('${request.method} ${request.uri}', 'GET $_base/money-profile/income');
      expect(request.headers['Authorization'], 'Bearer acceso');

      expect(income.sources.map((s) => s.kind), [
        IncomeKind.sueldo,
        IncomeKind.comisiones,
        IncomeKind.proyectos,
        IncomeKind.diario,
        IncomeKind.mesada,
      ]);
      final [sueldo, comisiones, proyectos, diario, mesada] = income.sources;
      expect((sueldo.amount, sueldo.low), (2500000, null));
      expect(sueldo.payDays, [15, 30]);
      expect((comisiones.amount, comisiones.low, comisiones.high), (1200000, 200000, 600000));
      expect(proyectos.lastMonths, [1500000, 800000.5, 2000000]);
      expect((diario.amount, diario.workDays, diario.frequency), (90000, 5, 'diario'));
      expect((mesada.amount, mesada.frequency), (150000, 'quincenal'));

      expect(
        (income.normal, income.lean, income.basis, income.estimated),
        (5900000, 4100000, 'declared', true),
      );
      expect(income.ownSalary, isNull);
      expect(
        (income.cushion!.saved, income.cushion!.goal, income.cushion!.metaId),
        (1200000, 4500000, 'meta-1'),
      );
      expect((income.socialSecurity!.health, income.socialSecurity!.total), (295000, 672600));
      expect((income.workDay!.daysLeft, income.workDay!.perDay), (7, 264300));
    });

    test('sin seguridad social ni meta por día: null; lo que no llegó queda null, nunca 0', () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonBody(200, {
          'sources': const <Object>[],
          'basis': 'none',
          'socialSecurity': null,
          'workDay': null,
        }),
      );
      final income = await repo(adapter).income();
      expect(income.sources, isEmpty);
      expect((income.normal, income.lean, income.ownSalary), (null, null, null));
      expect((income.cushion, income.socialSecurity, income.workDay), (null, null, null));
    });

    test('sin la lista de fuentes la respuesta no sirve: error de contrato', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {'normal': 0}));
      await expectLater(repo(adapter).income(), throwsA(isA<ContractException>()));
    });
  });

  group('GET /money-profile', () {
    test('lee los compromisos (descarta los mal formados) y la plata desconocida queda null', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, _profile));
      final profile = await repo(adapter).profile();
      expect('${adapter.requests.single.method} ${adapter.requests.single.uri}', 'GET $_base/money-profile');
      expect((profile.welcomeDone, profile.incomeType), (true, 'fecha_fija'));
      expect(profile.payDays, [15, 30]);
      expect((profile.balance, profile.money), (null, null));
      expect(profile.commitments.map((c) => c.name), ['Arriendo', 'Seguro']);
      final seguro = profile.commitments.last;
      expect((seguro.kind, seguro.frequency, seguro.month), ('subscription', 'yearly', 3));
      expect((profile.subscriptionCount, profile.subscriptionsMonthly), (1, 100000));
      // El backend de hoy no manda versión: el saldo no se escribe desde la app.
      expect(profile.version, isNull);
    });

    test('si el servidor manda la versión, se lee', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {..._profile, 'version': 7}));
      expect((await repo(adapter).profile()).version, 7);
    });
  });

  group('PUT /money-profile/sources', () {
    test('manda {sources} con lo que arma toApi, sin nombre', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, _income));
      final sources = [
        const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]).toApi(),
      ];
      await repo(adapter).saveSources(sources);
      final request = adapter.requests.single;
      expect('${request.method} ${request.uri}', 'PUT $_base/money-profile/sources');
      expect(request.data, {
        'sources': [
          {
            'kind': 'sueldo',
            'frequency': 'mensual',
            'payDays': [15, 30],
            'amount': 2500000,
            'low': null,
            'high': null,
            'lastMonths': <num>[],
            'workDays': null,
          },
        ],
      });
    });

    test('con expectedVersion la manda junto a las fuentes (y sin ella no)', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, _income));
      await repo(adapter).saveSources(const [], expectedVersion: 4);
      await repo(adapter).saveSources(const []);
      expect(adapter.requests.first.data, {'sources': <Object>[], 'expectedVersion': 4});
      expect(adapter.requests.last.data, {'sources': <Object>[]});
    });

    test('un 422 llega con el problema de cada campo', () async {
      final adapter = FakeHttpAdapter(
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
        repo(adapter).saveSources(const []),
        throwsA(
          isA<ApiException>().having((e) => e.fields, 'fields', {
            'sources[0].amount': 'Debe ser un número desde 0',
          }),
        ),
      );
    });
  });

  group('POST /money-profile/commitments', () {
    test('la PILA va con el mismo cuerpo de la web; el nombre repetido es un 409', () async {
      final adapter = FakeHttpAdapter(
        (_) => errorBody(409, 'COMMITMENT_EXISTS', 'Ya tienes un compromiso con ese nombre'),
      );
      const body = {'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 10};
      await expectLater(
        repo(adapter).createCommitment(body),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'COMMITMENT_EXISTS')
              .having((e) => e.serverMessage, 'mensaje', 'Ya tienes un compromiso con ese nombre'),
        ),
      );
      final request = adapter.requests.single;
      expect('${request.method} ${request.uri}', 'POST $_base/money-profile/commitments');
      expect(request.headers['Authorization'], 'Bearer acceso');
      expect(request.data, body);
    });
  });

  group('IncomeSourceForm.fromServer', () {
    test('de lo guardado al formulario y de vuelta: toApi manda lo mismo que había', () async {
      final income = await repo(FakeHttpAdapter((_) => jsonBody(200, _income))).income();
      for (final source in income.sources) {
        final sent = IncomeSourceForm.fromServer(source).toApi();
        expect(sameSources([sent], [source]), isTrue, reason: source.kind.name);
      }
      // Los centavos no se pierden (la web los redondea).
      expect(IncomeSourceForm.fromServer(income.sources[2]).lastMonths, ['1500000', '800000.5', '2000000']);
    });

    test('lo que no está entre las opciones vuelve al valor inicial, que es lo que se ve elegido', () {
      final form = IncomeSourceForm.fromServer(
        const IncomeSource(id: 'x', kind: IncomeKind.diario, frequency: 'diario', amount: 50000, workDays: 2),
      );
      expect((form.workDays, form.frequency, form.amount), ('6', 'mensual', '50000'));
    });
  });

  group('bloque 4B', () {
    test('GET /money-profile/plan trae `ledger`; sin plan queda null, nunca 0', () async {
      final ready = await ApiHomeRepository(
        ApiClient(
          config: _qa,
          session: holder,
          adapter: FakeHttpAdapter(
            (_) => jsonBody(200, {
              'ready': true,
              'money': 412300,
              'ledger': 405000.5,
              'pendingTotal': 338000,
              'free': 74300,
              'shortfall': 0,
              'pace': 13700,
              'hasCommitments': true,
              'pending': const <Object>[],
              'saveAdvice': 0,
              'mode': 'runway',
              'runwayDays': null,
            }),
          ),
        ),
      ).plan();
      expect(ready.ledger, 405000.5);
      final notReady = await ApiHomeRepository(
        ApiClient(
          config: _qa,
          session: holder,
          adapter: FakeHttpAdapter((_) => jsonBody(200, {'ready': false})),
        ),
      ).plan();
      expect(notReady.ledger, isNull);
    });

    test(
      'GET /money-profile/adjustments pide el periodo y lee cada ajuste; lo mal formado se descarta',
      () async {
        final adapter = FakeHttpAdapter(
          (_) => jsonBody(200, {
            'data': [
              {
                'id': 'aj2',
                'before': 650000,
                'after': 500000.25,
                'date': '2026-11-20',
                'createdAt': '2026-11-20T15:00:00Z',
              },
              {
                'id': 'aj1',
                'before': 0,
                'after': 120000,
                'date': '2026-11-03',
                'createdAt': '2026-11-03T12:00:00Z',
              },
              {'id': 'malo', 'before': 1, 'after': 2, 'date': '20/11/2026'},
              {'id': 'sin-monto', 'before': null, 'after': 2, 'date': '2026-11-01'},
            ],
          }),
        );
        final list = await repo(adapter).adjustments(from: '2026-11-01', to: '2026-11-30');
        final request = adapter.requests.single;
        expect(
          '${request.method} ${request.uri}',
          'GET $_base/money-profile/adjustments?from=2026-11-01&to=2026-11-30',
        );
        expect(request.headers['Authorization'], 'Bearer acceso');
        expect(
          [for (final a in list) (a.id, a.before, a.after, a.date)],
          [('aj2', 650000, 500000.25, '2026-11-20'), ('aj1', 0, 120000, '2026-11-03')],
        );
        expect(list.first.difference, -149999.75);
      },
    );

    test('GET /money-profile/adjustments con una fecha mal escrita: el 422 con su campo', () async {
      final adapter = FakeHttpAdapter(
        (_) => errorBody(
          422,
          'VALIDATION_ERROR',
          'Datos inválidos',
          details: [
            {'field': 'from', 'problem': 'Debe ser una fecha AAAA-MM-DD'},
          ],
        ),
      );
      await expectLater(
        repo(adapter).adjustments(from: '2026-13-01', to: '2026-11-30'),
        throwsA(
          isA<ApiException>().having((e) => e.status, 'status', 422).having((e) => e.fields, 'campos', {
            'from': 'Debe ser una fecha AAAA-MM-DD',
          }),
        ),
      );
    });

    test('PUT /money-profile manda el cuerpo tal cual, con token', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, _profile));
      const body = {
        'incomeType': 'fecha_fija',
        'payDays': [15, 30],
        'balance': 500000.5,
        'resetBalance': true,
      };
      await repo(adapter).saveProfile(body);
      final request = adapter.requests.single;
      expect('${request.method} ${request.uri}', 'PUT $_base/money-profile');
      expect(request.headers['Authorization'], 'Bearer acceso');
      expect(request.data, body);
    });
  });
}
