import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/auth/domain/auth_validators.dart';

void main() {
  group('normalizeEmail', () {
    test('recorta y pasa a minúsculas', () {
      expect(AuthValidators.normalizeEmail('  Ana.Perez@Rinde.CO \n'), 'ana.perez@rinde.co');
    });
  });

  group('normalizeName', () {
    test('recorta y deja un solo espacio entre palabras', () {
      expect(AuthValidators.normalizeName('  Ana   María \t  Pérez  '), 'Ana María Pérez');
      expect(AuthValidators.normalizeName('   '), '');
    });
  });

  group('email (login y recuperar)', () {
    test('vacío o solo espacios', () {
      for (final v in [null, '', '   ']) {
        expect(AuthValidators.email(v), 'Ingresa tu correo electrónico');
      }
    });

    test('inválido', () {
      for (final v in [
        'ana',
        'ana@',
        'ana@rinde',
        '@rinde.co',
        'ana@rinde.c',
        '.ana@rinde.co',
        'ana..p@rinde.co',
        'a na@rinde.co',
      ]) {
        expect(AuthValidators.email(v), 'Ingresa un correo válido', reason: v);
      }
    });

    test('válido aunque traiga espacios alrededor y mayúsculas', () {
      for (final v in [
        'ana@rinde.co',
        '  ANA@Rinde.CO  ',
        'ana.p+gastos@mail.rinde.com',
        "o'neil@rinde.co",
      ]) {
        expect(AuthValidators.email(v), isNull, reason: v);
      }
    });
  });

  group('registerEmail', () {
    test('vacío', () {
      expect(AuthValidators.registerEmail('  '), 'Ingresa tu correo electrónico');
    });

    test('inválido explica qué falta', () {
      expect(
        AuthValidators.registerEmail('ana@rinde'),
        'Al correo le falta algo: revisa la @ y el final, por ejemplo .com o .co',
      );
    });

    test('válido con mayúsculas y espacios', () {
      expect(AuthValidators.registerEmail(' Ana@Rinde.co '), isNull);
    });
  });

  group('loginPassword', () {
    test('vacía', () {
      expect(AuthValidators.loginPassword(null), 'Ingresa tu contraseña');
      expect(AuthValidators.loginPassword(''), 'Ingresa tu contraseña');
    });

    test('no se recorta ni se revisa la forma: la decide el servidor', () {
      expect(AuthValidators.loginPassword(' '), isNull);
      expect(AuthValidators.loginPassword('a'), isNull);
    });
  });

  group('name', () {
    test('vacío o solo espacios', () {
      for (final v in [null, '', '    ']) {
        expect(AuthValidators.name(v), 'Escribe tu nombre: no puede quedar solo con espacios.');
      }
    });

    test('60 caracteres pasa, 61 no', () {
      expect(AuthValidators.name('a' * 60), isNull);
      expect(AuthValidators.name('a' * 61), 'Máximo 60 caracteres');
    });

    test('los espacios de los bordes no cuentan', () {
      expect(AuthValidators.name('  ${'a' * 60}  '), isNull);
    });
  });

  group('newPassword', () {
    test('menos de 8', () {
      expect(AuthValidators.newPassword(null), 'Usa al menos 8 caracteres');
      expect(AuthValidators.newPassword('abc1234'), 'Usa al menos 8 caracteres');
    });

    test('72 pasa, 73 no', () {
      expect(AuthValidators.newPassword('a1${'x' * 70}'), isNull);
      expect(AuthValidators.newPassword('a1${'x' * 71}'), 'Usa máximo 72 caracteres');
    });

    test('solo letras', () {
      expect(AuthValidators.newPassword('abcdefgh'), 'Incluye al menos un número');
    });

    test('solo números', () {
      expect(AuthValidators.newPassword('12345678'), 'Incluye al menos una letra');
    });

    test('sin letras ni números revisa primero la letra (mismo orden que zod)', () {
      expect(AuthValidators.newPassword('!!!!!!!!'), 'Incluye al menos una letra');
    });

    test('la ñ y las tildes no cuentan como letra (/[A-Za-z]/ de la web)', () {
      expect(AuthValidators.newPassword('ñáéíóú12'), 'Incluye al menos una letra');
    });

    test('espacios cuentan como caracteres y no se recortan', () {
      expect(AuthValidators.newPassword('   a1   '), isNull);
    });

    test('válida', () {
      expect(AuthValidators.newPassword('rinde2026'), isNull);
    });
  });

  group('acceptTerms', () {
    test('solo true pasa', () {
      const message = 'Debes ser mayor de edad y aceptar los términos para continuar';
      expect(AuthValidators.acceptTerms(null), message);
      expect(AuthValidators.acceptTerms(false), message);
      expect(AuthValidators.acceptTerms(true), isNull);
    });
  });

  group('passwordRules', () {
    test('textos y estado de cada regla', () {
      List<(String, bool)> rules(String v) => [
        for (final r in AuthValidators.passwordRules(v)) (r.label, r.met),
      ];

      expect(rules(''), [('8 caracteres o más', false), ('Una letra', false), ('Un número', false)]);
      expect(rules('abc'), [('8 caracteres o más', false), ('Una letra', true), ('Un número', false)]);
      expect(rules('12345678'), [('8 caracteres o más', true), ('Una letra', false), ('Un número', true)]);
    });

    test('cumplirlas todas no basta si pasa de 72', () {
      final long = 'a1${'x' * 71}';
      expect(AuthValidators.passwordRules(long).every((r) => r.met), isTrue);
      expect(AuthValidators.newPassword(long), 'Usa máximo 72 caracteres');
    });
  });
}
