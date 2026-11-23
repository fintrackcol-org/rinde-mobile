import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/domain/home_notice.dart';

import '../../support/home_fixtures.dart';

/// Casos de homeNotice.test.js y de los vectores de la auditoría financiera (sección 5). El texto lo
/// arma quien dibuja: aquí se prueba QUÉ aviso sale y de quién.
void main() {
  const exceeded = BudgetLevel.exceeded;
  const warning = BudgetLevel.warning;

  group('como Rinde Web', () {
    test('sin nada que decir, no hay aviso', () {
      expect(pickHomeNotice(), isNull);
      expect(pickHomeNotice(cards: const [], budgets: const []), isNull);
      expect(pickHomeNotice(budgets: [budgetOf(BudgetLevel.none, percentage: 40)]), isNull);
    });

    test('una tarjeta atrasada va primero que todo', () {
      final notice = pickHomeNotice(cards: [cardOf(-1)], budgets: [budgetOf(exceeded)])!;
      expect(notice.kind, HomeNoticeKind.cardLate);
      expect(notice.card!.id, '7');
      expect(notice.budget, isNull);
    });

    test('un presupuesto pasado va antes que una tarjeta por vencer', () {
      final notice = pickHomeNotice(cards: [cardOf(2)], budgets: [budgetOf(exceeded)])!;
      expect(notice.kind, HomeNoticeKind.budgetExceeded);
      expect(notice.budget!.category, 'vivienda');
      expect(notice.card, isNull);
    });

    test('una tarjeta por vencer va antes que un presupuesto cerca del límite', () {
      final notice = pickHomeNotice(cards: [cardOf(3)], budgets: [budgetOf(warning)])!;
      expect(notice.kind, HomeNoticeKind.cardSoon);
      expect(notice.card!.daysToPayment, 3);
      expect(notice.card!.used, 320000);
    });

    test('«por vencer» va de hoy a $cardSoonDays días; a los 4 ya es «la próxima»', () {
      for (final days in [0, 1, 2, 3]) {
        expect(pickHomeNotice(cards: [cardOf(days)])!.kind, HomeNoticeKind.cardSoon, reason: '$days días');
      }
      expect(pickHomeNotice(cards: [cardOf(4)])!.kind, HomeNoticeKind.cardNext);
      expect(pickHomeNotice(cards: [cardOf(28)])!.kind, HomeNoticeKind.cardNext);
    });

    test('el presupuesto cerca del límite va antes que una tarjeta lejana', () {
      for (final days in [4, 12]) {
        final notice = pickHomeNotice(cards: [cardOf(days)], budgets: [budgetOf(warning)])!;
        expect(notice.kind, HomeNoticeKind.budgetWarning, reason: '$days días');
      }
    });

    test('el presupuesto cerca del límite trae lo que queda, al centavo', () {
      final budget = budgetOf(warning, category: 'mercado', amount: 100000, consumed: 80000.4);
      final notice = pickHomeNotice(budgets: [budget])!;
      expect(notice.kind, HomeNoticeKind.budgetWarning);
      expect(notice.budget!.left, 19999.6);
    });

    test('elige la tarjeta que se paga primero e ignora las ya pagadas', () {
      final cards = [cardOf(1, id: '1', paid: true), cardOf(12, id: '2'), cardOf(5, id: '3')];
      final notice = pickHomeNotice(cards: cards)!;
      expect(notice.kind, HomeNoticeKind.cardNext);
      expect(notice.card!.id, '3');
    });

    test('una tarjeta atrasada pero ya pagada en este ciclo no avisa', () {
      expect(pickHomeNotice(cards: [cardOf(-3, paid: true)]), isNull);
      expect(
        pickHomeNotice(
          cards: [
            cardOf(-3, paid: true),
            cardOf(9, id: '8'),
          ],
        )!.card!.id,
        '8',
      );
    });

    test('con todas las tarjetas pagadas mandan los presupuestos', () {
      final notice = pickHomeNotice(cards: [cardOf(-1, paid: true)], budgets: [budgetOf(warning)])!;
      expect(notice.kind, HomeNoticeKind.budgetWarning);
    });

    test('entre varias tarjetas, la más atrasada', () {
      final notice = pickHomeNotice(
        cards: [
          cardOf(2, id: 'a'),
          cardOf(-1, id: 'b'),
          cardOf(-9, id: 'c'),
        ],
      )!;
      expect(notice.kind, HomeNoticeKind.cardLate);
      expect(notice.card!.id, 'c');
    });

    test('entre varios presupuestos, el primero pasado en el orden del servidor', () {
      final budgets = [
        budgetOf(warning, category: 'mercado'),
        budgetOf(exceeded, category: 'vivienda'),
        budgetOf(exceeded, category: 'transporte'),
      ];
      final notice = pickHomeNotice(budgets: budgets)!;
      expect(notice.kind, HomeNoticeKind.budgetExceeded);
      expect(notice.budget!.category, 'vivienda');
      expect(pickHomeNotice(budgets: budgets.sublist(0, 1))!.budget!.category, 'mercado');
    });

    test('una categoría que la app no conoce igual avisa (quien dibuja pone la clave)', () {
      expect(
        pickHomeNotice(budgets: [budgetOf(warning, category: 'c_mascotas')])!.budget!.category,
        'c_mascotas',
      );
    });
  });

  group('distinto de Rinde Web a propósito', () {
    test('una tarjeta sin deuda no avisa (la web dice «pago atrasado · Debes 0»)', () {
      expect(pickHomeNotice(cards: [cardOf(-47, used: 0)]), isNull);
      expect(pickHomeNotice(cards: [cardOf(28, used: 0)]), isNull);
      expect(pickHomeNotice(cards: [cardOf(2, used: -1500)]), isNull);
    });

    test('una tarjeta sin deuda no le quita el aviso a la que sí debe', () {
      final notice = pickHomeNotice(
        cards: [
          cardOf(-47, id: 'nueva', used: 0),
          cardOf(9, id: 'debe'),
        ],
      )!;
      expect(notice.kind, HomeNoticeKind.cardNext);
      expect(notice.card!.id, 'debe');
    });

    test('un presupuesto justo en el 100 % avisa como «casi llega al límite» (en la web no avisa nada)', () {
      final notice = pickHomeNotice(budgets: [budgetOf(exceeded, percentage: 100, consumed: 450000)])!;
      expect(notice.kind, HomeNoticeKind.budgetWarning);
      expect(notice.budget!.left, 0);
    });

    test('pasado por centavos (100,004 % que el servidor guarda como 100) también avisa', () {
      final budget = budgetOf(exceeded, percentage: 100, amount: 450000, consumed: 450018);
      expect(pickHomeNotice(budgets: [budget])!.kind, HomeNoticeKind.budgetWarning);
    });

    test('justo en el 100 % va antes que una tarjeta lejana (la web muestra la tarjeta)', () {
      final notice = pickHomeNotice(cards: [cardOf(20)], budgets: [budgetOf(exceeded, percentage: 100)])!;
      expect(notice.kind, HomeNoticeKind.budgetWarning);
    });

    test(
      'justo en el 100 % no es «te pasaste»: no le gana a una tarjeta por vencer ni a uno pasado de verdad',
      () {
        final atLimit = budgetOf(exceeded, percentage: 100, category: 'mercado');
        expect(pickHomeNotice(cards: [cardOf(2)], budgets: [atLimit])!.kind, HomeNoticeKind.cardSoon);
        final notice = pickHomeNotice(budgets: [atLimit, budgetOf(exceeded, percentage: 100.01)])!;
        expect(notice.kind, HomeNoticeKind.budgetExceeded);
        expect(notice.budget!.category, 'vivienda');
      },
    );

    test('entre dos tarjetas con el mismo plazo gana la primera que mandó el servidor', () {
      // List.sort de Dart no es estable: con muchas empatadas se notaría.
      final tied = [for (var i = 0; i < 40; i++) cardOf(5, id: 'c$i')];
      expect(pickHomeNotice(cards: tied)!.card!.id, 'c0');
      expect(
        pickHomeNotice(
          cards: [
            cardOf(9, id: 'x'),
            ...tied,
          ],
        )!.card!.id,
        'c0',
      );
      final late = [cardOf(-2, id: 'a'), cardOf(-2, id: 'b')];
      expect(pickHomeNotice(cards: late)!.card!.id, 'a');
    });

    test(
      'una tarjeta sin días hasta el pago no llega al aviso (la web dice «se paga en undefined días»)',
      () {
        final raw = {
          'id': 9,
          'name': 'Mi Visa',
          'network': 'visa',
          'last4': '4242',
          'used': 320000,
          'paidThisCycle': false,
        };
        final cards = [?CardSummary.tryParse(raw)];
        expect(cards, isEmpty);
        expect(pickHomeNotice(cards: cards), isNull);
      },
    );
  });
}
