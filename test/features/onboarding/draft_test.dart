import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/commitments.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_flow.dart';

OnboardingDraft _read(Object? json, {String suggested = 'CO'}) =>
    OnboardingDraft.fromJson(json, suggestedCountry: suggested);

/// Borrador válido mínimo, para dañar un campo a la vez.
Map<String, dynamic> _valid([Map<String, dynamic> patch = const {}]) => {
  'v': OnboardingDraft.version,
  'position': 8,
  'country': 'MX',
  'language': 'es',
  ...patch,
};

void main() {
  group('ida y vuelta JSON', () {
    test('conserva todo, incluido el orden de las fuentes y la huella enviada', () {
      const draft = OnboardingDraft(
        position: OnboardingSteps.payments,
        country: 'BR',
        language: 'en',
        languagePicked: true,
        sources: {
          IncomeKind.proyectos: IncomeSourceForm(kind: IncomeKind.proyectos, lastMonths: ['', '2000000', '']),
          IncomeKind.sueldo: IncomeSourceForm(kind: IncomeKind.sueldo, amount: '2500000', payDays: [15, 30]),
          IncomeKind.mesada: IncomeSourceForm(kind: IncomeKind.mesada, frequency: 'semanal'),
          IncomeKind.diario: IncomeSourceForm(kind: IncomeKind.diario, workDays: '4'),
        },
        balance: '1234567.5',
        items: [
          CommitmentItem(key: 'a', name: 'Rent', amount: '800000', dayOfMonth: '5'),
          CommitmentItem(key: 'b', name: 'Gym', amount: '12.', dayOfMonth: '', custom: true),
        ],
        sentWelcome: '{"balance":1}',
      );
      final back = _read(jsonDecode(jsonEncode(draft.toJson())));
      expect(back.toJson(), draft.toJson());
      expect(back.sources.keys, [
        IncomeKind.proyectos,
        IncomeKind.sueldo,
        IncomeKind.mesada,
        IncomeKind.diario,
      ]);
      expect(back.items.last.custom, isTrue);
      expect(back.sentWelcome, '{"balance":1}');
    });

    test('sin huella no escribe la clave sentWelcome', () {
      expect(OnboardingDraft.fresh('CO').toJson().containsKey('sentWelcome'), isFalse);
    });

    test('la confirmación del servidor viaja aparte de la huella y solo vale con ella', () {
      const sent = OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: '{}');
      // Anotada antes de enviar: todavía no hay confirmación.
      expect(sent.toJson().containsKey('welcomeConfirmed'), isFalse);
      expect(_read(sent.toJson()).welcomeConfirmed, isFalse);

      final confirmed = sent.copyWith(welcomeConfirmed: true);
      expect(_read(jsonDecode(jsonEncode(confirmed.toJson()))).welcomeConfirmed, isTrue);
      expect(_read(_valid({'welcomeConfirmed': true})).welcomeConfirmed, isFalse, reason: 'sin huella');
      expect(_read(_valid({'sentWelcome': '{}', 'welcomeConfirmed': 'true'})).welcomeConfirmed, isFalse);
    });

    test('borrador nuevo: saludo, país sugerido y su idioma', () {
      final fresh = OnboardingDraft.fresh('BR');
      expect(fresh.position, OnboardingSteps.hello);
      expect(fresh.country, 'BR');
      expect(fresh.language, 'pt');
      expect(fresh.languagePicked, isFalse);
      // Un país sugerido que no existe cae en Colombia.
      expect(OnboardingDraft.fresh('XX').country, 'CO');
    });
  });

  group('datos dañados (campo por campo)', () {
    test('versión distinta, sin versión o que no es un objeto → borrador nuevo', () {
      for (final bad in <Object?>[
        _valid({'v': 2}),
        _valid()..remove('v'),
        [1, 2],
        'texto',
        null,
      ]) {
        expect(_read(bad, suggested: 'BR').toJson(), OnboardingDraft.fresh('BR').toJson(), reason: '$bad');
      }
    });

    test('posición fuera de rango o no entera → saludo', () {
      for (final p in [10, -1, '8', 8.5]) {
        expect(_read(_valid({'position': p})).position, OnboardingSteps.hello, reason: '$p');
      }
      expect(_read(_valid({'position': 9})).position, 9);
    });

    test('país inexistente → el sugerido; y su idioma si el guardado tampoco sirve', () {
      expect(_read(_valid({'country': 'XX'}), suggested: 'BR').country, 'BR');
      expect(_read(_valid({'country': 7}), suggested: 'BR').country, 'BR');
    });

    test('idioma zh (pausado) u otro → el idioma del país', () {
      expect(_read(_valid({'country': 'BR', 'language': 'zh'})).language, 'pt');
      expect(_read(_valid({'country': 'US', 'language': 'fr'})).language, 'en');
      expect(_read(_valid({'country': 'MX', 'language': null})).language, 'es');
      expect(_read(_valid({'country': 'BR', 'language': 'en'})).language, 'en');
    });

    test(
      'fuentes: sin kind o con kind desconocido se descartan; un kind repetido se queda con el primero',
      () {
        final draft = _read(
          _valid({
            'sources': [
              {'amount': '1'},
              {'kind': 'otro'},
              'basura',
              {'kind': 'sueldo', 'amount': '100'},
              {'kind': 'sueldo', 'amount': '200'},
              {'kind': 'mesada'},
            ],
          }),
        );
        expect(draft.sources.keys, [IncomeKind.sueldo, IncomeKind.mesada]);
        expect(draft.sources[IncomeKind.sueldo]!.amount, '100');
        expect(_read(_valid({'sources': 'x'})).sources, isEmpty);
        // Como mapa (forma de la web) tampoco se acepta: solo lista.
        expect(
          _read(
            _valid({
              'sources': {
                'sueldo': {'kind': 'sueldo'},
              },
            }),
          ).sources,
          isEmpty,
        );
      },
    );

    test('payDays: quita basura, fuera de 1..31 y repetidos; máximo 4 y ordenados', () {
      final form = _read(
        _valid({
          'sources': [
            {
              'kind': 'sueldo',
              'payDays': [30, 'x', 30, 40, 0, null, 15, 1, 2, 3],
            },
          ],
        }),
      ).sources[IncomeKind.sueldo]!;
      expect(form.payDays, [1, 2, 15, 30]);
      expect(form.payDays.length, lessThanOrEqualTo(maxPayDays));
      final notList = _read(
        _valid({
          'sources': [
            {'kind': 'sueldo', 'payDays': '15'},
          ],
        }),
      );
      expect(notList.sources[IncomeKind.sueldo]!.payDays, isEmpty);
    });

    test('lastMonths cortos o con números se completan a 3 textos', () {
      IncomeSourceForm proyectos(Object? months) => _read(
        _valid({
          'sources': [
            {'kind': 'proyectos', 'lastMonths': months},
          ],
        }),
      ).sources[IncomeKind.proyectos]!;
      expect(proyectos(['100']).lastMonths, ['100', '', '']);
      expect(proyectos([1, '2']).lastMonths, ['', '2', '']);
      expect(proyectos(['1', '2', '3', '4']).lastMonths, ['1', '2', '3']);
      expect(proyectos(null).lastMonths, ['', '', '']);
    });

    test('workDays y frequency fuera de las opciones vuelven a los iniciales', () {
      final draft = _read(
        _valid({
          'sources': [
            {'kind': 'diario', 'workDays': '9'},
            {'kind': 'mesada', 'frequency': 'anual'},
            {'kind': 'sueldo', 'amount': 5},
          ],
        }),
      );
      expect(draft.sources[IncomeKind.diario]!.workDays, '6');
      expect(draft.sources[IncomeKind.mesada]!.frequency, 'mensual');
      expect(draft.sources[IncomeKind.sueldo]!.amount, '');
    });

    test('items sin key o con key vacía se descartan; nombre a 60, día solo dígitos, máximo 30', () {
      final draft = _read(
        _valid({
          'items': [
            {'name': 'Sin clave'},
            {'key': '', 'name': 'Clave vacía'},
            {'key': 7, 'name': 'Clave numérica'},
            'basura',
            {'key': 'a', 'name': 'x' * 70, 'amount': 5, 'dayOfMonth': '1a5', 'custom': 'true'},
          ],
        }),
      );
      expect(draft.items, hasLength(1));
      final item = draft.items.single;
      expect(item.key, 'a');
      expect(item.name, 'x' * commitmentNameMax);
      expect(item.amount, '');
      expect(item.dayOfMonth, '15');
      expect(item.custom, isFalse);

      final many = _read(
        _valid({
          'items': [
            for (var i = 0; i < 35; i++) {'key': 'k$i', 'name': 'Pago $i'},
          ],
        }),
      );
      expect(many.items, hasLength(maxCommitments));
      expect(_read(_valid({'items': 'x'})).items, isEmpty);
    });

    test('saldo no numérico o que no es texto → vacío; "12." y "" se conservan', () {
      expect(_read(_valid({'balance': 'abc'})).balance, '');
      expect(_read(_valid({'balance': 5000})).balance, '');
      expect(_read(_valid({'balance': '12.'})).balance, '12.');
      expect(_read(_valid({'balance': '250000'})).balance, '250000');
      expect(_read(_valid({'balance': ''})).balance, '');
    });

    test('saldo con signo, notación científica o NaN tampoco es un crudo válido', () {
      // El crudo de MoneyInput es "solo dígitos y punto decimal opcional" (money_text.dart:3).
      for (final bad in ['-5', '1e3', 'NaN', 'Infinity']) {
        expect(_read(_valid({'balance': bad})).balance, '', reason: bad);
      }
    });

    test('languagePicked solo con true; sentWelcome solo si es texto', () {
      expect(_read(_valid({'languagePicked': 'true'})).languagePicked, isFalse);
      expect(_read(_valid({'languagePicked': true})).languagePicked, isTrue);
      expect(_read(_valid({'sentWelcome': 3})).sentWelcome, isNull);
    });
  });

  group('MemoryDraftStore', () {
    test('separado por usuario: leer, escribir y borrar no se mezclan', () async {
      final store = MemoryDraftStore();
      await store.write('ana', _valid({'balance': '100'}));
      await store.write('luis', _valid({'balance': '200'}));

      expect((await store.read('ana') as Map)['balance'], '100');
      expect((await store.read('luis') as Map)['balance'], '200');
      expect(await store.read('otra'), isNull);

      await store.clear('ana');
      expect(await store.read('ana'), isNull);
      expect((await store.read('luis') as Map)['balance'], '200');
      expect(store.writes, 2);
    });
  });
}
