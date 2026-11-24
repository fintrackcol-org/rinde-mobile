// Metas y Vacas (etapa 10): contrato de /vacas con el ApiClient real contra un adaptador falso, el aporte
// sin duplicados (dos toques, duda, borrador distinto), refrescos de Movimientos y Mi plata, bienvenida
// a medias, aislamiento por cuenta, y las pantallas a 320 de ancho con la letra al doble.
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
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';
import 'package:rinde_mobile/features/vacas/application/vacas_providers.dart';
import 'package:rinde_mobile/features/vacas/application/vacas_writer.dart';
import 'package:rinde_mobile/features/vacas/data/vaca_models.dart';
import 'package:rinde_mobile/features/vacas/data/vacas_repository.dart';
import 'package:rinde_mobile/features/vacas/presentation/vaca_detail_screen.dart';
import 'package:rinde_mobile/features/vacas/presentation/vacas_screens.dart';
import 'package:rinde_mobile/features/vacas/presentation/widgets/contribution_sheet.dart';
import 'package:rinde_mobile/features/vacas/presentation/widgets/vaca_widgets.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/home_money.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart' show CategoryLists;

import '../../support/fake_home_repository.dart';
import '../../support/fake_http.dart';
import '../../support/fake_money_repository.dart';
import '../../support/fake_movements_repository.dart';

const _qa = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa');
const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co'),
  accessToken: 'acceso',
  refreshToken: 'r',
);
const _beto = Session(
  user: AuthUser(id: 'b', email: 'beto@rinde.co'),
  accessToken: 'acceso-b',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _ana));

  void enter(Session session) => state = AsyncData(SessionState(session: session));
}

const _id = '0b6a9c1e-5d0e-4f61-9a43-1f0c2e6b8d11';
const _path = '/vacas/$_id';

/// La forma de GET /vacas/:id (buildDetail de vacas.service.js).
Map<String, dynamic> _vaca({bool personal = false, bool admin = true, num total = 650000, String? name}) => {
  'id': _id,
  'name': name ?? (personal ? 'Moto' : 'Paseo de fin de año'),
  'description': personal ? null : 'Hotel y transporte',
  'goal': personal ? 3000000 : 1200000,
  'deadline': '2027-01-02',
  'split': 'igual',
  'code': personal ? null : 'K7M2QX',
  'personal': personal,
  'role': admin ? 'admin' : 'miembro',
  'total': total,
  'percentage': 54.2,
  'status': 'activa',
  'membersCount': personal ? 1 : 3,
  'myQuota': 400000,
  'myContributed': 250000,
  'myRemaining': 150000,
  'myStatus': 'al_dia',
  'projection': {
    'remaining': 550000,
    'averagePerDay': 30952,
    'estimatedDate': '2026-12-11',
    'daysLeft': 40,
    'neededPerDay': 13750,
    'neededPerWeek': 96250,
    'onTrack': true,
  },
  'members': [
    {
      'userId': 'a',
      'name': 'Ana',
      'isMe': true,
      'role': 'admin',
      'quota': 400000,
      'customQuota': null,
      'contributed': 250000,
      'remaining': 150000,
      'percentage': 62.5,
      'status': 'al_dia',
    },
    if (!personal)
      {
        'userId': 'c',
        'name': 'Laura Valentina de los Ríos',
        'isMe': false,
        'role': 'miembro',
        'quota': 400000,
        'customQuota': null,
        'contributed': 0,
        'remaining': 400000,
        'percentage': 0,
        'status': 'atrasado',
      },
  ],
  'contributions': [
    {
      'id': 'c1',
      'userId': 'a',
      'name': 'Ana',
      'isMe': true,
      'amount': 250000,
      'note': 'Mi parte',
      'date': '2026-11-20',
      'createdAt': '2026-11-20T10:00:00Z',
    },
  ],
  if (admin) 'invitations': const <Object>[],
  'updatedAt': '2026-11-23T10:00:00Z',
};

Map<String, dynamic> _contributed(num amount) => {
  'contribution': {
    'id': 'c2',
    'amount': amount,
    'note': null,
    'date': '2026-11-23',
    'isMe': true,
    'name': 'Ana',
  },
  'transaction': {'id': 'tx'},
  'vaca': _vaca(),
};

/// La lectura del borrador (bienvenida pendiente) espera hasta que se abra [gate].
class _SlowDrafts extends MemoryDraftStore {
  final gate = Completer<void>();

  @override
  Future<Object?> read(String userId) async {
    await gate.future;
    return super.read(userId);
  }
}

Never _timeout(RequestOptions options) =>
    throw DioException.receiveTimeout(timeout: const Duration(seconds: 45), requestOptions: options);

