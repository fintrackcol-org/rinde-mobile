import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart'
    show movementDetailProvider;
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
import 'package:rinde_mobile/features/movements/presentation/detail/movement_detail_screen.dart';

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

const _lunch = Movement(
  id: 'm1',
  type: MovementType.expense,
  amount: 12500,
  description: 'Almuerzo',
  source: 'ia',
  date: '2026-11-22',
  category: 'alimentacion',
  card: MovementCard(id: 'c1', name: 'Mi Visa', last4: '4242', deleted: false),
  installments: 3,
);

/// El detalle abierto desde una lista falsa, para ver a dónde vuelve.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeMovementsRepository repo, {
  bool hidden = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.movements,
    routes: [
      GoRoute(
        path: Routes.movements,
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/app/transacciones/m1'),
            child: const Text('LISTA'),
          ),
        ),
      ),
      GoRoute(
        path: '/app/transacciones/:id',
        builder: (_, state) => MovementDetailScreen(movementId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/app/transacciones/:id/editar',
        builder: (_, state) => Scaffold(body: Text('RUTA ${state.uri}')),
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
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
        clockProvider.overrideWithValue(() => _now),
        initialRegionProvider.overrideWithValue(const Region(country: 'CO', currency: 'COP', language: 'es')),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        hiddenAmountsStoreProvider.overrideWithValue(const _NoStore()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: dark ? RindeTheme.dark : RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('LISTA'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late FakeMovementsRepository repo;

  setUp(() {
    repo = FakeMovementsRepository()
      ..onGet = ((_) async => _lunch)
      ..onCategories = () async => const CategoryLists(
        expense: [CategoryOption(key: 'alimentacion', name: 'Alimentación')],
        income: [],
      );
  });

  testWidgets('muestra lo que trae el servidor, como la web', (tester) async {
    await _pump(tester, repo);
    expect(repo.calls, contains('get m1'));
    expect(find.text('Gasto · Alimentación'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.textContaining('− '), findsOneWidget);
    expect(find.textContaining('12.500'), findsOneWidget);
    expect(find.textContaining('· sugerida por la IA', findRichText: true), findsOneWidget);
    expect(find.text('Hoy, 22 nov 2026'), findsOneWidget);
    expect(find.text('Mi Visa ••4242'), findsOneWidget);
    expect(find.text('Cuotas'), findsOneWidget);
    expect(find.text('Editar gasto'), findsOneWidget);
    expect(find.text('Eliminar gasto'), findsOneWidget);
  });

  testWidgets('un ingreso no muestra con qué se pagó y va en positivo', (tester) async {
    repo.onGet = (_) async => const Movement(
      id: 'm1',
      type: MovementType.income,
      amount: 700000,
      description: 'Salario',
      source: 'manual',
      date: '2026-11-01',
      category: null,
    );
    await _pump(tester, repo);
    expect(find.text('Ingreso · Sin clasificar'), findsOneWidget);
    expect(find.textContaining('+ '), findsOneWidget);
    expect(find.text('Pagado con'), findsNothing);
    expect(find.text('1 nov 2026'), findsOneWidget);
    expect(find.text('Editar ingreso'), findsOneWidget);
  });

  testWidgets('con montos ocultos no sale ni un dígito', (tester) async {
    await _pump(tester, repo, hidden: true);
    expect(find.textContaining('12.500'), findsNothing);
    await tester.tap(find.text('Eliminar gasto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12.500'), findsNothing);
    expect(find.textContaining('Almuerzo · '), findsOneWidget);
  });

  testWidgets('si falla la carga: el motivo y Reintentar', (tester) async {
    repo.onGet = (_) async => throw const ApiException(code: ApiCodes.network);
    await _pump(tester, repo);
    expect(find.text(ApiMessages.network), findsOneWidget);
    expect(find.text('Eliminar gasto'), findsNothing);
    repo.onGet = (_) async => _lunch;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Almuerzo'), findsOneWidget);
  });

  testWidgets('si ya cargó y al volver a pedirlo responde 404, no queda la copia vieja con Editar', (
    tester,
  ) async {
    await _pump(tester, repo);
    expect(find.text('Eliminar gasto'), findsOneWidget);
    repo.onGet = (_) async =>
        throw const ApiException(code: 'NOT_FOUND', status: 404, serverMessage: 'Transacción no encontrada');
    ProviderScope.containerOf(tester.element(find.byType(MovementDetailScreen)))
        .invalidate(movementDetailProvider);
    await tester.pumpAndSettle();
    expect(find.text('Eliminar gasto'), findsNothing);
    expect(find.text('Editar gasto'), findsNothing);
    expect(find.text('Transacción no encontrada'), findsOneWidget);
  });

  testWidgets('Editar abre la ruta de edición', (tester) async {
    await _pump(tester, repo);
    await tester.tap(find.text('Editar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('RUTA /app/transacciones/m1/editar'), findsOneWidget);
  });

  testWidgets('eliminar pide confirmación; Cancelar no borra nada', (tester) async {
    await _pump(tester, repo);
    await tester.tap(find.text('Eliminar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar este movimiento?'), findsOneWidget);
    expect(find.textContaining('Almuerzo · \$'), findsOneWidget);
    expect(find.textContaining('Se quita de tus totales.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
    expect(find.text('Almuerzo'), findsOneWidget);
  });

  testWidgets('Sí, eliminar borra, cierra y vuelve a la lista', (tester) async {
    final done = Completer<void>();
    repo.onDelete = (_) => done.future;
    await _pump(tester, repo);
    await tester.tap(find.text('Eliminar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, eliminar'));
    await tester.pump();
    expect(repo.calls, contains('delete m1'));
    // Mientras borra no se cierra con Atrás.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('¿Eliminar este movimiento?'), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('LISTA'), findsOneWidget);
  });

  testWidgets('si eliminar falla, el movimiento se queda y se dice por qué', (tester) async {
    repo.onDelete = (_) async => throw const ApiException(code: ApiCodes.network);
    await _pump(tester, repo);
    await tester.tap(find.text('Eliminar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, eliminar'));
    await tester.pumpAndSettle();
    expect(find.text(ApiMessages.network), findsOneWidget);
    expect(find.text('¿Eliminar este movimiento?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Almuerzo'), findsOneWidget);
  });

  testWidgets('320 de ancho con letra al doble y tema oscuro: sin desbordes', (tester) async {
    await _pump(tester, repo, size: const Size(320, 640), textScale: 2, dark: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Eliminar gasto'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
