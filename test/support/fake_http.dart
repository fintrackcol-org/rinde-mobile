import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Responde como el backend según `RequestOptions` y guarda cada petición recibida.
typedef FakeHandler = FutureOr<ResponseBody> Function(RequestOptions options);

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FakeHandler handler;
  final requests = <RequestOptions>[];

  List<RequestOptions> to(String path) => requests.where((r) => r.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// Forma de error del backend: `{ error: { code, message, details? } }`.
ResponseBody errorBody(int status, String code, String message, {List<Map<String, String>>? details}) =>
    jsonBody(status, {
      'error': {'code': code, 'message': message, 'details': ?details},
    });

/// Fallo de red: no hay respuesta.
Never networkFailure(RequestOptions options) =>
    throw DioException.connectionError(requestOptions: options, reason: 'sin red');
