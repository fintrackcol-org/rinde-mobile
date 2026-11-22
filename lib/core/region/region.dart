import 'dart:ui' show Locale;

part 'region_data.g.dart';

/// Idioma de la app, con su nombre en ese mismo idioma.
class Language {
  const Language(this.code, this.name);
  final String code;
  final String name;
}

/// País, moneda principal e idioma de la persona (lib/region.js de Rinde Web).
class Region {
  const Region({required this.country, required this.currency, required this.language});

  factory Region.fromJson(Map<String, dynamic> json) {
    final country = json['country'];
    final currency = json['currency'];
    final language = json['language'];
    if (country is String && currency is String && language is String && findCountry(country) != null) {
      return Region(
        country: country,
        currency: currency,
        language: isAppLanguage(language) ? language : 'es',
      );
    }
    return kDefaultRegion;
  }

  final String country;
  final String currency;
  final String language;

  Map<String, dynamic> toJson() => {'country': country, 'currency': currency, 'language': language};

  Region copyLanguage(String language) => Region(country: country, currency: currency, language: language);

  @override
  bool operator ==(Object other) =>
      other is Region && other.country == country && other.currency == currency && other.language == language;

  @override
  int get hashCode => Object.hash(country, currency, language);
}

/// Formato de dinero de un país, ya resuelto con ICU por el generador (Dart no trae esos datos).
class MoneyFormat {
  const MoneyFormat({
    required this.prefix,
    required this.suffix,
    required this.group,
    required this.decimal,
    required this.inputGroup,
    required this.inputDecimal,
    required this.minGrouping,
    this.secondaryGroup = 3,
  });

  final String prefix;
  final String suffix;
  final String group;
  final String decimal;

  /// Separadores para escribir montos (los del número simple del idioma del país).
  final String inputGroup;
  final String inputDecimal;

  /// 2 = no agrupa números de 4 cifras ("1250,50 €" en España), como ICU.
  final int minGrouping;

  /// Tamaño de los grupos después de los 3 primeros dígitos (2 en India: 12,34,567).
  final int secondaryGroup;

  /// `formatMoney` de la web: sin decimales si el monto es entero, con 2 si no.
  String money(num amount) {
    final negative = amount < 0;
    final abs = amount.abs();
    final whole = abs == abs.roundToDouble();
    final fixed = whole ? abs.round().toString() : abs.toStringAsFixed(2);
    final [integer, ...rest] = fixed.split('.');
    final body = _group(integer) + (rest.isEmpty ? '' : '$decimal${rest.first}');
    return '${negative ? '-' : ''}$prefix$body$suffix';
  }

  String _group(String digits) {
    if (digits.length < 4 || (minGrouping == 2 && digits.length < 5)) return digits;
    final groups = <String>[digits.substring(digits.length - 3)];
    var rest = digits.substring(0, digits.length - 3);
    while (rest.isNotEmpty) {
      final cut = rest.length > secondaryGroup ? rest.length - secondaryGroup : 0;
      groups.insert(0, rest.substring(cut));
      rest = rest.substring(0, cut);
    }
    return groups.join(group);
  }
}

class Country {
  const Country({
    required this.code,
    required this.currency,
    required this.language,
    required this.timeZone,
    required this.names,
    required this.currencyNames,
    required this.sample,
    required this.format,
  });

  final String code;
  final String currency;

  /// Idioma sugerido (puede ser uno que la app no tiene, p. ej. zh).
  final String language;
  final String timeZone;
  final Map<String, String> names;
  final Map<String, String> currencyNames;

  /// "Así se verá tu plata": 1.250.000 en COP y 1.250,5 en las demás, con el formato del país.
  final String sample;
  final MoneyFormat format;

  String name(String language) => names[language] ?? names['es'] ?? code;
  String currencyName(String language) => currencyNames[language] ?? currencyNames['es'] ?? currency;
}

Country? findCountry(String code) {
  for (final c in kCountries) {
    if (c.code == code) return c;
  }
  return null;
}

bool isAppLanguage(String code) => kLanguages.any((l) => l.code == code);

/// País → región completa. Un código desconocido cae en Colombia; un idioma que la app no tiene, en inglés.
Region regionForCountry(String code) {
  final country = findCountry(code) ?? findCountry(kDefaultRegion.country)!;
  return Region(
    country: country.code,
    currency: country.currency,
    language: isAppLanguage(country.language) ? country.language : 'en',
  );
}

/// Sugiere el país con los idiomas del sistema (es-CO → CO). La web usa primero la zona horaria;
/// Flutter no la da en formato IANA sin otro paquete, así que aquí solo se usan los idiomas.
String suggestCountry(List<Locale> locales) {
  for (final locale in locales) {
    final region = locale.countryCode?.toUpperCase();
    if (region != null && findCountry(region) != null) return region;
  }
  return kDefaultRegion.country;
}

/// Países ordenados por su nombre en el idioma dado (sin tildes para comparar, como localeCompare).
List<Country> countriesSorted(String language) {
  final list = [...kCountries];
  list.sort((a, b) => foldForSearch(a.name(language)).compareTo(foldForSearch(b.name(language))));
  return list;
}

/// Minúsculas y sin tildes, para ordenar y buscar ("Perú" ~ "peru").
String foldForSearch(String text) {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
  final buffer = StringBuffer();
  for (final ch in text.split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString().toLowerCase();
}

/// Formato de dinero de la región (los montos van como en el país de la moneda principal).
MoneyFormat formatFor(Region region) {
  final here = findCountry(region.country);
  if (here != null && here.currency == region.currency) return here.format;
  for (final c in kCountries) {
    if (c.currency == region.currency) return c.format;
  }
  return findCountry(kDefaultRegion.country)!.format;
}
