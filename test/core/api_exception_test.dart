import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';

final _options = RequestOptions(path: '/auth/login');

DioException _bad(int status, Object? data) => DioException(
  requestOptions: _options,
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(requestOptions: _options, statusCode: status, data: data),
);

void main() {
  group('ApiException.fromDio', () {
    test('lee code, message, status y details del contrato del backend', () {
      final e = ApiException.fromDio(
        _bad(422, {
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'Datos inválidos',
            'details': [
              {'field': 'email', 'problem': 'Debe ser un correo válido'},
              {'field': 'password', 'problem': 'Debe tener al menos 8 caracteres'},
              // Un segundo problema del mismo campo no pisa al primero.
              {'field': 'email', 'problem': 'otro'},
              {'field': 'raro'},
            ],
          },
        }),
      );
      expect(e.code, ApiCodes.validation);
      expect(e.serverMessage, 'Datos inválidos');
      expect(e.status, 422);
      expect(e.fields, {
        'email': 'Debe ser un correo válido',
        'password': 'Debe tener al menos 8 caracteres',
      });
    });

    test('sin details deja fields vacío', () {
      final e = ApiException.fromDio(
        _bad(401, {
          'error': {'code': 'UNAUTHORIZED', 'message': 'Correo o contraseña incorrectos'},
        }),
      );
      expect(e.code, ApiCodes.unauthorized);
      expect(e.fields, isEmpty);
    });

    test('sin respuesta es NETWORK', () {
      expect(ApiException.fromDio(DioException(requestOptions: _options)).code, ApiCodes.network);
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(ApiException.fromDio(DioException(requestOptions: _options, type: type)).isNetwork, isTrue);
      }
    });

    test('cuerpo que no es JSON (o sin "error") es UNKNOWN con el status', () {
      final html = ApiException.fromDio(_bad(502, '<html>Bad Gateway</html>'));
      expect(html.code, ApiCodes.unknown);
      expect(html.status, 502);
      expect(ApiException.fromDio(_bad(500, {'mensaje': 'x'})).code, ApiCodes.unknown);
      expect(ApiException.fromDio(_bad(500, null)).code, ApiCodes.unknown);
    });

    test('code que no es texto pasa a UNKNOWN', () {
      final e = ApiException.fromDio(
        _bad(400, {
          'error': {'code': 7, 'message': 'x'},
        }),
      );
      expect(e.code, ApiCodes.unknown);
      expect(e.serverMessage, 'x');
    });

    test('si el error ya es ApiException lo devuelve tal cual', () {
      const inner = ApiException(code: ApiCodes.notConfigured, serverMessage: 'Falta API_BASE_URL');
      expect(
        identical(ApiException.fromDio(DioException(requestOptions: _options, error: inner)), inner),
        isTrue,
      );
    });
  });

  group('messageFor', () {
    const fallback = 'No pudimos iniciar sesión.';

    test('1) el mensaje propio por código gana a todo', () {
      const e = ApiException(code: ApiCodes.network, serverMessage: 's', fields: {'email': 'f'});
      expect(e.messageFor(byCode: {ApiCodes.network: 'propio'}, fallback: fallback), 'propio');
    });

    test('2) red', () {
      const e = ApiException(code: ApiCodes.network, serverMessage: 's');
      expect(e.messageFor(fallback: fallback), ApiMessages.network);
    });

    test('3) límite de intentos, aunque el servidor mande su propio texto', () {
      const e = ApiException(
        code: ApiCodes.rateLimited,
        serverMessage: 'Demasiados intentos. Espera unos minutos',
      );
      expect(e.messageFor(fallback: fallback), ApiMessages.rateLimited);
    });

    test('4) primer detalle antes que el mensaje del servidor', () {
      const e = ApiException(
        code: ApiCodes.validation,
        serverMessage: 'Datos inválidos',
        fields: {'email': 'Debe ser un correo válido'},
      );
      expect(e.messageFor(fallback: fallback), 'Debe ser un correo válido');
    });

    test('5) mensaje del servidor', () {
      const e = ApiException(code: ApiCodes.unauthorized, serverMessage: 'Correo o contraseña incorrectos');
      expect(
        e.messageFor(byCode: {ApiCodes.emailTaken: 'x'}, fallback: fallback),
        'Correo o contraseña incorrectos',
      );
    });

    test('6) texto de respaldo', () {
      expect(const ApiException(code: ApiCodes.unknown).messageFor(fallback: fallback), fallback);
    });
  });
}
