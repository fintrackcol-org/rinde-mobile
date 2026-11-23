import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart' show ContractException;
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/domain/home_notice.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/home_fixtures.dart';

final _today = DateTime(2026, 11, 21);

const _expired = ApiException(code: ApiCodes.tokenExpired, status: 401);
const _unauthorized = ApiException(code: ApiCodes.unauthorized, status: 401);
const _timeout = ApiException(code: ApiCodes.timeout);

/// La tarjeta grande en una palabra, para leer las tablas de un vistazo.
String _hero(HomeHero hero) => switch (hero) {
  HeroLoading() => 'cargando',
  HeroPlan(:final tone) => 'plan:${tone.name}',
  HeroMoney(:final runway, :final note) =>
    runway != null ? 'plata:alcanza' : 'plata:${note?.name ?? 'sinNota'}',
  HeroUnknown(:final reason) => 'nada:${reason.name}',
};

HomeView _view({
  Block<WelcomeStatus>? status,
  Block<MoneyPlan>? plan,
  Block<MonthTotals>? totals,
  Block<List<BudgetStatus>> budgets = const Block(),
  Block<List<CardSummary>> cards = const Block(),
  int toConfirm = 0,
  DateTime? today,
}) => buildHomeView(
  status: status ?? Block.data(statusOf()),
  plan: plan ?? Block.data(planOf()),
  totals: totals ?? Block.data(totalsOf()),
  budgets: budgets,
  cards: cards,
  toConfirm: toConfirm,
  today: today ?? _today,
);

