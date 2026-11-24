import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/presentation/list/movements_screen.dart';

import '../../support/fake_movements_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _NoStore extends HiddenAmountsStore {
  const _NoStore();
  @override
  Future<bool> read() async => false;
  @override
  Future<void> write(bool hidden) async {}
}

final _now = DateTime(2026, 11, 22, 10);

/// La lista vertical (la fila de filtros también se desplaza, de lado).
final _list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

MovementPage _pageOf(MovementQuery q, List<Movement> all) {
  final start = (q.page - 1) * q.pageSize;
  return MovementPage(
    items: all.skip(start).take(q.pageSize).toList(),
    page: q.page,
    pageSize: q.pageSize,
    total: all.length,
  );
}

final _three = [
  movementOf('m1', date: '2026-11-22', description: 'Almuerzo', amount: 12500),
  Movement(
    id: 'm2',
    type: MovementType.income,
    amount: 700000,
    description: 'Salario',
    source: 'manual',
    date: '2026-11-21',
    category: 'salario',
  ),
  movementOf('m3', date: '2026-11-20', description: 'Taxi', amount: 9000),
];

Future<void> _pump(
  WidgetTester tester,
  FakeMovementsRepository repo, {
  MemoryJsonListStore? store,
  bool hidden = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.movements,
    routes: [
      GoRoute(path: Routes.movements, builder: (_, _) => const MovementsScreen()),
      GoRoute(
        path: '/app/transacciones/:id',
        builder: (_, state) => Scaffold(body: Text('RUTA ${state.uri}')),
      ),
      GoRoute(
        path: '/app/:a',
        builder: (_, state) => Scaffold(body: Text('RUTA ${state.uri}')),
      ),
      GoRoute(
        path: Routes.app,
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(_ana)),
        movementsRepositoryProvider.overrideWithValue(repo),
        pendingStoreProvider.overrideWithValue(store ?? MemoryJsonListStore()),
        clockProvider.overrideWithValue(() => _now),
        initialRegionProvider.overrideWithValue(const Region(country: 'CO', currency: 'COP', language: 'es')),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        hiddenAmountsStoreProvider.overrideWithValue(const _NoStore()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeMovementsRepository repo;

  setUp(() {
    repo = FakeMovementsRepository()
      ..onList = ((q) async => _pageOf(q, _three))
      ..onCategories = () async => const CategoryLists(
        expense: [CategoryOption(key: 'alimentacion', name: 'Alimentación')],
        income: [CategoryOption(key: 'salario', name: 'Salario')],
      );
  });

  testWidgets('arranca en el mes actual y agrupa por día con signo y categoría', (tester) async {
    await _pump(tester, repo);
    final q = repo.queries.last;
    expect((q.from, q.to, q.page, q.type, q.search), ('2026-11-01', '2026-11-30', 1, null, null));
    expect(find.text('¿En qué se te fue?'), findsOneWidget);
    expect(find.text('noviembre'), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('AYER'), findsOneWidget);
    expect(find.text('20 NOV'), findsOneWidget);
    expect(find.textContaining('−'), findsNWidgets(2));
    expect(find.textContaining('+'), findsOneWidget);
    expect(find.textContaining('12.500'), findsOneWidget);
    expect(find.text('Alimentación'), findsNWidgets(2));
    expect(find.text('3 movimientos'), findsOneWidget);
  });

  testWidgets('con montos ocultos no aparece ni un dígito de plata', (tester) async {
    await _pump(tester, repo, hidden: true);
    expect(find.textContaining('12.500'), findsNothing);
    expect(find.textContaining('700.000'), findsNothing);
    expect(find.textContaining('••••••'), findsNWidgets(3));
    expect(find.bySemanticsLabel(RegExp('Gasto de Monto oculto')), findsNWidgets(2));
  });

  testWidgets('sin movimientos dice el periodo, sin datos inventados', (tester) async {
    repo.onList = (q) async => _pageOf(q, const []);
    await _pump(tester, repo);
    expect(find.text('No hay movimientos en noviembre.'), findsOneWidget);
    expect(find.textContaining('movimiento '), findsNothing);
  });

  testWidgets('el buscador espera 300 ms y manda el texto recortado', (tester) async {
    await _pump(tester, repo);
    repo.onList = (q) async => _pageOf(q, const []);
    await tester.enterText(find.byType(TextField), '  café ');
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.queries.last.search, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(repo.queries.last.search, 'café');
    expect(repo.queries.last.page, 1);
    expect(find.text('Ningún movimiento coincide con la búsqueda.'), findsOneWidget);
  });

  testWidgets('la categoría se elige en la hoja y cambiar el tipo la borra', (tester) async {
    await _pump(tester, repo);
    await tester.ensureVisible(find.text('Categoría'));
    await tester.tap(find.text('Categoría'));
    await tester.pumpAndSettle();
    expect(find.text('Todas las categorías'), findsOneWidget);
    await tester.tap(find.text('Alimentación').last);
    await tester.pumpAndSettle();
    expect(repo.queries.last.category, 'alimentacion');
    await tester.tap(find.text('Ingresos'));
    await tester.pumpAndSettle();
    expect((repo.queries.last.type, repo.queries.last.category), (MovementType.income, null));
  });

  testWidgets('el periodo cambia el rango y no deja pasar del actual', (tester) async {
    await _pump(tester, repo);
    await tester.tap(find.byTooltip('Periodo siguiente'));
    await tester.pumpAndSettle();
    expect(repo.queries.last.from, '2026-11-01');
    await tester.tap(find.byTooltip('Periodo anterior'));
    await tester.pumpAndSettle();
    expect((repo.queries.last.from, repo.queries.last.to), ('2026-10-01', '2026-10-31'));
    expect(find.text('octubre'), findsOneWidget);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect((repo.queries.last.from, repo.queries.last.to), ('2026-11-16', '2026-11-22'));
  });

  testWidgets('sin conexión y sin datos: el motivo y Reintentar, sin cifras', (tester) async {
    repo.onList = (_) async => throw const ApiException(code: ApiCodes.network);
    await _pump(tester, repo);
    expect(find.text(ApiMessages.network), findsOneWidget);
    expect(find.textContaining('movimientos'), findsNothing);
    repo.onList = (q) async => _pageOf(q, _three);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text(ApiMessages.network), findsNothing);
  });

  testWidgets('si falla la recarga se conserva lo último y se marca', (tester) async {
    await _pump(tester, repo);
    repo.onList = (_) async => throw const ApiException(code: ApiCodes.network);
    await tester.fling(find.text('¿En qué se te fue?'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text(ApiMessages.network), findsOneWidget);
    expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsOneWidget);
  });

  testWidgets('pide la página siguiente al acercarse al final, sin repetir', (tester) async {
    final many = [
      for (var i = 0; i < 45; i++)
        movementOf('m$i', date: '2026-11-${(22 - i ~/ 3).toString().padLeft(2, '0')}'),
    ];
    repo.onList = (q) async => _pageOf(q, many);
    await _pump(tester, repo);
    expect(repo.calls.where((c) => c == 'list 2'), isEmpty);
    for (var i = 0; i < 12; i++) {
      await tester.drag(_list, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(repo.calls.where((c) => c.startsWith('list ') && c != 'list 1'), ['list 2', 'list 3']);
    expect(find.text('Ver más'), findsNothing);
    expect(find.text('45 movimientos'), findsNothing); // quedó arriba, fuera de la vista
  });

  testWidgets('tocar una fila abre su detalle', (tester) async {
    await _pump(tester, repo);
    await tester.tap(find.text('Almuerzo'));
    await tester.pumpAndSettle();
    expect(find.text('RUTA /app/transacciones/m1'), findsOneWidget);
  });

  testWidgets('lo guardado sin conexión se marca y Reintentar lo envía con el mismo localId', (tester) async {
    final store = MemoryJsonListStore()
      ..data['a'] = jsonEncode([
        PendingMovement(localId: 'm-local', input: inputOf, queuedAt: _now).toJson(),
      ]);
    final arrived = Completer<Movement>();
    repo.onCreate = (input, localId) => arrived.future;
    await _pump(tester, repo, store: store);
    expect(find.text('Pendientes de sincronizar (1)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Pendiente de sincronizar')), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(repo.localIds, ['m-local']);
    arrived.complete(movementOf('srv'));
    await tester.pumpAndSettle();
    expect(find.text('Pendientes de sincronizar (1)'), findsNothing);
  });

  testWidgets('deslizar para recargar también envía los pendientes, con el mismo localId', (tester) async {
    final store = MemoryJsonListStore()
      ..data['a'] = jsonEncode([
        PendingMovement(localId: 'm-local', input: inputOf, queuedAt: _now).toJson(),
      ]);
    repo.onCreate = (input, localId) async => movementOf('srv');
    await _pump(tester, repo, store: store);
    expect(find.text('Pendientes de sincronizar (1)'), findsOneWidget);
    await tester.fling(find.text('¿En qué se te fue?'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repo.localIds, ['m-local']);
    expect(find.text('Pendientes de sincronizar (1)'), findsNothing);
  });

  testWidgets('un reintento que sigue sin conexión lo deja en la cola y lo dice', (tester) async {
    final store = MemoryJsonListStore()
      ..data['a'] = jsonEncode([
        PendingMovement(localId: 'm-local', input: inputOf, queuedAt: _now).toJson(),
      ]);
    repo.onCreate = (_, _) async => throw const ApiException(code: ApiCodes.network);
    await _pump(tester, repo, store: store);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Pendientes de sincronizar (1)'), findsOneWidget);
    expect(find.text('No se pudo sincronizar'), findsOneWidget);
  });

  testWidgets('cardDropped: la fila avisa que se guardó sin tarjeta, sin decir «No se pudo sincronizar»', (
    tester,
  ) async {
    final store = MemoryJsonListStore()
      ..data['a'] = jsonEncode([
        {
          ...PendingMovement(localId: 'm-local', input: inputOf, queuedAt: _now).toJson(),
          'rejected': kCardDroppedMessage,
          'cardDropped': true,
        },
      ]);
    await _pump(tester, repo, store: store);
    expect(find.text('Almuerzo · $kCardDroppedMessage'), findsOneWidget);
    expect(find.textContaining('No se pudo sincronizar'), findsNothing);
    expect(find.text('Descartar'), findsOneWidget);
  });

  testWidgets('320 de ancho con letra al doble: sin desbordes', (tester) async {
    await _pump(tester, repo, size: const Size(320, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Almuerzo'), 300, scrollable: _list);
    expect(tester.takeException(), isNull);
  });
}
