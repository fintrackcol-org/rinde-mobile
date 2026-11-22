/// Posiciones de la bienvenida (pages/app/Welcome.jsx): un saludo y nueve pasos.
library;

/// Cómo se entra: completa (cuenta nueva) o solo las tres preguntas de plata (cuenta que ya tiene
/// movimientos y llega desde la invitación del inicio). En la web es `?paso=preguntas`.
enum OnboardingMode { full, questions }

abstract final class OnboardingSteps {
  static const hello = 0;
  static const country = 1;
  static const tour = 2;
  static const tourLength = 5;
  static const income = tour + tourLength; // 7
  static const balance = 8;
  static const payments = 9;

  static bool isTour(int position) => position >= tour && position < income;

  static int first(OnboardingMode mode) => mode == OnboardingMode.questions ? income : country;

  /// «Paso n de m» de la barra (el saludo no cuenta).
  static int stepNumber(int position, OnboardingMode mode) => position - first(mode) + 1;
  static int total(OnboardingMode mode) => payments - first(mode) + 1;

  /// Una posición guardada que no sirve vuelve al saludo (validPosition de la web).
  static int valid(Object? value) => value is int && value >= hello && value <= payments ? value : hello;
}
