import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'auth_models.dart';

/// Versión vigente de los términos (`backend/src/config/legal.js`). Si el backend la cambia,
/// el servidor responde 422 y hay que actualizarla aquí.
const legalVersion = '2026-11-05';

/// Endpoints de autenticación y perfil. Solo usa contratos que ya existen en el backend.
class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  /// POST /auth/login → 200 `{ user, accessToken, refreshToken }`.
  Future<Session> login({required String email, required String password}) async {
    final data = await _api.post('/auth/login', body: {'email': email, 'password': password});
    return Session.fromJson(_asMap(data));
  }

  /// POST /auth/register → 201 `{ email, verificationRequired: true }`. No abre sesión.
  /// A diferencia de la web, sí envía `name`: el backend lo acepta y el formulario lo pide.
  Future<String> register({required String name, required String email, required String password}) async {
    final data = await _api.post(
      '/auth/register',
      body: {'name': name, 'email': email, 'password': password, 'acceptTerms': true},
    );
    final map = _asMap(data);
    return map['email'] is String ? map['email'] as String : email;
  }

  /// POST /auth/forgot-password → 200 siempre (no revela si la cuenta existe).
  Future<void> forgotPassword(String email) => _api.post('/auth/forgot-password', body: {'email': email});

  /// POST /auth/resend-verification → 200 siempre.
  Future<void> resendVerification(String email) =>
      _api.post('/auth/resend-verification', body: {'email': email});

  /// GET /users/me (con sesión).
  Future<UserProfile> me() async => UserProfile.fromJson(_asMap(await _api.get('/users/me')));

  /// POST /users/me/terms → perfil actualizado.
  Future<UserProfile> acceptTerms() async => UserProfile.fromJson(
    _asMap(await _api.post('/users/me/terms', body: {'version': legalVersion}, auth: true)),
  );

  /// DELETE /users/me {password} → 204 (FT-0017). Borra la cuenta y todos sus datos; no se puede
  /// deshacer. 403 `CONFIRMATION_FAILED` si la contraseña no coincide. La web también confirma con
  /// Google; en la app el ingreso con Google aún no existe, así que quien está dentro tiene contraseña.
  Future<void> deleteAccount(String password) => _api.delete('/users/me', body: {'password': password});

  /// POST /auth/logout (con sesión) → 204. Revoca solo el refresh token de este dispositivo.
  Future<void> logout(String refreshToken) =>
      _api.post('/auth/logout', body: {'refreshToken': refreshToken}, auth: true);

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException(code: ApiCodes.unknown);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
