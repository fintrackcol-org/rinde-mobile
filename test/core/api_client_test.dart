import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';

import '../support/fake_http.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _user = AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana');
const _old = Session(user: _user, accessToken: 'acceso-viejo', refreshToken: 'refresh-viejo');

const _tokenExpired = 'TOKEN_EXPIRED';

Future<ApiException> _failure(Future<dynamic> request) async {
  try {
    await request;
  } on ApiException catch (e) {
    return e;
  }
  fail('se esperaba ApiException');
}

void main() {
  late MemorySessionStorage storage;
  late SessionHolder holder;

  setUp(() async {
    storage = MemorySessionStorage(_old);
    holder = SessionHolder(storage);
    await holder.load();
  });

  tearDown(() => holder.dispose());

  ApiClient client(FakeHttpAdapter adapter, {AppConfig config = _qa}) =>
      ApiClient(config: config, session: holder, adapter: adapter);

  group('ambiente', () {
    test('sin API_BASE_URL toda petición falla con NOT_CONFIGURED sin tocar el adaptador', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {}));
      final api = client(
        adapter,
        config: const AppConfig(apiBaseUrl: '', environment: 'local'),
      );

      expect((await _failure(api.post('/auth/login', body: {}))).code, ApiCodes.notConfigured);
      expect((await _failure(api.get('/users/me'))).code, ApiCodes.notConfigured);
      expect(adapter.requests, isEmpty);
    });

    test('producción con APP_ENV distinto de production falla igual', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {}));
      final api = client(
        adapter,
        config: const AppConfig(apiBaseUrl: 'https://api.rindecol.online', environment: 'qa'),
      );

      final e = await _failure(api.post('/auth/login', body: {}));
      expect(e.code, ApiCodes.notConfigured);
      expect(e.serverMessage, contains('producción'));
      expect((await _failure(api.get('/users/me'))).code, ApiCodes.notConfigured);
      expect(adapter.requests, isEmpty);
    });

    test('la URL directa de Render de producción también se bloquea fuera de production', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {}));
      final api = client(
        adapter,
        config: const AppConfig(apiBaseUrl: 'https://FINTRACK-API-2Z1P.onrender.com', environment: 'qa'),
      );
      expect((await _failure(api.post('/auth/login', body: {}))).code, ApiCodes.notConfigured);
      expect(adapter.requests, isEmpty);
    });

    test('producción con APP_ENV=production sí sale', () async {
      final adapter = FakeHttpAdapter((_) => jsonBody(200, {'ok': true}));
      final api = client(
        adapter,
        config: const AppConfig(apiBaseUrl: 'https://api.rindecol.online/', environment: 'production'),
      );
      await api.post('/auth/forgot-password', body: {'email': 'ana@rinde.co'});
      expect(
        adapter.requests.single.uri.toString(),
        'https://api.rindecol.online/api/v1/auth/forgot-password',
      );
    });
  });

  test('pública: sin Authorization, con Accept-Language: es y el cuerpo JSON', () async {
    final adapter = FakeHttpAdapter((_) => jsonBody(200, {'ok': true}));
    final data = await client(adapter).post('/auth/login', body: {'email': 'ana@rinde.co', 'password': 'x'});

    expect(data, {'ok': true});
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api-qa.ejemplo.test/api/v1/auth/login');
    expect(request.headers['Accept-Language'], 'es');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.data, {'email': 'ana@rinde.co', 'password': 'x'});
  });

  test('con sesión pone Authorization: Bearer <access> y Accept-Language: es', () async {
    final adapter = FakeHttpAdapter((_) => jsonBody(200, {'id': 'u1'}));
    await client(adapter).get('/users/me');

    final request = adapter.requests.single;
    expect(request.headers['Authorization'], 'Bearer acceso-viejo');
    expect(request.headers['Accept-Language'], 'es');
  });

  test('regionHeaders: idioma, moneda y país vigentes en cada petición (como la web)', () async {
    final adapter = FakeHttpAdapter((_) => jsonBody(200, {'ok': true}));
    var language = 'en';
    final api = ApiClient(
      config: _qa,
      session: holder,
      adapter: adapter,
      regionHeaders: () => {'Accept-Language': language, 'X-Rinde-Currency': 'USD', 'X-Rinde-Country': 'US'},
    );
    await api.get('/users/me');
    language = 'pt';
    await api.post('/auth/login', body: {});

    expect(adapter.requests[0].headers['Accept-Language'], 'en');
    expect(adapter.requests[0].headers['X-Rinde-Currency'], 'USD');
    expect(adapter.requests[0].headers['X-Rinde-Country'], 'US');
    expect(adapter.requests[1].headers['Accept-Language'], 'pt');
  });

  test('con sesión pero sin tokens guardados falla con UNAUTHORIZED sin salir a la red', () async {
    await holder.clear();
    final adapter = FakeHttpAdapter((_) => jsonBody(200, {}));
    final e = await _failure(client(adapter).get('/users/me'));
    expect(e.code, ApiCodes.unauthorized);
    expect(e.serverMessage, ApiMessages.sessionExpired);
    expect(adapter.requests, isEmpty);
  });

  test('un error que no es 401 llega tal cual a la pantalla', () async {
    final adapter = FakeHttpAdapter((_) => errorBody(409, 'EMAIL_TAKEN', 'El correo ya está registrado'));
    final e = await _failure(client(adapter).post('/auth/register', body: {}));
    expect(e.code, ApiCodes.emailTaken);
    expect(e.status, 409);
    expect(adapter.to('/auth/refresh'), isEmpty);
  });

  group('renovación ante 401', () {
    FakeHttpAdapter backend({required FakeHandler refresh, bool alwaysExpired = false}) =>
        FakeHttpAdapter((o) {
          if (o.path == '/auth/refresh') return refresh(o);
          if (!alwaysExpired && o.headers['Authorization'] == 'Bearer acceso-nuevo') {
            return jsonBody(200, {'id': 'u1'});
          }
          return errorBody(401, _tokenExpired, 'El token expiró');
        });

    ResponseBody newTokens(RequestOptions _) =>
        jsonBody(200, {'accessToken': 'acceso-nuevo', 'refreshToken': 'refresh-nuevo'});

    test('renueva con {refreshToken}, guarda los tokens y repite una vez con el token nuevo', () async {
      final adapter = backend(refresh: newTokens);
      final data = await client(adapter).get('/users/me');

      expect(data, {'id': 'u1'});
      final refresh = adapter.to('/auth/refresh').single;
      expect(refresh.method, 'POST');
      expect(refresh.data, {'refreshToken': 'refresh-viejo'});
      expect(refresh.headers.containsKey('Authorization'), isFalse);

      final calls = adapter.to('/users/me');
      expect(calls.map((r) => r.headers['Authorization']), ['Bearer acceso-viejo', 'Bearer acceso-nuevo']);

      expect(holder.current?.accessToken, 'acceso-nuevo');
      expect(holder.current?.refreshToken, 'refresh-nuevo');
      expect(holder.current?.user.id, 'u1', reason: 'refresh no trae user: se conserva el de la sesión');
      final saved = await storage.read();
      expect(saved?.accessToken, 'acceso-nuevo');
      expect(saved?.refreshToken, 'refresh-nuevo');
    });

    test('también renueva ante 401 UNAUTHORIZED (token inválido)', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.path == '/auth/refresh') return newTokens(o);
        if (o.headers['Authorization'] == 'Bearer acceso-nuevo') return jsonBody(200, {});
        return errorBody(401, 'UNAUTHORIZED', 'Token inválido o ausente');
      });
      await client(adapter).get('/users/me');
      expect(adapter.to('/auth/refresh'), hasLength(1));
    });

    test('logout con el access vencido repite con el refresh token NUEVO (si no, quedaría vivo)', () async {
      final adapter = backend(refresh: newTokens);
      await client(adapter).post('/auth/logout', body: {'refreshToken': 'refresh-viejo'}, auth: true);

      final calls = adapter.to('/auth/logout');
      expect(calls.map((r) => r.data), [
        {'refreshToken': 'refresh-viejo'},
        {'refreshToken': 'refresh-nuevo'},
      ]);
    });

    test('si la repetición vuelve a dar 401 no renueva otra vez', () async {
      final adapter = backend(refresh: newTokens, alwaysExpired: true);
      final e = await _failure(client(adapter).get('/users/me'));

      expect(e.code, _tokenExpired);
      expect(adapter.to('/auth/refresh'), hasLength(1));
      expect(adapter.to('/users/me'), hasLength(2));
    });

    test('si el refresh responde 401, borra la sesión y avisa por onExpired', () async {
      var expiredEvents = 0;
      final sub = holder.onExpired.listen((_) => expiredEvents++);
      addTearDown(sub.cancel);

      final adapter = backend(
        refresh: (_) => errorBody(401, 'UNAUTHORIZED', 'Refresh token inválido, vencido o revocado'),
      );
      final e = await _failure(client(adapter).get('/users/me'));
      await Future<void>.delayed(Duration.zero);

      expect(e.code, _tokenExpired);
      expect(e.serverMessage, ApiMessages.sessionExpired);
      expect(holder.current, isNull);
      expect(await storage.read(), isNull);
      expect(expiredEvents, 1);
      expect(adapter.to('/users/me'), hasLength(1), reason: 'no repite sin token');
    });

    test('si el refresh falla por red, conserva la sesión y el error es NETWORK', () async {
      var expiredEvents = 0;
      final sub = holder.onExpired.listen((_) => expiredEvents++);
      addTearDown(sub.cancel);

      final adapter = backend(refresh: networkFailure);
      final e = await _failure(client(adapter).get('/users/me'));
      await Future<void>.delayed(Duration.zero);

      expect(e.code, ApiCodes.network);
      expect(e.messageFor(fallback: 'x'), ApiMessages.network);
      expect(holder.current?.accessToken, 'acceso-viejo');
      expect((await storage.read())?.refreshToken, 'refresh-viejo');
      expect(expiredEvents, 0);
    });

    group('la sesión cambia mientras se renueva', () {
      const other = Session(
        user: AuthUser(id: 'u2', email: 'beto@rinde.co', name: 'Beto'),
        accessToken: 'acceso-beto',
        refreshToken: 'refresh-beto',
      );
      late Completer<void> refreshing;
      late Completer<void> release;
      late int expiredEvents;

      setUp(() {
        refreshing = Completer();
        release = Completer();
        expiredEvents = 0;
        final sub = holder.onExpired.listen((_) => expiredEvents++);
        addTearDown(sub.cancel);
      });

      /// El refresh avisa que llegó y espera a que la prueba lo suelte.
      FakeHandler slow(FakeHandler reply) => (o) async {
        refreshing.complete();
        await release.future;
        return reply(o);
      };

      test('salir mientras renueva: la sesión no revive y el logout revoca el refresh nuevo', () async {
        final adapter = backend(refresh: slow(newTokens));
        final logout = client(adapter)
            .post('/auth/logout', body: {'refreshToken': 'refresh-viejo'}, auth: true);
        await refreshing.future;
        // signOut no espera a un servidor dormido: borra la sesión con la renovación en camino.
        await holder.clear();
        release.complete();
        await logout;

        expect(holder.current, isNull);
        expect(await storage.read(), isNull, reason: 'guardar los tokens nuevos reviviría la sesión');
        expect(expiredEvents, 0);
        expect(adapter.to('/auth/logout').last.data, {'refreshToken': 'refresh-nuevo'});
      });

      test('entra otra cuenta mientras renueva: su sesión queda intacta', () async {
        final adapter = backend(refresh: slow(newTokens));
        final request = client(adapter).get('/users/me');
        await refreshing.future;
        await holder.clear();
        await holder.save(other);
        release.complete();
        await request;

        expect(holder.current, same(other));
        expect((await storage.read())?.accessToken, 'acceso-beto');
        expect(expiredEvents, 0);
        // La petición de la primera cuenta termina con SU token renovado, nunca con el de la otra.
        expect(adapter.to('/users/me').map((r) => r.headers['Authorization']), [
          'Bearer acceso-viejo',
          'Bearer acceso-nuevo',
        ]);
      });

      test('si el refresh de la sesión anterior se rechaza, no cierra la sesión nueva', () async {
        final adapter = backend(refresh: slow((_) => errorBody(401, 'UNAUTHORIZED', 'Refresh revocado')));
        final request = _failure(client(adapter).get('/users/me'));
        await refreshing.future;
        await holder.save(other);
        release.complete();

        expect((await request).code, _tokenExpired);
        await Future<void>.delayed(Duration.zero);
        expect(holder.current, same(other));
        expect((await storage.read())?.refreshToken, 'refresh-beto');
        expect(expiredEvents, 0);
      });

      test('un 401 que llega cuando ya entró otra cuenta no renueva ni repite con el token ajeno', () async {
        final arrived = Completer<void>();
        final adapter = FakeHttpAdapter((o) async {
          if (o.path == '/auth/refresh') return newTokens(o);
          if (o.headers['Authorization'] != 'Bearer acceso-viejo') return jsonBody(200, {'id': 'u2'});
          arrived.complete();
          await release.future;
          return errorBody(401, _tokenExpired, 'El token expiró');
        });
        final api = client(adapter);
        final request = _failure(api.post('/money-profile/welcome', body: {'balance': 1}, auth: true));
        await arrived.future;
        await holder.save(other);
        release.complete();

        final e = await request;
        expect(e.code, _tokenExpired);
        expect(e.serverMessage, ApiMessages.sessionExpired);
        expect(adapter.to('/auth/refresh'), isEmpty);
        expect(adapter.to('/money-profile/welcome'), hasLength(1), reason: 'escribiría en la otra cuenta');
        expect(holder.current, same(other));
        expect(expiredEvents, 0);

        // La cuenta nueva sigue usando la API con normalidad.
        expect(await api.get('/users/me'), {'id': 'u2'});
      });
    });

    test('dos peticiones concurrentes con 401 hacen UN solo refresh', () async {
      // El backend retiene los dos 401 hasta que ambas peticiones llegaron con el token viejo.
      final bothArrived = Completer<void>();
      var oldTokenCalls = 0;
      final adapter = FakeHttpAdapter((o) async {
        if (o.path == '/auth/refresh') return newTokens(o);
        if (o.headers['Authorization'] == 'Bearer acceso-nuevo') return jsonBody(200, {'path': o.path});
        if (++oldTokenCalls == 2) bothArrived.complete();
        await bothArrived.future;
        return errorBody(401, _tokenExpired, 'El token expiró');
      });
      final api = client(adapter);

      final results = await Future.wait([api.get('/users/me'), api.get('/users/me/reminder-settings')]);

      expect(results, [
        {'path': '/users/me'},
        {'path': '/users/me/reminder-settings'},
      ]);
      expect(oldTokenCalls, 2);
      expect(adapter.to('/auth/refresh'), hasLength(1));
      expect(holder.current?.accessToken, 'acceso-nuevo');
    });
  });
}
