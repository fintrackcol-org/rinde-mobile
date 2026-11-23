import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart' show ContractException;
import 'package:rinde_mobile/features/home/data/home_models.dart';

final _contract = throwsA(isA<ContractException>());

/// Como llega de la red: los enteros son `int` y los decimales `double`.
Object? _json(String raw) => jsonDecode(raw);

/// Ejemplo de GET /money-profile/plan del contrato (modo `daily`).
const _daily =
    '{"ready":true,"money":1850000,"ledger":650000,"pendingTotal":950000,"free":900000,"shortfall":0,'
    '"pace":42000,"hasCommitments":true,"pending":[{"id":"7c1e","name":"Arriendo","amount":900000,'
    '"date":"2026-12-05"},{"id":"9a2b","name":"Internet","amount":50000,"date":"2026-11-28"}],'
    '"saveAdvice":0,"mode":"daily","nextPay":"2026-11-30","days":9,"perDay":100000,"spentToday":35000,'
    '"leftToday":65000,"overBy":0,"dayStatus":"ok"}';

Map<String, dynamic> _plan([Map<String, dynamic> changes = const {}]) => {
  ...(_json(_daily)! as Map<String, dynamic>),
  ...changes,
};

void main() {
  group('readMoney', () {
    test('quita los residuos de coma flotante: nunca «-\$ 0,00»', () {
      final residue = 100000.26 + 0.2 - 100000.46;
      expect(residue, isNot(0), reason: 'el caso debe traer residuo');
      expect(residue.isNegative, isTrue);

      final money = readMoney(residue)!;
      expect(money, 0);
      expect(money, isA<int>());
      expect(money.isNegative, isFalse);
      expect(readMoney(0.1 + 0.2), 0.3);
      expect(readMoney(10000.000000171856), 10000);
    });

    test('el cero negativo sale como cero', () {
      for (final zero in <num>[-0.0, -0.001, -0.004, 0.004]) {
        final money = readMoney(zero)!;
        expect(money, isA<int>(), reason: '$zero');
        expect(money.isNegative, isFalse, reason: '$zero');
        expect('$money', '0', reason: '$zero');
      }
    });

    test('lo que es entero queda entero, llegue como llegue', () {
      expect(readMoney(45000), isA<int>());
      expect(readMoney(45000), 45000);
      expect(readMoney(45000.0), isA<int>());
      expect('${readMoney(45000.0)}', '45000');
      expect(readMoney(0), isA<int>());
      expect(readMoney(-500000), -500000);
      expect(readMoney(-500000.0), isA<int>());
      expect(readMoney(9999999999), 9999999999);
    });

    test('los centavos se conservan al centavo', () {
      expect(readMoney(1203400.5), 1203400.5);
      expect(readMoney(19999.6), 19999.6);
      expect(readMoney(-0.4), -0.4);
      expect(readMoney(-1234.56), -1234.56);
      expect(readMoney(0.01), 0.01);
      // El tope de NUMERIC(12,2).
      expect(readMoney(9999999999.99), 9999999999.99);
      expect(readMoney(-9999999999.99), -9999999999.99);
    });

    test('lo que no es un número finito no es plata: null, nunca 0', () {
      for (final value in <Object?>[null, '1000', '', true, false, <Object?>[], <String, Object?>{}]) {
        expect(readMoney(value), isNull, reason: '$value');
      }
      expect(readMoney(double.nan), isNull);
      expect(readMoney(double.infinity), isNull);
      expect(readMoney(double.negativeInfinity), isNull);
    });
  });

  group('MoneyPlan.fromJson', () {
    test('{"ready": false}: sin configurar', () {
      final plan = MoneyPlan.fromJson(_json('{"ready":false}'));
      expect(plan.ready, isFalse);
      expect(plan.pending, isEmpty);
      expect(plan.perDay, isNull);
      expect(plan.nextPay, isNull);
    });

    test('lee el ejemplo del contrato (modo daily)', () {
      final plan = MoneyPlan.fromJson(_json(_daily));
      expect(plan.ready, isTrue);
      expect(plan.mode, 'daily');
      expect(
        (plan.money, plan.pendingTotal, plan.free, plan.shortfall, plan.perDay),
        (1850000, 950000, 900000, 0, 100000),
      );
      expect(plan.nextPay, '2026-11-30');
      expect((plan.short, plan.negative), (false, false));
      // En el orden del servidor, sin reordenar.
      expect(plan.pending.map((p) => '${p.id} ${p.name} ${p.amount} ${p.date}'), [
        '7c1e Arriendo 900000 2026-12-05',
        '9a2b Internet 50000 2026-11-28',
      ]);
    });

    test('modos goal y runway: sin «al día» ni próximo pago', () {
      for (final mode in ['goal', 'runway']) {
        final json = _plan({'mode': mode})
          ..remove('perDay')
          ..remove('nextPay');
        final plan = MoneyPlan.fromJson(json);
        expect(plan.mode, mode);
        expect(plan.perDay, isNull);
        expect(plan.nextPay, isNull);
        expect(plan.free, 900000);
      }
    });

    test('no alcanza y en negativo salen de las cifras del servidor', () {
      final short = MoneyPlan.fromJson(_plan({'free': -180700, 'shortfall': 180700}));
      expect((short.short, short.negative, short.free, short.shortfall), (true, false, -180700, 180700));

      final negative = MoneyPlan.fromJson(_plan({'money': -500000, 'free': -500000, 'shortfall': 500000}));
      expect((negative.short, negative.negative), (true, true));

      // El servidor puede mandar free 0 con shortfall 1: se muestra lo que mandó, no se recalcula.
      final rounded = MoneyPlan.fromJson(
        _plan({'money': 100000, 'pendingTotal': 100001, 'free': 0, 'shortfall': 1}),
      );
      expect((rounded.short, rounded.free, rounded.shortfall), (false, 0, 1));
    });

    test('si falta una cifra obligatoria es un error de contrato, no un cero', () {
      for (final key in ['money', 'pendingTotal', 'free', 'shortfall']) {
        expect(() => MoneyPlan.fromJson(_plan()..remove(key)), _contract, reason: 'sin $key');
        expect(() => MoneyPlan.fromJson(_plan({key: null})), _contract, reason: '$key null');
        expect(() => MoneyPlan.fromJson(_plan({key: '1000'})), _contract, reason: '$key texto');
      }
    });

    test('sin "ready", o con otra forma, es un error de contrato', () {
      expect(() => MoneyPlan.fromJson(_plan()..remove('ready')), _contract);
      expect(() => MoneyPlan.fromJson(_plan({'ready': 'true'})), _contract);
      expect(() => MoneyPlan.fromJson(_json('{}')), _contract);
      expect(() => MoneyPlan.fromJson(_json('[]')), _contract);
      expect(() => MoneyPlan.fromJson(null), _contract);
      expect(() => MoneyPlan.fromJson('ready'), _contract);
    });

    test('tolera perDay NaN (llega null) y nextPay ausente o mal escrito', () {
      // fecha_fija sin días de pago: el servidor serializa NaN como null y no manda nextPay.
      final broken = MoneyPlan.fromJson(_plan({'perDay': null})..remove('nextPay'));
      expect(broken.ready, isTrue);
      expect(broken.perDay, isNull);
      expect(broken.nextPay, isNull);
      expect(broken.free, 900000);

      expect(MoneyPlan.fromJson(_plan({'nextPay': 'pronto'})).nextPay, isNull);
      expect(MoneyPlan.fromJson(_plan({'nextPay': 20261130})).nextPay, isNull);
      expect(MoneyPlan.fromJson(_plan({'perDay': 'mucho'})).perDay, isNull);
      expect(MoneyPlan.fromJson(_plan()..remove('mode')).mode, '');
    });

    test('se salta los pagos mal formados y conserva los buenos', () {
      final plan = MoneyPlan.fromJson(
        _plan({
          'pending': [
            {'id': 'a', 'name': 'Arriendo', 'amount': 900000, 'date': '2026-12-05'},
            {'id': 'b', 'name': 'Sin monto', 'date': '2026-12-05'},
            {'id': 'c', 'name': 'Monto texto', 'amount': '900000', 'date': '2026-12-05'},
            {'id': 'd', 'name': null, 'amount': 1, 'date': '2026-12-05'},
            {'id': 'e', 'name': 'Sin fecha', 'amount': 1},
            {'id': 'f', 'name': 'Fecha rara', 'amount': 1, 'date': '5 de diciembre'},
            {'id': 'g', 'name': 'Con hora', 'amount': 1, 'date': '2026-12-05T00:00:00.000Z'},
            'Arriendo',
            null,
            {'id': 7, 'name': 'Internet', 'amount': 50000.5, 'date': '2026-11-28'},
          ],
        }),
      );
      expect(plan.pending.map((p) => '${p.id} ${p.name} ${p.amount} ${p.date}'), [
        'a Arriendo 900000 2026-12-05',
        '7 Internet 50000.5 2026-11-28',
      ]);
    });

    test('pending ausente o con otra forma: lista vacía', () {
      expect(MoneyPlan.fromJson(_plan()..remove('pending')).pending, isEmpty);
      expect(MoneyPlan.fromJson(_plan({'pending': 'ninguno'})).pending, isEmpty);
      expect(MoneyPlan.fromJson(_plan({'pending': null})).pending, isEmpty);
    });

    test('el mismo pago puede venir dos veces (este mes y el otro) y vencido: se conservan', () {
      final plan = MoneyPlan.fromJson(
        _plan({
          'pending': [
            {'id': 'a', 'name': 'Arriendo', 'amount': 900000, 'date': '2026-11-05'},
            {'id': 'a', 'name': 'Arriendo', 'amount': 900000, 'date': '2026-12-05'},
          ],
        }),
      );
      expect(plan.pending.map((p) => p.date), ['2026-11-05', '2026-12-05']);
    });

    test('las cifras pasan por readMoney', () {
      final plan = MoneyPlan.fromJson(_plan({'money': 100000.26 + 0.2 - 100000.46, 'free': 900000.0}));
      expect(plan.money, 0);
      expect(plan.negative, isFalse);
      expect(plan.free, isA<int>());
    });
  });

  group('MonthTotals.fromJson', () {
    const summary =
        '{"period":"month","from":"2026-11-01","to":"2026-11-30",'
        '"income":{"total":2500000,"byCategory":[{"category":"salario","total":2500000,"percentage":100}]},'
        '"expense":{"total":1203400.5,"byCategory":[{"category":"alimentacion","total":600000,"percentage":49.9},'
        '{"category":null,"total":3400.5,"percentage":0.3}]},'
        '"savings":{"total":200000},"timeSeries":[{"date":"2026-11-02","income":0,"expense":45000}]}';
    Map<String, dynamic> body([Map<String, dynamic> changes = const {}]) => {
      ...(_json(summary)! as Map<String, dynamic>),
      ...changes,
    };

    test('lee el ejemplo del contrato', () {
      final totals = MonthTotals.fromJson(_json(summary));
      expect((totals.month, totals.income, totals.expense), ('2026-11', 2500000, 1203400.5));
    });

    test('un mes vacío son ceros que SÍ llegaron', () {
      final totals = MonthTotals.fromJson(
        body({
          'income': {'total': 0, 'byCategory': <Object?>[]},
          'expense': {'total': 0, 'byCategory': <Object?>[]},
        }),
      );
      expect((totals.income, totals.expense), (0, 0));
    });

    test('sin "from", sin los totales o con otra forma es un error de contrato', () {
      expect(() => MonthTotals.fromJson(body()..remove('from')), _contract);
      expect(() => MonthTotals.fromJson(body({'from': 'noviembre'})), _contract);
      expect(() => MonthTotals.fromJson(body()..remove('income')), _contract);
      expect(() => MonthTotals.fromJson(body({'expense': 1203400.5})), _contract);
      expect(() => MonthTotals.fromJson(body({'expense': <String, dynamic>{}})), _contract);
      expect(
        () => MonthTotals.fromJson(
          body({
            'income': <String, dynamic>{'total': '2500000'},
          }),
        ),
        _contract,
      );
      expect(() => MonthTotals.fromJson(_json('[]')), _contract);
    });
  });

  group('BudgetStatus', () {
    Map<String, dynamic> raw({Object? level = 'warning_80', Object? percentage = 81.25}) => {
      'id': 'uuid',
      'category': 'alimentacion',
      'month': '2026-11',
      'amount': 800000,
      'consumed': 650000,
      'percentage': percentage,
      'alert': {'level': level, 'percentage': percentage},
    };

    BudgetStatus of(BudgetLevel level, num percentage, {num amount = 100000, num consumed = 0}) =>
        BudgetStatus(
          category: 'mercado',
          amount: amount,
          consumed: consumed,
          percentage: percentage,
          level: level,
        );

    test('lee el ejemplo del contrato', () {
      final budget = BudgetStatus.tryParse(raw())!;
      expect(
        (budget.category, budget.amount, budget.consumed, budget.percentage, budget.level),
        ('alimentacion', 800000, 650000, 81.25, BudgetLevel.warning),
      );
      expect(budget.left, 150000);
    });

    test('niveles del servidor; uno desconocido no alarma', () {
      expect(BudgetStatus.tryParse(raw(level: 'none'))!.level, BudgetLevel.none);
      expect(BudgetStatus.tryParse(raw(level: 'warning_80'))!.level, BudgetLevel.warning);
      expect(BudgetStatus.tryParse(raw(level: 'exceeded_100'))!.level, BudgetLevel.exceeded);
      expect(BudgetStatus.tryParse(raw(level: 'nuevo_nivel'))!.level, BudgetLevel.none);
      expect(BudgetStatus.tryParse(raw(level: null))!.level, BudgetLevel.none);
    });

    test('displayLevel: justo en el 100 % es advertencia, no exceso', () {
      expect(of(BudgetLevel.exceeded, 100).displayLevel, BudgetLevel.warning);
      expect(of(BudgetLevel.exceeded, 100.0).displayLevel, BudgetLevel.warning);
      expect(of(BudgetLevel.exceeded, 100.01).displayLevel, BudgetLevel.exceeded);
      expect(of(BudgetLevel.exceeded, 120).displayLevel, BudgetLevel.exceeded);
      expect(of(BudgetLevel.warning, 89).displayLevel, BudgetLevel.warning);
      expect(of(BudgetLevel.warning, 100).displayLevel, BudgetLevel.warning);
      expect(of(BudgetLevel.none, 40).displayLevel, BudgetLevel.none);
      // El nivel lo decide el servidor: un porcentaje alto sin nivel no se vuelve alarma aquí.
      expect(of(BudgetLevel.none, 150).displayLevel, BudgetLevel.none);
    });

    test('«quedan» nunca es negativo', () {
      expect(of(BudgetLevel.exceeded, 120, amount: 450000, consumed: 540000).left, 0);
      expect(of(BudgetLevel.exceeded, 100, amount: 450000, consumed: 450000).left, 0);
      expect(of(BudgetLevel.exceeded, 100, amount: 450000, consumed: 450000.01).left, 0);
      expect(of(BudgetLevel.exceeded, 100, amount: 450000, consumed: 540000).left.isNegative, isFalse);
    });

    test('«quedan» es exacto al centavo', () {
      // En coma flotante 100000 − 80000.4 da 19999.600000000006.
      expect(100000 - 80000.4, isNot(19999.6));
      expect(of(BudgetLevel.warning, 80, amount: 100000, consumed: 80000.4).left, 19999.6);
      expect(of(BudgetLevel.warning, 89, amount: 450000, consumed: 400000).left, 50000);
      expect(of(BudgetLevel.warning, 89, amount: 450000, consumed: 400000).left, isA<int>());
      expect(of(BudgetLevel.warning, 99, amount: 0.3, consumed: 0.1).left, 0.2);
      expect(of(BudgetLevel.warning, 99, amount: 1000.1, consumed: 1000.09).left, 0.01);
    });

    test('sin monto, consumo, alerta o categoría legibles se descarta', () {
      expect(BudgetStatus.tryParse(raw()..remove('amount')), isNull);
      expect(BudgetStatus.tryParse(raw()..['amount'] = '800000'), isNull);
      expect(BudgetStatus.tryParse(raw()..remove('consumed')), isNull);
      expect(BudgetStatus.tryParse(raw()..remove('alert')), isNull);
      expect(BudgetStatus.tryParse(raw()..['alert'] = 'warning_80'), isNull);
      expect(BudgetStatus.tryParse(raw()..['category'] = null), isNull);
      expect(BudgetStatus.tryParse('alimentacion'), isNull);
      expect(BudgetStatus.tryParse(null), isNull);
    });

    test(
      'un porcentaje ilegible cuenta 0: con nivel «pasado» se muestra como advertencia, no como exceso',
      () {
        final budget = BudgetStatus.tryParse(raw(level: 'exceeded_100', percentage: null))!;
        expect(budget.percentage, 0);
        expect(budget.displayLevel, BudgetLevel.warning);
      },
    );
  });

  group('CardSummary', () {
    const card =
        '{"id":"uuid","name":"Visa Gold ••4821","network":"visa","tier":"gold","last4":"4821","limit":5000000,'
        '"used":1200000,"available":3800000,"paymentDay":15,"cutoffDay":null,"statementTotal":null,'
        '"statementDueDate":null,"nextPaymentDate":"2026-12-15","daysToPayment":24,"paidThisCycle":true,'
        '"paidDueDate":"2026-11-15","paidAmount":400000,"reminderSentFor":null,"expiryMonth":3,"expiryYear":2027,'
        '"expiry":{"label":"03/27","expired":false,"soon":false},"expiryNotified":[]}';
    Map<String, dynamic> raw([Map<String, dynamic> changes = const {}]) => {
      ...(_json(card)! as Map<String, dynamic>),
      ...changes,
    };

    test('lee el ejemplo del contrato', () {
      final c = CardSummary.tryParse(_json(card))!;
      expect(
        (c.id, c.name, c.network, c.last4, c.used, c.daysToPayment, c.paidThisCycle),
        ('uuid', 'Visa Gold ••4821', 'visa', '4821', 1200000, 24, true),
      );
    });

    test('los días pueden ser negativos (pago atrasado) o cero (hoy)', () {
      expect(CardSummary.tryParse(raw({'daysToPayment': -47}))!.daysToPayment, -47);
      expect(CardSummary.tryParse(raw({'daysToPayment': 0}))!.daysToPayment, 0);
    });

    test('sin días enteros hasta el pago se descarta', () {
      expect(CardSummary.tryParse(raw()..remove('daysToPayment')), isNull);
      expect(CardSummary.tryParse(raw({'daysToPayment': null})), isNull);
      expect(CardSummary.tryParse(raw({'daysToPayment': '24'})), isNull);
      expect(CardSummary.tryParse(raw({'daysToPayment': 2.5})), isNull);
    });

    test('sin deuda legible o sin saber si ya se pagó se descarta', () {
      expect(CardSummary.tryParse(raw()..remove('used')), isNull);
      expect(CardSummary.tryParse(raw({'used': '1200000'})), isNull);
      expect(CardSummary.tryParse(raw()..remove('paidThisCycle')), isNull);
      expect(CardSummary.tryParse(raw({'paidThisCycle': 'true'})), isNull);
      expect(CardSummary.tryParse('visa'), isNull);
      expect(CardSummary.tryParse(null), isNull);
    });

    test('lo que es solo para nombrarla tiene respaldo', () {
      final c = CardSummary.tryParse(
        raw({'id': 7})
          ..remove('name')
          ..remove('network')
          ..remove('last4'),
      )!;
      expect((c.id, c.name, c.network, c.last4), ('7', '', 'otra', ''));
    });

    test('la deuda pasa por readMoney', () {
      expect(CardSummary.tryParse(raw({'used': 320000.0}))!.used, isA<int>());
      expect(CardSummary.tryParse(raw({'used': 1500.55}))!.used, 1500.55);
    });
  });
}
