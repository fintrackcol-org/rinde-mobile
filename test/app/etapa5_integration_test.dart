// Integración de la etapa 5 (bloque 5C) en la app real con la demostración, sin red: Mi plata →
// Tarjetas → Anotar con la tarjeta → Movimientos → el aviso del Inicio → Abonar; Mi plata → Cuentas →
// «Debo» → abono con la casilla → «Abono a X» en Movimientos → saldar; y B no ve nada de A.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/app.dart';
import 'package:rinde_mobile/app/router.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/network/api_client.dart';
import 'package:rinde_mobile/core/network/session_holder.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_text_field.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/cards/data/demo_cards_store.dart';
import 'package:rinde_mobile/features/cards/presentation/card_detail_screen.dart';
import 'package:rinde_mobile/features/cards/presentation/cards_screen.dart';
import 'package:rinde_mobile/features/debts/data/demo_debts_store.dart';
import 'package:rinde_mobile/features/debts/presentation/debts_screen.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_payment_sheet.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_sheet.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/application/tour_controller.dart';
import 'package:rinde_mobile/features/home/presentation/widgets/home_notice_card.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/money_shortcuts.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart' show pendingStoreProvider;
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart'
    show demoMovementsStoreProvider;
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/presentation/detail/movement_detail_screen.dart';
import 'package:rinde_mobile/features/onboarding/application/onboarding_controller.dart'
    show systemLocalesProvider;
import 'package:rinde_mobile/features/onboarding/data/demo_onboarding_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';

import '../support/fake_http.dart';

class _FastControls extends DemoControlsNotifier {
  @override
  DemoControls build() => const DemoControls(latency: Duration.zero);
}

final _cop = formatFor(kDefaultRegion);

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(RindeTextField)).first,
  matching: find.byType(TextField),
);

Finder _money(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(RindeMoneyField)).first,
  matching: find.byType(TextField),
);

