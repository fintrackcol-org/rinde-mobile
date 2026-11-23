import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../i18n/tr.dart';
import '../region/region_provider.dart';
import 'api_exception.dart';
import 'session_holder.dart';

/// Acceso a la API de Rinde. `public` va sin token; `authed` pone el Bearer y renueva la
/// sesión ante un 401, igual que `authFetch` de Rinde Web.
class ApiClient {
  ApiClient({
    required AppConfig config,
    required SessionHolder session,
    HttpClientAdapter? adapter,
    Map<String, String> Function()? regionHeaders,
  }) {
    final options = BaseOptions(
      baseUrl: config.hasApi ? config.apiV1 : 'http://sin-configurar.invalid',
      connectTimeout: const Duration(seconds: 20),
      // El plan gratuito de Render puede tardar en despertar.
      receiveTimeout: const Duration(seconds: 45),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'Accept-Language': 'es'},
    );
    public = Dio(options);
    authed = Dio(options);
    if (adapter != null) {
      public.httpClientAdapter = adapter;
      authed.httpClientAdapter = adapter;
    }
    final guard = _ConfigGuard(config.problem);
    final region = _RegionHeaders(regionHeaders);
    public.interceptors
      ..add(guard)
      ..add(region);
    authed.interceptors
      ..add(guard)
      ..add(region)
      ..add(_AuthInterceptor(session: session, refresher: public));
  }

  late final Dio public;
  late final Dio authed;

  Future<dynamic> post(String path, {Object? body, bool auth = false}) =>
      _send(() => (auth ? authed : public).post<dynamic>(path, data: body));

  Future<dynamic> get(String path, {bool auth = true, Map<String, dynamic>? query}) =>
      _send(() => (auth ? authed : public).get<dynamic>(path, queryParameters: query));

  Future<dynamic> put(String path, {Object? body}) => _send(() => authed.put<dynamic>(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) => _send(() => authed.patch<dynamic>(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Corta toda petición si el ambiente no está bien configurado (sin URL o apuntando a producción).
class _ConfigGuard extends Interceptor {
  _ConfigGuard(this.problem);
  final String? problem;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (problem == null) return handler.next(options);
    handler.reject(
      DioException(
        requestOptions: options,
        error: ApiException(code: ApiCodes.notConfigured, serverMessage: problem),
      ),
    );
  }
}

/// regionHeaders() de la web: el servidor responde (errores, nombres por defecto) en el idioma que
/// se ve y con la moneda y el país de la persona, leídos en cada petición.
class _RegionHeaders extends Interceptor {
  _RegionHeaders(this.read);
  final Map<String, String> Function()? read;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (read case final read?) options.headers.addAll(read());
    handler.next(options);
  }
}

/// Pone el token y, ante 401, renueva una vez y repite la petición.
/// Es "en cola": si llegan varios 401 a la vez, se atienden de a uno y solo el primero renueva.
class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({required this.session, required this.refresher});

  final SessionHolder session;

  /// Dio sin este interceptor: renueva y repite sin volver a pasar por la cola (evita bloqueos).
  final Dio refresher;

  static const _retried = 'rinde.retried';
  static const _line = 'rinde.session';

  /// A qué inicio de sesión pertenece cada `Session`: la renovación cambia el objeto pero no la
  /// marca; salir o entrar con otra cuenta sí. Así una respuesta tardía no toca una sesión ajena.
  final _lines = Expando<Object>();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final current = session.current;
    if (current == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const ApiException(code: ApiCodes.unauthorized, serverMessage: ApiMessages.sessionExpired),
        ),
      );
      return;
    }
    if (current.demo) {
      // MODO DEMOSTRACIÓN: ninguna petición con sesión sale del dispositivo.
      handler.reject(
        DioException(
          requestOptions: options,
          error: const ApiException(
            code: ApiCodes.demoNoBackend,
            serverMessage: 'Modo demostración: esta acción no llega a ningún servidor.',
          ),
        ),
      );
      return;
    }
    options.headers['Authorization'] = 'Bearer ${current.accessToken}';
    options.extra[_line] = _lines[current] ??= Object();
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final failure = ApiException.fromDio(err);
    final isAuthError =
        err.response?.statusCode == 401 &&
        (failure.code == ApiCodes.unauthorized || failure.code == ApiCodes.tokenExpired);
    if (!isAuthError || err.requestOptions.extra[_retried] == true) return handler.next(err);

    final current = session.current;
    final line = err.requestOptions.extra[_line] as Object?;
    // La sesión de esta petición ya no es la vigente (el servidor la cerró, la persona salió o entró
    // otra cuenta): no se renueva ni se repite con un token que no es el suyo.
    if (current == null || !identical(_lines[current], line)) {
      return handler.reject(
        _withError(
          err,
          const ApiException(
            code: ApiCodes.tokenExpired,
            serverMessage: ApiMessages.sessionExpired,
            status: 401,
          ),
        ),
      );
    }

    final usedHeader = err.requestOptions.headers['Authorization'];
    var tokens = current;
    // Otra petición ya renovó mientras esta esperaba en la cola: basta con repetir.
    if (usedHeader == 'Bearer ${current.accessToken}') {
      try {
        final response = await refresher.post<dynamic>(
          '/auth/refresh',
          data: {'refreshToken': current.refreshToken},
        );
        final data = response.data;
        if (data is! Map || data['accessToken'] is! String || data['refreshToken'] is! String) {
          // La petición original fue un 401: seguro no se aplicó.
          throw const ApiException(code: ApiCodes.unknown, status: 401);
        }
        tokens = current.copyWith(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
        );
        // Mientras renovaba, la persona salió o entró otra cuenta: los tokens nuevos no se guardan
        // (revivirían o pisarían una sesión); solo sirven para terminar esta petición (el logout).
        if (identical(session.current, current)) {
          _lines[tokens] = line;
          await session.save(tokens);
        }
      } on DioException catch (e) {
        final refreshFailure = ApiException.fromDio(e);
        final status = e.response?.statusCode;
        if (status == 401 || status == 400) {
          if (identical(session.current, current)) await session.expire();
          return handler.reject(
            _withError(
              err,
              const ApiException(
                code: ApiCodes.tokenExpired,
                serverMessage: ApiMessages.sessionExpired,
                status: 401,
              ),
            ),
          );
        }
        // La petición original sí fue rechazada (401): aunque falle renovar, seguro no se aplicó.
        if (refreshFailure.isNetwork) {
          return handler.reject(_withError(err, ApiException(code: refreshFailure.code, status: 401)));
        }
        return handler.reject(
          _withError(
            err,
            const ApiException(
              code: 'REFRESH_FAILED',
              serverMessage: 'No pudimos renovar tu sesión. Inténtalo de nuevo.',
              status: 401,
            ),
          ),
        );
      } on ApiException catch (e) {
        return handler.reject(_withError(err, e));
      }
    }

    // Si el cuerpo lleva el refresh token (logout), va el vigente: el viejo ya se rotó y revocarlo
    // dejaría vivo el nuevo en el servidor.
    final body = err.requestOptions.data;
    final retry = err.requestOptions.copyWith(
      data: body is Map && body.containsKey('refreshToken')
          ? {...body, 'refreshToken': tokens.refreshToken}
          : body,
      headers: {...err.requestOptions.headers, 'Authorization': 'Bearer ${tokens.accessToken}'},
      extra: {...err.requestOptions.extra, _retried: true},
    );
    try {
      handler.resolve(await refresher.fetch<dynamic>(retry));
    } on DioException catch (e) {
      handler.reject(e);
    }
  }

  DioException _withError(DioException original, ApiException error) =>
      original.copyWith(error: error, type: DioExceptionType.unknown);
}

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(appConfigProvider),
    session: ref.watch(sessionHolderProvider),
    regionHeaders: () {
      final region = ref.read(appRegionProvider);
      return {
        'Accept-Language': ref.read(displayLanguageProvider),
        'X-Rinde-Currency': region.currency,
        'X-Rinde-Country': region.country,
      };
    },
  ),
);
