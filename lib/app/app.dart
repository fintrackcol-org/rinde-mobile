import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../core/i18n/tr.dart';
import '../design/theme/rinde_theme.dart';
import 'router.dart';

/// Tema elegido en «Yo» → Apariencia (ThemeProvider de la web, localStorage `rinde.tema`): uno por
/// dispositivo, se conserva al cerrar la app y al cambiar de cuenta. Claro por defecto, como la web.
class ThemeStore {
  ThemeStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'rinde.tema';
  final FlutterSecureStorage _storage;

  /// El último guardado mientras la app sigue abierta: al salir de la demostración se vuelve a este.
  ThemeMode? last;

  Future<ThemeMode> read() async {
    try {
      final saved = await _storage.read(key: _key);
      return ThemeMode.values.where((m) => m.name == saved).firstOrNull ?? ThemeMode.light;
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> write(ThemeMode mode) async {
    last = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {
      // Sin almacenamiento dura hasta cerrar la app, como en la web.
    }
  }
}

final themeStoreProvider = Provider<ThemeStore>((ref) => ThemeStore());

/// El guardado, leído en main antes de dibujar (sin un destello claro al abrir en oscuro).
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.light);

class AppThemeMode extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(themeStoreProvider).last ?? ref.watch(initialThemeModeProvider);

  /// Solo para la vista (panel de demostración): no se guarda.
  void set(ThemeMode mode) => state = mode;

  /// La elección de la persona en Apariencia: se guarda en el dispositivo.
  Future<void> choose(ThemeMode mode) async {
    state = mode;
    await ref.read(themeStoreProvider).write(mode);
  }
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
