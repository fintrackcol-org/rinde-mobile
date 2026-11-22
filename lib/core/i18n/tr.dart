import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../region/region_provider.dart';

/// Traducciones como en Rinde Web (lib/i18n.js): la clave es el texto en español y en/pt tienen
/// su versión. Si falta, se muestra el español. Las variables van entre llaves: «Hola, {name}».
///
/// Los archivos assets/l10n/{en,pt}.json los genera tool/export_l10n.mjs con las traducciones de la web
/// que usa la app móvil (no se escriben a mano).
class Translations {
  const Translations(this._byLanguage);

  static const empty = Translations({});

  final Map<String, Map<String, String>> _byLanguage;

  static Future<Translations> load(AssetBundle bundle) async {
    final byLanguage = <String, Map<String, String>>{};
    for (final language in const ['en', 'pt']) {
      try {
        final raw = jsonDecode(await bundle.loadString('assets/l10n/$language.json'));
        if (raw is Map) byLanguage[language] = raw.map((k, v) => MapEntry('$k', '$v'));
      } catch (_) {
        // Sin el archivo, ese idioma cae al español en vez de impedir que la app abra.
      }
    }
    return Translations(byLanguage);
  }

  Map<String, String> of(String language) => _byLanguage[language] ?? const {};
}

class Tr {
  const Tr(this.language, this._messages);

  final String language;
  final Map<String, String> _messages;

  String call(String spanish, [Map<String, Object?> vars = const {}]) {
    var text = _messages[spanish] ?? spanish;
    vars.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
    return text;
  }
}

final translationsProvider = Provider<Translations>((ref) => Translations.empty);

/// Idioma en que se ve la interfaz. Normalmente el de la región guardada; durante la bienvenida
/// cambia en vivo al elegir otro (la web hace `loadMessages` sin recargar).
class DisplayLanguage extends Notifier<String> {
  @override
  String build() => ref.watch(appRegionProvider.select((r) => r.language));

  void preview(String language) => state = language;
}

final displayLanguageProvider = NotifierProvider<DisplayLanguage, String>(DisplayLanguage.new);

final trProvider = Provider<Tr>((ref) {
  final language = ref.watch(displayLanguageProvider);
  return Tr(language, ref.watch(translationsProvider).of(language));
});
