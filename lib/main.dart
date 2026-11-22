import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/i18n/tr.dart';
import 'core/region/region.dart';
import 'core/region/region_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Antes de dibujar: traducciones y la región guardada (o la que sugieren los idiomas del sistema),
  // para abrir con el idioma y el formato de dinero correctos.
  final translations = await Translations.load(rootBundle);
  final saved = await RegionStore().read();
  final locales = PlatformDispatcher.instance.locales;
  // Sin región guardada (como la web): país sugerido y el idioma del sistema si la app lo tiene.
  final systemLanguage = locales.isEmpty ? 'es' : locales.first.languageCode;
  final region =
      saved ??
      regionForCountry(suggestCountry(locales))
          .copyLanguage(isAppLanguage(systemLanguage) ? systemLanguage : 'es');
  runApp(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        initialRegionProvider.overrideWithValue(region),
      ],
      child: const RindeApp(),
    ),
  );
}
