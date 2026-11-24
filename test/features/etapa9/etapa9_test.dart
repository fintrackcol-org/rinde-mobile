// Etapa 9: Notificaciones, Consejos, Exportar y Renta. El contrato con el servidor (bandeja y marcar
// leídos, chat con los últimos 10 mensajes, archivo en bytes con su nombre y errores en bytes), lo que
// se calcula en la app (hace cuánto, nombre del archivo) y las pantallas con los textos de la web,
// incluidos los límites del servidor y los periodos sin movimientos.
import 'package:flutter_riverpod/misc.dart' show Override;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/export/data/export_repository.dart';
import 'package:rinde_mobile/features/export/presentation/export_screen.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/insights/application/insights_providers.dart';
import 'package:rinde_mobile/features/insights/data/insights_repository.dart';
import 'package:rinde_mobile/features/insights/presentation/insights_screen.dart';
import 'package:rinde_mobile/features/notifications/application/notifications_writer.dart';
import 'package:rinde_mobile/features/notifications/data/notifications_repository.dart';
import 'package:rinde_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/renta/presentation/renta_screen.dart';

import '../../support/fake_http.dart';

const _session = Session(
  user: AuthUser(id: 'u1', email: 'ana@rinde.co'),
  accessToken: 'acceso',
  refreshToken: 'refresh',
);
const _t = Tr('es', {});
final _now = DateTime(2026, 11, 24, 10);

Future<ApiClient> _api(FakeHttpAdapter http) async {
  final holder = SessionHolder(MemorySessionStorage(_session));
  await holder.load();
  addTearDown(holder.dispose);
  return ApiClient(
    config: const AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa'),
    session: holder,
    adapter: http,
  );
}

class _FakeNotifications implements NotificationsRepository {
  int marks = 0;
  List<AppNotification> items = [
    AppNotification(
      id: 'n1',
      title: 'Tu tarjeta vence mañana',
      body: 'Paga Mi Visa antes del 25.',
      read: false,
      createdAt: DateTime(2026, 11, 24, 9, 55),
      url: '/app/tarjetas/t1',
    ),
    AppNotification(
      id: 'n2',
      title: 'Presupuesto al 80 %',
      body: 'Alimentación va en 80 %.',
      read: true,
      createdAt: DateTime(2026, 11, 20),
    ),
  ];

  @override
  bool get isDemo => false;

  @override
  Future<List<AppNotification>> list() async => items;

  @override
  Future<void> markAllRead() async => marks++;
}

