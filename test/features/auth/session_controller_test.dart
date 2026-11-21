import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';

const _user = AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana');
const _saved = Session(user: _user, accessToken: 'acceso-guardado', refreshToken: 'refresh-guardado');
const _fresh = Session(user: _user, accessToken: 'acceso-nuevo', refreshToken: 'refresh-nuevo');

class _FakeAuthRepository implements AuthRepository {
  final loginCalls = <(String, String)>[];
  final logoutCalls = <String>[];
  Object? loginError;
  Object? logoutError;

  @override
  Future<Session> login({required String email, required String password}) async {
    loginCalls.add((email, password));
    if (loginError case final e?) throw e;
    return _fresh;
  }

  @override
  Future<void> logout(String refreshToken) async {
    logoutCalls.add(refreshToken);
    if (logoutError case final e?) throw e;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late MemorySessionStorage storage;
  late _FakeAuthRepository repo;

  ProviderContainer container({Session? stored}) {
    storage = MemorySessionStorage(stored);
    repo = _FakeAuthRepository();
    final c = ProviderContainer.test(
      overrides: [
        sessionStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repo),
      ],
    );
    // Mantiene vivo el controlador como lo haría el router.
    c.listen(sessionControllerProvider, (_, _) {});
    return c;
  }

  test('arranca cargando y termina sin sesión si no hay nada guardado', () async {
    final c = container();
    expect(c.read(sessionControllerProvider).isLoading, isTrue);

    final state = await c.read(sessionControllerProvider.future);
    expect(state.signedIn, isFalse);
    expect(state.expired, isFalse);
  });

  test('arranca con la sesión guardada', () async {
    final c = container(stored: _saved);
    final state = await c.read(sessionControllerProvider.future);

    expect(state.signedIn, isTrue);
    expect(state.session?.accessToken, 'acceso-guardado');
    expect(c.read(sessionHolderProvider).current?.refreshToken, 'refresh-guardado');
  });

  test('signIn guarda la sesión y deja signedIn', () async {
    final c = container();
    await c.read(sessionControllerProvider.future);

    await c.read(sessionControllerProvider.notifier).signIn(email: 'ana@rinde.co', password: 'rinde2026');

    expect(repo.loginCalls, [('ana@rinde.co', 'rinde2026')]);
    expect(c.read(sessionControllerProvider).value?.signedIn, isTrue);
    expect(c.read(sessionHolderProvider).current?.accessToken, 'acceso-nuevo');
    expect((await storage.read())?.refreshToken, 'refresh-nuevo');
  });

  test('signIn rechazado lanza ApiException y no guarda nada', () async {
    final c = container();
    await c.read(sessionControllerProvider.future);
    repo.loginError = const ApiException(code: ApiCodes.emailNotVerified, status: 403);

    await expectLater(
      c.read(sessionControllerProvider.notifier).signIn(email: 'ana@rinde.co', password: 'x'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.emailNotVerified)),
    );
    expect(c.read(sessionControllerProvider).value?.signedIn, isFalse);
    expect(await storage.read(), isNull);
  });

  test('signOut llama logout con el refresh token y limpia', () async {
    final c = container(stored: _saved);
    await c.read(sessionControllerProvider.future);

    await c.read(sessionControllerProvider.notifier).signOut();

    expect(repo.logoutCalls, ['refresh-guardado']);
    expect(c.read(sessionControllerProvider).value?.signedIn, isFalse);
    expect(c.read(sessionControllerProvider).value?.expired, isFalse);
    expect(c.read(sessionHolderProvider).current, isNull);
    expect(await storage.read(), isNull);
  });

  test('signOut limpia aunque logout falle', () async {
    final c = container(stored: _saved);
    await c.read(sessionControllerProvider.future);
    repo.logoutError = const ApiException(code: ApiCodes.network);

    await c.read(sessionControllerProvider.notifier).signOut();

    expect(repo.logoutCalls, hasLength(1));
    expect(c.read(sessionControllerProvider).value?.signedIn, isFalse);
    expect(await storage.read(), isNull);
  });

  test('signOut sin sesión no llama al servidor', () async {
    final c = container();
    await c.read(sessionControllerProvider.future);

    await c.read(sessionControllerProvider.notifier).signOut();
    expect(repo.logoutCalls, isEmpty);
  });

  test('si el holder expira la sesión, queda expired=true y sin sesión', () async {
    final c = container(stored: _saved);
    await c.read(sessionControllerProvider.future);

    await c.read(sessionHolderProvider).expire();
    await Future<void>.delayed(Duration.zero);

    final state = c.read(sessionControllerProvider).value;
    expect(state?.expired, isTrue);
    expect(state?.signedIn, isFalse);
    expect(await storage.read(), isNull);
  });
}
