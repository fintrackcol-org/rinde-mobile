import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/features/account/application/account_writer.dart';
import 'package:rinde_mobile/features/account/data/account_models.dart';
import 'package:rinde_mobile/features/account/data/account_repository.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/auth/data/auth_repository.dart';
import 'package:rinde_mobile/features/cards/data/demo_cards_store.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_store.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';

const _ana = Session(
  user: AuthUser(id: 'ana', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _FakeAuth implements AuthRepository {
  final deleted = <String>[];
  Object? deleteError;
  Object? meError;
  int meCalls = 0;

  @override
  Future<void> deleteAccount(String password) async {
    deleted.add(password);
    if (deleteError case final e?) throw e;
  }

  @override
  Future<UserProfile> me() async {
    meCalls++;
    if (meError case final e?) throw e;
    return const UserProfile(
      id: 'ana',
      email: 'ana@rinde.co',
      termsAccepted: true,
      country: 'CO',
      currency: 'COP',
      language: 'es',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeAccount implements AccountRepository {
  final sent = <ReminderSettings>[];
  Object? deleteCategoryError;

  @override
  bool get isDemo => false;

  @override
  Future<ReminderSettings> reminderSettings() async =>
      const ReminderSettings(times: ['08:00', '20:00'], timezone: 'America/Bogota', cardReminders: true);

  @override
  Future<ReminderSettings> saveReminderSettings(ReminderSettings settings) async {
    sent.add(settings);
    return settings;
  }

  @override
  Future<int> deleteCategory(String key) async {
    if (deleteCategoryError case final e?) throw e;
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeAuth auth;
  late MemorySessionStorage storage;
  late MemoryJsonListStore pending;
  late MemoryDraftStore drafts;
  late MemoryTourSeenStore tours;
  late MemoryDemoStateStore demoState;

  Future<ProviderContainer> container(Session session, {List<Object> extra = const []}) async {
    auth = _FakeAuth();
    storage = MemorySessionStorage(session);
    pending = MemoryJsonListStore();
    drafts = MemoryDraftStore();
    tours = MemoryTourSeenStore();
    demoState = MemoryDemoStateStore();
    final c = ProviderContainer.test(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
        ),
        sessionStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(auth),
        pendingStoreProvider.overrideWithValue(pending),
        draftStoreProvider.overrideWithValue(drafts),
        tourSeenStoreProvider.overrideWithValue(tours),
        demoStateStoreProvider.overrideWithValue(demoState),
        demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        demoCardsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        demoDebtsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        ...extra.cast(),
      ],
    );
    c.listen(sessionControllerProvider, (_, _) {});
    await c.read(sessionControllerProvider.future);
    return c;
  }

  /// Lo que la cuenta [userId] dejó en el teléfono, más lo de otra cuenta que no se debe tocar.
  Future<void> seed(String userId) async {
    for (final id in [userId, 'beto']) {
      await pending.write(id, [
        {'localId': 'p-$id'},
      ]);
      await drafts.write(id, {'step': 'balance'});
      await tours.write(id);
    }
  }

  group('eliminar la cuenta', () {
    test('llama a DELETE /users/me con la contraseña, sale y no deja nada de la cuenta', () async {
      final c = await container(_ana);
      await seed('ana');

      await c.read(accountWriterProvider).deleteAccount('secreta-123');

      expect(auth.deleted, ['secreta-123']);
      final state = c.read(sessionControllerProvider).value!;
      expect(state.signedIn, isFalse);
      expect(state.deleted, isTrue);
      expect(await storage.read(), isNull);
      expect(c.read(sessionHolderProvider).current, isNull);
      // Ni la cola sin conexión, ni el borrador, ni la marca del tutorial: ni siquiera la llave.
      expect(pending.data.containsKey('ana'), isFalse);
      expect(drafts.data.containsKey('ana'), isFalse);
      expect(tours.seen.contains('ana'), isFalse);
      // Lo de otra cuenta en el mismo teléfono sigue.
      expect(pending.data.containsKey('beto'), isTrue);
      expect(drafts.data.containsKey('beto'), isTrue);
      expect(tours.seen.contains('beto'), isTrue);
      // La contraseña no queda en ningún almacén.
      expect('${pending.data}${drafts.data}', isNot(contains('secreta-123')));
    });

    test('contraseña equivocada (403): el error llega a la hoja y nada se borra', () async {
      final c = await container(_ana);
      await seed('ana');
      auth.deleteError = const ApiException(
        code: 'CONFIRMATION_FAILED',
        serverMessage: 'La contraseña no coincide',
        status: 403,
      );

      await expectLater(
        c.read(accountWriterProvider).deleteAccount('mala'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      expect(c.read(sessionControllerProvider).value!.signedIn, isTrue);
      expect(pending.data.containsKey('ana'), isTrue);
      expect(auth.meCalls, 0);
    });

    test('en duda y la cuenta ya no existe (401 al leer el perfil): cuenta como eliminada', () async {
      final c = await container(_ana);
      await seed('ana');
      auth
        ..deleteError = const ApiException(code: ApiCodes.timeout)
        ..meError = const ApiException(code: ApiCodes.unauthorized, status: 401);

      await c.read(accountWriterProvider).deleteAccount('secreta-123');

      expect(c.read(sessionControllerProvider).value!.deleted, isTrue);
      expect(pending.data.containsKey('ana'), isFalse);
    });

    test('en duda y la cuenta sigue: el error llega a la hoja y nada se borra', () async {
      final c = await container(_ana);
      await seed('ana');
      auth.deleteError = const ApiException(code: 'INTERNAL_ERROR', status: 500);

      await expectLater(
        c.read(accountWriterProvider).deleteAccount('secreta-123'),
        throwsA(isA<ApiException>()),
      );
      expect(auth.meCalls, 1);
      expect(c.read(sessionControllerProvider).value!.signedIn, isTrue);
      expect(drafts.data.containsKey('ana'), isTrue);
    });

    test('un segundo toque no manda un segundo DELETE', () async {
      final c = await container(_ana);
      final writer = c.read(accountWriterProvider);
      await Future.wait([writer.deleteAccount('x'), writer.deleteAccount('x')]);
      expect(auth.deleted, hasLength(1));
    });

    test('en la demostración solo la reinicia y sale, sin servidor', () async {
      final demo = Session.demo('planListo');
      final c = await container(demo);
      final id = demo.user.id;
      await demoState.write(
        id,
        const DemoState(
          region: Region(country: 'MX', currency: 'MXN', language: 'es'),
        ),
      );
      await seed(id);

      await c.read(accountWriterProvider).deleteAccount('cualquiera');

      expect(auth.deleted, isEmpty);
      final state = c.read(sessionControllerProvider).value!;
      expect(state.signedIn, isFalse);
      // No es una cuenta real: el login no dice que se eliminó.
      expect(state.deleted, isFalse);
      expect((await demoState.read(id)).region, isNull);
      expect(drafts.data.containsKey(id), isFalse);
      expect(tours.seen.contains(id), isFalse);
      expect(pending.data.containsKey(id), isFalse);
    });
  });

  test('«Pago de tarjetas» cambia solo el aviso y conserva las horas y la zona guardadas', () async {
    final account = _FakeAccount();
    final c = await container(_ana, extra: [accountRepositoryProvider.overrideWithValue(account)]);

    await c.read(accountWriterProvider).setCardReminders(false);

    expect(account.sent.single.toJson(), {
      'times': ['08:00', '20:00'],
      'timezone': 'America/Bogota',
      'cardReminders': false,
    });
  });

  test('borrar una categoría que ya no está (404) cuenta como hecho', () async {
    final account = _FakeAccount()..deleteCategoryError = const ApiException(code: 'NOT_FOUND', status: 404);
    final c = await container(_ana, extra: [accountRepositoryProvider.overrideWithValue(account)]);

    expect(await c.read(accountWriterProvider).deleteCategory('cat-1'), 0);
  });

  group('demostración', () {
    test('en un escenario fijo las escrituras dan demoNoBackend', () async {
      final c = await container(Session.demo('planListo'));
      await expectLater(
        c.read(accountWriterProvider).setCardReminders(false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.demoNoBackend)),
      );
    });

    test('en un recorrido se guardan, y el idioma cambia la región sin guardarla en el teléfono', () async {
      final c = await container(Session.demo('nuevo'));
      final writer = c.read(accountWriterProvider);

      expect((await writer.setCardReminders(false)).cardReminders, isFalse);
      final region = await writer.saveLanguage('en');

      expect(region.language, 'en');
      expect(c.read(appRegionProvider).language, 'en');
    });
  });
}
