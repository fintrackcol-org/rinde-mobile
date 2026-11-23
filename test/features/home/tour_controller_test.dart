import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

import '../../support/fake_home_repository.dart';

const _real = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);
final _demo = Session.demo('nueva');

WelcomeStatus _status({bool welcomeDone = true, bool tutorialDone = false}) =>
    WelcomeStatus(welcomeDone: welcomeDone, tutorialDone: tutorialDone, hasTransactions: false);

void main() {
  late FakeHomeRepository repo;
  late MemoryTourSeenStore seen;
  late int statusLoads;

  /// Contenedor con la sesión ya cargada y la respuesta de GET /money-profile ya recibida.
  Future<ProviderContainer> container(
    Session? session, {
    Future<WelcomeStatus> Function()? status,
    bool settle = true,
  }) async {
    repo = FakeHomeRepository();
    seen = MemoryTourSeenStore();
    statusLoads = 0;
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(session)),
        // Sin modo demostración, una sesión demo guardada se descarta al abrir.
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
        ),
        homeRepositoryProvider.overrideWithValue(repo),
        tourSeenStoreProvider.overrideWithValue(seen),
        welcomeStatusProvider.overrideWith((ref, _) {
          statusLoads++;
          return (status ?? () async => _status())();
        }),
      ],
    );
    c.listen(sessionControllerProvider, (_, _) {});
    c.listen(tourControllerProvider, (_, _) {});
    await c.read(sessionControllerProvider.future);
    c.listen(welcomeStatusProvider(c.read(accountProvider)), (_, _) {});
    if (settle) await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
    return c;
  }

  TourController tour(ProviderContainer c) => c.read(tourControllerProvider.notifier);

  group('se abre solo', () {
    test('en la demostración, después de la bienvenida y sin haberlo visto', () async {
      final c = await container(_demo);
      expect(c.read(tourControllerProvider), isFalse);

      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isTrue);
      // Abrirlo no le cuenta nada al servidor ni lo da por visto.
      expect(repo.calls, isEmpty);
      expect(seen.seen, isEmpty);
    });

    test('en una cuenta real está apagado: ni se abre ni se marca en el servidor', () async {
      expect(kCoachTourForRealAccounts, isFalse);
      final c = await container(_real);
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);

      // Tampoco el aviso callado de «ya se vio aquí».
      seen.seen.add('u1');
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('no antes de terminar la bienvenida', () async {
      final c = await container(_demo, status: () async => _status(welcomeDone: false));
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('no si el servidor ya lo tiene como visto', () async {
      final c = await container(_demo, status: () async => _status(tutorialDone: true));
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('no mientras el estado de la bienvenida carga, ni si falló, ni sin sesión', () async {
      var c = await container(_demo, status: () => Future.delayed(const Duration(days: 1)), settle: false);
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);

      c = await container(
        _demo,
        status: () async => throw const ApiException(code: 'NETWORK'),
        settle: false,
      );
      await expectLater(c.read(welcomeStatusProvider(c.read(accountProvider)).future), throwsA(anything));
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);

      c = await container(null);
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('visto en este dispositivo: no se abre y se le cuenta al servidor, una sola vez', () async {
      final c = await container(_demo);
      seen.seen.add(_demo.user.id);

      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(repo.count('finishTutorial'), 1);
      // Guardado: el estado de la bienvenida se vuelve a pedir.
      await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
      expect(statusLoads, 2);

      await tour(c).maybeStart();
      expect(repo.count('finishTutorial'), 1);
    });

    test('visto por otra cuenta en este dispositivo: a esta sí se le muestra', () async {
      final c = await container(_demo);
      seen.seen.add('demo-otra');
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isTrue);
    });

    test('si el aviso callado falla, no se nota', () async {
      final c = await container(_demo);
      seen.seen.add(_demo.user.id);
      repo.onFinishTutorial = () async => throw const ApiException(code: 'NETWORK');

      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
      expect(statusLoads, 1);
    });
  });

  group('cerrar', () {
    test('lo marca visto para esta cuenta y lo guarda en el servidor una vez', () async {
      final c = await container(_demo);
      await tour(c).maybeStart();

      await tour(c).close();
      expect(c.read(tourControllerProvider), isFalse);
      expect(seen.seen, {_demo.user.id});
      expect(repo.calls, ['finishTutorial']);
      await c.read(welcomeStatusProvider(c.read(accountProvider)).future);
      expect(statusLoads, 2);

      // Cerrar de nuevo (dos toques seguidos) no repite nada.
      await tour(c).close();
      expect(repo.calls, ['finishTutorial']);
      // Y ya no vuelve a abrirse solo.
      await tour(c).maybeStart();
      expect(c.read(tourControllerProvider), isFalse);
    });

    test('se cierra de inmediato, sin esperar al servidor', () async {
      final c = await container(_demo);
      await tour(c).maybeStart();
      repo.onFinishTutorial = () => Future.delayed(const Duration(days: 1));

      final closing = tour(c).close();
      expect(c.read(tourControllerProvider), isFalse);
      closing.ignore();
    });

    test('si guardar falla se calla: queda la marca local y el estado no se vuelve a pedir', () async {
      final c = await container(_demo);
      await tour(c).maybeStart();
      repo.onFinishTutorial = () async => throw const ApiException(code: 'NETWORK');

      await tour(c).close();
      expect(c.read(tourControllerProvider), isFalse);
      expect(seen.seen, {_demo.user.id});
      expect(repo.count('finishTutorial'), 1);
      expect(statusLoads, 1);
    });

    test('si el servidor ya lo tenía como visto no se vuelve a guardar', () async {
      final c = await container(_real, status: () async => _status(tutorialDone: true));
      tour(c).open();
      await tour(c).close();
      expect(seen.seen, {'u1'});
      expect(repo.calls, isEmpty);
    });
  });

  group('a pedido', () {
    test('se abre aunque ya se haya visto, también en una cuenta real', () async {
      final c = await container(_real, status: () async => _status(tutorialDone: true));
      seen.seen.add('u1');
      tour(c).open();
      expect(c.read(tourControllerProvider), isTrue);
    });

    test('al salir de la cuenta se cierra sin marcar nada', () async {
      final c = await container(_demo);
      tour(c).open();
      await c.read(sessionControllerProvider.notifier).signOut();
      expect(c.read(tourControllerProvider), isFalse);
      expect(seen.seen, isEmpty);
      expect(repo.calls, isEmpty);
    });
  });
}