void main() {
  late MemoryJsonListStore cards;
  late MemoryJsonListStore debts;
  late MemoryJsonListStore movements;
  late FakeHttpAdapter network;

  setUp(() {
    cards = MemoryJsonListStore();
    debts = MemoryJsonListStore();
    movements = MemoryJsonListStore();
    network = FakeHttpAdapter((_) => jsonBody(500, {}));
  });

  tearDown(() => expect(network.requests, isEmpty, reason: 'la demostración no sale a la red'));

  // Sin pumpAndSettle: Rin y los indicadores de carga no dejan de animarse.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// La app real con la sesión de demostración de [scenario]; los almacenes de tarjetas, cuentas y
  /// movimientos son los del test, compartidos entre aperturas (como el teléfono).
  Future<GoRouter> openApp(WidgetTester tester, String scenario) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const config = AppConfig(apiBaseUrl: 'https://api-qa.ejemplo.test', environment: 'qa', demoMode: true);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(config),
          sessionStorageProvider.overrideWithValue(MemorySessionStorage(Session.demo(scenario))),
          demoStateStoreProvider.overrideWithValue(MemoryDemoStateStore()),
          demoControlsProvider.overrideWith(_FastControls.new),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
          tourSeenStoreProvider.overrideWithValue(
            MemoryTourSeenStore()..seen.addAll([for (final s in DemoScenario.values) 'demo-${s.name}']),
          ),
          demoCardsStoreProvider.overrideWithValue(cards),
          demoDebtsStoreProvider.overrideWithValue(debts),
          demoMovementsStoreProvider.overrideWithValue(movements),
          pendingStoreProvider.overrideWithValue(MemoryJsonListStore()),
          systemLocalesProvider.overrideWithValue(const [Locale('es', 'CO')]),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(config: config, session: ref.watch(sessionHolderProvider), adapter: network),
          ),
        ],
        // Con el tamaño de la pantalla: un MediaQuery vacío deja en 0 lo que se mide con él (el pie de Anotar).
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(disableAnimations: true),
          child: const RindeApp(),
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(RindeApp))).read(routerProvider);
  }

  Future<void> openShortcut(WidgetTester tester, GoRouter router, String hint) async {
    router.go(Routes.myMoney);
    await settle(tester);
    await tap(tester, find.descendant(of: find.byType(MoneyShortcuts), matching: find.text(hint)));
  }

  testWidgets('tarjeta: agregar, anotar con ella, «Pagado con», el aviso del Inicio y abonar', (
    tester,
  ) async {
    final router = await openApp(tester, 'movimientos');
    await openShortcut(tester, router, 'Cupo y fechas de pago');
    expect(find.byType(CardsScreen), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('Agregar tarjeta'));
    await tester.enterText(_field('Últimos 4 dígitos'), '4242');
    final money = find.descendant(of: find.byType(RindeMoneyField), matching: find.byType(TextField));
    await tester.enterText(money.at(0), '1000000');
    await tester.enterText(money.at(1), '800000');
    await tester.enterText(_field('Día de pago'), '25');
    await tap(tester, find.text('Agregar tarjeta').last);
    expect(find.text('Visa ••4242'), findsOneWidget);

    // «Anotar» del detalle abre Anotar con ?tarjeta= y el gasto ya va con ella.
    await tap(tester, find.text('Visa ••4242'));
    expect(find.byType(CardDetailScreen), findsOneWidget);
    await tap(tester, find.text('Anotar'));
    expect(find.textContaining('· Tarjeta'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '50000');
    await tester.enterText(find.byType(TextField).at(1), 'Mercado');
    await tap(tester, find.textContaining('Guardar gasto'));
    expect(find.byType(CardDetailScreen), findsOneWidget, reason: 'Anotar vuelve al detalle');
    expect(find.text('Mercado'), findsOneWidget, reason: 'la compra ya está en el historial');

    router.go(Routes.movements);
    await settle(tester);
    await tap(tester, find.text('Mercado'));
    expect(find.byType(MovementDetailScreen), findsOneWidget);
    expect(find.text('Pagado con'), findsOneWidget);
    expect(find.textContaining('••4242'), findsOneWidget);

    // El aviso dice la etiqueta de la lista: 250.000 = 200.000 usados al crearla + la compra.
    router.go(Routes.app);
    await settle(tester);
    final notice = find.byType(HomeNoticeCard);
    expect(
      find.descendant(of: notice, matching: find.text('Tu Visa ••4242 se paga en 3 días')),
      findsOneWidget,
    );
    expect(find.descendant(of: notice, matching: find.text('Debes ${_cop.money(250000)}')), findsOneWidget);

    await tap(tester, notice);
    expect(find.byType(CardDetailScreen), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Abonar'));
    await tap(tester, find.text('Registrar pago'));
    expect(find.text('Pago registrado.'), findsOneWidget);

    router.go(Routes.app);
    await settle(tester);
    expect(find.textContaining('Tu Visa ••4242'), findsNothing, reason: 'pagada este mes, ya no se avisa');
  });

  testWidgets('cuenta: crear «Debo», abonar con la casilla, «Abono a X» en Movimientos y saldar', (
    tester,
  ) async {
    final router = await openApp(tester, 'movimientos');
    await openShortcut(tester, router, 'Lo que te deben y debes');
    expect(find.byType(DebtsScreen), findsOneWidget);

    await tap(tester, find.text('Agregar').first);
    await tap(tester, find.descendant(of: find.byType(DebtSheet), matching: find.text('Debo')));
    await tester.enterText(_field('¿A quién le debes?'), 'Tío Jorge');
    await tester.enterText(_money('¿Cuánto? (COP)'), '120000');
    await tap(tester, find.text('Siguiente'));
    await tap(tester, find.text('Guardar cuenta'));
    expect(find.text('Tío Jorge'), findsOneWidget);

    await tap(tester, find.text('Registrar abono'));
    expect(find.text('Anotar el gasto en Movimientos'), findsOneWidget);
    await tester.enterText(_money('¿Cuánto pagaste?'), '20000');
    await tap(
      tester,
      find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
    );
    expect(find.byType(DebtPaymentSheet), findsNothing);

    router.go(Routes.movements);
    await settle(tester);
    expect(find.text('Abono a Tío Jorge'), findsOneWidget);

    await openShortcut(tester, router, 'Lo que te deben y debes');
    await tap(tester, find.text('Debo · 1'));
    await tap(tester, find.text('Ya pagué todo'));
    await tap(tester, find.text('Ya pagué todo').last);
    expect(find.text('Saldada'), findsOneWidget);
    await tap(tester, find.text('ver el movimiento'));
    expect(find.byType(MovementDetailScreen), findsOneWidget);
  });

  testWidgets('A agrega una tarjeta y una cuenta y sale; entra B y no ve nada de A', (tester) async {
    var router = await openApp(tester, 'movimientos');
    await openShortcut(tester, router, 'Cupo y fechas de pago');
    await tap(tester, find.bySemanticsLabel('Agregar tarjeta'));
    await tester.enterText(_field('Últimos 4 dígitos'), '4242');
    final money = find.descendant(of: find.byType(RindeMoneyField), matching: find.byType(TextField));
    await tester.enterText(money.at(0), '1000000');
    await tester.enterText(money.at(1), '800000');
    await tester.enterText(_field('Día de pago'), '25');
    await tap(tester, find.text('Agregar tarjeta').last);
    await openShortcut(tester, router, 'Lo que te deben y debes');
    await tap(tester, find.text('Agregar').first);
    await tap(tester, find.descendant(of: find.byType(DebtSheet), matching: find.text('Debo')));
    await tester.enterText(_field('¿A quién le debes?'), 'Tío Jorge');
    await tester.enterText(_money('¿Cuánto? (COP)'), '120000');
    await tap(tester, find.text('Siguiente'));
    await tap(tester, find.text('Guardar cuenta'));
    expect(find.text('Tío Jorge'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    router = await openApp(tester, 'teFaltan');
    await openShortcut(tester, router, 'Cupo y fechas de pago');
    expect(find.text('Aún no tienes tarjetas'), findsOneWidget);
    expect(find.text('Visa ••4242'), findsNothing);
    await openShortcut(tester, router, 'Lo que te deben y debes');
    expect(find.text('Nadie te debe nada. Anota aquí cuando le prestes plata a alguien.'), findsOneWidget);
    await tap(tester, find.text('Debo'));
    expect(find.text('No le debes a nadie. Anota aquí lo que te prestan para no olvidarlo.'), findsOneWidget);
    expect(find.text('Tío Jorge'), findsNothing);
    router.go(Routes.app);
    await settle(tester);
    expect(find.textContaining('••4242'), findsNothing);
  });
}
