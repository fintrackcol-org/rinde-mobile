import 'package:dio/dio.dart';

/// Códigos de error del backend de Rinde que la app trata de forma especial.
/// Forma de todo error: `{ "error": { "code", "message", "details"?: [{ "field", "problem" }] } }`.
abstract final class ApiCodes {
  static const unauthorized = 'UNAUTHORIZED';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const emailNotVerified = 'EMAIL_NOT_VERIFIED';
  static const emailTaken = 'EMAIL_TAKEN';
  static const rateLimited = 'RATE_LIMITED';
  static const validation = 'VALIDATION_ERROR';
  static const googleNotConfigured = 'GOOGLE_NOT_CONFIGURED';

  // Códigos propios de la app (no vienen del servidor).
  static const network = 'NETWORK';
  static const notConfigured = 'NOT_CONFIGURED';
  static const unknown = 'UNKNOWN';
}

/// Mensajes comunes, iguales a los de Rinde Web.
abstract final class ApiMessages {
  static const network = 'No pudimos conectar con el servidor. Revisa tu conexión.';
  static const rateLimited = 'Demasiados intentos. Espera un momento y vuelve a intentarlo.';
  static const sessionExpired = 'Tu sesión venció. Inicia sesión de nuevo.';
  static const generic = 'Algo salió mal. Inténtalo de nuevo.';
}

class ApiException implements Exception {
  const ApiException({required this.code, this.serverMessage, this.status, this.fields = const {}});

  /// Convierte cualquier fallo de Dio en un error de la app con el contrato del backend.
  factory ApiException.fromDio(DioException e) {
    if (e.error is ApiException) return e.error! as ApiException;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(code: ApiCodes.network);
      default:
        break;
    }
    final response = e.response;
    if (response == null) return const ApiException(code: ApiCodes.network);
    final data = response.data;
    final error = data is Map ? data['error'] : null;
    if (error is! Map) return ApiException(code: ApiCodes.unknown, status: response.statusCode);

    final fields = <String, String>{};
    final details = error['details'];
    if (details is List) {
      for (final d in details) {
        if (d is Map && d['field'] is String && d['problem'] is String) {
          fields.putIfAbsent(d['field'] as String, () => d['problem'] as String);
        }
      }
    }
    return ApiException(
      code: error['code'] is String ? error['code'] as String : ApiCodes.unknown,
      serverMessage: error['message'] is String ? error['message'] as String : null,
      status: response.statusCode,
      fields: fields,
    );
  }

  final String code;

  /// Texto que mandó el servidor (ya traducido según Accept-Language).
  final String? serverMessage;
  final int? status;

  /// Problema por campo de los errores 422 (`details`).
  final Map<String, String> fields;

  bool get isNetwork => code == ApiCodes.network;

  /// Mismo orden que Rinde Web: mensaje propio por código → primer detalle → mensaje del
  /// servidor → texto de respaldo de la pantalla.
  String messageFor({Map<String, String> byCode = const {}, required String fallback}) {
    if (byCode[code] case final custom?) return custom;
    if (code == ApiCodes.network) return ApiMessages.network;
    if (code == ApiCodes.rateLimited) return ApiMessages.rateLimited;
    if (fields.isNotEmpty) return fields.values.first;
    return serverMessage ?? fallback;
  }

  @override
  String toString() => 'ApiException($code, $status, $serverMessage)';
}