Future<void> _pump(WidgetTester tester, String initial, List<Override> overrides) async {
  // Alto de sobra: las listas construyen todo lo que se revisa.
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: Routes.insights, builder: (_, _) => const InsightsScreen()),
      GoRoute(path: Routes.export, builder: (_, _) => const ExportScreen()),
      GoRoute(path: Routes.renta, builder: (_, _) => const RentaScreen()),
      for (final path in [Routes.app, Routes.record, Routes.myMoney, Routes.account, '/app/tarjetas/:id'])
        GoRoute(
          path: path,
          builder: (_, s) => Scaffold(body: Text('DESTINO ${s.uri}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      // Como main.dart: sin reintentos automáticos, el error se ve enseguida.
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        clockProvider.overrideWithValue(() => _now),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: RindeTheme.light,
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('contrato', () {
    test('la bandeja descarta avisos rotos y marcar leídos es POST /notifications/read', () async {
      final http = FakeHttpAdapter(
        (o) => o.method == 'POST'
            ? ResponseBody.fromString('', 204)
            : jsonBody(200, {
                'unread': 1,
                'items': [
                  {
                    'id': 'n1',
                    'title': 'Hola',
                    'body': 'Cuerpo',
                    'url': null,
                    'read': false,
                    'createdAt': '2026-11-24T14:00:00.000Z',
                  },
                  {'id': 'roto'},
                ],
              }),
      );
      final repo = ApiNotificationsRepository(await _api(http));
      final [n] = await repo.list();
      expect((n.id, n.title, n.read, n.url), ('n1', 'Hola', false, null));
      await repo.markAllRead();
      expect(
        [for (final r in http.requests) '${r.method} ${r.path}'],
        ['GET /notifications', 'POST /notifications/read'],
      );
    });

    test('el chat manda los últimos 10 mensajes empezando por una pregunta y lee las fuentes', () async {
      final http = FakeHttpAdapter(
        (_) => jsonBody(200, {
          'reply': 'Gastas más en comida.',
          'toolsUsed': ['resumen_de_movimientos', 42],
        }),
      );
      final messages = <ChatMessage>[
        for (var i = 0; i < 11; i++) (fromUser: i.isEven, text: 'm$i'),
        (fromUser: true, text: '¿En qué gasto más?'),
      ];
      final answer = await InsightsRepository(await _api(http)).ask(messages);
      expect(answer.reply, 'Gastas más en comida.');
      expect(answer.toolsUsed, ['resumen_de_movimientos']);
      final sent = (jsonDecode(jsonEncode(http.requests.single.data)) as Map)['messages'] as List;
      // De los últimos 10 (m2…m10 y la pregunta) se quita la respuesta inicial: arranca en m2.
      expect(sent.first, {'role': 'user', 'text': 'm2'});
      expect(sent.length, 10);
      expect(sent.last, {'role': 'user', 'text': '¿En qué gasto más?'});
      expect(toConversation([(fromUser: false, text: 'hola')]), isEmpty);
    });

    test('exportar baja los bytes con el nombre del servidor; un 422 en bytes conserva NO_DATA', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      var fail = false;
      final http = FakeHttpAdapter(
        (o) => fail
            ? ResponseBody.fromBytes(
                utf8.encode(
                  jsonEncode({
                    'error': {'code': 'NO_DATA', 'message': 'No hay movimientos'},
                  }),
                ),
                422,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              )
            : ResponseBody.fromBytes(
                bytes,
                200,
                headers: {
                  'content-disposition': ['attachment; filename="rinde_2026-11.pdf"'],
                },
              ),
      );
      final repo = ExportRepository(await _api(http));
      final file = await repo.export(ExportFormat.pdf, '2026-11-01', '2026-11-30', detail: false);
      expect(file.bytes, bytes);
      expect(file.filename, 'rinde_2026-11.pdf');
      expect(http.requests.single.uri.query, 'format=pdf&from=2026-11-01&to=2026-11-30&detail=false');

      fail = true;
      await expectLater(
        repo.export(ExportFormat.csv, '2026-11-01', '2026-11-30'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCodes.noData)),
      );
    });

    test('el nombre del archivo nunca trae barras; sin encabezado, el de respaldo', () {
      expect(filenameFrom('attachment; filename="../../x.csv"', 'r.csv'), '.._.._x.csv');
      expect(filenameFrom(null, 'rinde_2026-11-01_2026-11-15.csv'), 'rinde_2026-11-01_2026-11-15.csv');
    });
  });

  test('hace cuánto: ahora, minutos, horas, ayer, días y la fecha pasada una semana', () {
    String ago(DateTime d) => timeAgo(d, _now, kDefaultRegion, _t);
    expect(ago(_now), 'ahora');
    expect(ago(_now.subtract(const Duration(minutes: 5))), 'hace 5 min');
    expect(ago(_now.subtract(const Duration(hours: 3))), 'hace 3 h');
    expect(ago(_now.subtract(const Duration(days: 1))), 'ayer');
    expect(ago(_now.subtract(const Duration(days: 4))), 'hace 4 días');
    expect(ago(DateTime(2026, 10, 12, 10)), '12 oct');
  });

  testWidgets('Notificaciones: las sin leer van en «Nuevas», se marcan leídas una vez y abren su pantalla', (
    tester,
  ) async {
    final repo = _FakeNotifications();
    await _pump(tester, Routes.notifications, [notificationsRepositoryProvider.overrideWithValue(repo)]);
    expect(find.text('Nuevas'), findsOneWidget);
    expect(find.text('Anteriores'), findsOneWidget);
    expect(find.text('hace 5 min'), findsOneWidget);
    expect(repo.marks, 1);

    // Al recargar ya llegan leídos: siguen en «Nuevas» esta visita y no se vuelve a marcar.
    repo.items = [
      for (final n in repo.items)
        AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          read: true,
          createdAt: n.createdAt,
          url: n.url,
        ),
    ];
    final container = ProviderScope.containerOf(tester.element(find.byType(NotificationsScreen)));
    container.invalidate(notificationsListProvider);
    await tester.pumpAndSettle();
    expect(find.text('Nuevas'), findsOneWidget);
    expect(repo.marks, 1);

    await tester.tap(find.text('Tu tarjeta vence mañana'));
    await tester.pumpAndSettle();
    expect(find.text('DESTINO /app/tarjetas/t1'), findsOneWidget);
  });

  testWidgets('Notificaciones vacías: el estado de la web', (tester) async {
    await _pump(tester, Routes.notifications, [
      notificationsRepositoryProvider.overrideWithValue(_FakeNotifications()..items = []),
    ]);
    expect(find.text('No tienes notificaciones'), findsOneWidget);
    expect(find.text('Aquí verás tus pagos, tarjetas y presupuestos.'), findsOneWidget);
  });

  group('Consejos', () {
    final reflection = WeekReflection.fromJson({
      'from': '2026-11-23',
      'to': '2026-11-29',
      'expenses': {'count': 2, 'total': 50000},
      'withEmotion': 1,
      'emotions': [
        {'key': 'me_arrepiento', 'count': 1, 'total': 30000},
      ],
      'kakeibo': [
        {'key': 'deseo', 'count': 1, 'total': 30000},
      ],
      'withoutKakeibo': {'count': 1, 'total': 20000},
      'regrets': [
        {'id': 'm9', 'description': 'Domicilio', 'amount': 30000, 'emotion': 'me_arrepiento'},
      ],
      'questions': ['¿Lo volverías a pedir?'],
    });

    testWidgets('los consejos de la IA del servidor y la semana en Kakeibo', (tester) async {
      await _pump(tester, Routes.insights, [
        insightsProvider.overrideWith(
          (ref, _) async => InsightsResult.fromJson({
            'period': 'week',
            'month': '2026-11',
            'from': '2026-11-23',
            'insights': [
              {'type': 'general_tip', 'title': 'Vas bien', 'detail': 'Gastaste 10 % menos.'},
            ],
          }),
        ),
        reflectionProvider.overrideWith((ref, _) async => reflection),
      ]);
      expect(find.text('Esta semana'), findsOneWidget);
      expect(find.text('Vas bien'), findsOneWidget);
      expect(find.text('Del 23 al 29 de noviembre · cómo gastaste y cómo te sentiste'), findsOneWidget);
      expect(
        find.text('1 de 2 gastos tienen emoción. Puedes ponerla desde el detalle de cada gasto.'),
        findsOneWidget,
      );
      expect(find.text('Sin grupo'), findsOneWidget);
      expect(find.text('¿Lo volverías a pedir?'), findsOneWidget);
      expect(find.text('Renta y DIAN'), findsOneWidget);
      expect(find.text('Pregunta sobre tu plata'), findsOneWidget);
    });

    for (final (name, error, expected) in [
      (
        'sin historial',
        const ApiException(code: ApiCodes.insufficientHistory, serverMessage: 'Necesitas una semana.'),
        'Necesitas una semana.',
      ),
      (
        'la IA no responde',
        const ApiException(code: ApiCodes.aiUnavailable, serverMessage: 'x'),
        'Nuestro asistente no está disponible ahora mismo. Inténtalo de nuevo en unos minutos.',
      ),
      (
        'límite del servidor',
        const ApiException(code: ApiCodes.rateLimited, serverMessage: 'Llegaste al límite de hoy.'),
        'Llegaste al límite de hoy.',
      ),
    ]) {
      testWidgets('error: $name', (tester) async {
        await _pump(tester, Routes.insights, [
          insightsProvider.overrideWith((ref, _) => Future<InsightsResult>.error(error)),
          reflectionProvider.overrideWith((ref, _) async => reflection),
        ]);
        expect(find.text(expected), findsOneWidget);
        if (error.code == ApiCodes.insufficientHistory) {
          expect(find.text('Todavía no hay suficiente historial'), findsOneWidget);
          await tester.tap(find.text('Registrar un movimiento'));
          await tester.pumpAndSettle();
          expect(find.text('DESTINO ${Routes.record}'), findsOneWidget);
        }
      });
    }
  });

  testWidgets('Exportar: sin movimientos en el periodo lo dice y no deja descargar', (tester) async {
    final http = FakeHttpAdapter((_) => errorBody(422, 'NO_DATA', 'No hay movimientos'));
    final api = await _api(http);
    await _pump(tester, Routes.export, [exportRepositoryProvider.overrideWithValue(ExportRepository(api))]);
    expect(find.text('rinde_2026-11.xlsx'), findsOneWidget);
    expect(find.text('No hay movimientos en este periodo'), findsOneWidget);
    expect(
      find.text(
        'No tienes movimientos del 1 de noviembre de 2026 al 30 de noviembre de 2026. Prueba con otro periodo.',
      ),
      findsOneWidget,
    );
    final download = tester.widget<RindeButton>(find.widgetWithText(RindeButton, 'Descargar Excel'));
    expect(download.onPressed, isNull);
    expect(http.requests.single.uri.query, 'from=2026-11-01&to=2026-11-30');
  });

  testWidgets('Exportar: la vista previa muestra las cifras del servidor y el PDF su casilla', (
    tester,
  ) async {
    final http = FakeHttpAdapter(
      (_) => jsonBody(200, {
        'totals': {'income': 700000, 'expense': 220000, 'balance': 480000, 'count': 3},
        'expenseByCategory': [
          {'name': 'Alimentación', 'amount': 172000, 'count': 2, 'share': 0.78},
        ],
        'insights': [
          {'kind': 'balance', 'title': 'Te sobró plata', 'detail': 'Ingresaste más de lo que gastaste.'},
        ],
      }),
    );
    final api = await _api(http);
    await _pump(tester, Routes.export, [exportRepositoryProvider.overrideWithValue(ExportRepository(api))]);
    expect(find.text('Alimentación'), findsOneWidget);
    expect(find.text('Incluir el detalle de movimientos'), findsNothing);
    await tester.tap(find.text('Entiende y comparte'));
    await tester.pumpAndSettle();
    expect(find.text('Incluir el detalle de movimientos'), findsOneWidget);
    expect(find.text('Te sobró plata'), findsOneWidget);
    expect(find.text('rinde_2026-11.pdf'), findsOneWidget);
    // Cambiar el formato no vuelve a pedir la vista previa: las cifras son las mismas.
    expect(http.requests.length, 1);
  });

  testWidgets('Renta y DIAN: los dos servicios oficiales y la nota de privacidad', (tester) async {
    await _pump(tester, Routes.renta, const []);
    expect(find.text('¿Debo declarar renta?'), findsOneWidget);
    expect(find.text('Ver el calendario tributario'), findsOneWidget);
    expect(
      find.text(
        'Tu documento lo escribes en la página de la DIAN, nunca en Rinde. Esta guía no reemplaza a un contador.',
      ),
      findsOneWidget,
    );
  });
}
