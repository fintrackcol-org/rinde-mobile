// Tarjetas (bloque 5A): /app/tarjetas y /app/tarjetas/:id en la variante de celular de la web, las
// hojas de crear/editar, «Ya pagué» y «Actualizar con el banco», todos los estados, montos ocultos
// (también para el lector), en/pt con USD/BRL y 320 de ancho con la letra al doble, claro y oscuro.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/core/region/region_provider.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_text_field.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/cards/data/card_models.dart';
import 'package:rinde_mobile/features/cards/data/cards_repository.dart';
import 'package:rinde_mobile/features/cards/application/cards_providers.dart';
import 'package:rinde_mobile/features/cards/presentation/card_detail_screen.dart';
import 'package:rinde_mobile/features/cards/presentation/cards_screen.dart';
import 'package:rinde_mobile/features/cards/presentation/widgets/bank_sync_sheet.dart';
import 'package:rinde_mobile/features/cards/presentation/widgets/card_row.dart' show CardUsageBar;
import 'package:rinde_mobile/features/cards/presentation/widgets/card_sheet.dart';
import 'package:rinde_mobile/features/cards/presentation/widgets/pay_card_sheet.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';

import '../../support/card_fixtures.dart';
import '../../support/fake_cards_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/fake_money_repository.dart';

const _ana = Session(
  user: AuthUser(id: 'a', email: 'ana@rinde.co', name: 'Ana'),
  accessToken: 'a',
  refreshToken: 'r',
);

class _Sessions extends SessionController {
  @override
  Future<SessionState> build() => SynchronousFuture(const SessionState(session: _ana));
}

final _cop = formatFor(kDefaultRegion);
String _m(num value) => _cop.money(value);

late FakeCardsRepository repo;

final _visa = creditCard(id: 't1', name: 'Mi Visa', last4: '4242', limit: 2000000, used: 500000.5);
final _amex = creditCard(
  id: 't2',
  name: 'Amex Gold ••1005',
  network: 'amex',
  tier: 'gold',
  last4: '1005',
  limit: 3000000,
  used: 616000,
  daysToPayment: 2,
  nextPaymentDate: '2026-11-25',
  statementTotal: 650000,
  statementDueDate: '2026-11-25',
  expiry: {'label': '01/27', 'expired': false, 'soon': true},
);

Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

