// Reglas puras de «Cómo te entra la plata» (incomeSources.test.js de Rinde Web) y de las escrituras
// de Mi plata.
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/money/application/money_writer.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/domain/income_rules.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';

const _t = Tr('es', {});

/// Montos a la vista con una marca simple, para leer las frases sin depender del formato del país.
String _money(num value) => '\$$value';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co'),
  accessToken: 'a',
  refreshToken: 'r',
);

void main() {
  group('incomeHeadline', () {
    String? headline({num? normal, num? lean, String basis = 'declared'}) =>
        incomeHeadline(IncomeOverview(normal: normal, lean: lean, basis: basis), _t, _money);

    test('sin base o sin mes normal todavía no se sabe: null (la tarjeta pide configurarlo)', () {
      expect(headline(normal: 2000000, lean: 1500000, basis: 'none'), isNull);
      expect(headline(normal: 0, lean: 0), isNull);
      expect(headline(normal: -1, lean: 0), isNull);
      // Un dato que no llegó no es un cero ni una frase.
      expect(headline(lean: 100), isNull);
    });

    test('si el flaco es igual o mayor al normal, una sola cifra', () {
      expect(headline(normal: 2000000, lean: 2000000), 'Te entran unos \$2000000 al mes.');
      expect(headline(normal: 2000000, lean: 2500000), 'Te entran unos \$2000000 al mes.');
    });

    test('si no, el normal y el flaco, en montos redondos', () {
      expect(
        headline(normal: 866666.67, lean: 693333.33, basis: 'history'),
        'En un mes normal te entran \$866667; en uno flaco, \$693333. '
        'Planeamos con el flaco para que no te coja la tarde.',
      );
    });
  });

  group('sourceSummary', () {
    String summary(IncomeSource source) => sourceSummary(source, _t, _money);

    test('los cinco tipos con datos', () {
      expect(
        summary(const IncomeSource(id: '1', kind: IncomeKind.sueldo, amount: 2500000, payDays: [15, 30])),
        '\$2500000 al mes · días 15 y 30',
      );
      expect(
        summary(const IncomeSource(id: '2', kind: IncomeKind.comisiones, amount: 1200000, low: 1)),
        'Base de \$1200000 + comisiones',
      );
      expect(
        summary(const IncomeSource(id: '3', kind: IncomeKind.proyectos, lastMonths: [1500000, 800000])),
        'Últimos meses: \$1500000, \$800000',
      );
      expect(
        summary(const IncomeSource(id: '4', kind: IncomeKind.diario, amount: 90000, workDays: 5)),
        '5 días a la semana · \$90000 en un día normal',
      );
      for (final (frequency, text) in [
        ('mensual', '\$150000 al mes'),
        ('quincenal', '\$150000 cada quincena'),
        ('semanal', '\$150000 cada semana'),
      ]) {
        expect(
          summary(IncomeSource(id: '5', kind: IncomeKind.mesada, amount: 150000, frequency: frequency)),
          text,
        );
      }
    });

    test('sin datos (o en 0), el nombre corto de cada tipo', () {
      expect(summary(const IncomeSource(id: '1', kind: IncomeKind.sueldo, amount: 0)), 'Sueldo fijo');
      expect(summary(const IncomeSource(id: '2', kind: IncomeKind.comisiones)), 'Base + comisiones');
      expect(summary(const IncomeSource(id: '3', kind: IncomeKind.proyectos)), 'Por proyectos');
      expect(summary(const IncomeSource(id: '4', kind: IncomeKind.diario)), 'Por días');
      expect(summary(const IncomeSource(id: '5', kind: IncomeKind.mesada)), 'Mesada');
    });

    test('solo una parte: lo que haya', () {
      expect(summary(const IncomeSource(id: '1', kind: IncomeKind.sueldo, payDays: [30])), 'días 30');
      expect(
        summary(const IncomeSource(id: '4', kind: IncomeKind.diario, workDays: 6)),
        '6 días a la semana',
      );
    });

    test('«y» se traduce: en inglés no queda «15 y 30»', () {
      const en = Tr('en', {'días {join}': 'days {join}', 'y': 'and'});
      expect(
        sourceSummary(const IncomeSource(id: '1', kind: IncomeKind.sueldo, payDays: [15, 30]), en, _money),
        'days 15 and 30',
      );
    });
  });

  group('sameSources: ¿lo guardado es lo enviado?', () {
    final sent = [
      const IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [30, 15]).toApi(),
      const IncomeSourceForm(kind: IncomeKind.proyectos, lastMonths: ['900000', '', '700000.5']).toApi(),
    ];
    const saved = [
      // Otro orden y otros id: igual es lo mismo.
      IncomeSource(
        id: 'n2',
        kind: IncomeKind.proyectos,
        frequency: 'irregular',
        lastMonths: [900000, 700000.5],
      ),
      IncomeSource(id: 'n1', kind: IncomeKind.sueldo, amount: 2500000, payDays: [15, 30]),
    ];

    test('mismo contenido con otros id y otro orden: sí', () {
      expect(sameSources(sent, saved), isTrue);
      expect(sameSources(const [], const []), isTrue);
    });

    test('cualquier diferencia de tipo, monto, días o cantidad: no', () {
      expect(sameSources(sent, saved.take(1).toList()), isFalse);
      expect(
        sameSources(sent, [saved[0], const IncomeSource(id: 'n1', kind: IncomeKind.sueldo, amount: 2500000)]),
        isFalse,
      );
      expect(
        sameSources(sent, [
          saved[0],
          const IncomeSource(id: 'n1', kind: IncomeKind.sueldo, amount: 2400000, payDays: [15, 30]),
        ]),
        isFalse,
      );
      expect(
        sameSources(sent, [
          saved[0],
          const IncomeSource(id: 'n1', kind: IncomeKind.mesada, amount: 2500000, payDays: [15, 30]),
        ]),
        isFalse,
      );
      expect(sameSources(const [], saved), isFalse);
    });
  });

  group('escrituras', () {
    test('canWriteBalance: solo en la demostración o si el perfil trae versión', () {
      const noVersion = MoneyProfile(welcomeDone: true);
      const versioned = MoneyProfile(welcomeDone: true, version: 3);
      expect(canWriteBalance(_ana, noVersion), isFalse);
      expect(canWriteBalance(null, noVersion), isFalse);
      expect(canWriteBalance(_ana, versioned), isTrue);
      expect(canWriteBalance(Session.demo('nuevo'), noVersion), isTrue);
    });

    test(
      'en duda: se venció la espera o falló el servidor; sin conexión o un 4xx, no salió o no se aplicó',
      () {
        expect(inDoubt(const ApiException(code: ApiCodes.timeout)), isTrue);
        expect(inDoubt(const ApiException(code: 'INTERNAL_ERROR', status: 500)), isTrue);
        expect(inDoubt(const ApiException(code: 'X', status: 503)), isTrue);
        expect(inDoubt(const ApiException(code: ApiCodes.network)), isFalse);
        expect(inDoubt(const ApiException(code: ApiCodes.validation, status: 422)), isFalse);
        expect(inDoubt(const ApiException(code: 'COMMITMENT_EXISTS', status: 409)), isFalse);
      },
    );
  });
}
