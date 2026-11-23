import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/i18n/tr.dart';
import '../design/theme/rinde_theme.dart';
import 'router.dart';

/// Tema de la app. Como Rinde Web: claro por defecto. Elegir oscuro o «según el sistema» llega con
/// Cuenta; por ahora solo lo cambia el panel de demostración, y no se guarda.
class AppThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(AppThemeMode.new);

class RindeApp extends ConsumerWidget {
  const RindeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Rinde',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: RindeTheme.light,
      darkTheme: RindeTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      // Textos del sistema (copiar, pegar, lector de pantalla) en el idioma que se ve.
      locale: Locale(ref.watch(displayLanguageProvider)),
      supportedLocales: const [Locale('es'), Locale('en'), Locale('pt')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Respeta el tamaño de letra del sistema, con un tope para que no se rompa la composición.
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 2, child: child!),
    );
  }
}
