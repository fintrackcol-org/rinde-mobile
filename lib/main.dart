import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/i18n/tr.dart';
import 'core/region/region.dart';
import 'core/region/region_provider.dart';
import 'features/home/application/home_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Antes de dibujar: traducciones y la región guardada (o la que sugieren los idiomas del sistema),
  // para abrir con el idioma y el formato de dinero correctos. También si los montos van ocultos:
  // así ninguna cifra alcanza a verse antes de saberlo.
  final translations = await Translations.load(rootBundle);
  final (saved, hidden) = await (RegionStore().read(), const HiddenAmountsStore().read()).wait;
  final locales = PlatformDispatcher.instance.locales;
  // Sin región guardada (como la web): país sugerido y el idioma del sistema si la app lo tiene.
  final systemLanguage = locales.isEmpty ? 'es' : locales.first.languageCode;
  final region =
      saved ??
      // Como la web: hasta que la cuenta diga otra cosa los montos son en pesos. El país del teléfono
      // solo se sugiere en la bienvenida: tomar su moneda aquí pintaría pesos como dólares.
      kDefaultRegion.copyLanguage(isAppLanguage(systemLanguage) ? systemLanguage : 'es');
  runApp(
    ProviderScope(
      // Sin reintentos automáticos: Riverpod repetiría cada carga fallida hasta 10 veces en silencio
      // (unos 38 s con la rueda girando). Aquí un fallo se muestra y la persona decide reintentar.
      retry: (_, _) => null,
      overrides: [
        translationsProvider.overrideWithValue(translations),
        initialRegionProvider.overrideWithValue(region),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
      ],
      child: const RindeApp(),
    ),
  );
}
