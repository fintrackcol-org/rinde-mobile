import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/region/money_text.dart';
import 'package:rinde_mobile/core/region/region.dart';

void main() {
  test('el formato de dinero sale igual que en la web en los 72 países', () {
    // Generado por tool/export_region.mjs con el Intl de Node (el mismo motor que usa la web).
    final examples = jsonDecode(File('test/core/region_examples.json').readAsStringSync()) as List<dynamic>;
    expect(examples, hasLength(72));
    final failures = <String>[];
    for (final e in examples.cast<Map<String, dynamic>>()) {
      final format = findCountry(e['code'] as String)!.format;
      for (final c in (e['cases'] as List<dynamic>).cast<List<dynamic>>()) {
        final got = format.money(c[0] as num);
        if (got != c[1]) failures.add('${e['code']} ${c[0]}: "$got" ≠ "${c[1]}"');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('regionForCountry: desconocido → CO; idioma sin traducción → inglés', () {
    expect(regionForCountry('BR'), const Region(country: 'BR', currency: 'BRL', language: 'pt'));
    expect(regionForCountry('CN').language, 'en');
    expect(regionForCountry('XX').country, 'CO');
  });

  test('suggestCountry usa el país de los idiomas del sistema, o CO', () {
    expect(suggestCountry(const [Locale('es', 'MX')]), 'MX');
    expect(suggestCountry(const [Locale('es'), Locale('pt', 'BR')]), 'BR');
    expect(suggestCountry(const [Locale('es')]), 'CO');
  });

  test('países ordenados por su nombre traducido, sin tildes', () {
    final es = countriesSorted('es').map((c) => c.code).toList();
    expect(es.first, 'DE'); // Alemania
    expect(es.indexOf('PE') < es.indexOf('PL'), isTrue); // Perú antes que Polonia
    expect(countriesSorted('en').first.code, 'AO'); // Angola
  });

  group('montos escritos (MoneyInput)', () {
    test('lee con el separador del país, sin signo, máx. 10 enteros y 2 decimales', () {
      expect(parseMoneyInput('1.234.567,5', decimal: ','), '1234567.5');
      expect(parseMoneyInput('-250.000', decimal: ','), '250000');
      expect(parseMoneyInput(',5', decimal: ','), '0.5');
      expect(parseMoneyInput('12,', decimal: ','), '12.');
      expect(parseMoneyInput('007', decimal: ','), '7');
      expect(parseMoneyInput('123456789012', decimal: ','), '1234567890');
      expect(parseMoneyInput('1,999', decimal: ','), '1.99');
      expect(parseMoneyInput('1,234.5', decimal: '.'), '1234.5');
    });

    test('pegar decide si el separador es decimal o de miles', () {
      expect(parsePastedMoney('1500.50', decimal: ','), '1500.50');
      expect(parsePastedMoney('1.500.000', decimal: ','), '1500000');
      expect(parsePastedMoney('12,50', decimal: '.'), '12.50');
    });

    test('muestra agrupado y vuelve al mismo crudo', () {
      expect(formatMoneyInput('1234567.5', group: '.', decimal: ','), '1.234.567,5');
      expect(formatMoneyInput('9999999999.99', group: ',', decimal: '.'), '9,999,999,999.99');
      expect(formatMoneyInput('', group: '.', decimal: ','), '');
      expect(
        parseMoneyInput(
          formatMoneyInput('1234567.5', group: '.', decimal: ','),
          decimal: ',',
        ),
        '1234567.5',
      );
    });

    test('valor numérico', () {
      expect(moneyValue(''), isNull);
      expect(moneyValue('12.'), 12);
      expect(moneyValue('0'), 0);
      expect(moneyValue('1234.5'), 1234.5);
    });
  });
}
