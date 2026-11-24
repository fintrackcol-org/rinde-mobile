// Pagos recurrentes (bloque 4C) contra el ApiClient real y un adaptador falso: contrato de calendario,
// pagos y «Ya lo pagué», un envío a la vez, «en duda» verificado leyendo, conflicto y 404 al editar,
// «Tu sueldo» con el saldo releído, reglas puras, refresco y aislamiento por cuenta.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/application/money_writer.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/domain/commitment_rules.dart';
import 'package:rinde_mobile/features/money/domain/income_rules.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

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

final _today = DateTime(2026, 11, 22, 10);

/// La cola guardada, que no responde hasta abrir [gate].
class _SlowStore extends MemoryJsonListStore {
  final gate = Completer<void>();

  @override
  Future<List<Object?>?> read(String userId) async {
    await gate.future;
    return super.read(userId);
  }
}

/// Un pago fijo de cada mes como lo manda GET /money-profile.
Map<String, dynamic> _arriendo({String name = 'Arriendo', num amount = 900000, int day = 5}) => {
  'id': 'c1',
  'name': name,
  'amount': amount,
  'dayOfMonth': day,
  'kind': 'fixed',
  'frequency': 'monthly',
  'month': null,
  'reminder': {
    'daysBefore': [1],
    'time': null,
    'channel': 'push',
  },
};

Map<String, dynamic> _profile({
  List<Map<String, dynamic>> commitments = const [],
  num? balance = 500000,
  String? balanceAt = '2026-11-01T05:00:00.000Z',
  String? incomeType = 'fecha_fija',
  List<int> payDays = const [15, 30],
  int? version,
}) => {
  'incomeType': incomeType,
  'payDays': payDays,
  'balance': balance,
  'balanceAt': balanceAt,
  'money': 412300,
  'totals': {'income': 700000, 'expense': 287700},
  'welcomeDone': true,
  'tutorialDone': true,
  'commitments': commitments,
  'subscriptions': {'count': 0, 'monthly': 0},
  'version': ?version,
};

/// GET /money-profile/calendar con todo tipo de eventos: solo los `compromiso` cuentan.
const _calendar = {
  'month': '2026-11',
  'today': '2026-11-22',
  'money': 412300,
  'projectedUntil': '2026-11-30',
  'events': [
    {
      'date': '2026-11-05',
      'kind': 'compromiso',
      'id': 'c1',
      'name': 'Arriendo',
      'amount': 900000,
      'status': 'pagado',
      'balanceAfter': null,
      'risk': null,
      'subscription': false,
    },
    {
      'date': '2026-11-10',
      'kind': 'compromiso',
      'id': 'c2',
      'name': 'Internet',
      'amount': 65000.5,
      'status': 'atrasado',
      'balanceAfter': 347299.5,
      'risk': 'ok',
      'subscription': false,
    },
    {
      'date': '2026-11-15',
      'kind': 'ingreso',
      'id': null,
      'name': 'Día de pago',
      'amount': null,
      'status': null,
      'balanceAfter': null,
      'risk': null,
    },
    {
      'date': '2026-11-20',
      'kind': 'card',
      'id': 't1',
      'name': 'Visa',
      'amount': 180000,
      'status': 'pendiente',
      'balanceAfter': 167299.5,
      'risk': 'riesgo',
    },
    {
      'date': '2026-11-28',
      'kind': 'compromiso',
      'id': 'c3',
      'name': 'Netflix',
      'amount': 26900.25,
      'status': 'pendiente',
      'balanceAfter': 140399.25,
      'risk': 'ok',
      'subscription': true,
    },
    // Mal formado: sin monto. No se pinta como 0.
    {'date': '2026-11-29', 'kind': 'compromiso', 'id': 'c4', 'name': 'Raro', 'status': 'pendiente'},
  ],
  'cardDates': [],
  'totals': {'pending': 271900.75, 'paid': 900000},
};

