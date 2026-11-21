/// Modelos del contrato de autenticación de la API de Rinde (`/api/v1/auth`, `/api/v1/users`).
library;

/// Usuario que devuelven login, Google y verify-email: solo `{ id, email, name }`.
class AuthUser {
  const AuthUser({required this.id, required this.email, this.name});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: _string(json, 'id'),
    email: _string(json, 'email'),
    name: json['name'] is String && (json['name'] as String).trim().isNotEmpty
        ? json['name'] as String
        : null,
  );

  final String id;
  final String email;
  final String? name;

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}

class Session {
  const Session({required this.user, required this.accessToken, required this.refreshToken});

  /// Respuesta 200 de login, google y verify-email.
  factory Session.fromJson(Map<String, dynamic> json) => Session(
    user: AuthUser.fromJson(_map(json, 'user')),
    accessToken: _string(json, 'accessToken'),
    refreshToken: _string(json, 'refreshToken'),
  );

  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  Session copyWith({AuthUser? user, String? accessToken, String? refreshToken}) => Session(
    user: user ?? this.user,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
  );

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

/// `GET /api/v1/users/me`. Trae lo que el login no trae (términos y región).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.termsAccepted,
    required this.country,
    required this.currency,
    required this.language,
    this.name,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: _string(json, 'id'),
    email: _string(json, 'email'),
    name: json['name'] is String && (json['name'] as String).trim().isNotEmpty
        ? json['name'] as String
        : null,
    termsAccepted: json['termsAccepted'] == true,
    country: json['country'] is String ? json['country'] as String : 'CO',
    currency: json['currency'] is String ? json['currency'] as String : 'COP',
    language: json['language'] is String ? json['language'] as String : 'es',
  );

  final String id;
  final String email;
  final String? name;
  final bool termsAccepted;
  final String country;
  final String currency;
  final String language;
}

/// Error de forma: la respuesta no cumple el contrato esperado.
class ContractException implements Exception {
  const ContractException(this.message);
  final String message;
  @override
  String toString() => 'ContractException: $message';
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw ContractException('Falta "$key" o no es texto');
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw ContractException('Falta "$key" o no es un objeto');
}
