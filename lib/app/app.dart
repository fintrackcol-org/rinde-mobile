import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/theme/rinde_theme.dart';
import 'router.dart';

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
      // Como Rinde Web: claro por defecto. Elegir oscuro o "según el sistema" llega con Cuenta.
      themeMode: ThemeMode.light,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Respeta el tamaño de letra del sistema, con un tope para que no se rompa la composición.
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 2, child: child!),
    );
  }
}
