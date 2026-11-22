import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ambiente de la app. Se fija al compilar, nunca en el código:
///
///   flutter run --dart-define-from-file=config/qa.json
///
/// `config/qa.json` no se sube al repositorio (ver `config/example.json`).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.webUrl = 'https://www.rindecol.online',
    this.demoMode = false,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'local'),
    webUrl: String.fromEnvironment('WEB_URL', defaultValue: 'https://www.rindecol.online'),
    // Nunca en una versión de tienda: kReleaseMode lo apaga aunque se compile con DEMO_MODE=true.
    demoMode: bool.fromEnvironment('DEMO_MODE') && !kReleaseMode,
  );

  /// MODO DEMOSTRACIÓN / SIN BACKEND (solo desarrollo). Permite entrar con una cuenta sintética
  /// que no sale a la red y recorrer la bienvenida con datos simulados.
  final bool demoMode;

  /// Sitio web oficial: términos y privacidad se leen ahí (contenido público, solo lectura).
  final String webUrl;

  Uri webPage(String path) => Uri.parse('${webUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

  /// Dominios que llegan a la API de producción (el propio y el de Render).
  /// Solo se aceptan con APP_ENV=production.
  static const productionHosts = {'api.rindecol.online', 'fintrack-api-2z1p.onrender.com'};

  /// URL del backend sin `/api/v1` (ej. `https://api-qa.ejemplo.com`).
  final String apiBaseUrl;

  /// `local`, `qa` o `production`.
  final String environment;

  bool get hasApi => apiBaseUrl.trim().isNotEmpty;

  String get apiV1 => '${apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/api/v1';

  /// Por qué no se puede usar este ambiente, o null si está bien.
  /// Protege contra probar por error contra producción.
  String? get problem {
    if (!hasApi) return 'Falta API_BASE_URL: la app no sabe a qué servidor conectarse.';
    final host = (Uri.tryParse(apiBaseUrl.trim())?.host ?? '').toLowerCase();
    if (host.isEmpty) return 'API_BASE_URL no es una URL válida.';
    if (productionHosts.contains(host) && environment != 'production') {
      return 'API_BASE_URL apunta a producción pero APP_ENV es "$environment".';
    }
    return null;
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());