void main() {
  final plans = <String, Block<MoneyPlan>>{
    'cargando': const Block.loading(),
    'falló': const Block.failed(serverError),
    'falló sin red': const Block.failed(offlineError),
    'falló y quedó uno viejo': Block(value: planOf(), error: serverError),
    'reintentando tras fallar': const Block(loading: true, error: serverError),
    'sin configurar': const Block.data(MoneyPlan.notReady()),
    'sin configurar, recargando': const Block(value: MoneyPlan.notReady(), loading: true),
    'listo, alcanza': Block.data(planOf()),
    'listo, recargando': Block(value: planOf(), loading: true),
    'listo, justo en cero': Block.data(planOf(free: 0)),
    'listo, no alcanza': Block.data(planOf(free: -180700, shortfall: 180700)),
    'listo, en negativo': Block.data(
      planOf(money: -500000, pendingTotal: 0, free: -500000, shortfall: 500000),
    ),
  };
  final totals = <String, Block<MonthTotals>>{
    'cargando': const Block.loading(),
    // «Falló sin un valor anterior» va aparte, en el grupo «este mes».
    'falló y quedó uno viejo': Block(value: totalsOf(), error: serverError),
    'de otro mes': Block.data(totalsOf(month: '2026-10')),
    'con gastos': Block.data(totalsOf()),
    'con gastos, recargando': Block(value: totalsOf(), loading: true),
    'sin gastos': Block.data(totalsOf(expense: 0)),
  };
  // Sin plan que mostrar manda el saldo; cada columna es un estado de «Este mes», en el orden de arriba.
  const noPlan = [
    'plata:calculating',
    'plata:sinNota',
    'plata:calculating',
    'plata:alcanza',
    'plata:alcanza',
    'plata:needsData',
  ];
  // Fila = plan. Una sola palabra = igual sin importar «Este mes».
  const expected = <String, Object>{
    'cargando': 'cargando',
    'falló': noPlan,
    'falló sin red': noPlan,
    'falló y quedó uno viejo': noPlan,
    'reintentando tras fallar': noPlan,
    'sin configurar': noPlan,
    'sin configurar, recargando': noPlan,
    'listo, alcanza': 'plan:free',
    'listo, recargando': 'plan:free',
    'listo, justo en cero': 'plan:free',
    'listo, no alcanza': 'plan:short',
    'listo, en negativo': 'plan:negative',
  };

  /// Recorre plan × «Este mes» con un estado de la cuenta y comprueba cada celda.
  void table(Block<WelcomeStatus> status, String Function(String cell) expectedCell) {
    for (final MapEntry(key: planName, value: plan) in plans.entries) {
      final row = expected[planName]!;
      var column = 0;
      for (final MapEntry(key: totalsName, value: monthTotals) in totals.entries) {
        final where = 'plan $planName, este mes $totalsName';
        final view = buildHomeView(status: status, plan: plan, totals: monthTotals, today: _today);
        final hero = view.hero;
        expect(_hero(hero), expectedCell(row is List<String> ? row[column] : row as String), reason: where);

        // Lo que no cambia en ninguna celda: solo cifras que llegaron, y de un intento que salió bien.
        final money = status.value?.money;
        if (hero is HeroMoney) {
          expect(money, isNotNull, reason: where);
          expect(hero.money, money, reason: where);
        }
        if (hero is HeroPlan) {
          expect(plan.failed, isFalse, reason: where);
          expect(identical(hero.plan, plan.value), isTrue, reason: where);
        }
        if (hero is HeroMoney && hero.runway != null) {
          expect(monthTotals.failed, isFalse, reason: where);
          expect(monthTotals.value!.month, '2026-11', reason: where);
        }
        expect(view.nextPayments.length, hero is HeroPlan ? maxNextPayments : 0, reason: where);
        expect(
          view.showLinks,
          status.value != null &&
              (status.value!.balanceSet || !status.failed) &&
              (hero is HeroPlan || hero is HeroMoney || _hero(hero) == 'nada:noBalance'),
          reason: where,
        );
        column++;
      }
    }
  }

  group('la tarjeta grande: cuenta × plan × este mes', () {
    final withMoney = statusOf();
    final noMoney = statusOf(money: null, balanceSet: false);
    String same(String cell) => cell;
    // Sin saldo en el servidor no hay «Mi plata» que mostrar: se dice que falta, sea cual sea el resto.
    String neverMoney(String cell) => cell.startsWith('plata:') ? 'nada:noBalance' : cell;

    test('cuenta fresca con saldo', () => table(Block.data(withMoney), same));
    test('cuenta recargando (se conserva lo último, sin parpadear)', () {
      table(Block(value: withMoney, loading: true), same);
    });
    test('cuenta vieja porque no hay conexión: lo último que llegó', () {
      table(Block(value: withMoney, error: offlineError), same);
    });
    test('cuenta vieja porque el servidor falló: lo último que llegó', () {
      table(Block(value: withMoney, error: serverError), same);
    });

    test(
      'cuenta fresca SIN saldo: nunca un número en «Mi plata»',
      () => table(Block.data(noMoney), neverMoney),
    );
    test('cuenta sin saldo, recargando o vieja: tampoco', () {
      table(Block(value: noMoney, loading: true), neverMoney);
      // Vieja no puede afirmar «no sabemos cuánta plata tienes»: solo que no se pudo traer.
      table(Block(value: noMoney, error: offlineError), (c) => c.startsWith('plata:') ? 'nada:offline' : c);
      table(Block(value: noMoney, error: serverError), (c) => c.startsWith('plata:') ? 'nada:error' : c);
    });

    test('cuenta cargando por primera vez: un solo esqueleto', () {
      table(const Block.loading(), (_) => 'cargando');
    });
    test('cuenta que no llegó por falta de conexión', () {
      table(const Block.failed(offlineError), (cell) => cell.startsWith('plan:') ? cell : 'nada:offline');
    });
    test('cuenta que no llegó por otro fallo', () {
      // Un plan que sí llegó se sigue mostrando.
      String planOrNothing(String cell) => cell.startsWith('plan:') ? cell : 'nada:error';
      table(const Block.failed(serverError), planOrNothing);
      table(const Block.failed(ContractException('La respuesta no es un objeto')), planOrNothing);
      table(const Block.failed(_timeout), planOrNothing);
    });
    test('cuenta reintentando tras fallar: sigue el esqueleto, no un cero', () {
      table(const Block(loading: true, error: offlineError), (c) => c.startsWith('plan:') ? c : 'cargando');
    });
  });

  test('lo último que llegó se marca como desactualizado; lo fresco y lo que no llegó, no', () {
    expect(_view(status: Block.data(statusOf())).stale, isFalse);
    expect(
      _view(
        status: Block(value: statusOf(), error: offlineError),
      ).stale,
      isTrue,
    );
    expect(
      _view(
        status: Block(value: statusOf(), error: serverError),
      ).stale,
      isTrue,
    );
    expect(_view(status: const Block.failed(offlineError)).stale, isFalse);
    expect(
      _view(
        totals: Block(value: totalsOf(), error: offlineError),
      ).stale,
      isTrue,
    );
    expect(_view(totals: const Block.failed(offlineError)).stale, isFalse);
  });

  test('un perfil viejo no invita a responder lo que quizás ya respondió', () {
    final pending = statusOf(welcomeDone: false);
    expect(_view(status: Block.data(pending)).footer, HomeFooter.invite);
    expect(
      _view(
        status: Block(value: pending, error: offlineError),
      ).footer,
      HomeFooter.none,
    );
  });

  group('la plata que no llegó nunca es un cero', () {
    test('saldo null → «no sabemos cuánta plata tienes», con salida a corregirla', () {
      final view = _view(
        status: Block.data(statusOf(money: null, balanceSet: false)),
        plan: const Block.data(MoneyPlan.notReady()),
      );
      expect(view.hero, isA<HeroUnknown>().having((h) => h.reason, 'reason', UnknownReason.noBalance));
      expect(view.showLinks, isTrue);
      expect(view.balanceSet, isFalse);
      expect(view.negativeNote, isFalse);
    });

    test('un saldo en cero que SÍ llegó se muestra como cero', () {
      final view = _view(
        status: Block.data(statusOf(money: 0)),
        plan: const Block.data(MoneyPlan.notReady()),
      );
      final hero = view.hero as HeroMoney;
      expect(hero.money, 0);
      expect(hero.runway!.days, 0);
      expect(view.negativeNote, isFalse);
    });

    test('sin saldo no se usa el balance del mes como «Mi plata» (la web sí lo hace)', () {
      final view = _view(
        status: Block.data(statusOf(money: null)),
        plan: const Block.failed(serverError),
        totals: Block.data(totalsOf(income: 900000, expense: 100000)),
      );
      expect(_hero(view.hero), 'nada:noBalance');
    });

    test('un plan que falló no se muestra aunque quede uno viejo, ni sus próximos pagos', () {
      final view = _view(
        plan: Block(value: planOf(), error: offlineError),
      );
      expect(view.hero, isA<HeroMoney>());
      expect(view.nextPayments, isEmpty);
      expect(view.reviewExpenses, isFalse);
      expect(view.offline, isTrue);
    });

    test('con el plan listo manda el plan aunque el perfil no traiga saldo', () {
      final view = _view(status: Block.data(statusOf(money: null)));
      expect(_hero(view.hero), 'plan:free');
    });
  });

  group('tonos del plan', () {
    test('alcanza, no alcanza y en negativo; justo en cero todavía alcanza', () {
      PlanTone tone(MoneyPlan plan) => (_view(plan: Block.data(plan)).hero as HeroPlan).tone;
      expect(tone(planOf()), PlanTone.free);
      expect(tone(planOf(free: 0)), PlanTone.free);
      expect(tone(planOf(free: -180700, shortfall: 180700)), PlanTone.short);
      expect(tone(planOf(money: -500000, free: -500000, shortfall: 500000)), PlanTone.negative);
      // El tono sale de free, como en la web; el servidor puede mandar free 0 con shortfall 1.
      expect(tone(planOf(money: 100000, pendingTotal: 100001, free: 0, shortfall: 1)), PlanTone.free);
    });

    test('en negativo: «Revisa tus gastos» sale una sola vez, sin la nota repetida', () {
      final negative = planOf(money: -500000, pendingTotal: 0, free: -500000, shortfall: 500000);
      final view = _view(status: Block.data(statusOf(money: -500000)), plan: Block.data(negative));
      expect(view.reviewExpenses, isTrue);
      expect(view.negativeNote, isFalse);
      expect(view.showLinks, isTrue);
    });

    test('si no alcanza pero la plata no es negativa, no se manda a revisar gastos', () {
      final view = _view(plan: Block.data(planOf(free: -180700, shortfall: 180700)));
      expect(view.reviewExpenses, isFalse);
      expect(view.negativeNote, isFalse);
    });

    test('sin plan y con saldo bajo cero: nota con salida a revisar los gastos', () {
      final view = _view(
        status: Block.data(statusOf(money: -5000)),
        plan: const Block.data(MoneyPlan.notReady()),
      );
      expect((view.hero as HeroMoney).money, -5000);
      expect(view.negativeNote, isTrue);
      expect(view.reviewExpenses, isFalse);
    });

    test('la nota no sale bajo un plan aunque el perfil viejo diga negativo', () {
      final view = _view(status: Block.data(statusOf(money: -0.4)));
      expect(_hero(view.hero), 'plan:free');
      expect(view.negativeNote, isFalse);
    });
  });

  group('hasta cuándo alcanza (sin plan)', () {
    const notReady = Block.data(MoneyPlan.notReady());

    test('con gastos del mes: los días al ritmo del mes', () {
      // Día 21 con 287.700 gastados: 13.700 al día. 412.300 alcanzan 30 días y quedan 9 de noviembre.
      final hero = _view(plan: notReady).hero as HeroMoney;
      expect(hero.note, isNull);
      expect((hero.runway!.days, hero.runway!.lasts), (30, true));
    });

    test('mientras llegan los gastos dice que está calculando, no que falta anotar', () {
      final hero = _view(plan: notReady, totals: const Block.loading()).hero as HeroMoney;
      expect((hero.runway, hero.note), (null, RunwayNote.calculating));
    });

    test('con el mes sin gastos pide datos', () {
      final hero = _view(plan: notReady, totals: Block.data(totalsOf(expense: 0))).hero as HeroMoney;
      expect((hero.runway, hero.note), (null, RunwayNote.needsData));
    });

    test('si los gastos del mes fallaron y quedaron unos viejos, no calcula con ellos ni dice nada', () {
      final stale = Block(value: totalsOf(), error: offlineError);
      final hero = _view(plan: notReady, totals: stale).hero as HeroMoney;
      expect((hero.runway, hero.note), (null, null));
      expect(hero.money, 412300);
    });
  });

  group('lo próximo', () {
    test('como mucho $maxNextPayments pagos, en el orden del servidor', () {
      final view = _view();
      expect(view.nextPayments.map((p) => p.name), ['PILA', 'Plan celular']);
    });

    test('con menos pagos, los que haya', () {
      expect(
        _view(plan: Block.data(planOf(pending: pendingPayments.sublist(2)))).nextPayments.single.name,
        'Visa',
      );
      expect(_view(plan: Block.data(planOf(pending: const []))).nextPayments, isEmpty);
    });

    test('un pago vencido o repetido no se reordena ni se quita', () {
      const pending = [
        PendingPayment(id: 'a', name: 'Arriendo', amount: 900000, date: '2026-11-05'),
        PendingPayment(id: 'a', name: 'Arriendo', amount: 900000, date: '2026-12-05'),
        PendingPayment(id: 'b', name: 'Internet', amount: 50000, date: '2026-11-28'),
      ];
      final view = _view(plan: Block.data(planOf(pending: pending)));
      expect(view.nextPayments.map((p) => p.date), ['2026-11-05', '2026-12-05']);
    });

    test('sin plan no hay «Lo próximo»', () {
      expect(_view(plan: const Block.data(MoneyPlan.notReady())).nextPayments, isEmpty);
      expect(_view(plan: const Block.loading()).nextPayments, isEmpty);
    });

    test('el próximo pago no se repite en el aviso: los pagos fijos no entran', () {
      expect(_view().notice, isNull);
    });
  });

  group('este mes', () {
    test('los totales del mes en curso pasan tal cual', () {
      final block = Block.data(totalsOf());
      expect(identical(_view(totals: block).totals, block), isTrue);
    });

    test('recargando conserva las cifras; con error se sabe que están viejas', () {
      final refreshing = _view(totals: Block(value: totalsOf(), loading: true)).totals;
      expect((refreshing.value!.expense, refreshing.loading), (287700, true));
      final stale = _view(
        totals: Block(value: totalsOf(), error: serverError),
      ).totals;
      expect((stale.value!.expense, stale.failed), (287700, true));
    });

    // DEFECTO ABIERTO en buildHomeView (home_view.dart): hoy falla. Un resumen fallido sin valor se
    // trata como «de otro mes» y se cambia por Block(loading: true), con lo que se pierde el error.
    test('si falla sin un valor anterior llega como fallo: ni «cargando» para siempre ni «calculando»', () {
      for (final error in [serverError, offlineError]) {
        final view = _view(plan: const Block.data(MoneyPlan.notReady()), totals: Block.failed(error));
        expect((view.totals.failed, view.totals.loading, view.totals.value), (true, false, null));
        final hero = view.hero as HeroMoney;
        expect((hero.money, hero.runway, hero.note), (412300, null, null));
      }
    });

    test('cambio de mes con la app abierta: el resumen del mes pasado no es «este mes»', () {
      final october = Block.data(totalsOf(month: '2026-10', income: 5000000, expense: 4000000));
      final view = _view(
        plan: const Block.data(MoneyPlan.notReady()),
        totals: october,
        today: DateTime(2026, 11, 1),
      );
      expect((view.totals.value, view.totals.loading), (null, true));
      // Ni el ritmo se mide con lo gastado en octubre dividido por el día 1.
      final hero = view.hero as HeroMoney;
      expect((hero.runway, hero.note), (null, RunwayNote.calculating));
    });

    test('el mismo resumen deja de valer a medianoche del último día', () {
      final november = Block.data(totalsOf());
      expect(_view(totals: november, today: DateTime(2026, 11, 30)).totals.value, isNotNull);
      expect(_view(totals: november, today: DateTime(2026, 12, 1)).totals.value, isNull);
      expect(_view(totals: november, today: DateTime(2027, 11, 21)).totals.value, isNull);
    });
  });

  group('por confirmar', () {
    test('pasa la cuenta que llegó', () {
      expect(_view(toConfirm: 3).toConfirm, 3);
      expect(_view().toConfirm, 0);
    });
  });

  group('aviso', () {
    test('sale el más urgente de tarjetas y presupuestos', () {
      final view = _view(
        cards: Block.data([cardOf(2)]),
        budgets: Block.data([budgetOf(BudgetLevel.exceeded)]),
      );
      expect(view.notice!.kind, HomeNoticeKind.budgetExceeded);
    });

    test('mientras cargan o si fallan no hay aviso (ni con datos viejos)', () {
      expect(_view(cards: const Block.loading(), budgets: const Block.loading()).notice, isNull);
      expect(_view(cards: const Block.failed(serverError)).notice, isNull);
      final stale = _view(
        cards: Block(value: [cardOf(-1)], error: offlineError),
        budgets: Block(value: [budgetOf(BudgetLevel.exceeded)], error: offlineError),
      );
      expect(stale.notice, isNull);
    });

    test('recargando se conserva el aviso, sin parpadear', () {
      expect(_view(cards: Block(value: [cardOf(-1)], loading: true)).notice!.kind, HomeNoticeKind.cardLate);
    });

    test('si solo falla un bloque, el otro sigue avisando', () {
      final view = _view(
        cards: const Block.failed(serverError),
        budgets: Block.data([budgetOf(BudgetLevel.warning)]),
      );
      expect(view.notice!.kind, HomeNoticeKind.budgetWarning);
    });

    test('el aviso no depende de la tarjeta grande', () {
      final view = _view(status: const Block.loading(), cards: Block.data([cardOf(-1)]));
      expect(view.notice!.kind, HomeNoticeKind.cardLate);
    });
  });

  group('pie: aviso > invitación > terminar de configurar', () {
    final pendingWelcome = Block.data(statusOf(welcomeDone: false));
    const notReady = Block.data(MoneyPlan.notReady());
    final card = Block.data([cardOf(2)]);

    test('bienvenida hecha y plan listo: nada', () {
      expect(_view().footer, HomeFooter.none);
    });

    test('sin bienvenida: invitación, con o sin plan', () {
      expect(_view(status: pendingWelcome).footer, HomeFooter.invite);
      expect(_view(status: pendingWelcome, plan: notReady).footer, HomeFooter.invite);
      expect(_view(status: pendingWelcome, plan: const Block.loading()).footer, HomeFooter.invite);
      expect(_view(status: pendingWelcome, plan: const Block.failed(serverError)).footer, HomeFooter.invite);
    });

    test('bienvenida hecha y plan sin configurar: terminar de configurar', () {
      expect(_view(plan: notReady).footer, HomeFooter.setup);
      expect(_view(plan: const Block(value: MoneyPlan.notReady(), loading: true)).footer, HomeFooter.setup);
    });

    test('un aviso le gana a la invitación y a configurar', () {
      expect(_view(status: pendingWelcome, cards: card).footer, HomeFooter.none);
      expect(_view(status: pendingWelcome, plan: notReady, cards: card).footer, HomeFooter.none);
      expect(_view(plan: notReady, cards: card).footer, HomeFooter.none);
      expect(_view(plan: notReady, cards: card).notice, isNotNull);
    });

    test('no se pide configurar por un plan que no se sabe (cargando o fallido)', () {
      expect(_view(plan: const Block.loading()).footer, HomeFooter.none);
      expect(_view(plan: const Block.failed(serverError)).footer, HomeFooter.none);
      expect(
        _view(
          plan: const Block(value: MoneyPlan.notReady(), error: serverError),
        ).footer,
        HomeFooter.none,
      );
    });

    test('sin saber de la cuenta no se invita a nada', () {
      expect(_view(status: const Block.loading(), plan: notReady).footer, HomeFooter.none);
      expect(_view(status: const Block.failed(offlineError), plan: notReady).footer, HomeFooter.none);
    });
  });

  group('cuenta sin movimientos', () {
    final none = statusOf(hasTransactions: false);

    test('solo con un dato fresco del servidor', () {
      expect(_view(status: Block.data(none)).empty, isTrue);
      expect(_view(status: Block.data(statusOf())).empty, isFalse);
    });

    test('de una petición fallida, o a medias, no se concluye que no hay movimientos', () {
      expect(_view(status: const Block.failed(offlineError)).empty, isFalse);
      expect(_view(status: const Block.failed(serverError)).empty, isFalse);
      expect(_view(status: const Block.loading()).empty, isFalse);
      expect(
        _view(
          status: Block(value: none, error: offlineError),
        ).empty,
        isFalse,
      );
      expect(
        _view(
          status: Block(value: none, error: serverError),
        ).empty,
        isFalse,
      );
      // Al refrescar se conserva, para que la tarjeta no parpadee.
      expect(_view(status: Block(value: none, loading: true)).empty, isTrue);
    });
  });

  group('sin conexión, error de carga y sesión vencida', () {
    Block<T> failed<T>(Object error) => Block<T>.failed(error);
    (bool, bool) flags(HomeView view) => (view.offline, view.loadError);

    test('todo bien: ninguno', () {
      expect(flags(_view()), (false, false));
      expect(flags(_view(status: const Block.loading(), plan: const Block.loading())), (false, false));
    });

    test('la petición no salió del teléfono: sin conexión, no «error»', () {
      expect(flags(_view(status: failed(offlineError))), (true, false));
      expect(flags(_view(plan: failed(offlineError))), (true, false));
      expect(flags(_view(totals: failed(offlineError))), (true, false));
      expect(
        flags(
          _view(
            plan: Block(value: planOf(), error: offlineError),
          ),
        ),
        (true, false),
      );
    });

    test('cualquier otro fallo: error de carga con reintento', () {
      expect(flags(_view(status: failed(serverError))), (false, true));
      expect(flags(_view(plan: failed(serverError))), (false, true));
      expect(flags(_view(totals: failed(serverError))), (false, true));
      expect(flags(_view(plan: failed(const ContractException('Falta "ready"')))), (false, true));
      expect(flags(_view(totals: failed(StateError('otro')))), (false, true));
      // Venció la espera: la petición pudo llegar al servidor, no es «sin conexión».
      expect(flags(_view(plan: failed(_timeout))), (false, true));
    });

    test('la sesión venció: ni lo uno ni lo otro (el router ya lleva al login)', () {
      expect(flags(_view(status: failed(_expired), plan: failed(_expired), totals: failed(_expired))), (
        false,
        false,
      ));
      expect(flags(_view(status: failed(_unauthorized), plan: failed(_unauthorized))), (false, false));
    });

    test('pueden darse los dos a la vez', () {
      expect(flags(_view(status: failed(offlineError), plan: failed(serverError))), (true, true));
      expect(flags(_view(plan: failed(_expired), totals: failed(serverError))), (false, true));
    });

    test('tarjetas y presupuestos no son bloques principales: su fallo solo quita el aviso', () {
      final view = _view(cards: failed(serverError), budgets: failed(offlineError));
      expect(flags(view), (false, false));
      expect(view.notice, isNull);
    });
  });

  group('tutorial de primera vez', () {
    final firstTime = statusOf(tutorialDone: false);

    test('bienvenida hecha, tutorial sin ver e Inicio cargado', () {
      expect(_view(status: Block.data(firstTime)).tourEligible, isTrue);
      expect(
        _view(status: Block.data(firstTime), plan: const Block.data(MoneyPlan.notReady())).tourEligible,
        isTrue,
      );
      // Con el plan caído el Inicio igual está dibujado.
      expect(
        _view(status: Block.data(firstTime), plan: const Block.failed(serverError)).tourEligible,
        isTrue,
      );
    });

    test('no sale si ya lo vio o si no ha hecho la bienvenida', () {
      expect(_view().tourEligible, isFalse);
      expect(
        _view(status: Block.data(statusOf(welcomeDone: false, tutorialDone: false))).tourEligible,
        isFalse,
      );
    });

    test('no sale mientras la tarjeta grande es un esqueleto', () {
      expect(_view(status: Block.data(firstTime), plan: const Block.loading()).tourEligible, isFalse);
      expect(_view(status: const Block.loading()).tourEligible, isFalse);
    });

    test('no sale con un dato viejo o a medias de la cuenta', () {
      expect(_view(status: Block(value: firstTime, loading: true)).tourEligible, isFalse);
      expect(
        _view(
          status: Block(value: firstTime, error: offlineError),
        ).tourEligible,
        isFalse,
      );
      expect(_view(status: const Block.failed(serverError)).tourEligible, isFalse);
    });
  });

  group('lo demás del perfil', () {
    test('balanceSet viene del perfil; sin perfil es false', () {
      expect(_view().balanceSet, isTrue);
      expect(_view(status: Block.data(statusOf(balanceSet: false))).balanceSet, isFalse);
      expect(_view(status: const Block.loading()).balanceSet, isFalse);
    });

    test('los enlaces bajo la tarjeta solo salen cuando hay tarjeta o falta decir el saldo', () {
      expect(_view().showLinks, isTrue);
      expect(_view(status: const Block.loading()).showLinks, isFalse);
      expect(_view(status: const Block.failed(offlineError)).showLinks, isFalse);
      expect(_view(status: const Block.failed(serverError)).showLinks, isFalse);
      expect(_view(plan: const Block.loading()).showLinks, isFalse);
    });
  });

  group('Block', () {
    test('distingue sin conexión, sesión vencida y otros fallos', () {
      const offline = Block<int>.failed(offlineError);
      expect((offline.failed, offline.offline, offline.expired), (true, true, false));
      for (final error in [_expired, _unauthorized]) {
        final block = Block<int>.failed(error);
        expect((block.failed, block.offline, block.expired), (true, false, true));
      }
      for (final Object error in [serverError, _timeout, StateError('x'), const ContractException('x')]) {
        final block = Block<int>.failed(error);
        expect((block.failed, block.offline, block.expired), (true, false, false), reason: '$error');
      }
      const ok = Block.data(1);
      expect((ok.failed, ok.offline, ok.expired, ok.loading, ok.value), (false, false, false, false, 1));
      const loading = Block<int>.loading();
      expect((loading.failed, loading.loading, loading.value), (false, true, null));
    });
  });
}
