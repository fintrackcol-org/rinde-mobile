// Corregir saldo (bloque 4B): la escritura de PUT /money-profile con sus salvaguardas (versión,
// comprobación previa, en duda, un envío a la vez, bienvenida a medias) y la pantalla con todos sus
// estados: solo lectura sin versión, validación del campo, errores, navegación y letra al doble.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/design/widgets/rinde_feedback.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/application/money_writer.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/domain/money_view.dart';
import 'package:rinde_mobile/features/money/presentation/fix_balance_screen.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';
import '../../support/home_fixtures.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'acceso',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co'),
  accessToken: 'acceso-b',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  _Sessions([this.first = _ana]);
  final Session first;

  @override
  Future<SessionState> build() => SynchronousFuture(SessionState(session: first));

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

const _at = '2026-11-01T12:00:00.000Z';

/// GET /money-profile con la forma de money-profile.service.js; `version` solo si se pide.
Map<String, dynamic> _json({
  num? balance = 400000,
  String? balanceAt = _at,
  num? money = 380000,
  String? incomeType = 'fecha_fija',
  List<int> payDays = const [15, 30],
  int? version = 7,
}) => {
  'incomeType': incomeType,
  'payDays': payDays,
  'balance': balance,
  'balanceAt': balanceAt,
  'money': money,
  'totals': {'income': 900000, 'expense': 520000},
  'welcomeDone': true,
  'tutorialDone': true,
  'commitments': const <Object>[],
  'subscriptions': {'count': 0, 'monthly': 0},
  'version': ?version,
};

MoneyProfile _profile({num? money = 380000, int? version = 7, String? balanceAt = _at}) =>
    MoneyProfile.fromJson(_json(money: money, version: version, balanceAt: balanceAt));

Never _timeout(RequestOptions options) =>
    throw DioException.receiveTimeout(timeout: const Duration(seconds: 45), requestOptions: options);

final _cop = formatFor(kDefaultRegion);
String _m(num value) => _cop.money(value);

const _readOnly =
    'Por ahora corrige tu saldo en la web de Rinde, con tu misma cuenta. En la app llega pronto.';
const _conflict = 'Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.';
const _doubt = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

/// Las traducciones que lleva la app (assets/l10n).
Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

