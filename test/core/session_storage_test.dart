import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';

/// Doble del llavero: un solo valor, falla al leer a demanda y cuenta los borrados.
class _FakeKeychain implements FlutterSecureStorage {
  String? value;
  Object? readError;
  int deletes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #read:
        if (readError case final e?) return Future<String?>.error(e);
        return Future<String?>.value(value);
      case #write:
        value = invocation.namedArguments[#value] as String?;
        return Future<void>.value();
      case #delete:
        deletes++;
        value = null;
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);

void main() {
  late _FakeKeychain keychain;
  late SecureSessionStorage storage;

  setUp(() {
    keychain = _FakeKeychain();
    storage = SecureSessionStorage(keychain);
  });

  test('lo que se escribe se lee igual', () async {
    await storage.write(_session);
    final back = await storage.read();
    expect(back?.user.id, 'u1');
    expect(back?.accessToken, 'acceso');
    expect(back?.refreshToken, 'refresh');
    expect(keychain.deletes, 0);
  });

  test('sin nada guardado devuelve null sin borrar', () async {
    expect(await storage.read(), isNull);
    expect(keychain.deletes, 0);
  });

  test('un valor dañado se descarta: devuelve null y lo borra', () async {
    for (final corrupt in [
      '{no es json',
      '[]',
      '"texto"',
      jsonEncode({'user': 3}),
    ]) {
      keychain.value = corrupt;
      expect(await storage.read(), isNull, reason: corrupt);
      expect(keychain.value, isNull, reason: corrupt);
    }
    expect(keychain.deletes, 4);
  });

  test('si el llavero no responde (bloqueado) devuelve null y NO borra la sesión', () async {
    await storage.write(_session);
    keychain.readError = PlatformException(code: 'errSecInteractionNotAllowed');
    expect(await storage.read(), isNull);
    expect(keychain.deletes, 0);

    // Cuando el llavero vuelve, la sesión sigue ahí.
    keychain.readError = null;
    expect((await storage.read())?.refreshToken, 'refresh');
  });
}
