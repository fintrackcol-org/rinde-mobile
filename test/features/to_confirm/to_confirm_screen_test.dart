// Por confirmar en pantalla: lo resuelto sale de la lista sin esperar a la recarga (que puede tardar),
// y con los montos ocultos el aviso «Anotado: …» se lee «Monto oculto», no la máscara.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/features/cards/application/cards_providers.dart';
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/to_confirm/application/to_confirm_writer.dart';
import 'package:rinde_mobile/features/to_confirm/data/to_confirm_repository.dart';
import 'package:rinde_mobile/features/to_confirm/presentation/to_confirm_screen.dart';

import '../../support/card_fixtures.dart';

const _taxi = IncomingPayment(id: 'p1', merchant: 'Taxi', amount: 12400, date: '2026-11-21');
const _cafe = IncomingPayment(id: 'p2', merchant: 'Café X', amount: 8000, date: '2026-11-21');
const _rappi = IncomingPayment(
  id: 'p3',
  merchant: 'Rappi',
  amount: 30000,
  date: '2026-11-21',
  card: 'Visa 4242',
);

class _Writer extends ToConfirmWriter {
  _Writer(super.ref, this.sent);
  final List<String> sent;

  @override
  Future<void> discard(IncomingPayment payment) async => sent.add('discard ${payment.id}');

  @override
  Future<void> confirm(
    IncomingPayment payment, {
    required String description,
    String? category,
    String? card,
  }) async => sent.add('confirm ${payment.id}${card == null ? '' : ' $card'}');
}

Future<List<String>> _pump(
  WidgetTester tester, {
  bool hidden = false,
  List<IncomingPayment> items = const [_taxi, _cafe],
  List<CreditCard> cards = const [],
}) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const ToConfirmScreen())],
  );
  addTearDown(router.dispose);
  final sent = <String>[];
  var lists = 0;
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: <Override>[
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        // La recarga tras escribir no llega (red lenta): queda el valor anterior.
        toConfirmListProvider.overrideWith(
          (ref, _) => lists++ == 0 ? Future.value(items) : Completer<List<IncomingPayment>>().future,
        ),
        movementCategoriesProvider.overrideWith(
          (ref, _) async => const CategoryLists(expense: [], income: []),
        ),
        toConfirmWriterProvider.overrideWith((ref) => _Writer(ref, sent)),
        cardsProvider.overrideWith((ref, _) async => cards),
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
  return sent;
}

void main() {
  testWidgets('descartado o confirmado, el pago sale de la lista y de la cuenta aunque la recarga tarde', (
    tester,
  ) async {
    final sent = await _pump(tester);
    expect(find.text('2 pagos sin revisar'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Descartar el pago en Café X'));
    await tester.pump();
    expect(find.text('Café X'), findsNothing);
    expect(find.text('1 pago sin revisar'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anotar el gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Taxi'), findsNothing);
    expect(sent, ['discard p2', 'confirm p1']);
  });

  testWidgets('con los montos ocultos, el aviso «Anotado» se lee «Monto oculto»', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, hidden: true);
    await tester.tap(find.text('Confirmar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anotar el gasto'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Anotado: Taxi, Monto oculto')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('••')), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    '«Pagado con»: arranca con la tarjeta de Wallet si coincide; si no, en efectivo y se elige otra',
    (tester) async {
      final visa = cardOfJson(cardJson(id: 'visa', last4: '4242'));
      final master = cardOfJson(cardJson(id: 'master', network: 'mastercard', last4: '1111'));
      final sent = await _pump(tester, items: const [_rappi, _taxi], cards: [visa, master]);

      await tester.tap(find.text('Confirmar').first);
      await tester.pumpAndSettle();
      expect(find.text('Pagado con'), findsOneWidget);
      await tester.tap(find.text('Anotar el gasto'));
      await tester.pumpAndSettle();
      expect(sent, ['confirm p3 visa'], reason: 'Wallet dice 4242 y solo una tarjeta termina así');

      // Sin tarjeta en Wallet: arranca en «Efectivo o débito»; se puede elegir una tarjeta.
      await tester.tap(find.text('Confirmar').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mastercard ••1111'));
      await tester.tap(find.text('Mastercard ••1111'));
      await tester.pump();
      await tester.tap(find.text('Anotar el gasto'));
      await tester.pumpAndSettle();
      expect(sent, ['confirm p3 visa', 'confirm p1 master']);
    },
  );

  testWidgets('sin tarjetas, «Pagado con» no aparece y se anota en efectivo', (tester) async {
    final sent = await _pump(tester, items: const [_rappi]);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Pagado con'), findsNothing);
    await tester.tap(find.text('Anotar el gasto'));
    await tester.pumpAndSettle();
    expect(sent, ['confirm p3']);
  });
}