Future<GoRouter> _pump(
  WidgetTester tester, {
  String route = Routes.cards,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  bool hidden = false,
  Region region = kDefaultRegion,
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
      GoRoute(path: Routes.cards, builder: (_, _) => const CardsScreen()),
      GoRoute(
        path: Routes.card(':id'),
        builder: (_, state) => CardDetailScreen(cardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.record,
        // Como el formulario de Anotar, vigila la lista de tarjetas.
        builder: (_, state) => Consumer(
          builder: (_, ref, _) {
            ref.watch(cardsProvider(ref.watch(accountProvider)));
            return Scaffold(body: Text('ANOTAR ${state.uri.queryParameters['tarjeta'] ?? '-'}'));
          },
        ),
      ),
      GoRoute(
        path: Routes.plan,
        builder: (_, _) => const Scaffold(body: Text('PLANEAR')),
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
        cardsRepositoryProvider.overrideWithValue(repo),
        moneyRepositoryProvider.overrideWithValue(FakeMoneyRepository()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        initialRegionProvider.overrideWithValue(region),
        translationsProvider.overrideWithValue(_translations()),
        draftStoreProvider.overrideWithValue(MemoryDraftStore()),
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
  unawaited(router.push(route));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(RindeTextField)).first,
  matching: find.byType(TextField),
);

String _location(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  setUp(() {
    repo = FakeCardsRepository();
    repo.onList = () async => [_visa, _amex];
    repo.onGet = (id) async => id == 't2' ? _amex : _visa;
  });

  group('lista', () {
    testWidgets('«Debes en total» (en centavos), el próximo pago, los círculos y las filas', (tester) async {
      await _pump(tester);
      expect(find.text('Tarjetas'), findsOneWidget);
      expect(find.text('Debes en total'), findsOneWidget);
      expect(find.text(_m(1116000.5)), findsOneWidget);
      // La web: dueText(next).replace('Se paga', 'Próximo pago').
      expect(find.text('Próximo pago en 2 días'), findsOneWidget);
      expect(find.bySemanticsLabel('Anotar'), findsOneWidget);
      expect(find.bySemanticsLabel('Agregar tarjeta'), findsOneWidget);
      expect(find.text('Mis tarjetas'), findsOneWidget);
      // «{Franquicia} ••{last4}», no el nombre elegido (Cards.jsx:25).
      expect(find.text('Visa ••4242'), findsOneWidget);
      expect(find.text('Amex ••1005'), findsOneWidget);
      expect(find.text('Se paga en 22 días'), findsOneWidget);
      expect(find.text('${'Disponible'} ${_m(1499999.5)} de ${_m(2000000)}'), findsOneWidget);
      expect(find.text('Vence pronto (01/27) · pide la nueva al banco'), findsOneWidget);

      await _tap(tester, find.text('Amex ••1005'));
      expect(find.text('Amex ••1005 · Lo que debes'), findsOneWidget);
    });

    testWidgets('la barra se ve: el relleno ocupa el % usado y todo el alto (en el emulador salía vacía)', (
      tester,
    ) async {
      await _pump(tester);
      final bar = find.byType(CardUsageBar).first;
      final fill = find.descendant(of: bar, matching: find.byType(DecoratedBox));
      // Visa: usado 500.000,5 de 2.000.000 → 25 %.
      expect(tester.getSize(fill).height, tester.getSize(bar).height);
      expect(tester.getSize(fill).width, closeTo(tester.getSize(bar).width * 0.25, 0.5));
    });

    testWidgets('«Anotar» va a Anotar sin tarjeta', (tester) async {
      await _pump(tester);
      await _tap(tester, find.bySemanticsLabel('Anotar'));
      expect(find.text('ANOTAR -'), findsOneWidget);
    });

    testWidgets('vacío: la tarjeta de ejemplo, la invitación y los círculos; sin «Debes en total»', (
      tester,
    ) async {
      repo.onList = () async => const [];
      await _pump(tester);
      expect(find.text('Aún no tienes tarjetas'), findsOneWidget);
      expect(find.text('Agrega una para ver cuánto cupo te queda y cuándo toca pagar.'), findsOneWidget);
      expect(find.text('Agregar mi primera tarjeta'), findsOneWidget);
      expect(find.text('Ejemplo'), findsOneWidget);
      expect(find.text('•••• 1234'), findsOneWidget);
      expect(find.text('Debes en total'), findsNothing);
      expect(find.bySemanticsLabel('Agregar tarjeta'), findsOneWidget);
    });

    testWidgets('error sin datos: el mensaje y «Reintentar», que vuelve a pedir', (tester) async {
      var fail = true;
      repo.onList = () async {
        if (fail) throw const ApiException(code: ApiCodes.network);
        return [_visa];
      };
      await _pump(tester);
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.text('Debes en total'), findsNothing);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Visa ••4242'), findsOneWidget);
    });

    testWidgets('sesión vencida (401): lo dice sin inventar datos', (tester) async {
      repo.onList = () async => throw const ApiException(code: ApiCodes.unauthorized, status: 401);
      await _pump(tester);
      expect(find.text(ApiMessages.sessionExpired), findsOneWidget);
    });

    testWidgets('datos viejos: si la recarga falla, sigue lo último con el aviso y «Reintentar»', (
      tester,
    ) async {
      await _pump(tester);
      repo.onList = () async => throw const ApiException(code: ApiCodes.network);
      await tester.fling(find.text('Debes en total'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Visa ••4242'), findsOneWidget);
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('al volver a entrar se pide otra vez, con la carga: no muestra la deuda de antes', (
      tester,
    ) async {
      final router = await _pump(tester);
      router.pop();
      await tester.pumpAndSettle();
      // Desde la web se pagó la Amex: ya no debe nada.
      final next = Completer<List<CreditCard>>();
      repo.onList = () => next.future;
      unawaited(router.push(Routes.cards));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.calls.where((c) => c == 'list'), hasLength(2));
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      expect(find.text(_m(1116000.5)), findsNothing);
      next.complete([_visa, creditCard(id: 't2', network: 'amex', last4: '1005', limit: 3000000, used: 0)]);
      await tester.pumpAndSettle();
      expect(find.text(_m(500000.5)), findsWidgets);
      expect(find.text(_m(1116000.5)), findsNothing);
    });

    testWidgets('sin pantalla anterior, atrás va a Planear (backPath de la web)', (tester) async {
      final router = await _pump(tester);
      router.go(Routes.cards);
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('PLANEAR'), findsOneWidget);
    });

    testWidgets('montos ocultos: ni un dígito de los montos, y el lector oye «Monto oculto»', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: true);
      for (final digits in ['1.116.000', '500.000', '616.000', '2.000.000', '3.000.000']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      // Siguen a la vista los nombres, los últimos 4 y las fechas.
      expect(find.text('Visa ••4242'), findsOneWidget);
      expect(find.text('Próximo pago en 2 días'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Monto oculto')), findsWidgets);
      handle.dispose();
    });

    for (final (region, total, next) in [
      (
        const Region(country: 'US', currency: 'USD', language: 'en'),
        'You owe in total',
        'Next payment in 2 days',
      ),
      (
        const Region(country: 'BR', currency: 'BRL', language: 'pt'),
        'Você deve no total',
        'Próximo pagamento em 2 dias',
      ),
    ]) {
      testWidgets('en ${region.language} con ${region.currency}', (tester) async {
        await _pump(tester, region: region);
        expect(find.text(total), findsOneWidget);
        expect(find.text(next), findsOneWidget);
        expect(find.text(formatFor(region).money(1116000.5)), findsOneWidget);
      });
    }
  });

  group('detalle', () {
    testWidgets('lo que se debe, cuándo, el extracto, la barra, los círculos y el historial', (tester) async {
      repo.onMovements = (_) async => [
        const CardMovement(
          kind: CardMovementKind.purchase,
          id: 'c1',
          date: '2026-11-20',
          amount: 360000,
          description: 'Nevera',
          installments: 6,
        ),
        const CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 100000),
        const CardMovement(kind: CardMovementKind.adjustment, id: 'a1', date: '2026-11-10', amount: -34000),
      ];
      await _pump(tester, route: Routes.card('t2'));
      expect(find.text('Amex ••1005 · Lo que debes'), findsOneWidget);
      expect(find.text(_m(616000)), findsOneWidget);
      expect(find.text('Se paga en 2 días'), findsOneWidget);
      expect(find.text('Vence pronto (01/27) · pide la nueva al banco'), findsOneWidget);
      expect(find.text('Total del extracto ${_m(650000)} · vence el 25 nov'), findsOneWidget);
      expect(find.bySemanticsLabel('Uso de Amex Gold ••1005'), findsOneWidget);
      expect(find.text('Compras y pagos'), findsOneWidget);
      expect(find.text('Nevera'), findsOneWidget);
      expect(find.textContaining('a 6 cuotas*'), findsOneWidget);
      expect(find.text('* Los intereses los calcula tu banco a la fecha de corte.'), findsOneWidget);
      expect(find.text('Pago'), findsOneWidget);
      expect(find.text('−${_m(100000)}'), findsOneWidget);
      expect(find.text('Ajuste con el banco −${_m(34000)}'), findsOneWidget);
      // Solo los pagos se eliminan.
      expect(find.text('Eliminar pago'), findsOneWidget);

      await _tap(tester, find.bySemanticsLabel('Anotar'));
      expect(find.text('ANOTAR t2'), findsOneWidget);
    });

    testWidgets('error 500 sin datos: el mensaje y «Reintentar», sin inventar la tarjeta', (tester) async {
      var fail = true;
      repo.onGet = (_) async {
        if (fail) throw const ApiException(code: 'INTERNAL', status: 500, serverMessage: 'Error interno');
        return _visa;
      };
      await _pump(tester, route: Routes.card('t1'));
      expect(find.text('Error interno'), findsOneWidget);
      expect(find.textContaining('Lo que debes'), findsNothing);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Visa ••4242 · Lo que debes'), findsOneWidget);
    });

    testWidgets('datos viejos si la recarga falla: sigue lo último con el aviso y «Reintentar»', (
      tester,
    ) async {
      await _pump(tester, route: Routes.card('t1'));
      repo.onGet = (_) async => throw const ApiException(code: ApiCodes.network);
      final container = ProviderScope.containerOf(tester.element(find.byType(CardDetailScreen)));
      container.invalidate(cardDetailProvider);
      await tester.pumpAndSettle();
      expect(find.text('Visa ••4242 · Lo que debes'), findsOneWidget);
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsOneWidget);
      repo.onGet = (_) async => _visa;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsNothing);
    });

    testWidgets('sin deuda, «atrasada» NO dice «Pago atrasado» (se aparta de la web)', (tester) async {
      repo.onGet = (_) async =>
          creditCard(id: 't1', used: 0, daysToPayment: -3, nextPaymentDate: '2026-11-20');
      await _pump(tester, route: Routes.card('t1'));
      expect(find.textContaining('Pago atrasado'), findsNothing);
      expect(find.text('Aún no hay movimientos.'), findsOneWidget);
    });

    testWidgets('con deuda y atrasada: el estado va escrito, no solo en color', (tester) async {
      repo.onGet = (_) async =>
          creditCard(id: 't1', used: 10, daysToPayment: -3, nextPaymentDate: '2026-11-20');
      await _pump(tester, route: Routes.card('t1'));
      expect(find.text('Pago atrasado desde el 20 nov'), findsOneWidget);
    });

    testWidgets('404: «Tarjeta no encontrada» con «Reintentar» y «Volver» a la lista', (tester) async {
      repo.onGet = (_) async =>
          throw const ApiException(code: 'NOT_FOUND', status: 404, serverMessage: 'Tarjeta no encontrada');
      final router = await _pump(tester, route: Routes.card('x'));
      expect(find.text('Tarjeta no encontrada'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      router.go(Routes.card('x'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Volver').last);
      expect(_location(router), Routes.cards);
    });

    testWidgets('eliminar con confirmación EN LÍNEA y vuelve a la lista', (tester) async {
      final router = await _pump(tester);
      unawaited(router.push(Routes.card('t1')));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Eliminar tarjeta'));
      expect(find.text('¿Eliminar esta tarjeta? Las compras se quedan en tu historial.'), findsOneWidget);
      await _tap(tester, find.text('Cancelar'));
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      await _tap(tester, find.text('Eliminar tarjeta'));
      await _tap(tester, find.text('Sí, eliminar'));
      expect(repo.calls, contains('delete t1'));
      expect(find.text('Debes en total'), findsOneWidget, reason: 'volvió a la lista');
    });

    testWidgets('eliminar un pago: confirmación en línea, DELETE y «Pago eliminado.»', (tester) async {
      repo.onMovements = (_) async => [
        const CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 100000),
      ];
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.text('Eliminar pago'));
      expect(find.text('¿Eliminar este pago? Lo usado vuelve a subir.'), findsOneWidget);
      await _tap(tester, find.text('Sí, eliminar'));
      expect(repo.calls, contains('deletePayment t1 p1'));
      expect(find.text('Pago eliminado.'), findsOneWidget);
    });

    testWidgets('el aviso de la acción anterior no sigue ahí al volver de «Anotar» (se vio en el emulador)', (
      tester,
    ) async {
      repo.onMovements = (_) async => [
        const CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 100000),
      ];
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.text('Eliminar pago'));
      await _tap(tester, find.text('Sí, eliminar'));
      expect(find.text('Pago eliminado.'), findsOneWidget);
      await _tap(tester, find.text('Anotar'));
      expect(find.text('ANOTAR t1'), findsOneWidget);
      GoRouter.of(tester.element(find.text('ANOTAR t1'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Visa ••4242 · Lo que debes'), findsOneWidget);
      expect(find.text('Pago eliminado.'), findsNothing);
    });

    testWidgets('si la lista cambia con «Eliminar pago» abierto, se borra ESE pago y no el de al lado', (
      tester,
    ) async {
      const p1 = CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 100000);
      const p2 = CardMovement(kind: CardMovementKind.payment, id: 'p2', date: '2026-11-10', amount: 70000);
      repo.onMovements = (_) async => [p1, p2];
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.text('Eliminar pago').last);
      // Entra una compra arriba (jalar para recargar, volver de Anotar, otro pago…).
      repo.onMovements = (_) async => [
        const CardMovement(kind: CardMovementKind.purchase, id: 'c1', date: '2026-11-22', amount: 5000),
        p1,
        p2,
      ];
      final container = ProviderScope.containerOf(tester.element(find.byType(CardDetailScreen)));
      container.invalidate(cardDetailProvider);
      await tester.pumpAndSettle();
      expect(find.text(_m(5000)), findsOneWidget, reason: 'llegó la compra nueva');
      expect(find.text('Sí, eliminar'), findsOneWidget);
      await _tap(tester, find.text('Sí, eliminar'));
      expect(repo.calls.where((c) => c.startsWith('deletePayment')), ['deletePayment t1 p2']);
    });

    testWidgets('la confirmación se anuncia y sus botones miden al menos 48 de alto', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.text('Eliminar tarjeta'));
      final question = find.text('¿Eliminar esta tarjeta? Las compras se quedan en tu historial.');
      expect(tester.getSemantics(question), isSemantics(isLiveRegion: true));
      for (final label in ['Sí, eliminar', 'Cancelar']) {
        final button = find.ancestor(of: find.text(label), matching: find.byType(RindeButton));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48), reason: label);
      }
      handle.dispose();
    });

    testWidgets('pago en duda sin confirmar: la hoja se cierra y el aviso queda sobre el historial', (
      tester,
    ) async {
      repo.onMovements = (_) async => [
        const CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 100000),
      ];
      var reads = 0;
      final firstRead = repo.onMovements;
      repo.onMovements = (id) {
        // La foto previa sale; la relectura tras la duda no.
        if (++reads > 2) throw const ApiException(code: ApiCodes.network);
        return firstRead(id);
      };
      repo.onPay = (_, _, _) async => throw const ApiException(code: ApiCodes.timeout);
      await _pump(tester, route: Routes.card('t2'));
      await _tap(tester, find.bySemanticsLabel('Abonar'));
      await _tap(tester, find.text('Registrar pago'));
      expect(
        find.byType(PayCardSheet),
        findsNothing,
        reason: '«Registrar pago» no queda a mano para repetir',
      );
      expect(
        find.text('No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.'),
        findsOneWidget,
      );
      expect(find.text('Pago registrado.'), findsNothing);
      expect(repo.calls.where((c) => c.startsWith('pay')), hasLength(1));
    });

    testWidgets('«Anotar» vuelve a pedir la lista de tarjetas: la de Anotar puede ser vieja', (tester) async {
      final router = await _pump(tester);
      unawaited(router.push(Routes.card('t1')));
      await tester.pumpAndSettle();
      final lists = repo.calls.where((c) => c == 'list').length;
      await _tap(tester, find.bySemanticsLabel('Anotar'));
      expect(find.text('ANOTAR t1'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'list').length, lists + 1);
    });

    testWidgets('«Abonar»: sugiere el extracto, la moneda del usuario, y «Pago registrado.»', (tester) async {
      await _pump(tester, route: Routes.card('t2'));
      await _tap(tester, find.bySemanticsLabel('Abonar'));
      expect(find.text('Ya pagué'), findsOneWidget);
      // TEXTO ajustado: la web lo deja fijo en COP.
      expect(find.text('Monto pagado (COP)'), findsOneWidget);
      expect(find.text('650.000'), findsOneWidget, reason: 'statementTotal ?? used');
      await _tap(tester, find.text('Registrar pago'));
      expect(repo.bodies.last, {'amount': 650000, 'date': '2026-11-23'});
      expect(find.text('Pago registrado.'), findsOneWidget);
    });

    testWidgets('al volver a entrar se pide otra vez, con la carga: «Abonar» no sugiere lo ya pagado', (
      tester,
    ) async {
      final router = await _pump(tester, route: Routes.card('t2'));
      router.pop();
      await tester.pumpAndSettle();
      // Desde la web se pagaron 600.000 del extracto de la Amex.
      final next = Completer<CreditCard>();
      repo.onGet = (_) => next.future;
      unawaited(router.push(Routes.card('t2')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.calls.where((c) => c == 'get t2'), hasLength(2));
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      expect(find.bySemanticsLabel('Abonar'), findsNothing);
      next.complete(
        creditCard(
          id: 't2',
          network: 'amex',
          last4: '1005',
          limit: 3000000,
          used: 16000,
          statementTotal: 50000,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.bySemanticsLabel('Abonar'));
      expect(find.text('50.000'), findsOneWidget);
      expect(find.text('650.000'), findsNothing);
    });

    testWidgets('«Abonar» con 0: «El pago debe ser mayor que 0» y no se envía', (tester) async {
      await _pump(tester, route: Routes.card('t2'));
      await _tap(tester, find.bySemanticsLabel('Abonar'));
      await tester.enterText(
        find.descendant(of: find.byType(RindeMoneyField), matching: find.byType(TextField)),
        '0',
      );
      await _tap(tester, find.text('Registrar pago'));
      expect(find.text('El pago debe ser mayor que 0'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('pay')), isEmpty);
    });

    testWidgets('«Actualizar saldo»: vista previa del cargo, opcionales omitidos y el aviso', (tester) async {
      repo.onSync = (_, _) async => 34000;
      await _pump(tester, route: Routes.card('t2'));
      await _tap(tester, find.bySemanticsLabel('Actualizar saldo'));
      expect(find.text('Actualizar con el banco'), findsOneWidget);
      final available = find.descendant(
        of: find.byType(RindeMoneyField).first,
        matching: find.byType(TextField),
      );
      await tester.enterText(available, '2350000');
      await tester.pumpAndSettle();
      expect(find.text('Se registrará un gasto de ${_m(34000)} en Cargos del banco.'), findsOneWidget);
      await tester.enterText(available, '2400000');
      await tester.pumpAndSettle();
      expect(find.text('Se corregirá el cupo sin registrar gasto.'), findsOneWidget);
      await _tap(tester, find.text('Actualizar'));
      expect(repo.bodies.last, {'available': 2400000});
      expect(find.text('Se registró un gasto de ${_m(34000)} en Cargos del banco.'), findsOneWidget);
    });

    testWidgets('«Actualizar saldo»: la X de la fecha límite dice que la quita, no «Cancelar»', (
      tester,
    ) async {
      await _pump(tester, route: Routes.card('t2'));
      await _tap(tester, find.bySemanticsLabel('Actualizar saldo'));
      await _tap(tester, find.descendant(of: find.byType(BankSyncSheet), matching: find.text('—')));
      await _tap(tester, find.text('OK'));
      expect(find.byTooltip('Cancelar'), findsNothing, reason: 'la hoja no se cierra con ella');
      await _tap(tester, find.byTooltip('Quitar Fecha límite (opcional)'));
      expect(find.descendant(of: find.byType(BankSyncSheet), matching: find.text('—')), findsOneWidget);
      expect(find.text('Actualizar con el banco'), findsOneWidget, reason: 'la hoja sigue abierta');
    });

    testWidgets('«Actualizar saldo» con montos ocultos: la vista previa y el aviso sin cifras', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      repo.onSync = (_, _) async => 34000;
      await _pump(tester, route: Routes.card('t2'), hidden: true);
      await _tap(tester, find.bySemanticsLabel('Actualizar saldo'));
      await tester.enterText(
        find.descendant(of: find.byType(RindeMoneyField).first, matching: find.byType(TextField)),
        '2350000',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('34.000'), findsNothing);
      await _tap(tester, find.text('Actualizar'));
      expect(find.textContaining('34.000'), findsNothing);
      final mask = '${_cop.prefix}••••••${_cop.suffix}';
      expect(find.text('Se registró un gasto de $mask en Cargos del banco.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Se registró un gasto de Monto oculto')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('«Editar»: sin «Cupo disponible hoy», manda solo lo cambiado y «Cambios guardados.»', (
      tester,
    ) async {
      repo.onUpdate = (id, body) async => _visa;
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.bySemanticsLabel('Editar'));
      expect(find.text('Editar tarjeta'), findsOneWidget);
      expect(find.text('Cupo disponible hoy'), findsNothing);
      await tester.enterText(_field('Día de pago'), '20');
      await _tap(tester, find.text('Guardar cambios'));
      expect(repo.bodies.last, {'paymentDay': 20});
      expect(find.text('Cambios guardados.'), findsOneWidget);
    });

    testWidgets('«Editar» con el cupo menor que lo usado: el 422 va a «Cupo total» y la hoja sigue', (
      tester,
    ) async {
      repo.onUpdate = (_, _) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        serverMessage: 'Datos inválidos',
        fields: {'limit': 'No puede ser menor que lo que ya usas'},
      );
      await _pump(tester, route: Routes.card('t1'));
      await _tap(tester, find.bySemanticsLabel('Editar'));
      await tester.enterText(
        find.descendant(of: find.byType(RindeMoneyField).first, matching: find.byType(TextField)),
        '1000',
      );
      await _tap(tester, find.text('Guardar cambios'));
      expect(
        tester.widget<RindeMoneyField>(find.byType(RindeMoneyField).first).errorText,
        'No puede ser menor que lo que ya usas',
      );
      expect(find.text('Editar tarjeta'), findsOneWidget, reason: 'la hoja no se cierra');
    });
  });

  group('agregar', () {
    testWidgets('las validaciones de la web van al campo; el 409 de últimos 4 también', (tester) async {
      repo.onCreate = (_) async => throw const ApiException(
        code: 'CARD_EXISTS',
        status: 409,
        serverMessage: 'Ya tienes una tarjeta con esos últimos 4 dígitos',
      );
      await _pump(tester);
      await _tap(tester, find.bySemanticsLabel('Agregar tarjeta'));
      // El título visible de la web (Cards.jsx:199); «Nueva tarjeta» es solo su aria-label.
      expect(find.text('Nueva tarjeta'), findsNothing);
      expect(
        tester.getSemantics(
          find.descendant(of: find.byType(CardSheet), matching: find.text('Agregar tarjeta')).first,
        ),
        isSemantics(isHeader: true, label: 'Agregar tarjeta'),
      );
      await _tap(tester, find.text('Agregar tarjeta').last);
      expect(find.text('Escribe exactamente 4 dígitos'), findsOneWidget);
      expect(find.text('Ingresa un monto'), findsNWidgets(2));
      expect(find.text('Ingresa un día'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'create'), isEmpty);
      // El foco va al primer campo con error.
      expect(tester.widget<TextField>(_field('Últimos 4 dígitos')).focusNode?.hasFocus, isTrue);

      await tester.enterText(_field('Últimos 4 dígitos'), '4242');
      final money = find.descendant(of: find.byType(RindeMoneyField), matching: find.byType(TextField));
      await tester.enterText(money.at(0), '2000000');
      await tester.enterText(money.at(1), '1500000');
      await tester.enterText(_field('Día de pago'), '15');
      await tester.enterText(_field('Vence (MM/AA, opcional)'), '0327');
      await tester.pumpAndSettle();
      expect(find.text('03/27'), findsWidgets, reason: 'la barra se pone sola');
      await _tap(tester, find.text('Agregar tarjeta').last);
      expect(repo.bodies.last, {
        'network': 'visa',
        'tier': 'clasica',
        'last4': '4242',
        'limit': 2000000,
        'available': 1500000,
        'paymentDay': 15,
        'expiryMonth': 3,
        'expiryYear': 2027,
      });
      // El 409 va AL CAMPO (en la web sale abajo).
      final last4 = tester.widget<RindeTextField>(
        find.ancestor(of: find.text('Últimos 4 dígitos'), matching: find.byType(RindeTextField)).first,
      );
      expect(last4.serverError, 'Ya tienes una tarjeta con esos últimos 4 dígitos');
    });

    testWidgets('los últimos 4 y el vencimiento van sin autollenado ni sugerencias', (tester) async {
      await _pump(tester);
      await _tap(tester, find.bySemanticsLabel('Agregar tarjeta'));
      for (final label in ['Últimos 4 dígitos', 'Vence (MM/AA, opcional)']) {
        final field = tester.widget<TextField>(_field(label));
        expect(field.autofillHints, anyOf(isNull, isEmpty), reason: label);
        expect(field.autocorrect, isFalse, reason: label);
        expect(field.enableSuggestions, isFalse, reason: label);
      }
    });
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho, letra al doble, tema $name: lista, detalle y hojas sin desbordes', (
      tester,
    ) async {
      final long = 'Una tarjeta con nombre de 40 caracteres';
      repo.onList = () async => [
        for (var i = 0; i < 10; i++)
          creditCard(
            id: 'c$i',
            name: long.padRight(40, 'x'),
            network: const ['visa', 'mastercard', 'amex', 'otra'][i % 4],
            tier: i % 4 == 2 ? 'gold' : 'clasica',
            last4: '${1000 + i}',
            limit: 9999999999,
            used: 9999999999,
            daysToPayment: i - 3,
            expiry: {'label': '01/27', 'expired': i.isEven, 'soon': true},
          ),
      ];
      repo.onGet = (_) async => creditCard(
        id: 'c1',
        name: long,
        limit: 9999999999,
        used: 9999999999,
        statementTotal: 9999999999,
        statementDueDate: '2026-11-30',
        expiry: {'label': '01/27', 'expired': true, 'soon': false},
      );
      // El historial con montos de 10 dígitos, cuotas y un pago (con su «Eliminar pago»).
      repo.onMovements = (_) async => [
        CardMovement(
          kind: CardMovementKind.purchase,
          id: 'm1',
          date: '2026-11-20',
          amount: 9999999999,
          description: long,
          installments: 48,
        ),
        const CardMovement(kind: CardMovementKind.payment, id: 'p1', date: '2026-11-18', amount: 9999999999),
        const CardMovement(
          kind: CardMovementKind.adjustment,
          id: 'a1',
          date: '2026-11-10',
          amount: -9999999999,
        ),
      ];
      await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.bySemanticsLabel('Agregar tarjeta'));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Más detalles'));
      expect(tester.takeException(), isNull, reason: 'Más detalles');
      await _tap(tester, find.text('Cancelar'));

      await _pump(tester, route: Routes.card('c1'), size: const Size(320, 568), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.text('Compras y pagos'), findsOneWidget);
      for (final confirm in ['Eliminar pago', 'Eliminar tarjeta']) {
        await _tap(tester, find.text(confirm));
        expect(tester.takeException(), isNull, reason: confirm);
      }
      for (final action in ['Abonar', 'Actualizar saldo', 'Editar']) {
        await _tap(tester, find.bySemanticsLabel(action));
        expect(tester.takeException(), isNull, reason: action);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    });
  }
}
