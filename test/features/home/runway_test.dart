import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/home/domain/runway.dart';

/// Vectores sacados de ejecutar el `runway()` real de Rinde Web (auditoría financiera, sección 5).
/// Donde la app se aparta de la web a propósito, la prueba lo dice en el nombre.
void main() {
  Runway at(num balance, num expense, DateTime today) =>
      runway(balance: balance, monthExpense: expense, today: today)!;

  group('como Rinde Web (runway.test.js y vectores)', () {
    test('cuenta los días que dura la plata al ritmo del mes', () {
      // 10 de noviembre, $300.000 gastados: $30.000 al día. Con $420.000 alcanza 14 días.
      final r = at(420000, 300000, DateTime(2026, 11, 10));
      expect(r.days, 14);
      expect(r.lasts, isFalse);
      expect(r.until, DateTime(2026, 11, 24));
      expect(r.coverage, closeTo(14 / 20, 1e-9));
    });

    test('dice si llega a fin de mes', () {
      final r = at(2000000, 100000, DateTime(2026, 11, 10));
      expect(r.days, 200);
      expect(r.lasts, isTrue);
      expect(r.coverage, 1);
    });

    test('sin saldo o sin gastos no inventa un número', () {
      final today = DateTime(2026, 11, 10);
      expect(runway(balance: null, monthExpense: 100, today: today), isNull);
      expect(runway(balance: 1000, monthExpense: 0, today: today), isNull);
      // Los gastos del mes no han llegado o fallaron.
      expect(runway(balance: 1000, monthExpense: null, today: today), isNull);
      expect(runway(balance: 1000, monthExpense: -5, today: today), isNull);
      expect(runway(balance: null, monthExpense: null, today: today), isNull);
    });

    test('con saldo en cero alcanza 0 días, hasta hoy', () {
      final r = at(0, 10000, DateTime(2026, 11, 5));
      expect((r.days, r.coverage, r.lasts, r.until), (0, 0, false, DateTime(2026, 11, 5)));
    });

    test('con saldo negativo no da días negativos', () {
      final r = at(-5000, 10000, DateTime(2026, 11, 5));
      expect((r.days, r.coverage, r.lasts, r.until), (0, 0, false, DateTime(2026, 11, 5)));
    });

    test('exactamente 1 día', () {
      final r = at(2000, 20000, DateTime(2026, 11, 10));
      expect((r.days, r.lasts, r.until), (1, false, DateTime(2026, 11, 11)));
      expect(r.coverage, closeTo(0.05, 1e-9));
    });

    test('el día 1 el ritmo es todo lo gastado', () {
      final r = at(300000, 150000, DateTime(2026, 11, 1));
      expect((r.days, r.lasts, r.until), (2, false, DateTime(2026, 11, 3)));
      expect(r.coverage, closeTo(2 / 29, 1e-9));
    });

    test('último día del mes con 0 días: no llega', () {
      final r = at(100, 300000, DateTime(2026, 11, 30));
      expect((r.days, r.coverage, r.lasts, r.until), (0, 0, false, DateTime(2026, 11, 30)));
    });

    test('último día del mes con 1 día: llega (queda mínimo 1 día por cubrir)', () {
      final r = at(10000, 300000, DateTime(2026, 11, 30));
      expect((r.days, r.coverage, r.lasts), (1, 1, true));
    });

    test('28 de febrero de un año no bisiesto es el último día', () {
      final r = at(50000, 280000, DateTime(2026, 2, 28));
      expect((r.days, r.coverage, r.lasts), (5, 1, true));
    });

    test('28 de febrero de un año bisiesto: queda el 29', () {
      final r = at(5000, 280000, DateTime(2028, 2, 28));
      expect((r.days, r.coverage, r.lasts, r.until), (0, 0, false, DateTime(2028, 2, 28)));
    });

    test('montos con centavos', () {
      final r = at(1234.56, 789.01, DateTime(2026, 11, 21));
      expect((r.days, r.coverage, r.lasts), (32, 1, true));
    });

    test('la hora de hoy no cambia la cuenta', () {
      final r = at(420000, 300000, DateTime(2026, 11, 10, 23, 59, 59));
      expect((r.days, r.until), (14, DateTime(2026, 11, 24)));
    });
  });

  group('distinto de Rinde Web a propósito', () {
    test('cuenta exacta: 17.949 con 17.949 gastados al día 7 son 7 días (la web da 6)', () {
      final r = at(17949, 17949, DateTime(2026, 11, 7));
      expect(r.days, 7);
      expect(r.until, DateTime(2026, 11, 14));
      expect(r.coverage, closeTo(7 / 23, 1e-9));
    });

    test('cuenta exacta en cualquier día del mes: nunca un día de menos', () {
      // Ritmo entero al día y saldo para N días justos: saldo × día ÷ gastado da N exacto.
      for (var day = 1; day <= 31; day++) {
        for (final pace in [1, 7, 2564, 17949, 333333]) {
          for (final n in [0, 1, 3, 7, 30]) {
            final r = at(pace * n, pace * day, DateTime(2026, 1, day));
            expect(r.days, n, reason: 'día $day, ritmo $pace');
          }
        }
      }
    });

    test(
      'el día final se cuenta por calendario, no en milisegundos (la web da un día menos al cambiar la hora)',
      () {
        // Vectores de la auditoría: 1 de noviembre en Nueva York y 1 de abril en Santiago, 5 días.
        expect(at(50000, 10000, DateTime(2026, 11, 1)).until, DateTime(2026, 11, 6));
        expect(at(50000, 10000, DateTime(2026, 4, 1)).until, DateTime(2026, 4, 6));
        // Todo el año, con la zona horaria de esta máquina: si tiene cambio de hora, lo atraviesa.
        for (var d = DateTime(2026, 1, 1); d.year == 2026; d = DateTime(d.year, d.month, d.day + 1)) {
          // Gastado = el día del mes: ritmo de 1 al día, así que 5 alcanzan 5 días.
          final r = at(5, d.day, DateTime(d.year, d.month, d.day, 12));
          // Al final del mes el día final se recorta (prueba siguiente).
          if (DateTime(d.year, d.month + 1, 0).day - d.day <= 5) continue;
          expect(r.until, DateTime(d.year, d.month, d.day + 5), reason: '$d');
          expect((r.until.hour, r.until.minute), (0, 0), reason: '$d');
        }
      },
    );

    test('si llega a fin de mes, el día final no pasa del mes (en la web sigue de largo)', () {
      expect(at(2000000, 100000, DateTime(2026, 11, 10)).until, DateTime(2026, 11, 30));
    });

    test(
      'un resultado enorme no se rompe: se recorta y basta saber que pasa del mes (en la web, Invalid Date)',
      () {
        final r = at(9999999999.99, 0.01, DateTime(2026, 11, 30));
        expect((r.days, r.coverage, r.lasts), (100000, 1, true));
        expect(r.until, DateTime(2026, 12, 1));
      },
    );

    test('ni con valores fuera de todo rango lanza', () {
      final today = DateTime(2026, 11, 10);
      for (final (balance, expense) in <(num, num)>[
        (double.maxFinite, 0.01),
        (double.infinity, 1),
        (double.maxFinite, double.minPositive),
        (-double.maxFinite, 0.01),
        (double.negativeInfinity, 1),
        (1, double.infinity),
      ]) {
        final r = runway(balance: balance, monthExpense: expense, today: today)!;
        expect(r.days, inInclusiveRange(0, 100000), reason: '$balance / $expense');
        expect(r.coverage, inInclusiveRange(0, 1));
        expect(r.until.isBefore(DateTime(2026, 12, 1)), isTrue);
      }
    });
  });
}