void main() {
  late SessionHolder holder;
  late FakeHomeRepository home;
  late FakeMoneyRepository money;
  late FakeMovementsRepository movements;

  setUp(() async {
    holder = SessionHolder(MemorySessionStorage(_ana));
    await holder.load();
    home = FakeHomeRepository();
    money = FakeMoneyRepository();
    movements = FakeMovementsRepository();
  });

  tearDown(() => holder.dispose());

  Future<(ProviderContainer, FakeHttpAdapter)> open(FakeHandler handler, {DraftStore? drafts}) async {
    final adapter = FakeHttpAdapter(handler);
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        sessionControllerProvider.overrideWith(_Sessions.new),
        vacasRepositoryProvider.overrideWithValue(
          ApiVacasRepository(ApiClient(config: _qa, session: holder, adapter: adapter)),
        ),
        moneyRepositoryProvider.overrideWithValue(money),
        homeRepositoryProvider.overrideWithValue(home),
        movementsRepositoryProvider.overrideWithValue(movements),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
      ],
    );
    await c.read(sessionControllerProvider.future);
    return (c, adapter);
  }

  List<RequestOptions> posts(FakeHttpAdapter a) => a.requests.where((r) => r.method == 'POST').toList();
  final body = {'amount': 100000, 'date': '2026-11-23', 'note': null, 'category': 'ahorro_inversion'};

  group('contrato', () {
    test('GET /vacas y /vacas/:id con los modelos; una vaca ilegible falla la lista', () async {
      final (c, _) = await open(
        (o) => o.path == '/vacas' ? jsonBody(200, [_vaca(personal: true), _vaca()]) : jsonBody(200, _vaca()),
      );
      final account = c.read(accountProvider);
      final list = await c.read(vacasProvider(account).future);
      expect([for (final v in list) v.personal], [true, false]);
      final detail = await c.read(vacaDetailProvider((account, _id)).future);
      expect((detail.admin, detail.members.length, detail.contributions.single.note), (true, 2, 'Mi parte'));

      final (bad, _) = await open((o) => jsonBody(200, [_vaca()..remove('projection')]));
      await expectLater(
        bad.read(vacasProvider(bad.read(accountProvider)).future),
        throwsA(isA<ContractException>()),
      );
    });

    test('aportar: POST con monto, fecha, categoría y localId; devuelve lo registrado', () async {
      final (c, adapter) = await open((o) => jsonBody(201, _contributed(100000)));
      expect(await c.read(vacasWriterProvider).contribute(_id, body, localId: 'm-1'), 100000);
      final post = posts(adapter).single;
      expect(post.path, '$_path/contributions');
      expect({...post.data as Map}..remove('localId'), body);
      expect((post.data as Map)['localId'], 'm-1');
    });

    test('unirse, sacar, salir, invitar y pasar a Metas usan los endpoints de la web', () async {
      final (c, adapter) = await open(
        (o) => switch ((o.method, o.path)) {
          ('POST', '/vacas/join') => jsonBody(201, _vaca()),
          ('POST', '$_path/invitations') => jsonBody(201, {'email': 'x@y.co', 'sent': false}),
          ('POST', '$_path/personal') => jsonBody(200, _vaca(personal: true)),
          ('DELETE', _) => errorBody(404, 'NOT_FOUND', 'Miembro no encontrado'),
          _ => jsonBody(200, _vaca()),
        },
      );
      final writer = c.read(vacasWriterProvider);
      await writer.join('K7M2QX');
      // Un 404 al sacar a alguien es que ya no estaba: cuenta como hecho.
      await writer.removeMember(_id, 'c');
      await writer.leave(_id);
      expect(await writer.invite(_id, 'x@y.co'), isFalse);
      expect((await writer.makePersonal(_id)).personal, isTrue);
      expect(
        [for (final r in adapter.requests) '${r.method} ${r.path}'],
        [
          'POST /vacas/join',
          'DELETE $_path/members/c',
          'DELETE $_path/members/a',
          'POST $_path/invitations',
          'POST $_path/personal',
        ],
      );
      expect(posts(adapter).first.data, {'code': 'K7M2QX'});
    });
  });

  group('el aporte no se duplica', () {
    test('dos toques en «Aportar»: un solo POST y los dos reciben el monto', () async {
      final answer = Completer<void>();
      final (c, adapter) = await open((o) async {
        await answer.future;
        return jsonBody(201, _contributed(100000));
      });
      final writer = c.read(vacasWriterProvider);
      final first = writer.contribute(_id, body, localId: 'm-1');
      final second = writer.contribute(_id, body, localId: 'm-1');
      await pumpEventQueue();
      answer.complete();
      expect(await Future.wait([first, second]), [100000, 100000]);
      expect(posts(adapter), hasLength(1));
    });

    test('en duda: no se reintenta solo; el reintento lleva el localId que le dio la hoja', () async {
      var calls = 0;
      final (c, adapter) = await open((o) {
        calls++;
        // La primera respuesta se pierde (el aporte sí llegó); la segunda es la del servidor con ese localId.
        return calls == 1 ? _timeout(o) : jsonBody(201, _contributed(100000));
      });
      final writer = c.read(vacasWriterProvider);
      await expectLater(
        writer.contribute(_id, body, localId: 'm-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.timeout)),
      );
      expect(posts(adapter), hasLength(1), reason: 'nada de reintentos solos');
      await writer.contribute(_id, body, localId: 'm-1');
      final [first, second] = posts(adapter);
      expect((second.data as Map)['localId'], (first.data as Map)['localId']);
    });

    test(
      'crear una vaca en duda: si aparece una NUEVA con ese nombre y meta, es esa; si no, UNCONFIRMED',
      () async {
        for (final arrives in [true, false]) {
          var posted = false;
          final (c, adapter) = await open((o) {
            if (o.method == 'POST') {
              posted = true;
              return _timeout(o);
            }
            return jsonBody(200, posted && arrives ? [_vaca()] : const <Object>[]);
          });
          final creating = c.read(vacasWriterProvider).create({
            'name': 'Paseo de fin de año',
            'goal': 1200000,
          });
          if (arrives) {
            expect((await creating).id, _id);
          } else {
            await expectLater(
              creating,
              throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.unconfirmed)),
            );
          }
          expect(posts(adapter), hasLength(1), reason: '$arrives');
        }
      },
    );
  });

  group('plata y cuentas', () {
    test('aportar refresca Movimientos, Mi plata y el Inicio (el gasto lo crea el servidor)', () async {
      final (c, _) = await open((o) => jsonBody(201, _contributed(100000)));
      final account = c.read(accountProvider);
      c.listen(moneyProfileProvider(account), (_, _) {});
      c.listen(homePlanProvider(account), (_, _) {});
      c.listen(movementDetailProvider((account, 'm1')), (_, _) {});
      await c.read(moneyProfileProvider(account).future);
      await c.read(homePlanProvider(account).future);
      await c.read(movementDetailProvider((account, 'm1')).future);
      await c.read(vacasWriterProvider).contribute(_id, body, localId: 'm-1');
      await pumpEventQueue();
      expect((money.count('profile'), home.count('plan')), (2, 2));
      expect(movements.calls.where((call) => call == 'get m1'), hasLength(2));
    });

    test('con una bienvenida a medias no se aporta: al retomarla pisaría la plata', () async {
      final drafts = MemoryDraftStore();
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      final (c, adapter) = await open((o) => jsonBody(201, _contributed(1)), drafts: drafts);
      await expectLater(
        c.read(vacasWriterProvider).contribute(_id, body, localId: 'm-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.welcomePending)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('si otra cuenta entra antes de enviar, el aporte no sale; B no ve las vacas de A', () async {
      final drafts = _SlowDrafts();
      final (c, adapter) = await open((o) => jsonBody(200, [_vaca()]), drafts: drafts);
      final account = c.read(accountProvider);
      await c.read(vacasProvider(account).future);
      final sending = c.read(vacasWriterProvider).contribute(_id, body, localId: 'm-1');
      await pumpEventQueue();
      (c.read(sessionControllerProvider.notifier) as _Sessions).enter(_beto);
      drafts.gate.complete();
      await expectLater(sending, throwsA(isA<StateError>()));
      expect(posts(adapter), isEmpty);
      expect(c.read(vacasProvider(c.read(accountProvider))).hasValue, isFalse);
    });

    test('borrar un aporte: 404 cuenta como hecho solo si la vaca sigue a la vista', () async {
      final (c, adapter) = await open(
        (o) => o.method == 'DELETE'
            ? errorBody(404, 'NOT_FOUND', 'Aporte no encontrado')
            : jsonBody(200, _vaca()),
      );
      await c.read(vacasWriterProvider).deleteContribution(_id, 'c1');
      expect(
        [for (final r in adapter.requests) '${r.method} ${r.path}'],
        ['DELETE $_path/contributions/c1', 'GET $_path'],
      );

      final (gone, _) = await open((o) => errorBody(404, 'NOT_FOUND', 'Vaca no encontrada'));
      await expectLater(
        gone.read(vacasWriterProvider).deleteContribution(_id, 'c1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('pantallas', () {
    Translations translations() => Translations({
      for (final language in const ['en', 'pt'])
        language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
          (k, v) => MapEntry('$k', '$v'),
        ),
    });

    Future<void> pump(WidgetTester tester, String route, {ThemeData? theme}) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: route,
        routes: [
          GoRoute(path: Routes.goals, builder: (_, _) => const MetasScreen()),
          GoRoute(path: Routes.vacas, builder: (_, _) => const VacasScreen()),
          GoRoute(
            path: '${Routes.vacas}/:id',
            builder: (_, state) => VacaDetailScreen(vacaId: state.pathParameters['id']!, inMetas: false),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          retry: (_, _) => null,
          overrides: [
            sessionControllerProvider.overrideWith(_Sessions.new),
            vacasProvider.overrideWith(
              (ref, _) async => [Vaca.fromJson(_vaca(personal: true)), Vaca.fromJson(_vaca())],
            ),
            vacaDetailProvider.overrideWith((ref, _) async => Vaca.fromJson(_vaca())),
            vacaAdviceProvider.overrideWith((ref, _) => Completer<VacaAdvice>().future),
            moneyRepositoryProvider.overrideWithValue(FakeMoneyRepository()),
            homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
            movementsRepositoryProvider.overrideWithValue(FakeMovementsRepository()),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
            translationsProvider.overrideWithValue(translations()),
            draftStoreProvider.overrideWithValue(MemoryDraftStore()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme ?? RindeTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2), disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
      testWidgets('Metas, Vacas y el detalle a 320 con la letra al doble, tema $name: nada se desborda', (
        tester,
      ) async {
        for (final (route, text) in [
          (Routes.goals, '¿Para qué estás ahorrando?'),
          (Routes.vacas, 'Paseo de fin de año'),
          (Routes.vaca(_id), 'Laura Valentina de los Ríos'),
        ]) {
          await pump(tester, route, theme: theme);
          expect(tester.takeException(), isNull, reason: route);
          expect(find.text(text), findsWidgets, reason: route);
        }
      });
    }
  });

  group('la hoja de aporte', () {
    Future<List<String>> pump(
      WidgetTester tester,
      Widget Function(BuildContext) home, {
      bool hidden = false,
    }) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sent = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sessionControllerProvider.overrideWith(_Sessions.new),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
            initialHiddenAmountsProvider.overrideWithValue(hidden),
            draftStoreProvider.overrideWithValue(MemoryDraftStore()),
            movementCategoriesProvider.overrideWith(
              (ref, _) async => const CategoryLists(expense: [], income: []),
            ),
            vacasWriterProvider.overrideWith((ref) => _Writer(ref, sent)),
          ],
          child: MaterialApp(
            theme: RindeTheme.light,
            home: Scaffold(body: Builder(builder: home)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return sent;
    }

    Widget opener(BuildContext context, {bool quick = true}) => TextButton(
      onPressed: () =>
          showContributionSheet(context, vaca: Vaca.fromJson(_vaca(personal: true)), quick: quick),
      child: const Text('abrir'),
    );

    testWidgets(
      'el localId es de la hoja: el reintento lo reusa; otra hoja, aunque sea igual, es otro aporte',
      (tester) async {
        final sent = await pump(tester, opener);
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        // La primera respuesta se pierde (en duda); el reintento en la misma hoja sí llega.
        await tester.tap(find.byType(RindeButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(RindeButton));
        await tester.pumpAndSettle();
        expect(find.text('abrir'), findsOneWidget);

        // Otra hoja con el mismo monto y la misma fecha: un aporte nuevo.
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(RindeButton));
        await tester.pumpAndSettle();

        expect(sent, hasLength(3));
        expect(sent[1], sent[0]);
        expect(sent[2], isNot(sent[0]));
      },
    );

    testWidgets(
      'con los montos ocultos, el plan, «Apartar», «Poner lo que me falta» y «Borrar aporte» se leen «Monto oculto»',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final money = HomeMoney(format: formatFor(kDefaultRegion), hidden: true, hiddenLabel: 'Monto oculto');
        await pump(
          tester,
          (context) => Column(
            children: [
              opener(context),
              opener(context, quick: false),
              VacaContributionList(
                vaca: Vaca.fromJson(_vaca(personal: true)),
                money: money,
                onDelete: (_) async {},
              ),
            ],
          ),
          hidden: true,
        );
        expect(find.bySemanticsLabel(RegExp('Borrar aporte de Monto oculto')), findsOneWidget);
        await tester.tap(find.text('abrir').first);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('Monto oculto · tu plan')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Apartar Monto oculto')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('••')), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('abrir').last);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp(r'Poner lo que me falta \(Monto oculto\)')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('••')), findsNothing);
        semantics.dispose();
      },
    );
  });
}

/// Aportes a la medida: guarda el localId de cada envío; el primero queda en duda.
class _Writer extends VacasWriter {
  _Writer(super.ref, this.sent);
  final List<String> sent;

  @override
  Future<num> contribute(String id, Map<String, dynamic> body, {required String localId}) async {
    sent.add(localId);
    if (sent.length == 1) {
      throw const ApiException(code: ApiCodes.timeout, serverMessage: 'Se venció la espera');
    }
    return body['amount'] as num;
  }
}
