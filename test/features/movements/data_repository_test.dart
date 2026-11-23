import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';

import '../../support/fake_http.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);

// Una fila tal como la arma el repositorio del backend (COLUMNS de transactions.repository.js).
Map<String, dynamic> _row({Map<String, dynamic> extra = const {}}) => {
  'id': '6f1c2b1e-0000-4000-8000-000000000001',
  'userId': 'u1',
  'amount': 45000.1000000001,
  'description': 'Mercado',
  'type': 'gasto',
  'category': 'alimentacion',
  'source': 'ia',
  'date': '2026-11-20',
  'createdAt': '2026-11-20T15:03:11.123Z',
  'updatedAt': '2026-11-20T15:03:11.123Z',
  'deletedAt': null,
  'card': {'id': 'c1', 'name': 'Visa', 'last4': '4821', 'deleted': false},
  'installments': 3,
  'emotion': 'normal',
  'kakeibo': 'necesidad',
  'original': {'currency': 'USD', 'amount': 11.25, 'rate': 4000.009},
  ...extra,
};

void main() {
  late SessionHolder holder;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_session));
    await holder.load();
  });

  tearDown(() => holder.dispose());

  ApiMovementsRepository repo(FakeHttpAdapter adapter) =>
      ApiMovementsRepository(ApiClient(config: _qa, session: holder, adapter: adapter));

  group('Movement.fromJson', () {
    test('lee todos los campos y normaliza el monto a centavos', () {
      final m = Movement.fromJson(_row());
      expect(m.type, MovementType.expense);
      expect(m.amount, 45000.1);
      expect(m.category, 'alimentacion');
      expect(m.source, 'ia');
      expect(m.date, '2026-11-20');
      expect(m.createdAt, DateTime.utc(2026, 11, 20, 15, 3, 11, 123));
      expect(m.card!.last4, '4821');
      expect(m.installments, 3);
      expect(m.emotion, 'normal');
      expect(m.kakeibo, 'necesidad');
      expect(m.original, const OriginalAmount(currency: 'USD', amount: 11.25, rate: 4000.009));
      expect(m.pending, isFalse);
      expect(m.deleted, isFalse);
    });

    test('ingreso, entero y opcionales nulos', () {
      final m = Movement.fromJson(
        _row(
          extra: {
            'type': 'ingreso',
            'amount': 2500000,
            'category': null,
            'card': null,
            'installments': null,
            'emotion': null,
            'kakeibo': null,
            'original': null,
            'createdAt': null,
          },
        ),
      );
      expect(m.type, MovementType.income);
      expect(m.amount, 2500000);
      expect(m.amount, isA<int>());
      expect(m.category, isNull);
      expect(m.card, isNull);
      expect(m.installments, isNull);
      expect(m.original, isNull);
      expect(m.createdAt, isNull);
    });

    test('un reintento de uno ya borrado llega con deletedAt', () {
      expect(Movement.fromJson(_row(extra: {'deletedAt': '2026-11-21T00:00:00Z'})).deleted, isTrue);
    });

    for (final (name, broken) in [
      ('sin id', {'id': null}),
      ('tipo desconocido', {'type': 'transferencia'}),
      ('monto texto', {'amount': '45000'}),
      ('monto ausente', {'amount': null}),
      ('sin descripción', {'description': null}),
      ('categoría numérica', {'category': 3}),
      ('sin source', {'source': null}),
      ('fecha con hora', {'date': '2026-11-20T00:00:00Z'}),
    ]) {
      test('mal formado ($name) es ContractException', () {
        expect(() => Movement.fromJson(_row(extra: broken)), throwsA(isA<ContractException>()));
      });
    }

    test('lo que no es objeto es ContractException', () {
      expect(() => Movement.fromJson([]), throwsA(isA<ContractException>()));
    });
  });

  group('MovementPage y CategoryLists', () {
    test('página con total y hasMore', () {
      final page = MovementPage.fromJson({
        'data': [_row()],
        'page': 1,
        'pageSize': 1,
        'total': 3,
      });
      expect(page.items.single.description, 'Mercado');
      expect(page.total, 3);
      expect(page.hasMore, isTrue);
    });

    test('una fila ilegible falla la página entera', () {
      expect(
        () => MovementPage.fromJson({
          'data': [_row(), 'basura'],
          'page': 1,
          'pageSize': 20,
          'total': 2,
        }),
        throwsA(isA<ContractException>()),
      );
      expect(
        () => MovementPage.fromJson({'data': [], 'page': 1, 'pageSize': 20}),
        throwsA(isA<ContractException>()),
      );
    });

    test('categorías: Otros al final, propias con ícono, se saltan las ilegibles', () {
      final lists = CategoryLists.fromJson({
        'expense': [
          {'key': 'otros', 'name': 'Otros', 'icon': null, 'color': null, 'custom': false},
          {'key': 'alimentacion', 'name': 'Alimentación', 'icon': null, 'color': null, 'custom': false},
          {'key': 'c_x', 'name': 'Mascotas', 'icon': 'paw-print', 'color': 'amber', 'custom': true},
          {'name': 'sin clave'},
        ],
        'income': [
          {'key': 'otros_ingresos', 'name': 'Otros ingresos'},
          {'key': 'salario', 'name': 'Salario'},
        ],
      });
      expect([for (final c in lists.expense) c.key], ['alimentacion', 'c_x', 'otros']);
      expect(lists.expense[1].icon, 'paw-print');
      expect(lists.expense[1].custom, isTrue);
      expect([for (final c in lists.of(MovementType.income)) c.key], ['salario', 'otros_ingresos']);
      expect(lists.names['c_x'], 'Mascotas');
      expect(() => CategoryLists.fromJson({'expense': []}), throwsA(isA<ContractException>()));
    });
  });

  group('MovementQuery', () {
    test('igualdad por valor', () {
      expect(
        const MovementQuery(type: MovementType.income, search: 'a'),
        const MovementQuery(type: MovementType.income, search: 'a'),
      );
      expect(const MovementQuery(page: 2), isNot(const MovementQuery()));
    });

    test('los filtros viajan como en la web y los vacíos no viajan', () async {
      final http = FakeHttpAdapter((_) => jsonBody(200, {'data': [], 'page': 2, 'pageSize': 50, 'total': 0}));
      await repo(http).list(
        const MovementQuery(
          type: MovementType.expense,
          category: 'transporte',
          from: '2026-11-01',
          to: '2026-11-30',
          search: '  taxi ',
          page: 2,
          pageSize: 50,
        ),
      );
      await repo(http).list(const MovementQuery(category: '', search: '   '));
      final first = http.requests[0];
      expect(first.method, 'GET');
      expect(first.path, '/transactions');
      expect(first.queryParameters, {
        'type': 'gasto',
        'category': 'transporte',
        'from': '2026-11-01',
        'to': '2026-11-30',
        'q': 'taxi',
        'page': 2,
        'pageSize': 50,
      });
      expect(first.headers['Authorization'], 'Bearer acceso');
      expect(http.requests[1].queryParameters, {'page': 1, 'pageSize': 20});
    });
  });

  group('ApiMovementsRepository', () {
    test('create manda el localId y lee { transaction, alert }', () async {
      final http = FakeHttpAdapter((_) => jsonBody(201, {'transaction': _row(), 'alert': null}));
      const input = MovementInput(
        type: MovementType.expense,
        amount: 45000.1,
        description: 'Mercado',
        date: '2026-11-20',
        card: 'c1',
        installments: 3,
      );
      final created = await repo(http).create(input, localId: 'm-abc');
      final request = http.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/transactions');
      expect(jsonDecode(jsonEncode(request.data)), {
        'type': 'gasto',
        'amount': 45000.1,
        'description': 'Mercado',
        'date': '2026-11-20',
        'category': null,
        'card': 'c1',
        'installments': 3,
        'localId': 'm-abc',
      });
      expect(created.id, _row()['id']);
    });

    test('update manda el estado completo con nulos para quitar', () async {
      final http = FakeHttpAdapter((_) => jsonBody(200, {'transaction': _row(), 'alert': null}));
      await repo(http).update('id 1', inputOf);
      final request = http.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/transactions/id%201');
      expect((request.data as Map).keys, containsAll(['card', 'emotion', 'kakeibo', 'original']));
      expect((request.data as Map)['card'], isNull);
    });

    test('get, delete (204) y categorías van a sus rutas', () async {
      final http = FakeHttpAdapter(
        (o) => switch (o.method) {
          'DELETE' => ResponseBody.fromString('', 204),
          _ when o.path == '/categories' => jsonBody(200, {'expense': [], 'income': []}),
          _ => jsonBody(200, _row()),
        },
      );
      final r = repo(http);
      await r.get('abc');
      await r.delete('abc');
      await r.categories();
      expect(
        [for (final q in http.requests) '${q.method} ${q.path}'],
        ['GET /transactions/abc', 'DELETE /transactions/abc', 'GET /categories'],
      );
    });

    test('errores: 404 con mensaje del servidor, sin red como NETWORK', () async {
      final missing = repo(FakeHttpAdapter((_) => errorBody(404, 'NOT_FOUND', 'Transacción no encontrada')));
      await expectLater(
        missing.delete('x'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      final offline = repo(FakeHttpAdapter(networkFailure));
      await expectLater(
        offline.create(inputOf, localId: 'm-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.network)),
      );
    });

    test('respuesta de create sin transaction es ContractException', () async {
      final http = FakeHttpAdapter((_) => jsonBody(201, {'alert': null}));
      await expectLater(repo(http).create(inputOf, localId: 'm-1'), throwsA(isA<ContractException>()));
    });
  });
}

const inputOf = MovementInput(
  type: MovementType.expense,
  amount: 12500,
  description: 'Almuerzo',
  date: '2026-11-21',
);
