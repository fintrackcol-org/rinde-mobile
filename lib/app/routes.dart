/// Rutas de Rinde Mobile. Las de acceso usan los mismos nombres que Rinde Web.
abstract final class Routes {
  /// Mientras se lee la sesión guardada.
  static const boot = '/arranque';

  /// Primera pantalla sin sesión (en la web, el cierre de la landing).
  static const welcome = '/bienvenida';
  static const login = '/login';
  static const register = '/registro';
  static const forgot = '/recuperar';

  /// Dentro de la app (con sesión).
  static const app = '/app';

  /// Bienvenida completa (cuenta nueva) y solo las preguntas de plata (cuenta con movimientos).
  /// Las dos exigen sesión: están bajo /app.
  static const onboarding = '/app/bienvenida';
  static const onboardingQuestions = '/app/bienvenida/preguntas';
}
