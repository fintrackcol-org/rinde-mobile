// Reglas puras de Cuentas: la copia de debtSchedule.js con los casos de debtSchedule.test.js, los
// textos de lib/debts.js (con los casos de debts.test.js), las validaciones de lib/validation/debt.js
// (y la de B4 que agrega la app), los cuerpos que se envían y el modelo estricto.
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/debts/data/debt_models.dart';
import 'package:rinde_mobile/features/debts/domain/debt_rules.dart';
import 'package:rinde_mobile/features/debts/domain/debt_schedule.dart';

import '../../support/debt_fixtures.dart';

const _t = Tr('es', {});
String _money(num n) => '\$$n';

DebtFormValues _form({
  String person = 'Laura',
  String amount = '200000',
  String? loanDate = '2026-11-01',
  bool inInstallments = false,
  String installments = '4',
  DebtFrequency frequency = DebtFrequency.monthly,
  String? dueDate,
  String note = '',
}) => DebtFormValues(
  person: person,
  amount: amount,
  loanDate: loanDate,
  inInstallments: inInstallments,
  installments: installments,
  frequency: frequency,
  dueDate: dueDate,
  note: note,
);

void main() {
  group('debtSchedule (copia de la web y del servidor)', () {
    test('mensual se queda en el último día de los meses cortos; quincena = +15 días', () {
      expect(addPeriods('2027-01-31', DebtFrequency.monthly, 1), '2027-02-28');
      expect(addPeriods('2026-11-15', DebtFrequency.biweekly, 2), '2026-12-15');
      expect(addPeriods('2026-11-15', DebtFrequency.biweekly, 1), '2026-11-30');
      expect(addPeriods('2026-11-15', DebtFrequency.weekly, 2), '2026-11-29');
      // Bisiesto y cambio de año.
      expect(addPeriods('2027-12-31', DebtFrequency.monthly, 2), '2028-02-29');
    });

    test('la última cuota absorbe los centavos', () {
      final cuotas = schedule(
        amount: 100000,
        installments: 3,
        frequency: DebtFrequency.monthly,
        firstDueDate: '2026-12-01',
      );
      expect([for (final c in cuotas) c.amount], [33333.33, 33333.33, 33333.34]);
      expect([for (final c in cuotas) c.number], [1, 2, 3]);
    });

    test('3 cuotas mensuales que caen el 31: cada mes en su último día si es más corto', () {
      final cuotas = schedule(
        amount: 90000,
        installments: 3,
        frequency: DebtFrequency.monthly,
        firstDueDate: '2027-01-31',
      );
      expect([for (final c in cuotas) c.date], ['2027-01-31', '2027-02-28', '2027-03-31']);
    });

    test('un abono parcial deja la cuota en curso con lo que falta', () {
      final p = progress(
        amount: 200000,
        paid: 70000,
        installments: 4,
        frequency: DebtFrequency.monthly,
        firstDueDate: '2026-12-01',
      );
      expect((p.paid, p.pending, p.paidInstallments), (70000, 130000, 1));
      expect((p.next!.number, p.next!.date, p.next!.amount), (2, '2027-01-01', 30000));
    });

    test('de una vez: una sola «cuota» con lo pendiente en su fecha; sin fecha, ninguna', () {
      final fixed = progress(amount: 60000, paid: 10000, dueDate: '2026-12-10');
      expect((fixed.pending, fixed.next!.number, fixed.next!.amount), (50000, 1, 50000));
      expect(progress(amount: 60000, paid: 0).next, isNull);
      expect(progress(amount: 60000, paid: 60000, dueDate: '2026-12-10').next, isNull);
    });
  });

  group('textos de lib/debts.js', () {
    const today = '2026-11-04';
    const region = kDefaultRegion;

    test('dueText: sin fecha no dice nada; cerca de hoy usa palabras; lejos, la fecha', () {
      expect(debtDueText(_t, null, today, region), isNull);
      expect(debtDueText(_t, '2026-11-04', today, region), (text: 'Vence hoy', late: false));
      expect(debtDueText(_t, '2026-11-05', today, region), (text: 'Vence mañana', late: false));
      expect(debtDueText(_t, '2026-11-09', today, region), (text: 'Vence en 5 días', late: false));
      expect(debtDueText(_t, '2026-11-03', today, region), (text: 'Venció ayer', late: true));
      expect(debtDueText(_t, '2026-10-30', today, region), (text: 'Venció hace 5 días', late: true));
      expect(debtDueText(_t, '2026-12-15', today, region)!.text, 'Vence el 15 dic');
      expect(debtDueText(_t, '2027-01-20', today, region)!.text, 'Vence el 20 ene 2027');
    });

    test('progressText cuenta las cuotas', () {
      expect(
        debtProgressText(_t, debtOf(debtJson(amount: 200, paid: 50, installments: 4)), _money),
        'Pagado \$50 de \$200 · 1 de 4 cuotas',
      );
      expect(debtProgressText(_t, debtOf(onceJson(amount: 200)), _money), 'Pagado \$0 de \$200');
    });

    test('iniciales', () {
      expect(debtInitials('Laura Gómez Ruiz'), 'LR');
      expect(debtInitials('mamá'), 'M');
      expect(debtInitials('  '), '?');
      expect(debtInitials('🙂 Ana'), '🙂A');
    });

    test('fecha corta: el año solo si no es este', () {
      expect(debtShortDate('2026-11-12', today, region), '12 nov');
      expect(debtShortDate('2027-11-12', today, region), '12 nov 2027');
      // En inglés, el mes primero, como «Due {v2} {d}» (se vio «the 9 Nov» junto a «due dec 9» en el emulador).
      const en = Region(country: 'US', currency: 'USD', language: 'en');
      expect(debtShortDate('2026-11-12', today, en), 'Nov 12');
      expect(debtShortDate('2027-11-12', today, en), 'Nov 12 2027');
    });

    test('septiembre es «sept» como MONTHS de la web; en inglés y portugués, el mes del idioma', () {
      expect(debtShortDate('2026-09-12', today, region), '12 sept');
      expect(debtDueText(_t, '2027-09-30', today, region)!.text, 'Vence el 30 sept 2027');
      expect(debtShortDate('2026-09-12', today, region.copyLanguage('en')), 'Sep 12');
      expect(debtShortDate('2026-09-12', today, region.copyLanguage('pt')), '12 set');
    });

    test('las palabras de cada lado', () {
      expect(debtWords(_t, DebtKind.receivable).settleAll, 'Ya me pagó todo');
      expect(debtWords(_t, DebtKind.payable).settleAll, 'Ya pagué todo');
      expect(debtWords(_t, DebtKind.receivable).left, 'Te falta recibir');
      expect(debtWords(_t, DebtKind.payable).movement, 'Registrar el gasto en Movimientos');
    });
  });

  group('validación (lib/validation/debt.js)', () {
    test('cada mensaje de la web', () {
      expect(debtFormProblems(_t, _form()), isEmpty);
      expect(debtFormProblems(_t, _form(person: ' '))['person'], 'Escribe el nombre');
      expect(debtFormProblems(_t, _form(person: 'x' * 61))['person'], 'Máximo 60 caracteres');
      expect(debtFormProblems(_t, _form(person: 'x' * 60)), isEmpty);
      expect(debtFormProblems(_t, _form(amount: ''))['amount'], 'Ingresa un monto');
      expect(debtFormProblems(_t, _form(amount: 'abc'))['amount'], 'Ingresa un monto válido');
      expect(debtFormProblems(_t, _form(amount: '0'))['amount'], 'El monto debe ser mayor que 0');
      expect(debtFormProblems(_t, _form(amount: '99999999999'))['amount'], 'El monto es demasiado grande');
      expect(debtFormProblems(_t, _form(note: 'x' * 201))['note'], 'Máximo 200 caracteres');
    });

    test('en cuotas pide de 2 a 60 y la fecha de la primera, que no sea antes del préstamo', () {
      List<String> fields(DebtFormValues v) => debtFormProblems(_t, v).keys.toList();
      expect(fields(_form(inInstallments: true, installments: '1', dueDate: '2026-12-01')), ['installments']);
      expect(fields(_form(inInstallments: true, installments: '61', dueDate: '2026-12-01')), [
        'installments',
      ]);
      expect(fields(_form(inInstallments: true, installments: '60', dueDate: '2026-12-01')), isEmpty);
      expect(
        debtFormProblems(_t, _form(inInstallments: true))['dueDate'],
        'Elige la fecha de la primera cuota',
      );
      expect(
        debtFormProblems(_t, _form(inInstallments: true, dueDate: '2026-10-01'))['dueDate'],
        'No puede ser antes del préstamo',
      );
      // También de una vez.
      expect(
        debtFormProblems(_t, _form(dueDate: '2026-10-01'))['dueDate'],
        'No puede ser antes del préstamo',
      );
    });

    test('B4: al editar, el monto tiene que ser MAYOR que lo ya abonado (igual traba la cuenta)', () {
      String? amount(String raw) =>
          debtFormProblems(_t, _form(amount: raw), paid: 100000, paidText: r'$ 100.000')['amount'];
      expect(amount('99999'), r'Tiene que ser mayor que lo que ya se abonó ($ 100.000)');
      expect(amount('100000'), r'Tiene que ser mayor que lo que ya se abonó ($ 100.000)');
      expect(amount('100000.01'), isNull);
      // Sin abonos no hay regla extra.
      expect(debtFormProblems(_t, _form(amount: '1')), isEmpty);
    });

    test('el abono no pasa de lo pendiente (tolerancia 0,004)', () {
      Map<String, String> pay(String raw) =>
          debtPaymentProblems(_t, amount: raw, pending: 200000, pendingText: r'$ 200.000');
      expect(pay('200000'), isEmpty);
      expect(pay('200000.004'), isEmpty);
      expect(pay('200000.01')['amount'], r'No puede pasar de lo que falta ($ 200.000)');
      expect(pay('')['amount'], 'Ingresa un monto');
      expect(pay('0')['amount'], 'El monto debe ser mayor que 0');
    });
  });

  group('cuerpos que se envían', () {
    test('POST: kind, montos y cuotas como números, opcionales en null y SIN reminder', () {
      final body = debtBody(
        _form(
          person: ' Laura ',
          amount: '60000.5',
          inInstallments: true,
          installments: '3',
          dueDate: '2026-12-01',
        ),
        kind: DebtKind.receivable,
      );
      expect(body, {
        'kind': 'receivable',
        'person': 'Laura',
        'amount': 60000.5,
        'loanDate': '2026-11-01',
        'dueDate': '2026-12-01',
        'installments': 3,
        'frequency': 'monthly',
        'note': null,
      });
      expect(body.containsKey('reminder'), isFalse);
    });

    test('PUT: sin kind ni reminder; de una vez, cuotas y frecuencia en null', () {
      final body = debtBody(_form(loanDate: null, dueDate: null, note: ' bus '));
      expect(body, {
        'person': 'Laura',
        'amount': 200000,
        'loanDate': null,
        'dueDate': null,
        'installments': null,
        'frequency': null,
        'note': 'bus',
      });
    });

    test('vista previa: «{n} cuotas de {monto} · la última el {fecha}»', () {
      String? preview(DebtFormValues v) =>
          debtPlanPreview(_t, v, today: '2026-11-04', region: kDefaultRegion, money: _money);
      expect(
        preview(_form(amount: '90000', inInstallments: true, installments: '3', dueDate: '2027-01-31')),
        r'3 cuotas de $30000 · la última el 31 mar 2027',
      );
      expect(
        preview(
          _form(
            amount: '100000',
            inInstallments: true,
            installments: '3',
            frequency: DebtFrequency.biweekly,
            dueDate: '2026-11-15',
          ),
        ),
        r'3 cuotas de $33333.33 · la última el 15 dic',
      );
      expect(preview(_form(inInstallments: true, installments: '1', dueDate: '2026-12-01')), isNull);
      expect(preview(_form(inInstallments: true)), isNull);
      expect(preview(_form(dueDate: '2026-12-01')), isNull);
    });
  });

  group('modelo estricto (formas de QA)', () {
    test('lee la cuenta en cuotas de QA: dueDate es la próxima, firstDueDate la primera', () {
      final debt = debtOf();
      expect((debt.kind, debt.installments, debt.frequency), (DebtKind.payable, 3, DebtFrequency.monthly));
      expect((debt.dueDate, debt.firstDueDate), ('2027-01-01', '2026-12-01'));
      expect((debt.paid, debt.pending, debt.paidInstallments), (100000, 200000, 1));
      expect(debt.nextInstallment!.number, 2);
      expect(debt.payments.single.transactionId, '359a15f5-01db-4c28-9f5d-f7ab570d9f11');
      expect(debt.settled, isFalse);
    });

    test('la respuesta de saldar trae payments vacío y sin reminder: también se lee', () {
      final json = debtJson(settledAt: '2026-11-23T22:44:27.165Z', transactionId: 'm1', payments: const [])
        ..remove('reminder');
      final debt = debtOf(json);
      expect((debt.settled, debt.pending, debt.nextInstallment), (true, 0, null));
    });

    test('una cuenta ilegible falla la lista entera (no se esconde)', () {
      for (final broken in [
        {...debtJson()}..remove('pending'),
        {...debtJson(), 'kind': 'otro'},
        {...debtJson(), 'frequency': 'diaria'},
        {...debtJson(), 'amount': '300000'},
        {...debtJson(), 'payments': null},
        {...debtJson(), 'dueDate': '1/12/2026'},
      ]) {
        expect(() => debtsOf([onceJson(), broken]), throwsA(isA<ContractException>()), reason: '$broken');
      }
    });

    test('los totales vienen del servidor', () {
      final list = debtsOf([debtJson(), onceJson()]);
      expect((list.total(DebtKind.payable), list.total(DebtKind.receivable)), (200000, 60000));
    });
  });
}