void main() {
  late FakeHomeRepository home;
  late SessionHolder holder;

  setUp(() async {
    home = FakeHomeRepository();
    holder = SessionHolder(MemorySessionStorage(_ana));
    await holder.load();
  });

  tearDown(() => holder.dispose());

  group('MoneyWriter.saveBalance (PUT /money-profile)', () {
    Future<ProviderContainer> open(MoneyRepository repo, {DraftStore? drafts, Session session = _ana}) async {
      final c = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          sessionControllerProvider.overrideWith(() => _Sessions(session)),
          moneyRepositoryProvider.overrideWithValue(repo),
          homeRepositoryProvider.overrideWithValue(home),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
          draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
        ],
      );
      await c.read(sessionControllerProvider.future);
      return c;
    }

    Future<(ProviderContainer, FakeHttpAdapter)> openApi(
      FakeHandler handler, {
      Session session = _ana,
    }) async {
      final adapter = FakeHttpAdapter(handler);
      final c = await open(
        ApiMoneyRepository(ApiClient(config: _qa, session: holder, adapter: adapter)),
        session: session,
      );
      return (c, adapter);
    }

    List<String> sent(FakeHttpAdapter adapter) => [for (final r in adapter.requests) '${r.method} ${r.path}'];

    test('lee antes, manda los tres campos de lo recién leído, resetBalance y expectedVersion', () async {
      final (c, adapter) = await openApi((o) => jsonBody(200, _json()));
      await c.read(moneyWriterProvider).saveBalance(_profile(), 500000.5);
      expect(sent(adapter), ['GET /money-profile', 'PUT /money-profile']);
      expect(adapter.requests.last.data, {
        'incomeType': 'fecha_fija',
        'payDays': [15, 30],
        'balance': 500000.5,
        'resetBalance': true,
        'expectedVersion': 7,
      });
    });

    test('sin versión (demostración) no manda expectedVersion; sin fecha fija, días vacíos', () async {
      final (c, adapter) = await openApi(
        (o) => jsonBody(200, _json(incomeType: 'sin_fecha', payDays: const [], version: null)),
        session: Session.demo('nuevo'),
      );
      await c
          .read(moneyWriterProvider)
          .saveBalance(
            MoneyProfile.fromJson(_json(incomeType: 'sin_fecha', payDays: const [], version: null)),
            0,
          );
      expect(adapter.requests.last.data, {
        'incomeType': 'sin_fecha',
        'payDays': <int>[],
        'balance': 0,
        'resetBalance': true,
      });
    });

    test('cuenta real sin versión: no se escribe nada, ni se lee', () async {
      final (c, adapter) = await openApi((o) => jsonBody(200, _json(version: null)));
      await expectLater(
        c.read(moneyWriterProvider).saveBalance(_profile(version: null), 500000),
        throwsA(isA<StateError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('comprobación previa: si cambió algo desde que se abrió, no hay PUT y avisa', () async {
      for (final (name, now) in [
        ('balanceAt', _json(balanceAt: '2026-11-21T09:00:00.000Z')),
        ('saldo', _json(balance: 410000)),
        ('tipo', _json(incomeType: 'sin_fecha', payDays: const [])),
        ('días', _json(payDays: const [30])),
        ('versión', _json(version: 8)),
      ]) {
        final (c, adapter) = await openApi((o) => jsonBody(200, now));
        await expectLater(
          c.read(moneyWriterProvider).saveBalance(_profile(), 500000),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', ApiCodes.profileChanged)
                .having((e) => e.serverMessage, 'mensaje', _conflict),
          ),
          reason: name,
        );
        expect(sent(adapter), ['GET /money-profile'], reason: name);
      }
    });

    test(
      'la comprobación previa sin conexión o vencida: su error tal cual (no salió nada), sin PUT',
      () async {
        for (final (handler, code) in <(FakeHandler, String)>[
          (networkFailure, ApiCodes.network),
          (_timeout, ApiCodes.timeout),
        ]) {
          final (c, adapter) = await openApi(handler);
          await expectLater(
            c.read(moneyWriterProvider).saveBalance(_profile(), 500000),
            throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
          );
          expect(sent(adapter), ['GET /money-profile']);
        }
      },
    );

    test('en duda (se venció la espera): verifica leyendo y, si quedó, no repite el PUT', () async {
      var reads = 0;
      final (c, adapter) = await openApi((o) {
        if (o.method == 'PUT') return _timeout(o);
        reads++;
        return jsonBody(
          200,
          reads == 1 ? _json() : _json(balance: 500000, balanceAt: '2026-11-22T15:00:00.000Z', version: 8),
        );
      });
      await c.read(moneyWriterProvider).saveBalance(_profile(), 500000);
      expect(sent(adapter), ['GET /money-profile', 'PUT /money-profile', 'GET /money-profile']);
    });

    test('en duda y lo leído no es lo enviado: el error del envío, un solo PUT', () async {
      final (c, adapter) = await openApi(
        (o) => o.method == 'PUT'
            ? errorBody(500, 'INTERNAL_ERROR', 'Error interno del servidor')
            : jsonBody(200, _json()),
      );
      await expectLater(
        c.read(moneyWriterProvider).saveBalance(_profile(), 500000),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiCodes.unconfirmed)
              .having((e) => e.status, 'status', 500)
              .having((e) => e.serverMessage, 'mensaje', _doubt),
        ),
      );
      expect(adapter.to('/money-profile').where((r) => r.method == 'PUT'), hasLength(1));
    });

    test('dos toques mientras va el primero: un solo PUT', () async {
      final answer = Completer<void>();
      final (c, adapter) = await openApi((o) async {
        if (o.method == 'PUT') await answer.future;
        return jsonBody(200, _json());
      });
      final writer = c.read(moneyWriterProvider);
      final first = writer.saveBalance(_profile(), 500000);
      final second = writer.saveBalance(_profile(), 500000);
      await pumpEventQueue();
      answer.complete();
      await Future.wait([first, second]);
      expect(adapter.requests.where((r) => r.method == 'PUT'), hasLength(1));
    });

    test('con una bienvenida a medias en este dispositivo no se lee ni se envía nada', () async {
      final drafts = MemoryDraftStore();
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      final repo = FakeMoneyRepository()..onProfile = () async => _profile();
      final c = await open(repo, drafts: drafts);
      await expectLater(
        c.read(moneyWriterProvider).saveBalance(_profile(), 500000),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending)),
      );
      expect((repo.count('profile'), repo.count('saveProfile')), (0, 0));
    });

    test('un 409 PROFILE_CHANGED del servidor (con versión): se vuelve a leer y llega el error', () async {
      final repo = FakeMoneyRepository()
        ..onSaveProfile = (_) async => throw const ApiException(
          code: ApiCodes.profileChanged,
          status: 409,
          serverMessage: 'Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.',
        );
      repo.onProfile = () async => _profile();
      final c = await open(repo);
      final account = c.read(accountProvider);
      c.listen(moneyProfileProvider(account), (_, _) {});
      await c.read(moneyProfileProvider(account).future);
      await expectLater(
        c.read(moneyWriterProvider).saveBalance(_profile(), 500000),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.profileChanged)),
      );
      await pumpEventQueue();
      // La carga, la comprobación previa y la relectura.
      expect(repo.count('profile'), 3);
    });

    test(
      'después de guardar: el plan del Inicio se recarga sin mostrar la cifra vieja, y los ajustes',
      () async {
        final repo = FakeMoneyRepository()..onProfile = () async => _profile();
        final c = await open(repo);
        final account = c.read(accountProvider);
        c.listen(homePlanProvider(account), (_, _) {});
        c.listen(balanceAdjustmentsProvider((account, '2026-11-01', '2026-11-30')), (_, _) {});
        await c.read(homePlanProvider(account).future);
        await c.read(balanceAdjustmentsProvider((account, '2026-11-01', '2026-11-30')).future);

        await c.read(moneyWriterProvider).saveBalance(_profile(), 500000);
        // asReload: el valor viejo ya no se presenta como vigente.
        expect(c.read(homePlanProvider(account)).isReloading, isTrue);
        expect(blockOf(c.read(homePlanProvider(account))).value, isNull);
        await pumpEventQueue();
        expect((home.count('plan'), repo.count('adjustments')), (2, 2));
      },
    );

    test('aislamiento: la cuenta que entra no ve la plata de la que salió', () async {
      final repo = FakeMoneyRepository()..onProfile = () async => _profile(money: 380000);
      final c = await open(repo);
      c.listen(myMoneyViewProvider, (_, _) {});
      await c.read(moneyProfileProvider(c.read(accountProvider)).future);
      await c.read(homePlanProvider(c.read(accountProvider)).future);

      repo.onProfile = () => Completer<MoneyProfile>().future;
      home.onPlan = () => Completer<MoneyPlan>().future;
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      await pumpEventQueue();
      final beto = c.read(moneyProfileProvider(_beto));
      expect((beto.isLoading, beto.value), (true, null));
      expect(c.read(myMoneyViewProvider).left, isA<MoneyLeftLoading>());
    });

    test('otra cuenta entra mientras se lee: no sale ningún PUT, ni a la una ni a la otra', () async {
      final gate = Completer<MoneyProfile>();
      final ana = FakeMoneyRepository()..onProfile = () => gate.future;
      final beto = FakeMoneyRepository()..onProfile = () async => _profile(version: null);
      final c = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          sessionControllerProvider.overrideWith(() => _Sessions(_ana)),
          moneyRepositoryProvider.overrideWith((ref) => ref.watch(accountProvider) == _ana ? ana : beto),
          homeRepositoryProvider.overrideWithValue(home),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        ],
      );
      await c.read(sessionControllerProvider.future);
      final save = c.read(moneyWriterProvider).saveBalance(_profile(), 500000);
      await pumpEventQueue();
      expect(ana.count('profile'), 1);
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      await pumpEventQueue();
      gate.complete(_profile());
      await expectLater(save, throwsA(isA<StateError>()));
      expect((ana.count('saveProfile'), beto.count('saveProfile')), (0, 0));
    });
  });

  group('balanceProblem', () {
    const t = Tr('es', {});
    test('vacío pide el monto; 0 y decimales valen; más del tope no', () {
      expect(balanceProblem('', t, _cop), 'Escribe cuánta plata tienes.');
      expect(balanceProblem('0', t, _cop), isNull);
      expect(balanceProblem('1500.5', t, _cop), isNull);
      expect(balanceProblem('9999999999.99', t, _cop), isNull);
      expect(balanceProblem('10000000000', t, _cop), startsWith('Supera el máximo permitido'));
    });
  });

  group('la pantalla', () {
    late FakeMoneyRepository repo;

    setUp(() {
      repo = FakeMoneyRepository()..onProfile = () async => _profile();
    });

    Future<GoRouter> pump(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      double textScale = 1,
      ThemeData? theme,
      bool hidden = false,
      Session session = _ana,
      DraftStore? drafts,
      Region region = kDefaultRegion,
      // Lo que se abre encima del Inicio, en orden.
      List<String> open = const [Routes.fixBalance],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: Routes.app,
        routes: [
          GoRoute(
            path: Routes.app,
            builder: (_, _) => const Scaffold(body: Text('INICIO')),
          ),
          GoRoute(path: Routes.myMoney, builder: (_, _) => const MyMoneyScreen()),
          GoRoute(path: Routes.fixBalance, builder: (_, _) => const FixBalanceScreen()),
          GoRoute(
            path: Routes.expenses,
            builder: (_, _) => const Scaffold(body: Text('GASTOS')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          retry: (_, _) => null,
          overrides: [
            sessionControllerProvider.overrideWith(() => _Sessions(session)),
            moneyRepositoryProvider.overrideWithValue(repo),
            homeRepositoryProvider.overrideWithValue(home),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
            initialHiddenAmountsProvider.overrideWithValue(hidden),
            draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
            initialRegionProvider.overrideWithValue(region),
            translationsProvider.overrideWithValue(_translations()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme ?? RindeTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final location in open) {
        unawaited(router.push(location));
        await tester.pumpAndSettle();
      }
      return router;
    }

    Future<void> tap(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    final field = find.byType(TextField);
    String fieldText(WidgetTester tester) => tester.widget<TextField>(field).controller!.text;

    testWidgets('cuenta real sin versión: la plata de hoy, el aviso y nada para guardar', (tester) async {
      repo.onProfile = () async => _profile(version: null);
      await pump(tester);
      expect(find.text('Corregir saldo'), findsOneWidget);
      expect(find.text('¿Cuánta plata tienes?'), findsOneWidget);
      expect(find.text(_m(380000)), findsOneWidget);
      expect(find.text(_readOnly), findsOneWidget);
      expect(field, findsNothing);
      expect(find.text('Guardar saldo'), findsNothing);
      expect(find.text('Usar lo que dicen mis movimientos'), findsNothing);
      expect(repo.count('saveProfile'), 0);
    });

    testWidgets('solo lectura y sin plata conocida: «—» y por qué, nunca un cero', (tester) async {
      repo.onProfile = () async => _profile(money: null, version: null);
      await pump(tester);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Todavía no sabemos cuánta plata tienes.'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('solo lectura con montos ocultos: ningún dígito', (tester) async {
      final handle = tester.ensureSemantics();
      repo.onProfile = () async => _profile(version: null);
      await pump(tester, hidden: true);
      expect(find.textContaining('380'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Monto oculto')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('con versión: el campo trae la plata de hoy y «Guardar saldo» la manda', (tester) async {
      await pump(tester);
      expect(fieldText(tester), '380.000');
      expect(find.text(_readOnly), findsNothing);
      await tap(tester, find.text('Guardar saldo'));
      expect(repo.sentProfiles.single, {
        'incomeType': 'fecha_fija',
        'payDays': [15, 30],
        'balance': 380000,
        'resetBalance': true,
        'expectedVersion': 7,
      });
    });

    testWidgets('plata negativa: el campo arranca vacío', (tester) async {
      repo.onProfile = () async => _profile(money: -35000);
      await pump(tester);
      expect(fieldText(tester), '');
    });

    testWidgets('vacío: «Guardar saldo» no se apaga; lleva al campo y dice qué falta, sin PUT', (
      tester,
    ) async {
      repo.onProfile = () async => _profile(money: null);
      await pump(tester);
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text('Escribe cuánta plata tienes.'), findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(repo.count('saveProfile'), 0);
    });

    testWidgets('el 0, los decimales y el tope de 10 cifras', (tester) async {
      for (final (typed, balance) in [('0', 0), ('1500,5', 1500.5), ('99999999999', 9999999999)]) {
        repo.sentProfiles.clear();
        await pump(tester);
        await tester.enterText(field, typed);
        await tester.pumpAndSettle();
        await tap(tester, find.text('Guardar saldo'));
        expect(repo.sentProfiles.single['balance'], balance, reason: typed);
      }
    });

    testWidgets('al guardar va a Mi plata reemplazando la pantalla: atrás no vuelve a Corregir', (
      tester,
    ) async {
      final router = await pump(tester);
      await tester.enterText(field, '500000');
      await tap(tester, find.text('Guardar saldo'));
      expect(find.byType(FixBalanceScreen), findsNothing);
      expect(find.byType(MyMoneyScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('abierta desde Mi plata, al guardar vuelve a ella: no quedan dos y atrás va al Inicio', (
      tester,
    ) async {
      final router = await pump(tester, open: const [Routes.myMoney, Routes.fixBalance]);
      await tester.enterText(field, '500000');
      await tap(tester, find.text('Guardar saldo'));
      expect(find.byType(FixBalanceScreen), findsNothing);
      expect(find.byType(MyMoneyScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('se lee al abrir: con Mi plata ya cargada, el campo trae la plata de ahora', (tester) async {
      final router = await pump(tester, open: const [Routes.myMoney]);
      final reads = repo.count('profile');
      // Un gasto anotado (aquí, en la web o por el bot) bajó la plata; el saldo y su fecha no cambian.
      repo.onProfile = () async => _profile(money: 330000);
      unawaited(router.push(Routes.fixBalance));
      await tester.pumpAndSettle();
      expect(repo.count('profile'), reads + 1);
      expect(fieldText(tester), '330.000');
      await tap(tester, find.text('Guardar saldo'));
      expect(repo.sentProfiles.single['balance'], 330000);
    });

    testWidgets('«Usar lo que dicen mis movimientos»: solo si dicen otra cosa, y guarda esa cifra', (
      tester,
    ) async {
      home.onPlan = () async => MoneyPlan(
        money: 380000,
        pendingTotal: 0,
        free: 380000,
        shortfall: 0,
        mode: 'runway',
        ledger: 405000.5,
      );
      await pump(tester);
      await tap(tester, find.text('Usar lo que dicen mis movimientos'));
      expect(repo.sentProfiles.single['balance'], 405000.5);

      for (final plan in [
        const MoneyPlan.notReady(),
        const MoneyPlan(
          money: 380000,
          pendingTotal: 0,
          free: 0,
          shortfall: 0,
          mode: 'runway',
          ledger: 380000.2,
        ),
        const MoneyPlan(money: 380000, pendingTotal: 0, free: 0, shortfall: 0, mode: 'runway', ledger: -1000),
      ]) {
        home.onPlan = () async => plan;
        await pump(tester);
        expect(find.text('Usar lo que dicen mis movimientos'), findsNothing, reason: '${plan.ledger}');
      }
    });

    testWidgets('la plata cambió en otro lado: no se manda, lo dice y el campo trae lo releído', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(field, '500000');
      repo.onProfile = () async => _profile(money: 250000, balanceAt: '2026-11-22T08:00:00.000Z');
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text(_conflict), findsOneWidget);
      expect(repo.count('saveProfile'), 0);
      expect(fieldText(tester), '250.000');
      expect(find.byType(FixBalanceScreen), findsOneWidget);

      // Revisado, el siguiente intento compara con lo releído y sí sale.
      await tap(tester, find.text('Guardar saldo'));
      expect(repo.sentProfiles.single['balance'], 250000);
    });

    testWidgets('en duda sin confirmar: lo dice sin repetir, con lo releído a la vista', (tester) async {
      repo.onSaveProfile = (_) async => throw const ApiException(code: ApiCodes.timeout);
      await pump(tester);
      await tester.enterText(field, '500000');
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text(_doubt), findsOneWidget);
      expect(repo.count('saveProfile'), 1);
      expect(fieldText(tester), '380.000');
    });

    testWidgets('en duda y la relectura también falla: la duda sigue a la vista junto a «Reintentar»', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(field, '500000');
      // Desde el envío se cae la conexión: ni la verificación ni la recarga pueden leer.
      repo.onSaveProfile = (_) async {
        repo.onProfile = () async => throw offlineError;
        throw const ApiException(code: ApiCodes.timeout);
      };
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text(_doubt), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(repo.count('saveProfile'), 1);
    });

    testWidgets('un 422 del saldo se marca en el campo; sin conexión, el mensaje de siempre', (tester) async {
      repo.onSaveProfile = (_) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        fields: {'balance': 'Debe ser un número desde 0'},
      );
      await pump(tester);
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text('Debe ser un número desde 0'), findsOneWidget);

      repo.onSaveProfile = (_) async => throw offlineError;
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.byType(FixBalanceScreen), findsOneWidget);
    });

    testWidgets('con una bienvenida a medias: lo dice y no envía', (tester) async {
      final drafts = MemoryDraftStore();
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      await pump(tester, drafts: drafts);
      // De entrada, el aviso con «Terminar» (bloque 4D) y nada que invite a guardar: sin teclado y
      // «Guardar saldo» apagado, así el mismo mensaje no sale dos veces.
      expect(find.widgetWithText(RindeBanner, 'Terminar'), findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(tester.widget<RindeButton>(find.widgetWithText(RindeButton, 'Guardar saldo')).onPressed, isNull);
      await tester.enterText(field, '500000');
      await tap(tester, find.text('Guardar saldo'));
      expect(find.text('Primero terminemos de guardar tu bienvenida.'), findsOneWidget);
      expect(repo.count('saveProfile'), 0);
    });

    testWidgets('si no carga: el error y «Reintentar» lo vuelve a pedir', (tester) async {
      var fail = true;
      repo.onProfile = () async {
        if (fail) throw serverError;
        return _profile();
      };
      await pump(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(field, findsNothing);
      fail = false;
      await tap(tester, find.text('Reintentar'));
      expect(fieldText(tester), '380.000');
    });

    for (final (region, shown, title, question, save, readOnly) in const [
      (
        Region(country: 'US', currency: 'USD', language: 'en'),
        '380,000',
        'Fix balance',
        'How much money do you have?',
        'Save balance',
        "For now, fix your balance on the Rinde website, with the same account. It's coming to the app soon.",
      ),
      (
        Region(country: 'BR', currency: 'BRL', language: 'pt'),
        '380.000',
        'Corrigir saldo',
        'Quanto dinheiro você tem?',
        'Salvar saldo',
        'Por enquanto, corrija seu saldo no site do Rinde, com a mesma conta. Em breve chega ao app.',
      ),
    ]) {
      testWidgets('en ${region.language} con ${region.currency}: sus textos y la plata en su formato', (
        tester,
      ) async {
        await pump(tester, region: region);
        expect(find.text(title), findsOneWidget);
        expect(find.text(question), findsOneWidget);
        expect(find.text(save), findsOneWidget);
        expect(fieldText(tester), shown);

        repo.onProfile = () async => _profile(version: null);
        await pump(tester, region: region);
        expect(find.text(formatFor(region).money(380000)), findsOneWidget);
        expect(find.text(readOnly), findsOneWidget);
      });
    }

    for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
      testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
        home.onPlan = () async => const MoneyPlan(
          money: 0,
          pendingTotal: 0,
          free: 0,
          shortfall: 0,
          mode: 'runway',
          ledger: 9999999998,
        );
        repo.onProfile = () async => _profile(money: 9999999999);
        await pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(find.text('Usar lo que dicen mis movimientos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Guardar saldo'));
        expect(tester.takeException(), isNull);

        repo.onProfile = () async => _profile(money: 9999999999, version: null);
        await pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(find.text(_readOnly), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
