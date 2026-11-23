import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/auth/domain/auth_validators.dart';

Map<String, String> _read(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>).cast<String, String>();

void main() {
  // Los assets los genera tool/export_l10n.mjs; lo propio de la app se escribe en tool/l10n_mobile.
  final assets = {
    for (final l in const ['en', 'pt']) l: _read('assets/l10n/$l.json'),
  };
  final mobile = {
    for (final l in const ['en', 'pt']) l: _read('tool/l10n_mobile/$l.json'),
  };

  test('los textos que la web no tiene y «Cuota» salen traducidos', () {
    const expected = {
      'Buscar país': ('Search for a country', 'Buscar país'),
      'No encontramos ese país.': ("We couldn't find that country.", 'Não encontramos esse país.'),
      'Hasta {max} días.': ('Up to {max} days.', 'Até {max} dias.'),
      'Llegaste al tope de {max} pagos. Quita uno para agregar otro.': (
        "You've reached the limit of {max} payments. Remove one to add another.",
        'Você chegou ao limite de {max} pagamentos. Remova um para adicionar outro.',
      ),
      'Se activa por cuenta: pídelo en Cuenta.': (
        "It's turned on per account: ask for it in Account.",
        'É ativado por conta: peça em Conta.',
      ),
      'Tus pagos ya quedaron guardados. Si quieres cambiarlos, hazlo luego en Mi plata.': (
        'Your payments are already saved. To change them, do it later in My money.',
        'Seus pagamentos já foram salvos. Se quiser mudá-los, faça isso depois em Meu dinheiro.',
      ),
      '¡Listo!': ('All set!', 'Tudo pronto!'),
      'Ya agregaste {name}. Cambia el nombre o quítalo.': (
        'You already added {name}. Change the name or remove it.',
        'Você já adicionou {name}. Mude o nome ou remova.',
      ),
      // En la web es la parte de una vaca («Share»); aquí es la cuota de un crédito.
      'Cuota': ('Loan payment', 'Prestação'),
    };
    for (final MapEntry(key: spanish, value: (en, pt)) in expected.entries) {
      expect(assets['en']![spanish], en, reason: spanish);
      expect(assets['pt']![spanish], pt, reason: spanish);
    }
  });

  test('todo lo de tool/l10n_mobile está en los assets y gana sobre la web', () {
    for (final language in mobile.keys) {
      expect(mobile[language], isNotEmpty);
      for (final MapEntry(:key, :value) in mobile[language]!.entries) {
        expect(assets[language]![key], value, reason: '$language «$key»: falta volver a generar los assets');
      }
    }
  });

  test('ningún valor está vacío y cada clave conserva sus variables en los dos idiomas', () {
    final variable = RegExp(r'\{(\w+)\}');
    Set<String> vars(String text) => {for (final m in variable.allMatches(text)) m[1]!};
    final failures = <String>[];
    for (final language in assets.keys) {
      for (final MapEntry(:key, :value) in assets[language]!.entries) {
        if (value.trim().isEmpty) failures.add('$language «$key»: vacío');
        final expected = vars(key);
        final got = vars(value);
        if (!expected.containsAll(got) || !got.containsAll(expected)) {
          failures.add('$language «$key»: variables $got ≠ $expected');
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('los mensajes que llegan a t() en una variable (validadores, errores comunes) tienen traducción', () {
    final long = 'a' * 80;
    final keys = <String?>[
      AuthValidators.email(''),
      AuthValidators.email('ana@'),
      AuthValidators.registerEmail('ana@'),
      AuthValidators.loginPassword(''),
      AuthValidators.name(' '),
      AuthValidators.name(long),
      AuthValidators.newPassword(''),
      AuthValidators.newPassword(long),
      AuthValidators.newPassword('12345678'),
      AuthValidators.newPassword('abcdefgh'),
      AuthValidators.acceptTerms(false),
      for (final rule in AuthValidators.passwordRules('')) rule.label,
      ApiMessages.network,
      ApiMessages.rateLimited,
      ApiMessages.sessionExpired,
      ApiMessages.generic,
      // El de la demostración: llega a t() como mensaje del error (DEMO_NO_BACKEND).
      'Modo demostración: esta acción no llega a ningún servidor.',
    ];
    expect(keys, isNot(contains(null)));
    for (final language in assets.keys) {
      for (final key in keys) {
        expect(assets[language], contains(key), reason: '$language «$key»');
      }
    }
  });

  group('Tr', () {
    test('sin traducción muestra el español; con ella, reemplaza las variables', () {
      expect(const Tr('es', {})('Hola, {name}', {'name': 'Ana'}), 'Hola, Ana');
      expect(Tr('en', assets['en']!)('Hasta {max} días.', {'max': 4}), 'Up to 4 days.');
      expect(const Tr('en', {})('Sin {esto}', {'otra': 1}), 'Sin {esto}');
    });

    test('reemplaza en una sola pasada: un valor con llaves no se vuelve a sustituir', () {
      const t = Tr('es', {});
      expect(t('{name} debe {amount}', {'name': '{amount}', 'amount': 5}), '{amount} debe 5');
      expect(t('{a}{b}', {'b': '{a}', 'a': '{b}'}), '{b}{a}');
    });

    test('maybe: null sigue siendo null (validadores sin error)', () {
      final t = Tr('pt', assets['pt']!);
      expect(t.maybe(null), isNull);
      expect(t.maybe(AuthValidators.loginPassword('')), 'Digite sua senha');
    });
  });
}
