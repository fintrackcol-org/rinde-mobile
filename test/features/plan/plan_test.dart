// Planear (etapa 7): lectura del calendario completo y del motor de liquidez, las reglas de pintado
// (sin recalcular plata: solo agrupar y elegir colores, el total de un día en centavos), el writer de
// presupuestos (un envío a la vez, en duda se relee, 404 al borrar = hecho, bienvenida pendiente
// bloquea, aislamiento por cuenta) y la demo (recorridos guardan, fijos dan demoNoBackend, la
// proyección dice lo mismo que el plan del Inicio).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/demo_home_repository.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/data/demo_money_repository.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/plan/application/budgets_writer.dart';
import 'package:rinde_mobile/features/plan/application/plan_providers.dart';
import 'package:rinde_mobile/features/plan/data/budgets_repository.dart';
import 'package:rinde_mobile/features/plan/data/demo_budgets_repository.dart';
import 'package:rinde_mobile/features/plan/data/plan_models.dart';
import 'package:rinde_mobile/features/plan/domain/plan_rules.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_money_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co'),
  accessToken: 'b',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() async => const SessionState(session: _ana);

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

/// Escrituras de presupuestos a la medida; guarda cada envío.
class _FakeBudgets implements BudgetsRepository {
  final sent = <String>[];
  Future<void> Function() onSend = () async {};

  @override
  bool get isDemo => false;

  @override
  Future<void> create({required String category, required String month, required num amount}) {
    sent.add('POST $category $month $amount');
    return onSend();
  }

  @override
  Future<void> update(String id, num amount) {
    sent.add('PUT $id $amount');
    return onSend();
  }

  @override
  Future<void> delete(String id) {
    sent.add('DELETE $id');
    return onSend();
  }
}

const _tr = Tr('es', {});
const _co = Region(country: 'CO', language: 'es', currency: 'COP');

const _timeout = ApiException(code: ApiCodes.timeout, serverMessage: 'Se venció la espera');

BudgetStatus _budget(String category, num amount, num consumed, num percentage, BudgetLevel level) =>
    BudgetStatus(
      id: 'p-$category',
      category: category,
      amount: amount,
      consumed: consumed,
      percentage: percentage,
      level: level,
    );

