import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/features/home/domain/home_dates.dart';

/// Las fechas deben salir como `toLocaleDateString(dateLocale())` de Rinde Web: idioma de la app + país.
void main() {
  const esCO = Region(country: 'CO', currency: 'COP', language: 'es');
  const esPE = Region(country: 'PE', currency: 'PEN', language: 'es');
  const esUY = Region(country: 'UY', currency: 'UYU', language: 'es');
  const enUS = Region(country: 'US', currency: 'USD', language: 'en');
  const enGB = Region(country: 'GB', currency: 'GBP', language: 'en');
  const enCO = Region(country: 'CO', currency: 'COP', language: 'en');
  const ptBR = Region(country: 'BR', currency: 'BRL', language: 'pt');

  group('dayAndMonth', () {
    test('es-CO: «30 de noviembre», sin cero a la izquierda', () {
      expect(dayAndMonth('2026-11-30', esCO), '30 de noviembre');
      expect(dayAndMonth('2026-11-05', esCO), '5 de noviembre');
      expect(dayAndMonth('2026-01-01', esCO), '1 de enero');
      expect(dayAndMonth('2026-09-08', esCO), '8 de septiembre');
    });

    test('es-PE y es-UY escriben «setiembre»', () {
      expect(dayAndMonth('2026-09-08', esPE), '8 de setiembre');
      expect(dayAndMonth('2026-09-08', esUY), '8 de setiembre');
      expect(dayAndMonth('2026-11-30', esPE), '30 de noviembre');
    });

    test('en-US pone el mes primero', () {
      expect(dayAndMonth('2026-11-30', enUS), 'November 30');
      expect(dayAndMonth('2026-11-05', enUS), 'November 5');
      // Inglés en un país que no está en la lista de «día primero».
      expect(dayAndMonth('2026-11-30', enCO), 'November 30');
    });

    test('en-GB pone el día primero', () {
      expect(dayAndMonth('2026-11-30', enGB), '30 November');
      expect(dayAndMonth('2026-09-08', enGB), '8 September');
    });

    test('pt-BR: «30 de novembro»', () {
      expect(dayAndMonth('2026-11-30', ptBR), '30 de novembro');
      expect(dayAndMonth('2026-03-01', ptBR), '1 de março');
      expect(dayAndMonth('2026-09-08', ptBR), '8 de setembro');
    });

    test('un idioma sin tabla de meses sale en español', () {
      expect(
        dayAndMonth('2026-11-30', const Region(country: 'CO', currency: 'COP', language: 'zh')),
        '30 de noviembre',
      );
    });
  });

  test('monthName: los doce meses por idioma', () {
    String all(Region region) => [for (var m = 1; m <= 12; m++) monthName(m, region)].join(' ');
    expect(
      all(esCO),
      'enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre',
    );
    expect(
      all(esPE),
      'enero febrero marzo abril mayo junio julio agosto setiembre octubre noviembre diciembre',
    );
    expect(
      all(enUS),
      'January February March April May June July August September October November December',
    );
    expect(all(enGB), all(enUS));
    expect(
      all(ptBR),
      'janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro',
    );
  });

  test('shortMonthName: «nov» para «hasta el 24 nov»', () {
    String all(Region region) => [for (var m = 1; m <= 12; m++) shortMonthName(m, region)].join(' ');
    expect(all(esCO), 'ene feb mar abr may jun jul ago sep oct nov dic');
    // Como MONTHS de lib/runway.js: el corto no cambia en Perú.
    expect(all(esPE), all(esCO));
    expect(all(enUS), 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec');
    expect(all(enGB), all(enUS));
    expect(all(ptBR), 'jan fev mar abr mai jun jul ago set out nov dez');
  });

  group('isoDay e isoMonth usan la fecha local del dispositivo', () {
    test('de noche no saltan de día ni de mes (en UTC ya sería el siguiente, o el anterior)', () {
      // Sea cual sea la zona de la máquina, una de las dos horas cae en otro día en UTC.
      expect(isoDay(DateTime(2026, 11, 30, 23, 30)), '2026-11-30');
      expect(isoMonth(DateTime(2026, 11, 30, 23, 30)), '2026-11');
      expect(isoDay(DateTime(2026, 12, 1, 0, 30)), '2026-12-01');
      expect(isoMonth(DateTime(2026, 12, 1, 0, 30)), '2026-12');
    });

    test('un instante en UTC se lee con el día local', () {
      final instant = DateTime.utc(2026, 12, 1, 3);
      final local = instant.toLocal();
      expect(isoDay(local), isoDay(DateTime(local.year, local.month, local.day)));
    });

    test('rellena con ceros', () {
      expect(isoDay(DateTime(2026, 1, 5)), '2026-01-05');
      expect(isoMonth(DateTime(2026, 1, 5)), '2026-01');
      expect(isoDay(DateTime(987, 3, 4)), '0987-03-04');
    });
  });
}
