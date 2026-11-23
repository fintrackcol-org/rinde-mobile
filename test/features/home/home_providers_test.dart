import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/home/domain/home_view.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/fake_home_repository.dart';
import '../../support/home_fixtures.dart';

const _ana = Session(
  user: AuthUser(id: 'ana', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'beto', email: 'beto@rinde.co', name: 'Beto'),
  accessToken: 'b',
  refreshToken: 'r',
);

/// Sesión ya leída, que se puede cambiar por la de otra cuenta sin pasar por el login.
class _Session extends SessionController {
  @override
  Future<SessionState> build() async => const SessionState(session: _ana);

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

/// Solo responde `status()`, a la medida, y cuenta las veces que se lo piden.
class _Onboarding implements OnboardingRepository {
  Future<WelcomeStatus> Function() onStatus = () async => statusOf();
  int statusCalls = 0;

  @override
  bool get isDemo => false;

  @override
  Future<WelcomeStatus> status() {
    statusCalls++;
    return onStatus();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Llavero en memoria; con [broken] falla como un llavero bloqueado.
class _Keychain implements FlutterSecureStorage {
  final values = <String, String?>{};
  bool broken = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (broken) throw PlatformException(code: 'llavero');
    final key = invocation.namedArguments[#key] as String;
    if (invocation.memberName == #read) return Future<String?>.value(values[key]);
    if (invocation.memberName == #write) {
      values[key] = invocation.namedArguments[#value] as String?;
      return Future<void>.value();
    }
    throw UnimplementedError('${invocation.memberName}');
  }
}

UserProfile _profileOf(Session? account) => UserProfile(
  id: account?.user.id ?? '-',
  email: account?.user.email ?? 'ana@rinde.co',
  termsAccepted: true,
  country: 'CO',
  currency: 'COP',
  language: 'es',
);

class _Home {
  _Home({DateTime Function()? clock}) {
    container = ProviderContainer(
      // Como en main.dart: un fallo se muestra, no se reintenta solo.
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Session.new),
        profileProvider.overrideWith((ref, account) => _profileOf(account)),
        homeRepositoryProvider.overrideWithValue(repo),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        clockProvider.overrideWithValue(clock ?? () => DateTime(2026, 11, 21, 10)),
      ],
    );
  }

  final repo = FakeHomeRepository();
  final onboarding = _Onboarding();
  late final ProviderContainer container;

  /// Deja la sesión leída y el Inicio escuchado, como con la pantalla abierta.
  Future<void> open() async {
    await container.read(sessionControllerProvider.future);
    container.listen(homeViewProvider, (_, _) {});
    await settle();
  }

  /// Espera a que cada bloque responda, bien o mal.
  Future<void> settle() {
    final id = container.read(accountProvider);
    Future<void> done<T>(FutureProviderFamily<T, Session?> provider) =>
        container.read(provider(id).future).then<void>((_) {}, onError: (_) {});
    return Future.wait([
      done(welcomeStatusProvider),
      done(homePlanProvider),
      done(homeTotalsProvider),
      done(homeBudgetsProvider),
      done(homeCardsProvider),
      done(homeToConfirmProvider),
    ]);
  }

  void enter(Session session) =>
      (container.read(sessionControllerProvider.notifier) as _Session).enter(session);

  HomeView get view => container.read(homeViewProvider);
}

Never _offline() => throw offlineError;
Never _down() => throw serverError;

void main() {
  late _Home home;

  setUp(() => home = _Home());
  tearDown(() => home.container.dispose());

  group('blockOf', () {
    test('primera carga, valor y fallo', () {
      final loading = blockOf(const AsyncLoading<int>());
      expect((loading.loading, loading.value, loading.error), (true, null, null));

      final data = blockOf(const AsyncData(7));
      expect((data.loading, data.value, data.error), (false, 7, null));

      final failed = blockOf(const AsyncError<int>(offlineError, StackTrace.empty));
      expect((failed.loading, failed.value, failed.error, failed.offline), (false, null, offlineError, true));
    });

    test('al recargar la misma cuenta conserva el valor: las cifras no parpadean', () async {
      await home.open();
      final next = Completer<MoneyPlan>();
      home.repo.onPlan = () => next.future;
      home.container.invalidate(homePlanProvider);

      final during = blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider))));
      expect((during.loading, during.value?.free, during.error), (true, 139300, null));

      next.complete(planOf(free: 50000));
      await home.settle();
      final after = blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider))));
      expect((after.loading, after.value?.free, after.error), (false, 50000, null));
    });

    test('si la recarga falla, queda el último valor de ESTA cuenta junto al error', () async {
      await home.open();
      home.repo.onPlan = () async => _offline();
      home.container.invalidate(homePlanProvider);
      await home.settle();

      final stale = blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider))));
      expect((stale.loading, stale.value?.free, stale.offline), (false, 139300, true));

      // Y al reintentar con éxito el error se limpia.
      home.repo.onPlan = () async => planOf(free: 1);
      home.container.invalidate(homePlanProvider);
      await home.settle();
      final fresh = blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider))));
      expect((fresh.value?.free, fresh.failed), (1, false));
    });

    test('al cambiar de cuenta descarta el valor anterior: era de OTRA persona', () async {
      await home.open();
      final next = Completer<MoneyPlan>();
      home.repo.onPlan = () => next.future;
      home.enter(_beto);

      // Cada cuenta tiene su copia: la de Beto nace sin nada de Ana.
      final raw = home.container.read(homePlanProvider(home.container.read(accountProvider)));
      expect((raw.isLoading, raw.value), (true, null));
      final during = blockOf(raw);
      expect((during.loading, during.value, during.error), (true, null, null));

      next.complete(planOf(free: 777));
      await home.settle();
      expect(
        blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider)))).value?.free,
        777,
      );
      expect(home.repo.count('plan'), 2);
    });

    // Regresión: un proveedor único conservaba el valor de la otra cuenta también en el AsyncError.
    test('al cambiar de cuenta, si la carga de la nueva falla, el valor de la anterior NO vuelve', () async {
      await home.open();
      home.repo.onPlan = () async => _offline();
      home.repo.onTotals = (_) async => _offline();
      home.onboarding.onStatus = () async => _offline();
      home.enter(_beto);
      await home.settle();

      for (final block in <Block<Object>>[
        blockOf(home.container.read(welcomeStatusProvider(home.container.read(accountProvider)))),
        blockOf(home.container.read(homePlanProvider(home.container.read(accountProvider)))),
        blockOf(home.container.read(homeTotalsProvider(home.container.read(accountProvider)))),
      ]) {
        expect((block.value, block.offline), (null, true));
      }
    });
  });

  group('homeViewProvider', () {
    test('mientras nada ha llegado: un esqueleto, ninguna cifra', () async {
      await home.container.read(sessionControllerProvider.future);
      final pending = Completer<WelcomeStatus>();
      home.onboarding.onStatus = () => pending.future;
      expect(home.view.hero, isA<HeroLoading>());
      expect((home.view.empty, home.view.offline, home.view.loadError), (false, false, false));
      pending.complete(statusOf());
    });

    test('arma la vista con lo que mandó el servidor', () async {
      home.repo.onToConfirm = () async => 3;
      home.repo.onCards = () async => [cardOf(-1)];
      await home.open();

      final view = home.view;
      expect((view.hero as HeroPlan).plan.free, 139300);
      expect(view.nextPayments.map((p) => p.name), ['PILA', 'Plan celular']);
      expect((view.totals.value!.month, view.totals.value!.expense), ('2026-11', 287700));
      expect(view.toConfirm, 3);
      expect(view.notice!.card!.daysToPayment, -1);
      expect((view.offline, view.loadError, view.empty), (false, false, false));
    });

    test('si «por confirmar» falla, la fila no sale y no es un error del Inicio', () async {
      home.repo.onToConfirm = () async => _down();
      await home.open();
      expect(home.view.toConfirm, 0);
      expect(home.view.loadError, isFalse);
    });

    // Regresión: salía «Mi plata» con el saldo de la otra cuenta.
    test('al cambiar de cuenta sin conexión no se ve ninguna cifra de la cuenta anterior', () async {
      await home.open();
      expect(home.view.hero, isA<HeroPlan>());

      home.repo
        ..onPlan = (() async => _offline())
        ..onTotals = ((_) async => _offline())
        ..onCards = (() async => _offline())
        ..onBudgets = (() async => _offline());
      home.onboarding.onStatus = () async => _offline();
      home.enter(_beto);
      await home.settle();

      final view = home.view;
      expect(view.hero, isA<HeroUnknown>().having((h) => h.reason, 'reason', UnknownReason.offline));
      expect(view.totals.value, isNull);
      expect(view.nextPayments, isEmpty);
      expect((view.offline, view.empty, view.balanceSet), (true, false, false));
    });

    test(
      'los nombres de las categorías se vuelven a pedir al cambiar de idioma (los traduce el servidor)',
      () async {
        await home.open();
        home.container.listen(homeCategoryNamesProvider(home.container.read(accountProvider)), (_, _) {});
        await home.container.read(homeCategoryNamesProvider(home.container.read(accountProvider)).future);
        expect(home.repo.count('categoryNames'), 1);

        home.container.read(displayLanguageProvider.notifier).preview('en');
        await home.container.read(homeCategoryNamesProvider(home.container.read(accountProvider)).future);
        expect(home.repo.count('categoryNames'), 2);
        // Lo demás no depende del idioma.
        expect(home.repo.count('plan'), 1);
      },
    );
  });

  group('hoy', () {
    test('es la fecha local del dispositivo, sin hora', () {
      final late = _Home(clock: () => DateTime(2026, 11, 30, 23, 30));
      addTearDown(late.container.dispose);
      expect(late.container.read(todayProvider), DateTime(2026, 11, 30));
    });

    test('el resumen y los presupuestos se piden con el día y el mes locales, también de noche', () async {
      // En UTC una de las dos horas ya es otro día (y otro mes), sea cual sea la zona de la máquina.
      for (final (now, date, month) in [
        (DateTime(2026, 11, 30, 23, 30), '2026-11-30', '2026-11'),
        (DateTime(2026, 12, 1, 0, 30), '2026-12-01', '2026-12'),
      ]) {
        final h = _Home(clock: () => now);
        addTearDown(h.container.dispose);
        await h.open();
        expect(h.repo.calls, containsAll(['monthTotals $date', 'budgets $month']));
        expect(h.repo.count('monthTotals'), 1);
      }
    });

    test('sync: si ya es otro día, cambia y lo que depende de hoy se vuelve a pedir', () async {
      var now = DateTime(2026, 11, 30, 22);
      final h = _Home(clock: () => now);
      addTearDown(h.container.dispose);
      await h.open();
      expect(h.view.totals.value!.month, '2026-11');

      now = DateTime(2026, 12, 1, 7);
      h.container.read(todayProvider.notifier).sync();
      expect(h.container.read(todayProvider), DateTime(2026, 12, 1));
      // Antes de que llegue el resumen de diciembre, el de noviembre no se muestra como «este mes».
      expect(h.view.totals.value, isNull);

      await h.settle();
      expect(h.repo.calls, containsAll(['monthTotals 2026-12-01', 'budgets 2026-12']));
      expect(h.view.totals.value!.month, '2026-12');
      // El plan lo calcula el servidor para «hoy»: el de ayer ya no vale.
      expect(h.repo.count('plan'), 2);
    });

    test('sync el mismo día no vuelve a pedir nada', () async {
      var now = DateTime(2026, 11, 21, 10);
      final h = _Home(clock: () => now);
      addTearDown(h.container.dispose);
      await h.open();
      final before = [...h.repo.calls];

      now = DateTime(2026, 11, 21, 23, 59, 59);
      h.container.read(todayProvider.notifier).sync();
      await h.settle();
      expect(h.container.read(todayProvider), DateTime(2026, 11, 21));
      expect(h.repo.calls, before);
    });

    testWidgets('a medianoche cambia solo, con la app abierta', (tester) async {
      var now = DateTime(2026, 11, 30, 23, 59, 30);
      final h = _Home(clock: () => now);
      final days = <DateTime>[];
      h.container.listen(todayProvider, (_, next) => days.add(next), fireImmediately: true);
      expect(days, [DateTime(2026, 11, 30)]);

      await tester.pump(const Duration(seconds: 20));
      expect(h.container.read(todayProvider), DateTime(2026, 11, 30));

      now = DateTime(2026, 12, 1, 0, 0, 1);
      await tester.pump(const Duration(seconds: 11));
      expect(h.container.read(todayProvider), DateTime(2026, 12, 1));
      await tester.pump();
      expect(days, [DateTime(2026, 11, 30), DateTime(2026, 12, 1)]);
      // Cancela el temporizador de la medianoche siguiente.
      h.container.dispose();
    });
  });

  group('refreshHome', () {
    /// Monta un widget que mira todo el Inicio y entrega su `WidgetRef`.
    Future<WidgetRef> mount(WidgetTester tester, _Home h) async {
      late WidgetRef ref;
      // Con la sesión ya leída, para que los bloques se pidan una sola vez.
      await h.container.read(sessionControllerProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: Consumer(
            builder: (context, r, _) {
              ref = r;
              r.watch(homeViewProvider);
              r.watch(homeUnreadProvider(r.read(accountProvider)));
              r.watch(homeCategoryNamesProvider(r.read(accountProvider)));
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return ref;
    }

    Map<String, int> counts(_Home h) => {
      for (final call in ['plan', 'monthTotals', 'budgets', 'cards', 'toConfirm', 'unread', 'categoryNames'])
        call: h.repo.count(call),
      'status': h.onboarding.statusCalls,
    };

    Future<bool> refresh(WidgetTester tester, WidgetRef ref) async {
      var done = false;
      unawaited(refreshHome(ref).then((_) => done = true));
      for (var i = 0; i < 5 && !done; i++) {
        await tester.pump();
      }
      return done;
    }

    testWidgets('vuelve a pedir TODO el Inicio una vez', (tester) async {
      final h = _Home();
      final ref = await mount(tester, h);
      expect(counts(h).values, everyElement(1));

      h.repo.onPlan = () async => planOf(free: 50000);
      expect(await refresh(tester, ref), isTrue);
      expect(counts(h).values, everyElement(2));
      expect((h.view.hero as HeroPlan).plan.free, 50000);
      h.container.dispose();
    });

    testWidgets('termina aunque todos los bloques fallen, y cada uno queda con su estado', (tester) async {
      final h = _Home();
      final ref = await mount(tester, h);

      h.repo
        ..onPlan = (() async => _offline())
        ..onTotals = ((_) async => _offline())
        ..onBudgets = (() async => _offline())
        ..onCards = (() async => _offline())
        ..onToConfirm = (() async => _offline())
        ..onUnread = (() async => _offline())
        ..onCategoryNames = (() async => _offline());
      h.onboarding.onStatus = () async => _offline();

      expect(await refresh(tester, ref), isTrue);
      expect(counts(h).values, everyElement(2));
      expect((h.view.offline, h.view.loadError), (true, false));
      // El plan que falló no se muestra como vigente; queda el último saldo que sí llegó.
      expect((h.view.hero as HeroMoney).money, 412300);
      expect(h.view.nextPayments, isEmpty);
      expect(tester.takeException(), isNull);
      h.container.dispose();
    });

    testWidgets('si solo falla un bloque, los demás traen lo nuevo', (tester) async {
      final h = _Home();
      final ref = await mount(tester, h);

      h.repo
        ..onPlan = (() async => _down())
        ..onTotals = ((date) async => totalsOf(month: date.substring(0, 7), expense: 1));
      expect(await refresh(tester, ref), isTrue);
      expect((h.view.offline, h.view.loadError), (false, true));
      expect(h.view.totals.value!.expense, 1);
      h.container.dispose();
    });

    testWidgets('si ya es otro día, pide el mes nuevo', (tester) async {
      var now = DateTime(2026, 11, 30, 22);
      final h = _Home(clock: () => now);
      final ref = await mount(tester, h);

      now = DateTime(2026, 12, 1, 7);
      final before = h.repo.calls.length;
      expect(await refresh(tester, ref), isTrue);
      expect(h.container.read(todayProvider), DateTime(2026, 12, 1));
      final after = h.repo.calls.skip(before);
      expect(after, containsAll(['monthTotals 2026-12-01', 'budgets 2026-12']));
      expect(after.where((call) => call.contains('2026-11')), isEmpty);
      expect(h.view.totals.value!.month, '2026-12');
      h.container.dispose();
    });
  });

  test('invalidateHome marca los ocho bloques para volver a pedirse', () async {
    await home.open();
    final id = home.container.read(accountProvider);
    home.container
      ..listen(homeUnreadProvider(id), (_, _) {})
      ..listen(homeCategoryNamesProvider(id), (_, _) {});
    await home.container.read(homeUnreadProvider(home.container.read(accountProvider)).future);
    await home.container.read(homeCategoryNamesProvider(home.container.read(accountProvider)).future);

    invalidateHome(home.container.invalidate);
    await home.settle();
    await home.container.read(homeUnreadProvider(home.container.read(accountProvider)).future);
    await home.container.read(homeCategoryNamesProvider(home.container.read(accountProvider)).future);

    for (final call in ['plan', 'monthTotals', 'budgets', 'cards', 'toConfirm', 'unread', 'categoryNames']) {
      expect(home.repo.count(call), 2, reason: call);
    }
    expect(home.onboarding.statusCalls, 2);
  });

  test('tourRequested: se pide desde «Yo» y el Inicio lo apaga al abrirlo', () {
    final c = home.container;
    expect(c.read(tourRequestedProvider), isFalse);
    c.read(tourRequestedProvider.notifier).request();
    expect(c.read(tourRequestedProvider), isTrue);
    c.read(tourRequestedProvider.notifier).clear();
    expect(c.read(tourRequestedProvider), isFalse);
  });

  group('ocultar montos', () {
    late _Keychain keychain;
    late HiddenAmountsStore store;

    setUp(() {
      keychain = _Keychain();
      store = HiddenAmountsStore(keychain);
    });

    ProviderContainer app({required bool initial}) {
      final c = ProviderContainer(
        overrides: [
          hiddenAmountsStoreProvider.overrideWithValue(store),
          initialHiddenAmountsProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('sin nada guardado los montos se ven', () async {
      expect(await store.read(), isFalse);
      expect(home.container.read(hiddenAmountsProvider), isFalse);
    });

    test('arranca con lo que se leyó antes de dibujar', () {
      expect(app(initial: true).read(hiddenAmountsProvider), isTrue);
      expect(app(initial: false).read(hiddenAmountsProvider), isFalse);
    });

    test('al cambiar se guarda, y al reabrir la app sigue igual', () async {
      final first = app(initial: await store.read());
      first.read(hiddenAmountsProvider.notifier).toggle();
      expect(first.read(hiddenAmountsProvider), isTrue);
      await pumpEventQueue();
      expect(keychain.values.values, ['1']);

      final reopened = app(initial: await store.read());
      expect(reopened.read(hiddenAmountsProvider), isTrue);

      reopened.read(hiddenAmountsProvider.notifier).toggle();
      expect(reopened.read(hiddenAmountsProvider), isFalse);
      await pumpEventQueue();
      expect(keychain.values.values, ['0']);
      expect(await store.read(), isFalse);
    });

    test('si no se puede leer lo guardado arranca oculto: mejor tapar de más', () async {
      await store.write(false);
      keychain.broken = true;
      expect(await store.read(), isTrue);
    });

    test('si no se puede guardar, igual cambia en pantalla y no lanza', () async {
      keychain.broken = true;
      final c = app(initial: false);
      c.read(hiddenAmountsProvider.notifier).toggle();
      expect(c.read(hiddenAmountsProvider), isTrue);
      await pumpEventQueue();
      await expectLater(store.write(true), completes);
    });
  });
}
