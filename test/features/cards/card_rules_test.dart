// Reglas puras de Tarjetas: solo presentación (textos de cardFormat.js, %, «Debes en total» en
// centavos, vista previa del banco) y los cuerpos que se envían (PUT con solo lo que cambió, sync sin
// opcionales vacíos). Los importes autoritativos son del servidor y aquí solo se leen.
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart' show ContractException;
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/domain/card_rules.dart';

import '../../support/card_fixtures.dart';

const _t = Tr('es', {});
const _co = kDefaultRegion;

Map<String, String> _problems({
  String network = 'visa',
  String tier = 'clasica',
  String last4 = '4242',
  String name = '',
  String expiry = '',
  num? limit = 2000000,
  num? available = 1500000,
  String paymentDay = '15',
  String cutoffDay = '',
  bool editing = false,
}) => cardFormProblems(
  _t,
  network: network,
  tier: tier,
  last4: last4,
  name: name,
  expiry: expiry,
  limit: limit,
  available: available,
  paymentDay: paymentDay,
  cutoffDay: cutoffDay,
  editing: editing,
);

void main() {
  group('modelo estricto (forma de QA)', () {
    test('lee la tarjeta de QA tal cual, sin inventar ceros', () {
      final card = cardOfJson();
      expect(card.used, 500000);
      expect(card.available, 1500000);
      expect(card.statementTotal, isNull);
      expect(card.expiry, isNull);
      expect(card.cutoffDay, 30);
      expect(card.nextPaymentDate, '2026-12-15');
    });

    test('sin «used» (o no numérico) es error del bloque, no una tarjeta en cero', () {
      expect(() => CreditCard.fromJson({...cardJson()}..remove('used')), throwsA(isA<ContractException>()));
      expect(() => CreditCard.fromJson({...cardJson(), 'used': '500000'}), throwsA(isA<ContractException>()));
      expect(
        () => CreditCard.fromJson({...cardJson(), 'daysToPayment': null}),
        throwsA(isA<ContractException>()),
      );
    });

    test('available negativo (compras por encima del cupo) se acepta y la barra se topa en 100', () {
      final card = creditCard(limit: 1000000, used: 1200000);
      expect(card.available, -200000);
      expect(usagePercent(card), 100);
    });

    test('vencimiento: null sin fecha y el de servidor si la hay', () {
      final card = creditCard(
        expiry: {'label': '03/27', 'expired': false, 'soon': true},
        expiryMonth: 3,
        expiryYear: 2027,
      );
      expect(card.expiry!.label, '03/27');
      expect(card.expiry!.soon, isTrue);
    });

    test('movimiento de tarjeta: pago, ajuste negativo sin descripción, compra con cuotas', () {
      final payment = CardMovement.fromJson({
        'kind': 'payment',
        'id': 'p1',
        'date': '2026-11-23',
        'amount': 100000,
      });
      expect(payment.kind, CardMovementKind.payment);
      final adjustment = CardMovement.fromJson({
        'kind': 'adjustment',
        'id': 'a1',
        'date': '2026-11-23',
        'amount': -34000,
      });
      expect(adjustment.amount, -34000);
      expect(adjustment.description, isNull);
      expect(
        () => CardMovement.fromJson({'kind': 'otro', 'id': 'x', 'date': '2026-11-23', 'amount': 1}),
        throwsA(isA<ContractException>()),
      );
    });
  });

  group('textos de cardFormat.js', () {
    test('paymentText: al día, atrasado, hoy, 1 día y N días con la fecha corta', () {
      expect(paymentText(_t, creditCard(paidThisCycle: true), _co), 'Pago de este mes al día');
      expect(
        paymentText(_t, creditCard(daysToPayment: -3, nextPaymentDate: '2026-11-20'), _co),
        'Pago atrasado desde el 20 nov',
      );
      expect(
        paymentText(_t, creditCard(daysToPayment: 0, nextPaymentDate: '2026-11-23'), _co),
        'Pagas hoy (23 nov)',
      );
      expect(
        paymentText(_t, creditCard(daysToPayment: 1, nextPaymentDate: '2026-11-24'), _co),
        'Pagas en 1 día (24 nov)',
      );
      expect(paymentText(_t, creditCard(), _co), 'Pagas en 22 días (15 dic)');
      expect(paymentText(_t, creditCard(nextPaymentDate: null), _co), 'Pagas en 22 días');
    });

    test('dueText: hoy, mañana, en N días; pagada o atrasada cae en paymentText', () {
      expect(dueText(_t, creditCard(daysToPayment: 0), _co), 'Se paga hoy');
      expect(dueText(_t, creditCard(daysToPayment: 1), _co), 'Se paga mañana');
      expect(dueText(_t, creditCard(daysToPayment: 5), _co), 'Se paga en 5 días');
      expect(dueText(_t, creditCard(paidThisCycle: true), _co), 'Pago de este mes al día');
      expect(
        dueText(_t, creditCard(daysToPayment: -1, nextPaymentDate: '2026-11-22'), _co),
        'Pago atrasado desde el 22 nov',
      );
    });

    test('«Pago atrasado» sin deuda NO se dice (se aparta de la web, como el aviso del Inicio)', () {
      expect(showDueLine(creditCard(daysToPayment: -2, used: 0)), isFalse);
      expect(showDueLine(creditCard(daysToPayment: -2, used: 1)), isTrue);
      expect(showDueLine(creditCard(daysToPayment: 4, used: 0)), isTrue);
      expect(showDueLine(creditCard(daysToPayment: -2, used: 0, paidThisCycle: true)), isTrue);
    });

    test('expiryNotice: vencida, por vencer o nada', () {
      expect(expiryNotice(_t, const CardExpiry(label: '03/26', expired: true, soon: false)), (
        text: 'Vencida (03/26) · actualiza la fecha',
        expired: true,
      ));
      expect(
        expiryNotice(_t, const CardExpiry(label: '01/27', expired: false, soon: true))!.text,
        'Vence pronto (01/27) · pide la nueva al banco',
      );
      expect(expiryNotice(_t, const CardExpiry(label: '01/29', expired: false, soon: false)), isNull);
      expect(expiryNotice(_t, null), isNull);
    });

    test('etiqueta «{Franquicia} ••{last4}»; «otra» dice «Otra» y una red desconocida usa el nombre', () {
      expect(cardListLabel(_t, network: 'visa', name: 'Mi Visa', last4: '4242'), 'Visa ••4242');
      expect(cardListLabel(_t, network: 'otra', name: 'Falabella', last4: '1111'), 'Otra ••1111');
      expect(cardListLabel(_t, network: 'diners', name: 'Diners', last4: '9'), 'Diners ••9');
    });
  });

  group('lo único que calcula el cliente', () {
    test('el % redondeado y topado; con cupo 0 no se divide', () {
      expect(usagePercent(creditCard(limit: 3000000, used: 616000)), 21);
      expect(usagePercent(creditCard(limit: 3, used: 2)), 67);
      expect(usagePercent(creditCard(limit: 0, used: 10, available: -10)), 0);
    });

    test('«Debes en total» se suma en CENTAVOS (la web suma flotantes y arrastra residuos)', () {
      final cards = [creditCard(used: 0.1), creditCard(used: 0.2), creditCard(used: 1000000.7)];
      expect(debtTotal(cards), 1000001);
      expect(debtTotal([creditCard(used: 0.1), creditCard(used: 0.2)]), 0.3);
      expect(debtTotal(const []), 0);
    });

    test('la próxima a pagar: sin pagar, la de menos días; no la atrasada sin deuda', () {
      final a = creditCard(id: 'a', daysToPayment: 5);
      final b = creditCard(id: 'b', daysToPayment: 2);
      final paid = creditCard(id: 'c', daysToPayment: 0, paidThisCycle: true);
      final lateEmpty = creditCard(id: 'd', daysToPayment: -4, used: 0);
      expect(nextDueCard([a, b, paid, lateEmpty])!.id, 'b');
      expect(nextDueCard([paid, lateEmpty]), isNull);
    });

    test('vista previa del banco igual a cardFormat.test.js', () {
      final card = creditCard(limit: 3000000, used: 616000);
      expect(syncDifference(card, 2350000), 34000);
      expect(syncDifference(card, 2384000), 0);
      expect(syncDifference(card, 2400000), -16000);
      expect(syncDifference(card, null), isNull);
      expect(syncDifference(creditCard(limit: 100.3, used: 0.1), 100.1), closeTo(0.1, 1e-9));
    });

    test('la barra del vencimiento se pone sola: MM/AA', () {
      expect(formatExpiry('0'), '0');
      expect(formatExpiry('032'), '03/2');
      expect(formatExpiry('0327'), '03/27');
      expect(formatExpiry('03/27'), '03/27');
      expect(formatExpiry('12345'), '12/34');
      expect(parseExpiry('03/27'), (3, 2027));
      expect(parseExpiry(''), isNull);
    });
  });

  group('validaciones de lib/validation/card.js', () {
    test('cada mensaje, con su campo', () {
      expect(_problems(), isEmpty);
      expect(_problems(last4: '42a2')['last4'], 'Escribe exactamente 4 dígitos');
      expect(_problems(last4: '424')['last4'], 'Escribe exactamente 4 dígitos');
      expect(_problems(name: 'x' * 41)['name'], 'Máximo 40 caracteres');
      expect(_problems(name: 'x' * 40), isEmpty);
      expect(_problems(expiry: '13/27')['expiry'], 'Escribe el mes y el año: MM/AA');
      expect(_problems(expiry: '3/27')['expiry'], 'Escribe el mes y el año: MM/AA');
      expect(_problems(limit: null)['limit'], 'Ingresa un monto');
      expect(_problems(limit: 0)['limit'], 'El cupo debe ser mayor que 0');
      expect(_problems(limit: 10000000000)['limit'], 'El monto es demasiado grande');
      expect(_problems(available: null)['available'], 'Ingresa un monto');
      expect(_problems(available: 2000001)['available'], 'No puede ser mayor que el cupo total');
      expect(_problems(available: 0), isEmpty);
      expect(_problems(paymentDay: '')['paymentDay'], 'Ingresa un día');
      expect(_problems(paymentDay: '32')['paymentDay'], 'Del 1 al 31');
      expect(_problems(paymentDay: '0')['paymentDay'], 'Del 1 al 31');
      expect(_problems(paymentDay: '31'), isEmpty);
      expect(_problems(cutoffDay: '40')['cutoffDay'], 'Del 1 al 31');
      expect(_problems(cutoffDay: ''), isEmpty);
    });

    test('editar no pide «Cupo disponible hoy»', () {
      expect(_problems(available: null, editing: true), isEmpty);
    });

    test('cada franquicia solo con sus niveles', () {
      for (final MapEntry(key: network, value: tiers) in cardTiers.entries) {
        for (final tier in const ['clasica', 'gold', 'platinum', 'black', 'green', 'blue']) {
          expect(
            _problems(network: network, tier: tier).containsKey('tier'),
            !tiers.contains(tier),
            reason: '$network $tier',
          );
        }
      }
      expect(_problems(network: 'amex', tier: 'clasica')['tier'], 'Elige un tipo de tarjeta');
    });
  });

  group('cuerpos', () {
    Map<String, dynamic>? body(
      CreditCard? initial, {
      String network = 'visa',
      String tier = 'clasica',
      String last4 = '4242',
      String limit = '2000000',
      String available = '1500000',
      String paymentDay = '15',
      String name = '',
      String cutoffDay = '30',
      String expiry = '',
    }) => cardBody(
      initial,
      network: network,
      tier: tier,
      last4: last4,
      limit: limit,
      available: available,
      paymentDay: paymentDay,
      name: name,
      cutoffDay: cutoffDay,
      expiry: expiry,
    );

    test('crear: montos y días como NÚMEROS JSON; sin nombre vacío; vencimiento en el par', () {
      expect(body(null, limit: '2000000.5', cutoffDay: '', expiry: '03/27'), {
        'network': 'visa',
        'tier': 'clasica',
        'last4': '4242',
        'limit': 2000000.5,
        'available': 1500000,
        'paymentDay': 15,
        'expiryMonth': 3,
        'expiryYear': 2027,
      });
      expect(body(null, name: '  Mi Visa ')!['name'], 'Mi Visa');
    });

    test('editar: SOLO lo que cambió y nunca available', () {
      final initial = creditCard(cutoffDay: 30);
      expect(body(initial, name: initial.name), isNull, reason: 'nada cambió: no se envía nada');
      expect(body(initial, available: '1', name: initial.name), isNull);
      expect(body(initial, limit: '2500000', name: initial.name), {'limit': 2500000});
      expect(body(initial, last4: '1111', name: initial.name), {'last4': '1111'});
      // Cambiar la franquicia manda también el nivel (el servidor los valida juntos).
      expect(body(initial, network: 'mastercard', name: initial.name), {
        'network': 'mastercard',
        'tier': 'clasica',
      });
      // Borrar el corte va en null; un nombre borrado no se envía (con "" daría 422).
      expect(body(initial, cutoffDay: '', name: ''), {'cutoffDay': null});
    });

    test('editar el vencimiento: el par siempre junto, y null para borrarlo', () {
      final initial = creditCard(expiryMonth: 3, expiryYear: 2027);
      expect(body(initial, expiry: '03/27', name: initial.name), isNull);
      expect(body(initial, expiry: '04/27', name: initial.name), {'expiryMonth': 4, 'expiryYear': 2027});
      expect(body(initial, expiry: '', name: initial.name), {'expiryMonth': null, 'expiryYear': null});
    });

    test('actualizar con el banco: los opcionales vacíos SE OMITEN (null da 422)', () {
      expect(bankSyncBody(available: '1300000', statementTotal: ''), {'available': 1300000});
      expect(bankSyncBody(available: '0', statementTotal: '250000.5', statementDueDate: '2026-12-10'), {
        'available': 0,
        'statementTotal': 250000.5,
        'statementDueDate': '2026-12-10',
      });
    });
  });
}
