/// Reglas de los formularios de acceso. Son las mismas de Rinde Web
/// (frontend/src/lib/validation/auth.js, zod): mismos textos y mismo orden de revisión.
/// El backend es más permisivo (solo largo ≥ 8), así que validar aquí evita cuentas
/// que la web no permitiría crear.
library;

abstract final class AuthValidators {
  // Expresión de `z.email()` de zod 4.
  static final _email = RegExp(
    r"^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$",
  );
  static final _letter = RegExp('[A-Za-z]');
  static final _digit = RegExp(r'\d');

  static const nameMax = 60;
  static const passwordMin = 8;
  static const passwordMax = 72;

  /// Como en la web: se recorta y se pasa a minúsculas antes de validar y de enviar.
  static String normalizeEmail(String value) => value.trim().toLowerCase();

  /// Recorta y deja un solo espacio entre palabras, igual que hace el backend.
  static String normalizeName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Login y recuperar contraseña.
  static String? email(String? value) {
    final v = normalizeEmail(value ?? '');
    if (v.isEmpty) return 'Ingresa tu correo electrónico';
    if (!_email.hasMatch(v)) return 'Ingresa un correo válido';
    return null;
  }

  /// Registro: el mismo chequeo con un mensaje que explica qué falta.
  static String? registerEmail(String? value) {
    final v = normalizeEmail(value ?? '');
    if (v.isEmpty) return 'Ingresa tu correo electrónico';
    if (!_email.hasMatch(v)) return 'Al correo le falta algo: revisa la @ y el final, por ejemplo .com o .co';
    return null;
  }

  static String? loginPassword(String? value) => (value ?? '').isEmpty ? 'Ingresa tu contraseña' : null;

  static String? name(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Escribe tu nombre: no puede quedar solo con espacios.';
    if (v.length > nameMax) return 'Máximo 60 caracteres';
    return null;
  }

  /// Contraseña nueva (registro y restablecer).
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.length < passwordMin) return 'Usa al menos 8 caracteres';
    if (v.length > passwordMax) return 'Usa máximo 72 caracteres';
    if (!_letter.hasMatch(v)) return 'Incluye al menos una letra';
    if (!_digit.hasMatch(v)) return 'Incluye al menos un número';
    return null;
  }

  static String? acceptTerms(bool? value) =>
      value == true ? null : 'Debes ser mayor de edad y aceptar los términos para continuar';

  /// Reglas visibles mientras se escribe (PasswordRules.jsx). El máximo de 72 lo revisa [newPassword] al enviar.
  static List<PasswordRule> passwordRules(String value) => [
    PasswordRule('8 caracteres o más', value.length >= passwordMin),
    PasswordRule('Una letra', _letter.hasMatch(value)),
    PasswordRule('Un número', _digit.hasMatch(value)),
  ];
}

class PasswordRule {
  const PasswordRule(this.label, this.met);
  final String label;
  final bool met;
}
