// Mi plata, bloque 4B: qué cifra va arriba (buildMyMoneyView) y el primer pago que no alcanza
// (firstUncovered), como MiPlataMobile.jsx y MiPlataMobile.test.jsx de Rinde Web. Funciones puras.
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/home/domain/runway.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/domain/commitment_rules.dart';
import 'package:rinde_mobile/features/money/domain/money_view.dart';

import '../../support/home_fixtures.dart';

final _today = DateTime(2026, 11, 22);

MoneyProfile _profile({num? money = 400000, List<Commitment> commitments = const []}) =>
    MoneyProfile(welcomeDone: true, money: money, balance: money, commitments: commitments);

MyMoneyView _view({Block<MoneyProfile>? profile, Block<MoneyPlan>? plan, Block<MonthTotals>? totals}) =>
    buildMyMoneyView(
      profile: profile ?? Block.data(_profile()),
      plan: plan ?? const Block.data(MoneyPlan.notReady()),
      totals: totals ?? Block.data(totalsOf()),
      today: _today,
    );

num? _money(MyMoneyView v) => switch (v.left) {
  MoneyLeftValue(:final money) => money,
  _ => null,
};

Commitment _c(String name, int day, {String frequency = 'monthly', int? month, num amount = 65000}) =>
    Commitment(id: name, name: name, amount: amount, dayOfMonth: day, frequency: frequency, month: month);

void main() {
  group('buildMyMoneyView', () {
    test('plan listo y vigente: la plata del plan, no la del perfil', () {
      final v = _view(plan: Block.data(planOf(money: 412300)));
      expect(_money(v), 412300);
      expect(v.negative, isFalse);
      expect(v.loadError, isFalse);
    });

    test('sin plan: la plata del perfil', () {
      expect(_money(_view()), 400000);
    });

    test('el plan falló o no hay conexión: se oculta y se usa la del perfil, sin aviso de error', () {
      for (final error in [offlineError, serverError]) {
        final v = _view(
          plan: Block(value: planOf(money: 999999), error: error),
        );
        expect(_money(v), 400000, reason: '$error');
        expect(v.loadError, isFalse);
      }
    });

    test('plata desconocida (null): «no sabemos», nunca 0', () {
      final v = _view(profile: Block.data(_profile(money: null)));
      expect(v.left, isA<MoneyLeftUnknown>().having((l) => l.reason, 'razón', UnknownReason.noBalance));
      expect(_money(v), isNull);
      expect(v.warn, isNull);
    });

    test('sin perfil: sin conexión o error, con «Reintentar»; si llegó el plan, su cifra', () {
      final offline = _view(profile: const Block.failed(offlineError));
      expect(offline.left, isA<MoneyLeftUnknown>().having((l) => l.reason, 'razón', UnknownReason.offline));
      expect(offline.loadError, isTrue);
      final error = _view(profile: const Block.failed(serverError));
      expect(error.left, isA<MoneyLeftUnknown>().having((l) => l.reason, 'razón', UnknownReason.error));
      final withPlan = _view(profile: const Block.failed(serverError), plan: Block.data(planOf()));
      expect(_money(withPlan), 412300);
      expect(withPlan.loadError, isTrue);
    });

    test('perfil viejo sin plata tras un refresco fallido: no dice «no sabemos», dice que falló', () {
      final v = _view(
        profile: Block(value: _profile(money: null), error: offlineError),
      );
      expect(v.left, isA<MoneyLeftUnknown>().having((l) => l.reason, 'razón', UnknownReason.offline));
    });

    test('cargando: mientras llegan el perfil o el plan, sin cifra', () {
      expect(_view(profile: const Block.loading()).left, isA<MoneyLeftLoading>());
      expect(_view(plan: const Block.loading()).left, isA<MoneyLeftLoading>());
    });

    test('negativa: la cifra con su signo', () {
      final v = _view(plan: Block.data(planOf(money: -35000)));
      expect(_money(v), -35000);
      expect(v.negative, isTrue);
    });

    test('datos viejos: el perfil o los gastos del mes no se pudieron actualizar', () {
      expect(
        _view(
          profile: Block(value: _profile(), error: offlineError),
        ).stale,
        isTrue,
      );
      expect(
        _view(
          totals: Block(value: totalsOf(), error: serverError),
        ).stale,
        isTrue,
      );
      expect(_view().stale, isFalse);
    });

    test('alcance y ritmo: salen de la plata y lo gastado en el mes', () {
      final v = _view(plan: Block.data(planOf(money: 412300)));
      final r = (v.left as MoneyLeftValue).runway!;
      // 412.300 × 22 ÷ 287.700 = 31,5 días: pasa del 30.
      expect((r.days, r.lasts, r.pace), (31, true, 13077));
      expect(v.totals?.income, 700000);
    });

    test('sin los gastos del mes (o de otro mes) no hay alcance ni línea, y la cifra sigue', () {
      for (final totals in [
        const Block<MonthTotals>.failed(serverError),
        Block.data(totalsOf(month: '2026-10')),
      ]) {
        final v = _view(totals: totals);
        expect(_money(v), 400000);
        expect((v.left as MoneyLeftValue).runway, isNull);
        expect(v.totals, isNull);
      }
    });

    test('«Ojo con el…»: el primer pago fijo que vence después de que se acaba la plata', () {
      final v = _view(
        profile: Block.data(_profile(money: 50000, commitments: [_c('Arriendo', 5), _c('Internet', 28)])),
      );
      // 50.000 × 22 ÷ 287.700 = 3,8: alcanza hasta el 25.
      expect((v.left as MoneyLeftValue).runway!.until, DateTime(2026, 11, 25));
      expect(v.warn?.name, 'Internet');
    });
  });

  group('firstUncovered', () {
    Runway until(int day) =>
        Runway(days: day - 22, until: DateTime(2026, 11, day), coverage: 0.5, lasts: false, pace: 1000);

    test('null si alcanza todo el mes o no hay ritmo', () {
      final lasts = Runway(days: 40, until: DateTime(2026, 11, 30), coverage: 1, lasts: true, pace: 1);
      expect(firstUncovered([_c('Internet', 28)], lasts, _today), isNull);
      expect(firstUncovered([_c('Internet', 28)], null, _today), isNull);
    });

    test('el más próximo después del día en que se acaba; no los que ya pasaron ni los cubiertos', () {
      final all = [_c('Gimnasio', 29), _c('Arriendo', 5), _c('Celular', 24), _c('Internet', 27)];
      expect(firstUncovered(all, until(25), _today)?.name, 'Internet');
      expect(firstUncovered(all, until(29), _today), isNull);
    });

    test('a igual día gana el primero de la lista (el orden del servidor)', () {
      expect(firstUncovered([_c('Luz', 28), _c('Agua', 28)], until(25), _today)?.name, 'Luz');
    });

    test('los anuales solo cuentan en su mes', () {
      final yearly = [
        _c('Seguro', 27, frequency: 'yearly', month: 3),
        _c('Dominio', 28, frequency: 'yearly', month: 11),
      ];
      expect(firstUncovered(yearly, until(25), _today)?.name, 'Dominio');
      expect(commitmentsOfMonth(yearly, _today).map((c) => c.name), ['Dominio']);
    });
  });
}
