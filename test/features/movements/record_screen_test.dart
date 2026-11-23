import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart'
    show movementDetailProvider;
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/presentation/record/record_screen.dart';
import 'package:rinde_mobile/features/onboarding/presentation/widgets/onboarding_shell.dart';

import '../../support/fake_movements_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  _Sessions(this.session);
  final Session session;

  @override
  Future<SessionState> build() => SynchronousFuture(SessionState(session: session));
}

const _categories = CategoryLists(
  expense: [
    CategoryOption(key: 'alimentacion', name: 'Alimentación'),
    CategoryOption(key: 'transporte', name: 'Transporte'),
    CategoryOption(key: 'vivienda', name: 'Vivienda'),
    CategoryOption(key: 'salud', name: 'Salud'),
    CategoryOption(key: 'ocio', name: 'Ocio'),
    CategoryOption(key: 'educacion', name: 'Educación'),
    CategoryOption(key: 'otros', name: 'Otros'),
  ],
  income: [CategoryOption(key: 'salario', name: 'Salario')],
);

late FakeMovementsRepository repo;
late MemoryJsonListStore store;
final inputs = <MovementInput>[];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String initial = '/app/anotar',
  Session session = _ana,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
        routes: [
          GoRoute(
            path: 'anotar',
            builder: (_, state) => RecordScreen(
              initialType: state.uri.queryParameters['tipo'] == 'ingreso'
                  ? MovementType.income
                  : MovementType.expense,
            ),
          ),
          GoRoute(
            path: 'transacciones/:id/editar',
            builder: (_, state) => EditMovementScreen(movementId: state.pathParameters['id']!),
          ),
        ],
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
        movementsRepositoryProvider.overrideWithValue(repo),
        pendingStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? RindeTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(initial));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('INICIO', skipOffstage: false)));
}

Finder get _amount => find.byType(TextField).at(0);
Finder get _description => find.byType(TextField).at(1);
Finder _save([String label = 'Guardar gasto']) => find.textContaining(label);

