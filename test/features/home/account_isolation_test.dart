import 'dart:async';
import 'dart:io' show HttpException, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';

import '../../support/fake_home_repository.dart';

// Regresiones de la revisión de la etapa 2: datos y moneda de una cuenta no pasan a otra, y un
// error se lee como lo que es.

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co', name: 'Beto'),
  accessToken: 'b',
  refreshToken: 's',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _ana));

  void enter(Session? session) => state = AsyncData(SessionState(session: session));
}

class _Auth implements AuthRepository {
  final waiting = <Completer<UserProfile>>[];

  @override
  Future<UserProfile> me() => (waiting..add(Completer())).last.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _NoRegionStore extends RegionStore {
  @override
  Future<Region?> read() async => null;
  @override
  Future<void> write(Region region) async {}
}

void main() {
  late FakeHomeRepository repo;
  late _Auth auth;
  late ProviderContainer c;

  setUp(() {
    repo = FakeHomeRepository();
    auth = _Auth();
    c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        homeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
        regionStoreProvider.overrideWithValue(_NoRegionStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
    );
  });

  void enter(Session? session) => (c.read(sessionControllerProvider.notifier) as _Sessions).enter(session);

  test('salir y volver a entrar empieza de cero: no vuelve la plata de la sesión anterior', () async {
    c.listen(homePlanProvider(_ana), (_, _) {});
    await c.read(homePlanProvider(_ana).future);

    final again = _ana.copyWith(accessToken: 'a2');
    enter(null);
    enter(again);
    expect(c.read(accountProvider), same(again));
    repo.onPlan = () async => throw const ApiException(code: ApiCodes.network);
    c.listen(homePlanProvider(again), (_, _) {});
    await expectLater(c.read(homePlanProvider(again).future), throwsA(isA<ApiException>()));
    expect(c.read(homePlanProvider(again)).value, isNull);
  });

  test('el perfil que llega tarde de quien salió no le cambia la moneda a quien entró', () async {
    final before = c.read(appRegionProvider);
    // Sin escucha, como al desmontarse el Inicio.
    final late_ = c.read(profileProvider(_ana).future);
    await Future<void>.delayed(Duration.zero);
    enter(_beto);
    auth.waiting.first.complete(
      const UserProfile(
        id: 'a',
        email: 'ana@rinde.co',
        termsAccepted: true,
        country: 'US',
        currency: 'USD',
        language: 'en',
      ),
    );
    await late_
        .timeout(const Duration(seconds: 1), onTimeout: () => throw StateError('sin respuesta'))
        .then((_) {}, onError: (_) {});
    expect(c.read(appRegionProvider), before);
  });

  test('actualizar anota la hora, y que cambie el día (el plan solo) no', () async {
    await c.read(homePlanProvider(_ana).future);
    expect(c.read(homeFreshnessProvider).of(_ana), isNull);
    await c.read(homeToConfirmProvider(_ana).future);
    expect(c.read(homeFreshnessProvider).of(_ana), DateTime(2026, 11, 22, 10));
    expect(c.read(homeFreshnessProvider).of(_beto), isNull);
  });

  test('pedir el tutorial no pasa a la cuenta que entra después', () {
    c.listen(tourRequestedProvider, (_, _) {});
    c.read(tourRequestedProvider.notifier).request();
    enter(_beto);
    expect(c.read(tourRequestedProvider), isFalse);
  });

  test('un plan sin datos nunca se lee como cero', () {
    expect(() => MoneyPlan.fromJson(<String, dynamic>{'ready': true}), throwsA(isA<ContractException>()));
  });

  group('qué prueba cada fallo de red', () {
    String code(DioExceptionType type, Object error) => ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: type,
        error: error,
      ),
    ).code;

    test('no se pudo conectar: no salió', () {
      expect(code(DioExceptionType.connectionTimeout, const SocketException('timed out')), ApiCodes.network);
      expect(code(DioExceptionType.connectionError, const SocketException('x')), ApiCodes.network);
    });
    test('se cortó con la conexión abierta: pudo llegar', () {
      expect(code(DioExceptionType.connectionError, const HttpException('x')), ApiCodes.timeout);
      expect(code(DioExceptionType.unknown, const SocketException('x')), ApiCodes.timeout);
    });
    test('un corte sin tipo de Dio con la petición ya enviada: pudo llegar', () {
      for (final message in ['Connection reset by peer', 'Connection closed while receiving data']) {
        expect(code(DioExceptionType.unknown, HttpException(message)), ApiCodes.timeout, reason: message);
      }
    });
    test('una respuesta que no es JSON es un fallo, no falta de conexión', () {
      expect(code(DioExceptionType.unknown, const FormatException('x')), ApiCodes.unknown);
    });
  });

  test('el nombre de un pago se corta sin partir un emoji', () {
    final name = '${'a' * 59}😀';
    expect(clipCommitmentName(name), 'a' * 59);
    expect(clipCommitmentName('Arriendo'), 'Arriendo');
  });
}
