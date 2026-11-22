import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';

CommitmentItem _item(String name, {String amount = '100000', String day = '5', String key = 'k'}) =>
    CommitmentItem(key: key, name: name, amount: amount, dayOfMonth: day);

void main() {
  group('toApi (toApiSources de la web)', () {
    test('sueldo vacío: frecuencia mensual y montos null', () {
      expect(IncomeSourceForm.empty(IncomeKind.sueldo).toApi(), {
        'kind': 'sueldo',
        'frequency': 'mensual',
        'payDays': <int>[],
        'amount': null,
        'low': null,
        'high': null,
        'lastMonths': <num>[],
        'workDays': null,
      });
    });

    test('sueldo con monto y días de pago', () {
      final api = const IncomeSourceForm(
        kind: IncomeKind.sueldo,
        amount: '2500000',
        payDays: [15, 30],
      ).toApi();
      expect(api['amount'], 2500000);
      expect(api['payDays'], [15, 30]);
      expect(api['frequency'], 'mensual');
      expect(api['workDays'], isNull);
    });

    test('comisiones: mensual por respaldo, rango con vacíos en null', () {
      final api = const IncomeSourceForm(
        kind: IncomeKind.comisiones,
        amount: '1000000',
        low: '200000',
        payDays: [5],
      ).toApi();
      expect(api, {
        'kind': 'comisiones',
        'frequency': 'mensual',
        'payDays': [5],
        'amount': 1000000,
        'low': 200000,
        'high': null,
        'lastMonths': <num>[],
        'workDays': null,
      });
    });

    test('proyectos: irregular, sin monto ni días, lastMonths filtra vacíos y 0 y pierde la posición', () {
      final api = const IncomeSourceForm(
        kind: IncomeKind.proyectos,
        amount: '999',
        payDays: [10],
        lastMonths: ['', '2000000', '0'],
      ).toApi();
      expect(api['frequency'], 'irregular');
      expect(api['amount'], isNull);
      expect(api['payDays'], isEmpty);
      expect(api['lastMonths'], [2000000]);
      // Caso de la prueba web (incomeSources.test.js).
      expect(
        const IncomeSourceForm(
          kind: IncomeKind.proyectos,
          lastMonths: ['3000000', '', '2500000'],
        ).toApi()['lastMonths'],
        [3000000, 2500000],
      );
    });

    test('diario: frecuencia diario y workDays entero solo aquí', () {
      final api = const IncomeSourceForm(kind: IncomeKind.diario, amount: '70000').toApi();
      expect(api['frequency'], 'diario');
      expect(api['amount'], 70000);
      expect(api['workDays'], 6);
      expect(api['workDays'], isA<int>());
      expect(api['payDays'], isEmpty);
      for (final kind in IncomeKind.values.where((k) => k != IncomeKind.diario)) {
        expect(IncomeSourceForm.empty(kind).toApi()['workDays'], isNull, reason: kind.name);
      }
    });

    test('mesada: usa la frecuencia elegida y nunca manda días de pago', () {
      expect(IncomeSourceForm.empty(IncomeKind.mesada).toApi()['frequency'], 'mensual');
      final api = const IncomeSourceForm(
        kind: IncomeKind.mesada,
        amount: '300000',
        frequency: 'quincenal',
        payDays: [10],
      ).toApi();
      expect(api['frequency'], 'quincenal');
      expect(api['payDays'], isEmpty);
      expect(api['amount'], 300000);
    });

    test('un monto que termina en punto se lee como entero ("12." → 12)', () {
      expect(const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '12.').toApi()['amount'], 12);
      expect(const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '12.5').toApi()['amount'], 12.5);
    });
  });

  group('toggleKind', () {
    test('guarda el orden de selección y no cambia el mapa original', () {
      var forms = <IncomeKind, IncomeSourceForm>{};
      forms = toggleKind(forms, IncomeKind.proyectos);
      forms = toggleKind(forms, IncomeKind.sueldo);
      final before = forms;
      forms = toggleKind(forms, IncomeKind.mesada);
      expect(forms.keys, [IncomeKind.proyectos, IncomeKind.sueldo, IncomeKind.mesada]);
      expect(before.keys, [IncomeKind.proyectos, IncomeKind.sueldo]);
    });

    test('desmarcar borra lo escrito; volver a marcar empieza vacío y al final', () {
      var forms = toggleKind(const {}, IncomeKind.sueldo);
      forms = {...forms, IncomeKind.sueldo: forms[IncomeKind.sueldo]!.copyWith(amount: '2000000')};
      forms = toggleKind(forms, IncomeKind.diario);
      forms = toggleKind(forms, IncomeKind.sueldo);
      expect(forms.keys, [IncomeKind.diario]);
      forms = toggleKind(forms, IncomeKind.sueldo);
      expect(forms.keys, [IncomeKind.diario, IncomeKind.sueldo]);
      expect(forms[IncomeKind.sueldo]!.amount, '');
      // Como la web: marcar dos veces deja el mapa vacío.
      expect(toggleKind(toggleKind(const {}, IncomeKind.mesada), IncomeKind.mesada), isEmpty);
    });
  });

  group('togglePayDay', () {
    test('agrega ordenado y quita', () {
      var days = togglePayDay(const [], 30);
      days = togglePayDay(days, 15);
      expect(days, [15, 30]);
      expect(togglePayDay(days, 30), [15]);
    });

    test('tope de 4: el quinto no entra, pero se puede quitar uno', () {
      const full = [1, 10, 20, 30];
      expect(togglePayDay(full, 5), full);
      expect(togglePayDay(full, 10), [1, 20, 30]);
      expect(maxPayDays, 4);
    });
  });

  group('readCommitment (readCommitmentForm de la web)', () {
    const es = Tr('es', {});

    test('nombre vacío o solo espacios', () {
      for (final name in ['', '   ']) {
        final p = readCommitment(_item(name, amount: '', day: '')).problem!;
        expect(p.message, 'Escribe el nombre del pago.');
        expect(p.key, 'k');
      }
    });

    test('monto vacío, 0 o ilegible, con el nombre recortado', () {
      for (final amount in ['', '0', '0.', 'abc']) {
        final p = readCommitment(_item('  Arriendo ', amount: amount, day: '')).problem!;
        expect(p.message, 'Escribe cuánto pagas por {cleanName}.', reason: amount);
        expect(p.vars, {'cleanName': 'Arriendo'});
        expect(es(p.message, p.vars), 'Escribe cuánto pagas por Arriendo.');
      }
    });

    test("día '0', '32', '' o con letras", () {
      for (final day in ['0', '32', '', '1a']) {
        final p = readCommitment(_item('Internet', day: day)).problem!;
        expect(p.message, 'Escribe un día entre 1 y 31 para {cleanName}.', reason: day);
        expect(es(p.message, p.vars), 'Escribe un día entre 1 y 31 para Internet.');
      }
    });

    test("válido: cuerpo exacto; monto '12.' se lee 12; días 1 y 31 son válidos", () {
      expect(readCommitment(_item(' Celular ', amount: '12.', day: '31')).data, {
        'name': 'Celular',
        'amount': 12,
        'dayOfMonth': 31,
        'kind': 'fixed',
        'frequency': 'monthly',
        'month': null,
      });
      expect(readCommitment(_item('Cuota', amount: '12.5', day: '1')).data?['amount'], 12.5);
      expect(readCommitment(_item('Cuota', day: '1')).problem, isNull);
    });

    test('las claves de los mensajes con variable existen en las traducciones de la web', () {
      // La web usa {cleanName}: 'Escribe cuánto pagas por {cleanName}.' (lib/moneyProfile.js:86-87).
      final en = jsonDecode(File('assets/l10n/en.json').readAsStringSync()) as Map<String, dynamic>;
      final amount = readCommitment(_item('Arriendo', amount: '')).problem!;
      final day = readCommitment(_item('Arriendo', day: '')).problem!;
      expect(en.containsKey(amount.message), isTrue, reason: amount.message);
      expect(en.containsKey(day.message), isTrue, reason: day.message);
    });

    test('los t() dentro de una interpolación también llegan a las traducciones (tool/export_l10n.mjs)', () {
      final en = jsonDecode(File('assets/l10n/en.json').readAsStringSync()) as Map<String, dynamic>;
      final pt = jsonDecode(File('assets/l10n/pt.json').readAsStringSync()) as Map<String, dynamic>;
      for (final key in [
        '· almuerzo',
        'de',
        '· 4 amigos',
        'Listo, anoté un ingreso de',
        '. Hoy llevas',
        'millón',
      ]) {
        expect(en.containsKey(key), isTrue, reason: key);
        expect(pt.containsKey(key), isTrue, reason: key);
      }
    });
  });

  group('readCommitments', () {
    test('todos válidos: en orden', () {
      final read = readCommitments([
        _item('Arriendo', amount: '800000', key: 'a'),
        _item('Internet', amount: '90000', day: '20', key: 'b'),
      ]);
      expect(read.problem, isNull);
      expect(read.commitments.map((c) => c['name']), ['Arriendo', 'Internet']);
    });

    test('nombre repetido sin importar mayúsculas ni espacios: marca el segundo', () {
      final read = readCommitments([_item('Arriendo', key: 'a'), _item('  ARRIENDO ', key: 'b')]);
      expect(read.commitments, isEmpty);
      expect(read.problem!.key, 'b');
      expect(read.problem!.message, 'Ya agregaste {name}. Cambia el nombre o quítalo.');
      expect(read.problem!.vars, {'name': 'ARRIENDO'});
    });

    test('el primer problema en orden gana, aunque haya un repetido después', () {
      final read = readCommitments([
        _item('Internet', key: 'a'),
        _item('Celular', amount: '', key: 'b'),
        _item('internet', key: 'c'),
      ]);
      expect(read.problem!.key, 'b');
      expect(read.problem!.message, 'Escribe cuánto pagas por {cleanName}.');
    });

    test('sin pagos: lista vacía y sin problema', () {
      final read = readCommitments(const []);
      expect(read.commitments, isEmpty);
      expect(read.problem, isNull);
    });
  });

  group('welcomeBody', () {
    test("saldo '' → null (no 0) y sin commitments cuando es omitir", () {
      final body = welcomeBody(balance: '');
      expect(body, {'incomeType': null, 'payDays': <int>[], 'balance': null});
      expect(body.containsKey('commitments'), isFalse);
    });

    test("saldo '0' → 0; '1234567.5' → 1234567.5; '12.' → 12", () {
      expect(welcomeBody(balance: '0')['balance'], 0);
      expect(welcomeBody(balance: '1234567.5')['balance'], 1234567.5);
      expect(welcomeBody(balance: '12.')['balance'], 12);
    });

    test('con commitments (también vacíos, como la web al terminar sin pagos)', () {
      final c = [
        {'name': 'Arriendo', 'amount': 800000},
      ];
      expect(welcomeBody(balance: '5', commitments: c)['commitments'], c);
      expect(welcomeBody(balance: '5', commitments: const [])['commitments'], isEmpty);
    });

    test('la huella es estable para el mismo cuerpo y cambia con el saldo', () {
      expect(fingerprint(welcomeBody(balance: '10')), fingerprint(welcomeBody(balance: '10')));
      expect(fingerprint(welcomeBody(balance: '10')), isNot(fingerprint(welcomeBody(balance: '11'))));
    });
  });

  group('OnboardingSteps', () {
    test('entrada completa: País 1 de 9 … Pagos 9 de 9', () {
      const m = OnboardingMode.full;
      expect(OnboardingSteps.total(m), 9);
      expect(OnboardingSteps.first(m), OnboardingSteps.country);
      expect([for (var p = 1; p <= 9; p++) OnboardingSteps.stepNumber(p, m)], [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('preguntas: Ingresos 1 de 3, Saldo 2 de 3, Pagos 3 de 3', () {
      const m = OnboardingMode.questions;
      expect(OnboardingSteps.total(m), 3);
      expect(OnboardingSteps.first(m), OnboardingSteps.income);
      expect([for (var p = 7; p <= 9; p++) OnboardingSteps.stepNumber(p, m)], [1, 2, 3]);
    });

    test('posiciones: recorrido 2-6, ingresos 7, saldo 8, pagos 9', () {
      expect(OnboardingSteps.income, 7);
      expect(OnboardingSteps.balance, 8);
      expect(OnboardingSteps.payments, 9);
      expect(
        [for (var p = 0; p <= 9; p++) OnboardingSteps.isTour(p)],
        [false, false, true, true, true, true, true, false, false, false],
      );
    });

    test('valid: fuera de rango o sin ser entero vuelve al saludo', () {
      expect(OnboardingSteps.valid(9), 9);
      for (final bad in [10, -1, '3', 3.0, null]) {
        expect(OnboardingSteps.valid(bad), OnboardingSteps.hello, reason: '$bad');
      }
    });
  });
}