/// Lo que manda el formulario de un pago (readCommitment).
const _form = {
  'name': 'Arriendo',
  'amount': 950000,
  'dayOfMonth': 5,
  'kind': 'fixed',
  'frequency': 'monthly',
  'month': null,
};

Never _timeout(RequestOptions options) =>
    throw DioException.receiveTimeout(timeout: const Duration(seconds: 45), requestOptions: options);

Map<String, dynamic> _sent(RequestOptions r) => Map<String, dynamic>.from(r.data as Map);

void main() {
  late SessionHolder holder;
  late FakeHomeRepository home;
  late MemoryJsonListStore queue;
  late MemoryJsonListStore dismissed;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_ana));
    await holder.load();
    home = FakeHomeRepository();
    queue = MemoryJsonListStore();
    dismissed = MemoryJsonListStore();
  });

  tearDown(() => holder.dispose());

  Future<ProviderContainer> open(
    MoneyRepository repo, {
    MovementsRepository? movements,
    DraftStore? drafts,
  }) async {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        moneyRepositoryProvider.overrideWithValue(repo),
        if (movements != null) movementsRepositoryProvider.overrideWithValue(movements),
        homeRepositoryProvider.overrideWithValue(home),
        clockProvider.overrideWithValue(() => _today),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
        pendingStoreProvider.overrideWithValue(queue),
        dismissedStoreProvider.overrideWithValue(dismissed),
      ],
    );
    await c.read(sessionControllerProvider.future);
    return c;
  }

  Future<(ProviderContainer, FakeHttpAdapter)> openApi(FakeHandler handler, {DraftStore? drafts}) async {
    final adapter = FakeHttpAdapter(handler);
    final api = ApiClient(config: _qa, session: holder, adapter: adapter);
    final c = await open(ApiMoneyRepository(api), movements: ApiMovementsRepository(api), drafts: drafts);
    return (c, adapter);
  }

  List<String> calls(FakeHttpAdapter adapter) => [for (final r in adapter.requests) '${r.method} ${r.path}'];

  group('contrato', () {
    test(
      'GET /money-profile/calendar?month=: solo los pagos fijos; tarjetas, ingresos y lo mal formado no',
      () async {
        final (c, adapter) = await openApi((_) => jsonBody(200, _calendar));
        final payments = await c.read(paymentCalendarProvider(c.read(accountProvider)).future);
        expect(adapter.requests.single.path, '/money-profile/calendar');
        expect(adapter.requests.single.queryParameters, {'month': '2026-11'});
        expect(payments.map((p) => (p.id, p.name, p.amount, p.date, p.status, p.subscription)), [
          ('c1', 'Arriendo', 900000, '2026-11-05', 'pagado', false),
          ('c2', 'Internet', 65000.5, '2026-11-10', 'atrasado', false),
          ('c3', 'Netflix', 26900.25, '2026-11-28', 'pendiente', true),
        ]);
      },
    );

    test(
      'tarjetas, cuentas, cobros y cardDates no cambian «Falta por pagar» ni la lista (MoneyPayments.jsx)',
      () async {
        Future<List<CalendarPayment>> read(Map<String, Object?> calendar) async {
          final (c, _) = await openApi((_) => jsonBody(200, calendar));
          return c.read(paymentCalendarProvider(c.read(accountProvider)).future);
        }

        final events = _calendar['events']! as List;
        final only = await read({
          ..._calendar,
          'events': [
            for (final e in events)
              if ((e as Map)['kind'] == 'compromiso') e,
          ],
        });
        Map<String, Object?> event(String kind, String id, num amount, String status) => {
          'date': '2026-11-25',
          'kind': kind,
          'id': id,
          'name': 'Tío Jorge',
          'amount': amount,
          'status': status,
          'balanceAfter': null,
          'risk': null,
        };
        final mixed = await read({
          ..._calendar,
          'events': [
            ...events,
            event('card', 't2', 50000, 'atrasado'),
            event('cuenta', 'd1', 120000, 'pendiente'),
            event('cobro', 'd2', 60000, 'pendiente'),
          ],
          'cardDates': [
            {...event('corte', 't1', 0, 'pendiente'), 'amount': null, 'status': null},
            {...event('limite', 't2', 0, 'pendiente'), 'amount': null, 'status': null},
          ],
          // Lo que el servidor suma con tarjetas y cuentas: la app no lo usa.
          'totals': {'pending': 501900.75, 'paid': 900000},
        });
        expect([for (final p in mixed) p.id], [for (final p in only) p.id]);
        expect(paymentTotals(mixed), paymentTotals(only));
        expect(paymentTotals(mixed), (pending: 91900.75, paid: 900000));
      },
    );

    test('POST /commitments: siempre con kind, frequency y month, y nunca reminder', () async {
      final (c, adapter) = await openApi((_) => jsonBody(201, {..._form, 'id': 'nuevo'}));
      final yearly = readCommitment(
        const CommitmentItem(
          key: 'k',
          name: ' Seguro ',
          amount: '1200000',
          dayOfMonth: '5',
          kind: 'subscription',
          frequency: 'yearly',
          month: 3,
        ),
      ).data!;
      await c.read(moneyWriterProvider).createCommitment(yearly);
      final body = _sent(adapter.requests.single);
      expect(body, {
        'name': 'Seguro',
        'amount': 1200000,
        'dayOfMonth': 5,
        'kind': 'subscription',
        'frequency': 'yearly',
        'month': 3,
      });
      expect(body.containsKey('reminder'), isFalse);
    });

    test(
      'PUT /commitments/:id: lee antes, manda el pago completo y sin reminder (el aviso no se toca)',
      () async {
        final opened = Commitment.tryParse(_arriendo())!;
        final (c, adapter) = await openApi(
          (o) => o.method == 'GET'
              ? jsonBody(200, _profile(commitments: [_arriendo()]))
              : jsonBody(200, {..._form, 'id': 'c1'}),
        );
        await c.read(moneyWriterProvider).updateCommitment(opened, _form);
        expect(calls(adapter), ['GET /money-profile', 'PUT /money-profile/commitments/c1']);
        final body = _sent(adapter.requests.last);
        expect(body, _form);
        expect(body.keys, containsAll(['kind', 'frequency', 'month']));
        expect(body.containsKey('reminder'), isFalse);
      },
    );

    for (final status in [204, 404]) {
      test('DELETE /commitments/:id con $status: borrado', () async {
        final (c, adapter) = await openApi(
          (_) => status == 204
              ? ResponseBody.fromString('', 204)
              : errorBody(404, 'NOT_FOUND', 'Compromiso no encontrado'),
        );
        await c.read(moneyWriterProvider).deleteCommitment('c1');
        expect(calls(adapter), ['DELETE /money-profile/commitments/c1']);
      });
    }

    test(
      '«Ya lo pagué»: POST /transactions con el nombre exacto, el monto, hoy, sin categoría y localId',
      () async {
        final (c, adapter) = await openApi(
          (o) => jsonBody(201, {
            'transaction': {
              'id': 't1',
              'type': 'gasto',
              'amount': 65000.5,
              'description': 'Internet Claro',
              'category': 'servicios_publicos',
              'source': 'manual',
              'date': '2026-11-22',
            },
          }),
        );
        await c
            .read(moneyWriterProvider)
            .markPaid(key: 'c2-2026-11-10', name: 'Internet Claro', amount: 65000.5);
        final r = adapter.requests.single;
        expect('${r.method} ${r.path}', 'POST /transactions');
        final body = _sent(r);
        expect(body..remove('localId'), {
          'type': 'gasto',
          'amount': 65000.5,
          'description': 'Internet Claro',
          'date': '2026-11-22',
          'category': null,
        });
        expect(jsonDecode(jsonEncode(r.data))['localId'], matches(RegExp(r'^m-[0-9a-f]{32}$')));
      },
    );

    test(
      '«Tu sueldo»: GET y luego PUT con el saldo releído, sin resetBalance y con expectedVersion',
      () async {
        final opened = MoneyProfile.fromJson(_profile(version: 7));
        final (c, adapter) = await openApi(
          (o) => o.method == 'GET'
              // Otra pantalla corrigió el saldo después de abrir: se manda el nuevo, no el viejo.
              ? jsonBody(200, _profile(balance: 800000, balanceAt: '2026-11-21T15:00:00.000Z', version: 7))
              : jsonBody(200, _profile(incomeType: 'sin_fecha', payDays: [], version: 8)),
        );
        await c.read(moneyWriterProvider).saveIncomeType(opened, 'sin_fecha', const [15]);
        expect(calls(adapter), ['GET /money-profile', 'PUT /money-profile']);
        expect(_sent(adapter.requests.last), {
          'incomeType': 'sin_fecha',
          'payDays': <int>[],
          'balance': 800000,
          'expectedVersion': 7,
        });
      },
    );
  });

  group('pagos: un envío a la vez y en duda', () {
    test('dos toques en «Guardar pago»: un solo POST', () async {
      final answer = Completer<void>();
      final (c, adapter) = await openApi((o) async {
        await answer.future;
        return jsonBody(201, {..._form, 'id': 'nuevo'});
      });
      final writer = c.read(moneyWriterProvider);
      final first = writer.createCommitment(_form);
      final second = writer.createCommitment(_form);
      await pumpEventQueue();
      answer.complete();
      await Future.wait([first, second]);
      expect(adapter.to('/money-profile/commitments'), hasLength(1));
    });

    test('POST en duda → GET → ya está (sin mayúsculas, día y monto) → listo, sin segundo POST', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'POST'
            ? _timeout(o)
            : jsonBody(200, _profile(commitments: [_arriendo(name: 'ARRIENDO', amount: 950000)])),
      );
      await c.read(moneyWriterProvider).createCommitment(_form);
      expect(calls(adapter), ['POST /money-profile/commitments', 'GET /money-profile']);
    });

    test('editar: si el pago cambió en otro lado desde que se abrió, no se envía y se recarga', () async {
      final opened = Commitment.tryParse(_arriendo())!;
      final (c, adapter) = await openApi(
        (_) => jsonBody(200, _profile(commitments: [_arriendo(amount: 1000000)])),
      );
      await expectLater(
        c.read(moneyWriterProvider).updateCommitment(opened, _form),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.profileChanged)),
      );
      expect(calls(adapter), ['GET /money-profile']);
    });

    test('editar: si ya no está, 404 sin PUT', () async {
      final opened = Commitment.tryParse(_arriendo())!;
      final (c, adapter) = await openApi((_) => jsonBody(200, _profile()));
      await expectLater(
        c.read(moneyWriterProvider).updateCommitment(opened, _form),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      expect(calls(adapter), ['GET /money-profile']);
    });

    test('editar: el 404 del servidor llega tal cual (la hoja se cierra)', () async {
      final opened = Commitment.tryParse(_arriendo())!;
      final (c, _) = await openApi(
        (o) => o.method == 'GET'
            ? jsonBody(200, _profile(commitments: [_arriendo()]))
            : errorBody(404, 'NOT_FOUND', 'Compromiso no encontrado'),
      );
      await expectLater(
        c.read(moneyWriterProvider).updateCommitment(opened, _form),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });

    test('editar en duda: relee y, si ya es lo enviado, listo sin segundo PUT', () async {
      final opened = Commitment.tryParse(_arriendo())!;
      var reads = 0;
      final (c, adapter) = await openApi((o) {
        if (o.method == 'PUT') return _timeout(o);
        reads++;
        return jsonBody(200, _profile(commitments: [reads == 1 ? _arriendo() : _arriendo(amount: 950000)]));
      });
      await c.read(moneyWriterProvider).updateCommitment(opened, _form);
      expect(calls(adapter), [
        'GET /money-profile',
        'PUT /money-profile/commitments/c1',
        'GET /money-profile',
      ]);
    });

    test('editar en duda sin confirmar y repetir: lo guardado ya es lo enviado, se reenvía igual', () async {
      final opened = Commitment.tryParse(_arriendo())!;
      var reads = 0;
      final (c, adapter) = await openApi((o) {
        if (o.method == 'PUT') return _timeout(o);
        reads++;
        // 1: comprobación previa; 2: la relectura en duda también falla; 3+: el PUT sí había llegado.
        if (reads == 2) return networkFailure(o);
        return jsonBody(200, _profile(commitments: [_arriendo(amount: reads == 1 ? 900000 : 950000)]));
      });
      final writer = c.read(moneyWriterProvider);
      await expectLater(
        writer.updateCommitment(opened, _form),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.timeout)),
      );
      await writer.updateCommitment(opened, _form);
      expect(adapter.to('/money-profile/commitments/c1'), hasLength(2));
    });

    test('borrar en duda: relee y, si ya no está, listo', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'DELETE' ? errorBody(502, 'BAD_GATEWAY', 'x') : jsonBody(200, _profile()),
      );
      await c.read(moneyWriterProvider).deleteCommitment('c1');
      expect(calls(adapter), ['DELETE /money-profile/commitments/c1', 'GET /money-profile']);
    });

    for (final (status, code, message) in [
      (409, 'COMMITMENT_EXISTS', 'Ya tienes un compromiso con ese nombre'),
      (409, 'COMMITMENT_LIMIT', 'Puedes tener hasta 30 compromisos'),
      (401, 'UNAUTHORIZED', 'No autorizado'),
    ]) {
      test('$status $code no está en duda: llega tal cual, sin releer', () async {
        final (c, adapter) = await openApi((_) => errorBody(status, code, message));
        await expectLater(
          c.read(moneyWriterProvider).createCommitment(_form),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', status)),
        );
        expect(calls(adapter).where((call) => call.contains('/money-profile')), [
          'POST /money-profile/commitments',
        ]);
      });
    }

    test('con una bienvenida a medias no se crea, edita, borra ni paga nada', () async {
      final drafts = MemoryDraftStore();
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      final (c, adapter) = await openApi(
        (_) => jsonBody(200, _profile(commitments: [_arriendo()])),
        drafts: drafts,
      );
      final writer = c.read(moneyWriterProvider);
      final blocked = throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending));
      await expectLater(writer.createCommitment(_form), blocked);
      await expectLater(writer.updateCommitment(Commitment.tryParse(_arriendo())!, _form), blocked);
      await expectLater(writer.deleteCommitment('c1'), blocked);
      await expectLater(writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000), blocked);
      expect(adapter.requests, isEmpty);
    });
  });

  group('«Ya lo pagué»', () {
    test('dos veces sin conexión: un solo gasto en la cola', () async {
      final (c, adapter) = await openApi(networkFailure);
      final writer = c.read(moneyWriterProvider);
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      final pending = await c.read(pendingMovementsProvider.future);
      expect(pending.items, hasLength(1));
      expect(pending.items.single.input.description, 'Internet');
      // El segundo ni salió: ya estaba en la cola.
      expect(adapter.to('/transactions'), hasLength(1));
      expect(queuedPayment(pending, name: 'Internet', amount: 65000, date: '2026-11-22'), isTrue);
      // Como el servidor: cualquier gasto del mes con su nombre lo da por pagado; uno de otro mes, no.
      expect(queuedPayment(pending, name: 'Internet', amount: 65000, date: '2026-11-29'), isTrue);
      expect(queuedPayment(pending, name: 'Internet', amount: 65000, date: '2026-12-02'), isFalse);
      expect(queuedPayment(pending, name: 'internet', amount: 65000, date: '2026-11-22'), isFalse);
    });

    test('sin conexión ayer y aún en la cola: hoy no se anota otro', () async {
      final (c, adapter) = await openApi(networkFailure);
      await c
          .read(pendingMovementsProvider.notifier)
          .enqueue(
            'm-ayer',
            const MovementInput(
              type: MovementType.expense,
              amount: 65000,
              description: 'Internet',
              date: '2026-11-21',
            ),
          );
      await c.read(moneyWriterProvider).markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      expect((await c.read(pendingMovementsProvider.future)).items.map((p) => p.localId), ['m-ayer']);
      expect(adapter.requests, isEmpty);
    });

    test('si otra cuenta entra mientras se lee la cola, no se anota nada con la suya', () async {
      final slow = _SlowStore();
      queue = slow;
      final (c, adapter) = await openApi((_) => jsonBody(201, {}));
      final paying = c
          .read(moneyWriterProvider)
          .markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      await pumpEventQueue();
      await holder.save(_beto);
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      await pumpEventQueue();
      slow.gate.complete();
      await expectLater(paying, throwsStateError);
      expect(adapter.to('/transactions'), isEmpty);
    });

    test('pagado pero el calendario nuevo no llegó: otro toque no anota otro gasto, solo recarga', () async {
      final repo = FakeMoneyRepository();
      final movements = FakeMovementsRepository();
      final c = await open(repo, movements: movements);
      final account = c.read(accountProvider);
      c.listen(paymentCalendarProvider(account), (_, _) {});
      await c.read(paymentCalendarProvider(account).future);
      var fail = true;
      repo.onCalendar = (_) async => fail ? throw const ApiException(code: ApiCodes.network) : const [];
      final writer = c.read(moneyWriterProvider);
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      expect(movements.localIds, hasLength(1));
      expect(repo.count('calendar'), 3);
      // Ya llegó lo nuevo: si el servidor lo sigue dando por pagar, el siguiente toque sí anota.
      fail = false;
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      expect(movements.localIds, hasLength(2));
    });

    test('un reintento tras un error usa el mismo localId; el siguiente toque, uno nuevo', () async {
      var fail = true;
      final (c, adapter) = await openApi(
        (o) => fail
            ? errorBody(500, 'INTERNAL_ERROR', 'Error')
            : jsonBody(201, {
                'transaction': {
                  'id': 't1',
                  'type': 'gasto',
                  'amount': 65000,
                  'description': 'Internet',
                  'category': null,
                  'source': 'manual',
                  'date': '2026-11-22',
                },
              }),
      );
      final writer = c.read(moneyWriterProvider);
      String localId(int i) => _sent(adapter.requests[i])['localId'] as String;
      await expectLater(
        writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000),
        throwsA(isA<ApiException>()),
      );
      fail = false;
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      expect(localId(1), localId(0));
      await writer.markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      expect(localId(2), isNot(localId(0)));
    });

    test('después de pagar se vuelven a pedir el plan, el calendario y el perfil', () async {
      final repo = FakeMoneyRepository();
      final c = await open(repo, movements: FakeMovementsRepository());
      final account = c.read(accountProvider);
      c.listen(moneyProfileProvider(account), (_, _) {});
      c.listen(paymentCalendarProvider(account), (_, _) {});
      c.listen(homePlanProvider(account), (_, _) {});
      await c.read(moneyProfileProvider(account).future);
      await c.read(paymentCalendarProvider(account).future);
      await c.read(homePlanProvider(account).future);
      await c.read(moneyWriterProvider).markPaid(key: 'c2-2026-11-10', name: 'Internet', amount: 65000);
      await c.read(moneyProfileProvider(account).future);
      await c.read(paymentCalendarProvider(account).future);
      await c.read(homePlanProvider(account).future);
      expect((repo.count('profile'), repo.count('calendar'), home.count('plan')), (2, 2, 2));
    });

    test('en la demostración no se anota (el plan no lo daría por pagado)', () async {
      final repo = _DemoFake();
      final c = await open(repo);
      await expectLater(
        c.read(moneyWriterProvider).markPaid(key: 'c-x', name: 'Internet', amount: 1),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
      );
      expect((await c.read(pendingMovementsProvider.future)).items, isEmpty);
    });
  });

  group('«Tu sueldo» (PUT /money-profile)', () {
    test('cuenta real sin version: no hay PUT por ningún camino', () async {
      final (c, adapter) = await openApi((_) => jsonBody(200, _profile()));
      await expectLater(
        c.read(moneyWriterProvider).saveIncomeType(MoneyProfile.fromJson(_profile()), 'sin_fecha', const []),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
    });

    test('si el perfil cambió desde que se abrió: no se envía y se dice', () async {
      final (c, adapter) = await openApi((_) => jsonBody(200, _profile(payDays: [30], version: 7)));
      await expectLater(
        c
            .read(moneyWriterProvider)
            .saveIncomeType(MoneyProfile.fromJson(_profile(version: 7)), 'sin_fecha', const []),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.profileChanged)),
      );
      expect(calls(adapter), ['GET /money-profile']);
    });

    test('en duda: relee y, si el tipo y los días ya son los enviados, listo sin segundo PUT', () async {
      var reads = 0;
      final (c, adapter) = await openApi((o) {
        if (o.method == 'PUT') return _timeout(o);
        reads++;
        return jsonBody(200, reads == 1 ? _profile(version: 7) : _profile(payDays: [1, 15], version: 8));
      });
      await c.read(moneyWriterProvider).saveIncomeType(
        MoneyProfile.fromJson(_profile(version: 7)),
        'fecha_fija',
        const [1, 15],
      );
      expect(calls(adapter), ['GET /money-profile', 'PUT /money-profile', 'GET /money-profile']);
    });

    test('en duda sin confirmar: «No pudimos confirmar si se guardó…»', () async {
      final (c, _) = await openApi(
        (o) => o.method == 'PUT' ? _timeout(o) : jsonBody(200, _profile(version: 7)),
      );
      await expectLater(
        c
            .read(moneyWriterProvider)
            .saveIncomeType(MoneyProfile.fromJson(_profile(version: 7)), 'sin_fecha', const []),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
    });
  });

  group('reglas', () {
    const es = Tr('es', {});
    test('totales en centavos: lo atrasado cuenta como pendiente; tarjetas e ingresos no llegan', () {
      final totals = paymentTotals(CalendarPayment.listFromJson(_calendar));
      expect(totals.pending, 91900.75);
      expect(totals.paid, 900000);
      // Sin residuos de coma flotante (0.1 + 0.2).
      final cents = paymentTotals([
        for (final (i, amount) in [0.1, 0.2].indexed)
          CalendarPayment(id: '$i', name: '$i', amount: amount, date: '2026-11-01', status: 'pendiente'),
      ]);
      expect(cents.pending, 0.3);
      expect(paymentTotals(const []), (pending: 0, paid: 0));
    });

    test('payableNow: solo lo del mes en curso', () {
      final today = DateTime(2026, 11, 30);
      expect(payableNow('2026-11-30', today), isTrue);
      expect(payableNow('2026-11-01', today), isTrue);
      expect(payableNow('2026-12-01', today), isFalse);
      expect(payableNow('2025-11-30', today), isFalse);
    });

    test('dismissKey lleva la fecha: el mes siguiente es otra clave', () {
      expect(dismissKey('c1', '2026-11-05'), 'c1-2026-11-05');
      expect(dismissKey('c1', '2026-12-05'), isNot(dismissKey('c1', '2026-11-05')));
    });

    test('commitmentWhen: «día 20» y «cada año, el 5 de marzo» (mes en el idioma de la app)', () {
      const monthly = Commitment(id: 'a', name: 'a', amount: 1, dayOfMonth: 20);
      const yearly = Commitment(id: 'b', name: 'b', amount: 1, dayOfMonth: 5, frequency: 'yearly', month: 3);
      expect(commitmentWhen(monthly, es, kDefaultRegion), 'día 20');
      expect(commitmentWhen(yearly, es, kDefaultRegion), 'cada año, el 5 de marzo');
      const en = Tr('en', {'cada año, el {dayOfMonth} de {v2}': 'every year, on {v2} {dayOfMonth}'});
      expect(
        commitmentWhen(yearly, en, const Region(country: 'US', currency: 'USD', language: 'en')),
        'every year, on March 5',
      );
    });

    test('incomeSummary: sin fecha, sin decir, un día y varios', () {
      MoneyProfile of(String? type, List<int> days) =>
          MoneyProfile(welcomeDone: true, incomeType: type, payDays: days);
      expect(incomeSummary(of('sin_fecha', const []), es), 'Sin fecha fija');
      expect(incomeSummary(of(null, const []), es), 'Aún no nos has dicho');
      expect(incomeSummary(of('fecha_fija', const [15]), es), 'Con fecha fija, el día 15');
      expect(incomeSummary(of('fecha_fija', const [1, 15, 30]), es), 'Con fecha fija, los días 1, 15 y 30');
    });

    test('readCommitment: los cuatro mensajes de la web en su orden', () {
      ({Map<String, dynamic>? data, CommitmentProblem? problem}) read({
        String name = 'Seguro',
        String amount = '10',
        String day = '5',
        String frequency = 'yearly',
        int? month,
      }) => readCommitment(
        CommitmentItem(
          key: 'k',
          name: name,
          amount: amount,
          dayOfMonth: day,
          frequency: frequency,
          month: month,
        ),
      );
      expect(read(name: ' ', amount: '', day: '').problem!.message, 'Escribe el nombre del pago.');
      expect(read(amount: '0', day: '').problem!.message, 'Escribe cuánto pagas por {cleanName}.');
      for (final day in ['0', '32', '']) {
        expect(read(day: day).problem!.message, 'Escribe un día entre 1 y 31 para {cleanName}.', reason: day);
      }
      final yearly = read().problem!;
      expect(es(yearly.message, yearly.vars), 'Elige en qué mes se cobra Seguro.');
      expect(read(month: 13).problem, isNotNull);
      expect(read(month: 12).data!['month'], 12);
      // Mensual: el mes no viaja aunque el formulario lo tenga.
      expect(read(frequency: 'monthly', month: 3).data!['month'], isNull);
    });

    test('nombre de 61 caracteres: se recorta a 60', () {
      expect(clipCommitmentName('a' * 61), 'a' * 60);
    });
  });

  test('aislamiento: los avisos que cerró A no ocultan los de B', () async {
    final c = await open(FakeMoneyRepository());
    await c.read(dismissedPaymentsProvider.future);
    await c.read(dismissedPaymentsProvider.notifier).dismiss('c1-2026-11-05');
    expect(await c.read(dismissedPaymentsProvider.future), {'c1-2026-11-05'});
    (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
    await pumpEventQueue();
    expect(await c.read(dismissedPaymentsProvider.future), isEmpty);
    expect(jsonDecode(dismissed.data['a']!), ['c1-2026-11-05']);
    expect(dismissed.data['b'], isNull);
  });

  test('un aviso cerrado se guarda; si no se pudo leer lo guardado, no se pisa', () async {
    dismissed.failReads = true;
    final c = await open(FakeMoneyRepository());
    await c.read(dismissedPaymentsProvider.future);
    await c.read(dismissedPaymentsProvider.notifier).dismiss('c1-2026-11-05');
    expect(await c.read(dismissedPaymentsProvider.future), {'c1-2026-11-05'});
    expect(dismissed.data, isEmpty);
  });
}

/// Un repositorio de demostración mínimo: solo dice que lo es.
class _DemoFake extends FakeMoneyRepository {
  @override
  bool get isDemo => true;
}