Future<void> _fill(WidgetTester tester, {String amount = '12500', String description = 'Almuerzo'}) async {
  await tester.enterText(_amount, amount);
  await tester.enterText(_description, description);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    repo = FakeMovementsRepository()..onCategories = () async => _categories;
    store = MemoryJsonListStore();
    inputs.clear();
    repo.onCreate = (input, localId) async {
      inputs.add(input);
      return Movement(
        id: 'srv-1',
        type: input.type,
        amount: input.amount,
        description: input.description,
        source: input.category == null ? 'ia' : 'manual',
        date: input.date,
        category: input.category ?? 'alimentacion',
      );
    };
  });

  testWidgets('Guardar sin datos marca el monto y luego la descripción, sin llamar al servidor', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Anotar un gasto'), findsOneWidget);
    await _tap(tester, _save());
    expect(find.text('Escribe cuánto gastaste.'), findsOneWidget);
    await tester.enterText(_amount, '12500');
    await _tap(tester, _save());
    expect(find.text('Escribe en qué fue, p. ej. «almuerzo».'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);
  });

  testWidgets('guarda con la IA por defecto, hoy, vuelve atrás y avisa', (tester) async {
    await _pump(tester);
    await _fill(tester);
    expect(_save('Guardar gasto · '), findsOneWidget);
    await _tap(tester, _save());
    final input = inputs.single;
    expect(input.type, MovementType.expense);
    expect(input.amount, 12500);
    expect(input.description, 'Almuerzo');
    expect(input.date, '2026-11-22');
    expect(input.category, isNull);
    expect(find.text('INICIO'), findsOneWidget);
    expect(find.text('Guardado en Alimentación (sugerida por IA).'), findsOneWidget);
  });

  testWidgets('categoría elegida, «Ver todas», Kakeibo y «Ayer» viajan al servidor', (tester) async {
    await _pump(tester);
    await _fill(tester);
    expect(find.text('Educación'), findsNothing);
    await _tap(tester, find.text('Ver todas'));
    await _tap(tester, find.text('Educación'));
    await _tap(tester, find.textContaining('Más detalles'));
    await _tap(tester, find.text('Ayer'));
    await _tap(tester, find.text('Deseo'));
    await _tap(tester, _save());
    expect(inputs.single.category, 'educacion');
    expect(inputs.single.date, '2026-11-21');
    expect(inputs.single.kakeibo, 'deseo');
  });

  testWidgets('cambiar a ingreso cambia título y categorías y vuelve a la IA', (tester) async {
    await _pump(tester);
    await _tap(tester, find.text('Alimentación'));
    await _tap(tester, find.text('Ingreso'));
    expect(find.text('Anotar un ingreso'), findsOneWidget);
    expect(find.text('Alimentación'), findsNothing);
    expect(find.text('Salario'), findsOneWidget);
    await _fill(tester, description: 'Pago');
    await _tap(tester, _save('Guardar ingreso'));
    expect(inputs.single.type, MovementType.income);
    expect(inputs.single.category, isNull);
    expect(inputs.single.kakeibo, isNull);
  });

  testWidgets('tocar el tipo que ya está elegido no borra la categoría', (tester) async {
    await _pump(tester);
    await _fill(tester);
    await _tap(tester, find.text('Transporte'));
    await _tap(tester, find.text('Gasto'));
    await _tap(tester, _save());
    expect(inputs.single.category, 'transporte');
  });

  testWidgets('?tipo=ingreso abre en ingreso', (tester) async {
    await _pump(tester, initial: '/app/anotar?tipo=ingreso');
    expect(find.text('Anotar un ingreso'), findsOneWidget);
    expect(find.text('¿De qué fue? *'), findsOneWidget);
  });

  testWidgets('un error del servidor se muestra y el reintento usa el mismo localId', (tester) async {
    await _pump(tester);
    final create = repo.onCreate;
    repo.onCreate = (_, _) async => throw const ApiException(code: 'INTERNAL_ERROR', status: 500);
    await _fill(tester);
    await _tap(tester, _save());
    expect(find.text('Algo salió mal. Inténtalo de nuevo.'), findsOneWidget);
    expect(find.text('INICIO'), findsNothing);
    repo.onCreate = create;
    await _tap(tester, _save());
    expect(repo.localIds, hasLength(2));
    expect(repo.localIds.toSet(), hasLength(1));
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets('422: el problema va en su campo y no se cierra', (tester) async {
    await _pump(tester);
    repo.onCreate = (_, _) async => throw const ApiException(
      code: ApiCodes.validation,
      status: 422,
      serverMessage: 'Datos inválidos',
      fields: {'description': 'Máximo 200 caracteres'},
    );
    await _fill(tester);
    await _tap(tester, _save());
    expect(find.text('Máximo 200 caracteres'), findsOneWidget);
    expect(find.text('Datos inválidos'), findsNothing);
    expect(find.text('Anotar un gasto'), findsOneWidget);
  });

  testWidgets('sin conexión queda pendiente con un aviso honesto', (tester) async {
    await _pump(tester);
    repo.onCreate = (_, _) async => throw const ApiException(code: ApiCodes.network);
    await _fill(tester);
    await _tap(tester, _save());
    expect(find.text('INICIO'), findsOneWidget);
    expect(find.text('Guardado sin conexión. Se sincronizará cuando vuelva internet.'), findsOneWidget);
    expect(store.data['a'], contains('Almuerzo'));
  });

  testWidgets('sin conexión y con la cola llena: error de red y lo escrito se queda', (tester) async {
    final container = await _pump(tester);
    for (var i = 0; i < kMaxPendingMovements; i++) {
      await container.read(pendingMovementsProvider.notifier).enqueue('m-$i', inputOf);
    }
    repo.onCreate = (_, _) async => throw const ApiException(code: ApiCodes.network);
    await _fill(tester);
    await _tap(tester, _save());
    expect(find.text('No pudimos conectar con el servidor. Revisa tu conexión.'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);
  });

  testWidgets('un monto grande pide un segundo toque', (tester) async {
    await _pump(tester);
    await _fill(tester, amount: '6000000');
    await _tap(tester, _save());
    expect(find.textContaining('¿Seguro que son'), findsOneWidget);
    expect(inputs, isEmpty);
    await _tap(tester, find.textContaining('Sí, guardar'));
    expect(inputs.single.amount, 6000000);
  });

  testWidgets('no guarda dos veces con dos toques seguidos', (tester) async {
    await _pump(tester);
    final done = Completer<Movement>();
    repo.onCreate = (input, _) {
      inputs.add(input);
      return done.future;
    };
    await _fill(tester);
    await tester.tap(_save());
    await tester.pump();
    await tester.tap(find.text('Guardando…'), warnIfMissed: false);
    await tester.pump();
    expect(inputs, hasLength(1));
    done.complete(movementOf('srv-1'));
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets('X cierra sin anotar', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byTooltip('Cerrar sin anotar'));
    expect(find.text('INICIO'), findsOneWidget);
    expect(inputs, isEmpty);
  });

  testWidgets('demo: muestra la franja de demostración', (tester) async {
    await _pump(
      tester,
      session: const Session(
        user: AuthUser(id: 'd', email: 'demo@rinde.co', name: 'Demo'),
        accessToken: 'x',
        refreshToken: 'y',
        demo: true,
      ),
    );
    expect(find.byType(DemoStrip), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('320 px con letra al doble (${dark ? 'oscuro' : 'claro'}): sin desbordes', (tester) async {
      await _pump(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        theme: dark ? RindeTheme.dark : RindeTheme.light,
      );
      await _tap(tester, find.textContaining('Más detalles'));
      await _tap(tester, _save());
      expect(tester.takeException(), isNull);
      expect(find.text('Escribe cuánto gastaste.'), findsOneWidget);
    });
  }

  group('editar', () {
    const saved = Movement(
      id: 'id-1',
      type: MovementType.expense,
      amount: 50000,
      description: 'Mercado',
      source: 'manual',
      date: '2026-11-20',
      category: 'alimentacion',
      card: MovementCard(id: 'card-1', name: 'Visa', last4: '1234', deleted: false),
      installments: 2,
      emotion: 'normal',
    );
    final updates = <MovementInput>[];

    setUp(() {
      updates.clear();
      repo.onGet = (_) async => saved;
      repo.onUpdate = (id, input) async {
        updates.add(input);
        return saved;
      };
    });

    testWidgets('llega lleno y manda el cambio con lo que no se muestra', (tester) async {
      await _pump(tester, initial: '/app/transacciones/id-1/editar');
      expect(find.text('Editar movimiento'), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);
      expect(find.text('50.000'), findsOneWidget);
      await tester.enterText(_description, 'Mercado grande');
      await _tap(tester, find.text('Guardar cambios'));
      final body = updates.single.toJson(update: true);
      expect(body['description'], 'Mercado grande');
      expect(body['category'], 'alimentacion');
      expect(body['card'], 'card-1');
      expect(body['installments'], 2);
      expect(body['emotion'], 'normal');
      expect(find.text('Cambios guardados.'), findsOneWidget);
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('si el detalle se refresca mientras se edita, el cambio se calcula contra lo que se abrió', (
      tester,
    ) async {
      final c = await _pump(tester, initial: '/app/transacciones/id-1/editar');
      await tester.enterText(_description, 'Mercado grande');
      // Otra pantalla de edición guardó encima otra categoría y el detalle se volvió a pedir.
      repo.onGet = (_) async => Movement(
        id: saved.id,
        type: saved.type,
        amount: saved.amount,
        description: saved.description,
        source: 'manual',
        date: saved.date,
        category: 'transporte',
      );
      c.invalidate(movementDetailProvider);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Guardar cambios'));
      expect(repo.froms.single, same(saved));
      expect(updates.single.changesFrom(repo.froms.single!), {'description': 'Mercado grande'});
    });

    testWidgets('sin cambios vuelve atrás sin llamar al servidor', (tester) async {
      await _pump(tester, initial: '/app/transacciones/id-1/editar');
      await _tap(tester, find.text('Guardar cambios'));
      expect(updates, isEmpty);
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('sin conexión no edita: dice el error y conserva lo escrito', (tester) async {
      repo.onUpdate = (_, _) async => throw const ApiException(code: ApiCodes.network);
      await _pump(tester, initial: '/app/transacciones/id-1/editar');
      await tester.enterText(_description, 'Otra cosa');
      await _tap(tester, find.text('Guardar cambios'));
      expect(find.text('No pudimos conectar con el servidor. Revisa tu conexión.'), findsOneWidget);
      expect(find.text('Otra cosa'), findsOneWidget);
    });

    testWidgets('si no carga: el error y Reintentar', (tester) async {
      var fail = true;
      repo.onGet = (_) async {
        if (fail) throw const ApiException(code: 'NOT_FOUND', status: 404, serverMessage: 'No existe');
        return saved;
      };
      await _pump(tester, initial: '/app/transacciones/id-1/editar');
      expect(find.text('No existe'), findsOneWidget);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Mercado'), findsOneWidget);
    });
  });
}
