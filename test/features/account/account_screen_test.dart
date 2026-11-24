import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart' show themeModeProvider;
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/account/presentation/account_screen.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/cards/data/demo_cards_store.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_store.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/plan/data/demo_budgets_repository.dart' show demoBudgetsStoreProvider;

/// «Yo» con una cuenta de demostración (no sale a la red) y un router mínimo.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String scenario = 'nuevo',
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.account,
    routes: [
      GoRoute(
        path: Routes.app,
        builder: (_, _) => const Scaffold(body: Text('INICIO')),
      ),
      GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: '', environment: 'local', demoMode: true),
        ),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage(Session.demo(scenario))),
        demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
        demoMovementsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        demoCardsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        demoDebtsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        demoBudgetsStoreProvider.overrideWithValue(MemoryJsonListStore()),
        pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        tourSeenStoreProvider.overrideWithValue(MemoryTourSeenStore()),
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
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  // Sin la espera sintética de la demo: las pruebas no son de la latencia.
  container.read(demoControlsProvider.notifier).setLatency(Duration.zero);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _open(WidgetTester tester, String row) async {
  await tester.scrollUntilVisible(find.text(row).first, 150, scrollable: find.byType(Scrollable).first);
  // Al centro: abajo la tapa la barra de pestañas.
  await Scrollable.ensureVisible(tester.element(find.text(row).first), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(find.text(row).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra quién eres y los ajustes; nada de PWA, Apple Pay ni push', (tester) async {
    await _pump(tester);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('demo@rinde.test'), findsOneWidget);
    for (final row in [
      'Anotar por WhatsApp',
      'Apariencia',
      'Avisos y recordatorios',
      'Mis categorías',
      'País',
      'Idioma',
      'Ver el tutorial otra vez',
      'Cerrar sesión',
      'Eliminar cuenta',
    ]) {
      expect(find.text(row), findsWidgets, reason: row);
    }
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text('En desarrollo'), findsNothing);
    for (final hidden in ['Pagos con Apple Pay', 'Instalar Rinde', 'Notificaciones en este dispositivo']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
  });

  testWidgets('«Cerrar sesión» pide confirmación: «Cancelar» se queda, confirmar sale', (tester) async {
    final container = await _pump(tester);
    await _open(tester, 'Cerrar sesión');
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);
    expect(
      find.text('Lo que anotaste sin conexión se queda en este celular y se sube cuando vuelvas a entrar.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).value?.signedIn, isTrue);

    await _open(tester, 'Cerrar sesión');
    await tester.tap(find.text('Cerrar sesión').last);
    // Sin pumpAndSettle: aquí no hay router que lleve al login y el botón se queda cargando.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(sessionControllerProvider).value?.signedIn, isFalse);
  });

  testWidgets('«Ver el tutorial otra vez» lo pide y va al Inicio', (tester) async {
    final container = await _pump(tester);
    await _open(tester, 'Ver el tutorial otra vez');
    expect(container.read(tourRequestedProvider), isTrue);
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets('Apariencia cambia el tema en el acto', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('Avisos: solo «Pago de tarjetas», sin recordatorios diarios que prometan push', (tester) async {
    await _pump(tester);
    await _open(tester, 'Avisos y recordatorios');
    expect(find.text('Pago de tarjetas'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Recordatorios diarios'), findsNothing);
    expect(find.text('Activar notificaciones'), findsNothing);
  });

  testWidgets('eliminar cuenta: hasta marcar y escribir la contraseña no se puede; luego sale', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _open(tester, 'Eliminar cuenta');
    expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Eliminar mi cuenta para siempre');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(EditableText).last, 'clave');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    final check = find.text('Entiendo que mi cuenta y mis datos se borran y no se pueden recuperar.');
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).value?.signedIn, isFalse);
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
      await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      // Se llega hasta «Eliminar cuenta» desplazando, por encima de la barra.
      await tester.scrollUntilVisible(
        find.text('Eliminar cuenta'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Eliminar cuenta')).bottom,
        lessThanOrEqualTo(tester.getRect(find.bySemanticsLabel('Secciones')).top),
      );
      await _open(tester, 'Eliminar cuenta');
      expect(tester.takeException(), isNull);
    });
  }
}