void main() {
  group('modelos', () {
    test(
      'el calendario completo trae pagos, tarjetas, cuentas y cortes; los pagos fijos, con el modelo de Mi '
      'plata',
      () {
        final calendar = PaymentCalendar.fromJson({
          'month': '2026-11',
          'today': '2026-11-22',
          'money': 412300,
          'projectedUntil': '2026-11-30',
          'events': [
            {
              'date': '2026-11-25',
              'kind': 'compromiso',
              'id': 'c1',
              'name': 'Internet',
              'amount': 65000,
              'status': 'pendiente',
              'balanceAfter': 347300,
              'risk': 'ok',
            },
            {
              'date': '2026-11-26',
              'kind': 'cobro',
              'id': 'd1',
              'name': 'Laura',
              'amount': 20000,
              'status': 'pendiente',
            },
            {'date': 'mal', 'kind': 'card', 'name': 'Visa'},
          ],
          'cardDates': [
            {
              'date': '2026-11-28',
              'kind': 'corte',
              'id': 't1',
              'name': 'Visa',
              'amount': null,
              'status': null,
            },
          ],
          'totals': {'pending': 65000, 'paid': 0},
        });
        expect((calendar.money, calendar.pending, calendar.projectedUntil), (412300, 65000, '2026-11-30'));
        expect([for (final e in calendar.events) e.kind], ['compromiso', 'cobro']);
        expect((calendar.events.first.balanceAfter, calendar.events.last.isInflow), (347300, true));
        expect(calendar.cardDates.single.isCardDate, isTrue);
        expect(calendar.payments.single.name, 'Internet');
      },
    );

    test('liquidez: sin Mi plata, `ready: false`; lista, con el hueco y lo que me deben aparte', () {
      expect(Liquidity.fromJson({'ready': false, 'today': '2026-11-22'}).ready, isFalse);
      final l = Liquidity.fromJson({
        'ready': true,
        'today': '2026-11-22',
        'money': 180000,
        'pace': null,
        'until': '2026-11-30',
        'days': [
          {'date': '2026-11-22', 'end': 180000, 'events': []},
          {
            'date': '2026-11-23',
            'end': -48000,
            'events': [
              {'kind': 'compromiso', 'name': 'PILA', 'amount': 228000, 'date': '2026-11-23'},
            ],
          },
        ],
        'firstShortfall': {
          'date': '2026-11-23',
          'missing': 48000,
          'causes': [
            {'kind': 'compromiso', 'name': 'PILA', 'amount': 228000, 'date': '2026-11-23'},
          ],
        },
        'lowest': {'date': '2026-11-23', 'amount': -48000},
        'risk': 'falta',
        'safeDailySpend': 0,
        'receivable': 60000,
        'assumptions': ['No contamos ingresos futuros: solo la plata que ya tienes.'],
      });
      expect((l.risk, l.firstShortfall!.missing, l.receivable, l.hasData), ('falta', 48000, 60000, true));
      // Lo que me deben no se suma: solo sale como sugerencia.
      expect(avoidTips(l, _tr, (v) => '\$$v'), [
        'Cobra lo que te deben (\$60000): con eso llegas.',
        'Mira si puedes correr unos días «PILA».',
      ]);
      expect(liquidityMessage(l, _tr, _co, (v) => '\$$v').title, 'El 23 de noviembre te faltan \$48000');
    });
  });

  group('reglas', () {
    test('cada día suma lo que falta pagar en centavos; lo pagado, lo que entra y los cortes no suman', () {
      CalendarEvent e(String kind, num? amount, {String? status, String? risk}) => CalendarEvent(
        date: '2026-11-10',
        kind: kind,
        name: 'x',
        amount: amount,
        status: status,
        risk: risk,
      );
      final cells = calendarCells('2026-11', [
        e('compromiso', 0.1, status: 'pendiente', risk: 'ok'),
        e('compromiso', 0.2, status: 'pendiente', risk: 'riesgo'),
        e('card', 50000, status: 'pagado'),
        e('cobro', 20000, status: 'pendiente'),
        e('corte', null),
      ], '2026-11-22');
      // Noviembre de 2026 empieza en domingo: seis huecos antes del 1.
      expect(cells.take(6), everyElement(isNull));
      final day = cells.whereType<CalendarCell>().firstWhere((c) => c.day == 10);
      expect((day.total, day.count, day.tone, day.isPast), (0.3, 5, CalendarTone.risk, true));
      expect(shortMoney(89000, _tr), '89 mil');
      expect(shortMoney(1250000, _tr), '1,3 M');
    });

    test('lo más grave manda: atrasado es rojo aunque el saldo alcance; lo pagado no tiene color', () {
      expect(
        toneOf(
          const CalendarEvent(
            date: '2026-11-01',
            kind: 'compromiso',
            name: 'x',
            status: 'atrasado',
            risk: 'ok',
          ),
        ),
        CalendarTone.negative,
      );
      expect(
        toneOf(const CalendarEvent(date: '2026-11-01', kind: 'compromiso', name: 'x', status: 'pagado')),
        isNull,
      );
      expect(
        toneOf(const CalendarEvent(date: '2026-11-01', kind: 'compromiso', name: 'x', status: 'pendiente')),
        (CalendarTone.payment),
      );
    });

    test('aviso de presupuestos: pasarse gana a «justo en el límite» y este a «cerca del 80 %»', () {
      final warn = _budget('ocio', 100, 85, 85, BudgetLevel.warning);
      final limit = _budget('comida', 100, 100, 100, BudgetLevel.exceeded);
      final over = _budget('taxi', 100, 120, 120, BudgetLevel.exceeded);
      final names = {'ocio': 'Ocio', 'comida': 'Comida', 'taxi': 'Taxi'};
      expect(budgetAlert([warn], names, _tr, _co)!.message, 'Ocio va en 85 % del límite.');
      expect(
        budgetAlert([warn, limit], names, _tr, _co)!.message,
        'Ya usaste todo tu presupuesto de Comida.',
      );
      expect(budgetAlert([warn, limit, over], names, _tr, _co), (
        message: 'Te pasaste del presupuesto de Taxi.',
        exceeded: true,
      ));
      expect(budgetAlert([_budget('x', 100, 10, 10, BudgetLevel.none)], names, _tr, _co), isNull);
      expect(budgetPercent(106.25, _co), '106,25 %');
      final total = budgetsTotal([
        _budget('a', 0.1, 0.2, 200, BudgetLevel.exceeded),
        _budget('b', 0.2, 0.1, 50, BudgetLevel.none),
      ]);
      expect((total.limit, total.spent, total.share), (0.3, 0.3, 1.0));
      expect((shiftMonth('2026-01', -1), shiftMonth('2026-12', 1)), ('2025-12', '2027-01'));
    });
  });

  group('BudgetsWriter', () {
    late FakeHomeRepository home;
    late _FakeBudgets budgets;
    late MemoryDraftStore drafts;

    ProviderContainer open() {
      final c = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          sessionControllerProvider.overrideWith(_Sessions.new),
          homeRepositoryProvider.overrideWithValue(home),
          moneyRepositoryProvider.overrideWithValue(FakeMoneyRepository()),
          budgetsRepositoryProvider.overrideWithValue(budgets),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      return c;
    }

    setUp(() {
      home = FakeHomeRepository();
      budgets = _FakeBudgets();
      drafts = MemoryDraftStore();
    });

    test('dos toques, un envío; después se recargan el mes y los presupuestos del Inicio', () async {
      final c = open();
      await c.read(sessionControllerProvider.future);
      c.listen(homeBudgetsProvider(_ana), (_, _) {});
      await c.read(homeBudgetsProvider(_ana).future);
      final before = home.count('budgets');
      final writer = c.read(budgetsWriterProvider);
      await Future.wait([
        writer.create(category: 'ocio', month: '2026-11', amount: 150000),
        writer.create(category: 'ocio', month: '2026-11', amount: 150000),
      ]);
      expect(budgets.sent, ['POST ocio 2026-11 150000']);
      await c.read(homeBudgetsProvider(_ana).future);
      expect(home.count('budgets'), greaterThan(before));
    });

    test(
      'un 409 BUDGET_EXISTS recarga el mes y el Inicio: la categoría repetida deja de ofrecerse',
      () async {
        final c = open();
        await c.read(sessionControllerProvider.future);
        c.listen(homeBudgetsProvider(_ana), (_, _) {});
        await c.read(homeBudgetsProvider(_ana).future);
        final before = home.count('budgets');
        budgets.onSend = () async => throw const ApiException(
          code: 'BUDGET_EXISTS',
          status: 409,
          serverMessage: 'Ya existe un presupuesto para esa categoría en ese mes',
        );
        await expectLater(
          c.read(budgetsWriterProvider).create(category: 'ocio', month: '2026-11', amount: 150000),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        await c.read(homeBudgetsProvider(_ana).future);
        expect(home.count('budgets'), greaterThan(before));
      },
    );

    test('en duda, crear vale si al releer la categoría ya tiene ese límite; si no, UNCONFIRMED', () async {
      final c = open();
      await c.read(sessionControllerProvider.future);
      budgets.onSend = () async => throw _timeout;
      home.onBudgets = () async => [_budget('ocio', 150000, 0, 0, BudgetLevel.none)];
      await c.read(budgetsWriterProvider).create(category: 'ocio', month: '2026-11', amount: 150000);

      home.onBudgets = () async => const [];
      await expectLater(
        c.read(budgetsWriterProvider).create(category: 'ocio', month: '2026-11', amount: 150000),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
      );
      expect(budgets.sent, hasLength(2), reason: 'nunca se reintenta solo');
    });

    test('borrar: un 404 cuenta como hecho; en duda vale si ya no está', () async {
      final c = open();
      await c.read(sessionControllerProvider.future);
      final b = _budget('ocio', 150000, 0, 0, BudgetLevel.none);
      budgets.onSend = () async => throw const ApiException(
        code: 'NOT_FOUND',
        status: 404,
        serverMessage: 'Presupuesto no encontrado',
      );
      await c.read(budgetsWriterProvider).delete(b, '2026-11');
      budgets.onSend = () async => throw _timeout;
      await c.read(budgetsWriterProvider).delete(b, '2026-11');
      home.onBudgets = () async => [b];
      await expectLater(c.read(budgetsWriterProvider).delete(b, '2026-11'), throwsA(isA<ApiException>()));
    });

    test('con la bienvenida a medias no se escribe nada', () async {
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      final c = open();
      await c.read(sessionControllerProvider.future);
      await expectLater(
        c.read(budgetsWriterProvider).update(_budget('ocio', 1, 0, 0, BudgetLevel.none), '2026-11', 2),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending)),
      );
      expect(budgets.sent, isEmpty);
    });

    test('la copia del mes de quien salió no pide nada ni pasa a quien entra', () async {
      final c = open();
      await c.read(sessionControllerProvider.future);
      home.onBudgets = () async => [_budget('ocio', 1, 0, 0, BudgetLevel.none)];
      c.listen(budgetsMonthProvider((_ana, '2026-11')), (_, _) {});
      expect(await c.read(budgetsMonthProvider((_ana, '2026-11')).future), hasLength(1));
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      final calls = home.count('budgets');
      c.listen(budgetsMonthProvider((_ana, '2026-11')), (_, _) {});
      c.invalidate(budgetsMonthProvider((_ana, '2026-11')));
      await Future<void>.delayed(Duration.zero);
      expect(home.count('budgets'), calls);
    });
  });

  group('demo', () {
    late ProviderContainer c;
    late MemoryJsonListStore budgetsStore;

    setUp(() {
      budgetsStore = MemoryJsonListStore();
      c = ProviderContainer.test(
        overrides: [
          demoBudgetsStoreProvider.overrideWithValue(budgetsStore),
          demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
          demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        ],
      );
      c.read(demoControlsProvider.notifier).setLatency(Duration.zero);
    });

    test('un recorrido guarda su presupuesto y lo lee con lo gastado del escenario y la alerta', () async {
      const user = 'demo-movimientos';
      await c
          .read(demoBudgetsRepositoryProvider(user))
          .create(category: 'alimentacion', month: '2026-11', amount: 600000);
      final [b] = await c.read(demoHomeRepositoryProvider(user)).budgets('2026-11');
      expect((b.amount, b.consumed, b.percentage, b.level), (600000, 520000, 86.67, BudgetLevel.warning));
      await expectLater(
        c
            .read(demoBudgetsRepositoryProvider(user))
            .create(category: 'alimentacion', month: '2026-11', amount: 1),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'BUDGET_EXISTS')),
      );
      await c.read(demoBudgetsRepositoryProvider(user)).delete(b.id);
      expect(await c.read(demoHomeRepositoryProvider(user)).budgets('2026-11'), isEmpty);
    });

    test('los escenarios fijos no escriben y su presupuesto sembrado es solo del mes en curso', () async {
      await expectLater(
        c
            .read(demoBudgetsRepositoryProvider('demo-planListo'))
            .create(category: 'ocio', month: '2026-11', amount: 1),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
      );
      expect(await c.read(demoHomeRepositoryProvider('demo-planListo')).budgets('2026-11'), hasLength(1));
      expect(await c.read(demoHomeRepositoryProvider('demo-planListo')).budgets('2026-10'), isEmpty);
    });

    test(
      '«Te faltan»: la proyección queda en -93.000, lo mismo que el faltante del plan del Inicio',
      () async {
        final money = c.read(demoMoneyRepositoryProvider('demo-teFaltan'));
        final plan = await c.read(demoHomeRepositoryProvider('demo-teFaltan')).plan();
        final l = await money.liquidity();
        expect((l.ready, l.risk, l.days.last.end), (true, 'falta', -plan.shortfall));
        expect(l.firstShortfall!.causes.single.name, 'PILA');
        final calendar = await money.monthCalendar('2026-11');
        expect(
          (calendar.pending, calendar.events.last.balanceAfter, calendar.events.last.risk),
          (plan.pendingTotal, -plan.shortfall, 'negativo'),
        );
        expect((await money.monthCalendar('2026-12')).events, isEmpty);
      },
    );
  });
}
