// Cuentas (bloque 5B): /app/cuentas con «Me deben» | «Debo», las tarjetas de cada cuenta, las
// saldadas, las hojas (nueva/editar en dos pasos, abono y saldar), todos los estados, montos ocultos
// (también para el lector), en/pt con USD/BRL y 320 de ancho con la letra al doble, claro y oscuro.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/semantics.dart' show SemanticsAction;
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
import 'package:rinde_mobile/design/tokens/rinde_colors.dart';
import 'package:rinde_mobile/design/widgets/rinde_line.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_text_field.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/debts/application/debts_providers.dart';
import 'package:rinde_mobile/features/debts/data/debt_models.dart';
import 'package:rinde_mobile/features/debts/data/debts_repository.dart';
import 'package:rinde_mobile/features/debts/presentation/debts_screen.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_card.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_date_field.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_payment_sheet.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/debt_sheet.dart';
import 'package:rinde_mobile/features/debts/presentation/widgets/settle_sheet.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';

import '../../support/debt_fixtures.dart';
import '../../support/fake_debts_repository.dart';
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

late FakeDebtsRepository repo;

/// «Laura Gómez» me debe 60.000 de una vez, para el 30 nov; «Prueba QA» (QA): le debo 300.000 en 3
/// cuotas con un abono de 100.000; «Mamá», saldada con «Ya me pagó todo»; «Juan», saldada por un abono.
final _laura = onceJson(id: 'd2', person: 'Laura Gómez', note: 'le presté para el bus');
final _qa = debtJson();
final _mama = onceJson(
  id: 'd3',
  person: 'Mamá',
  amount: 50000,
  settledAt: '2026-11-20T10:00:00Z',
  transactionId: 'm9',
);
final _juan = onceJson(id: 'd4', person: 'Juan', amount: 10000, settledAt: '2026-11-19T10:00:00Z');

Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

Future<GoRouter> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  bool hidden = false,
  Region region = kDefaultRegion,
  bool animate = false,
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
      GoRoute(path: Routes.debts, builder: (_, _) => const DebtsScreen()),
      GoRoute(
        path: '/app/transacciones/:id',
        builder: (_, state) => Scaffold(body: Text('MOVIMIENTO ${state.pathParameters['id']}')),
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
        debtsRepositoryProvider.overrideWithValue(repo),
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
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: !animate),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(Routes.debts));
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

Finder _money(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(RindeMoneyField)).first,
  matching: find.byType(TextField),
);

/// ¿El campo tiene el foco? (el del EditableText que lleva adentro).
bool _focused(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

void main() {
  setUp(() {
    repo = FakeDebtsRepository();
    repo.onList = () async => debtsOf([_qa, _laura, _mama, _juan]);
  });

  group('lista', () {
    testWidgets('las pestañas con su total y su cuenta, y la tarjeta de una cuenta de una vez', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Cuentas'), findsOneWidget);
      expect(find.text('Quién te debe y a quién le debes.'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
      expect(find.text('Me deben · 1'), findsOneWidget);
      expect(find.text('Debo · 1'), findsOneWidget);
      expect(find.text(_m(60000)), findsNWidgets(2), reason: 'el total de la pestaña y lo pendiente');
      expect(find.text(_m(200000)), findsOneWidget);
      // Laura (me debe, de una vez).
      expect(find.text('LG'), findsOneWidget);
      expect(find.text('Laura Gómez'), findsOneWidget);
      expect(find.text('le presté para el bus'), findsOneWidget);
      expect(find.text('TE FALTA RECIBIR'), findsOneWidget);
      expect(find.text('Pagado ${_m(0)} de ${_m(60000)}'), findsOneWidget);
      expect(find.text('${_m(60000)} · vence en 7 días'), findsOneWidget);
      expect(find.text('Registrar abono'), findsOneWidget);
      expect(find.text('Ya me pagó todo'), findsOneWidget);
      expect(find.byTooltip('Editar la cuenta de Laura Gómez'), findsOneWidget);
      // Las saldadas de este lado, con «ver el movimiento» SOLO si se saldó con movimiento.
      expect(find.text('Saldadas'), findsOneWidget);
      expect(find.text('Mamá'), findsOneWidget);
      expect(find.text('Juan'), findsOneWidget);
      expect(find.text('Saldada'), findsNWidgets(2));
      expect(find.text('ver el movimiento'), findsOneWidget);
      // Nada del otro lado.
      expect(find.text('Prueba QA'), findsNothing);
      // Lo dibujado tiene su tamaño: el avatar de 44 y las dos pestañas, iguales y de al menos 64.
      expect(tester.getSize(find.byType(DebtAvatar).first), const Size(44, 44));
      final owed = tester.getSize(
        find.ancestor(of: find.text('Me deben · 1'), matching: find.byType(InkWell)).first,
      );
      final owe = tester.getSize(
        find.ancestor(of: find.text('Debo · 1'), matching: find.byType(InkWell)).first,
      );
      expect(owed.height, greaterThanOrEqualTo(64));
      expect(owed, owe);
    });

    testWidgets('«Debo»: la cuenta en cuotas con la próxima cuota, el avance y el último abono', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      expect(find.text('Prueba QA'), findsOneWidget);
      expect(find.text('TE FALTA PAGAR'), findsOneWidget);
      expect(find.text(_m(200000)), findsNWidgets(2));
      expect(find.text('Pagado ${_m(100000)} de ${_m(300000)} · 1 de 3 cuotas'), findsOneWidget);
      expect(find.text('Cuota 2: ${_m(100000)} · vence el 1 ene 2027'), findsOneWidget);
      expect(find.text('Último abono: ${_m(100000)} el 23 nov'), findsOneWidget);
      expect(find.text('Ya pagué todo'), findsOneWidget);
      // Sin saldadas de este lado.
      expect(find.text('Saldadas'), findsNothing);
    });

    testWidgets('la línea de avance se ve: el relleno ocupa lo pagado y tiene alto', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      final line = find.byType(RindeLine);
      final parts = find.descendant(of: line, matching: find.byType(Container));
      final rail = tester.getSize(parts.at(0));
      final fill = tester.getSize(parts.at(1));
      // 100.000 de 300.000.
      expect(rail.height, greaterThan(0));
      expect(fill.height, rail.height);
      expect(fill.width, closeTo(rail.width / 3, 0.5));
    });

    testWidgets('la cuota vencida va en rojo CON texto («venció hace 3 días»)', (tester) async {
      repo.onList = () async => debtsOf([onceJson(id: 'v', person: 'Pedro', dueDate: '2026-11-20')]);
      await _pump(tester);
      final late = find.text('${_m(60000)} · venció hace 3 días');
      expect(late, findsOneWidget);
      final style = tester.widget<Text>(late).style!;
      expect(style.color, RindeTheme.light.extension<RindePalette>()!.negative);
    });

    testWidgets('«ver el movimiento» lleva al movimiento; el aviso anterior no sigue al volver', (
      tester,
    ) async {
      repo.onPay = (_, _, _, _) async => throw const ApiException(
        code: 'ALREADY_SETTLED',
        status: 409,
        serverMessage: 'Esta cuenta ya está saldada',
      );
      await _pump(tester);
      await _tap(tester, find.text('Registrar abono'));
      await _tap(
        tester,
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      expect(find.text('Esta cuenta ya está saldada'), findsOneWidget);
      await _tap(tester, find.text('ver el movimiento'));
      expect(find.text('MOVIMIENTO m9'), findsOneWidget);
      GoRouter.of(tester.element(find.text('MOVIMIENTO m9'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Laura Gómez'), findsOneWidget);
      expect(find.text('Esta cuenta ya está saldada'), findsNothing);
    });

    testWidgets('vacío por lado: la invitación y «Agregar»; «Todo está saldado.» si solo hay saldadas', (
      tester,
    ) async {
      repo.onList = () async => debtsOf([_mama]);
      await _pump(tester);
      expect(find.text('Todo está saldado.'), findsOneWidget);
      await _tap(tester, find.text('Debo'));
      expect(
        find.text('No le debes a nadie. Anota aquí lo que te prestan para no olvidarlo.'),
        findsOneWidget,
      );
      expect(find.text('Agregar'), findsNWidgets(2), reason: 'el del encabezado y el del vacío');
      await _tap(tester, find.text('Agregar').last);
      expect(find.text('¿A quién le debes?'), findsOneWidget, reason: 'abre con el lado de la pestaña');

      repo.onList = () async => debtsOf([]);
      await _pump(tester);
      expect(find.text('Nadie te debe nada. Anota aquí cuando le prestes plata a alguien.'), findsOneWidget);
    });

    testWidgets('cargando: el esqueleto, sin cifras', (tester) async {
      repo.onList = () => Completer<DebtsList>().future;
      await _pump(tester);
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      expect(find.textContaining('Me deben'), findsNothing);
    });

    testWidgets('error sin datos: el mensaje y «Reintentar», que vuelve a pedir', (tester) async {
      var fail = true;
      repo.onList = () async {
        if (fail) throw const ApiException(code: ApiCodes.network);
        return debtsOf([_laura]);
      };
      await _pump(tester);
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.text('Me deben · 1'), findsNothing);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Laura Gómez'), findsOneWidget);
    });

    testWidgets('datos viejos: si la recarga falla, sigue lo último con el aviso y «Reintentar»', (
      tester,
    ) async {
      await _pump(tester);
      repo.onList = () async => throw const ApiException(code: ApiCodes.network);
      final container = ProviderScope.containerOf(tester.element(find.byType(DebtsScreen)));
      container.invalidate(debtsProvider);
      await tester.pumpAndSettle();
      expect(find.text('Laura Gómez'), findsOneWidget);
      expect(find.text(ApiMessages.network), findsOneWidget);
      expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      // Lo que se ve ya no es verdad: nada que dependa de esos montos se puede tocar (lección de 5A).
      await tester.tap(find.text('Registrar abono'));
      await tester.tap(find.text('Ya me pagó todo'));
      await tester.tap(find.byTooltip('Editar la cuenta de Laura Gómez'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(DebtPaymentSheet), findsNothing);
      expect(find.byType(DebtSheet), findsNothing);
      expect(find.text('Agregar'), findsOneWidget);
      repo.onList = () async => debtsOf([_laura]);
      await _tap(tester, find.text('Reintentar'));
      await _tap(tester, find.text('Registrar abono'));
      expect(find.byType(DebtPaymentSheet), findsOneWidget);
    });

    testWidgets(
      'al volver a entrar se pide otra vez, con la carga: no propone la cuota ya pagada en la web',
      (tester) async {
        // Antes: le debo 300.000 en 3 cuotas sin abonos; la app propondría la cuota 1.
        repo.onList = () async => debtsOf([
          debtJson(
            dueDate: '2026-12-01',
            paid: 0,
            paidInstallments: 0,
            nextInstallment: const {'number': 1, 'date': '2026-12-01', 'amount': 100000},
            payments: const [],
          ),
        ]);
        final router = await _pump(tester);
        router.pop();
        await tester.pumpAndSettle();
        // Desde la web se pagó la cuota 1: el servidor ya va en la 2.
        final next = Completer<DebtsList>();
        repo.onList = () => next.future;
        unawaited(router.push(Routes.debts));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(repo.count('list'), 2);
        expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
        expect(find.textContaining('Debo'), findsNothing);
        next.complete(debtsOf([_qa]));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Debo · 1'));
        expect(find.text('Pagado ${_m(100000)} de ${_m(300000)} · 1 de 3 cuotas'), findsOneWidget);
        await _tap(tester, find.text('Registrar abono'));
        expect(find.textContaining('cuota 2 de 3'), findsOneWidget);
      },
    );

    testWidgets('sin pantalla anterior, atrás va a Planear (backPath de la web)', (tester) async {
      final router = await _pump(tester);
      router.go(Routes.debts);
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('PLANEAR'), findsOneWidget);
    });

    testWidgets('montos ocultos: ni un dígito de los montos, y el lector oye «Monto oculto»', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: true);
      for (final digits in ['60.000', '200.000', '100.000', '50.000', '10.000']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      expect(find.text('Laura Gómez'), findsOneWidget);
      expect(find.textContaining('vence en 7 días'), findsOneWidget, reason: 'las fechas siguen a la vista');
      expect(find.bySemanticsLabel(RegExp('Me deben · 1, Monto oculto')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Pagado Monto oculto de Monto oculto')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'\$ ••••••')),
        findsNothing,
        reason: 'el lector no lee la máscara',
      );
      await _tap(tester, find.text('Debo · 1'));
      expect(find.bySemanticsLabel(RegExp('Cuota 2: Monto oculto · vence el 1 ene 2027')), findsOneWidget);
      handle.dispose();
    });

    for (final (region, owed, owe, left) in [
      (
        const Region(country: 'US', currency: 'USD', language: 'en'),
        "I'm owed · 1",
        'I owe · 1',
        'LEFT TO RECEIVE',
      ),
      (
        const Region(country: 'BR', currency: 'BRL', language: 'pt'),
        'Me devem · 1',
        'Devo · 1',
        'FALTA RECEBER',
      ),
    ]) {
      testWidgets('en ${region.language} con ${region.currency}', (tester) async {
        await _pump(tester, region: region);
        expect(find.text(owed), findsOneWidget);
        expect(find.text(owe), findsOneWidget);
        expect(find.text(left), findsOneWidget);
        expect(find.text(formatFor(region).money(200000)), findsOneWidget);
        await _tap(tester, find.text(region.language == 'en' ? 'Add' : 'Adicionar'));
        expect(find.text(region.language == 'en' ? 'How much? (USD)' : 'Quanto? (BRL)'), findsOneWidget);
      });

      testWidgets('montos ocultos en ${region.currency}: la máscara de su moneda', (tester) async {
        final f = formatFor(region);
        await _pump(tester, hidden: true, region: region);
        expect(find.textContaining('${f.prefix}••••••${f.suffix}'), findsWidgets);
        expect(find.textContaining(f.money(200000)), findsNothing);
      });
    }

    testWidgets('en inglés, «· due Jan 1 2027» con el mes en mayúscula (salía «due jan» en el emulador)', (
      tester,
    ) async {
      await _pump(
        tester,
        region: const Region(country: 'US', currency: 'USD', language: 'en'),
      );
      await _tap(tester, find.text('I owe · 1'));
      expect(find.textContaining('· due Jan 1 2027', findRichText: true), findsOneWidget);
      expect(find.textContaining('due jan', findRichText: true), findsNothing);
    });
  });

  group('nueva cuenta', () {
    testWidgets('dos pasos; abre del lado de la pestaña; préstamo hoy; POST sin reminder; salta de pestaña', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      expect(find.text('Nueva cuenta'), findsOneWidget);
      expect(find.bySemanticsLabel('Paso 1 de 2 · Quién y cuánto'), findsOneWidget);
      expect(find.text('PASO 1 DE 2 · QUIÉN Y CUÁNTO'), findsOneWidget);
      expect(find.text('¿Quién te debe?'), findsOneWidget);
      expect(find.text('¿Cuánto? (COP)'), findsOneWidget);
      expect(find.text('¿Cuándo le prestaste?'), findsOneWidget);
      expect(find.text('23 nov'), findsOneWidget, reason: 'la fecha del préstamo es hoy');
      // Las dos barritas del avance se ven (con alto).
      for (final i in [0, 1]) {
        expect(tester.getSize(find.byKey(ValueKey('paso-$i'))).height, 4);
        expect(tester.getSize(find.byKey(ValueKey('paso-$i'))).width, greaterThan(0));
      }
      // El lado se elige al crear: «Debo».
      await _tap(tester, find.descendant(of: find.byType(DebtSheet), matching: find.text('Debo')));
      expect(find.text('¿A quién le debes?'), findsOneWidget);
      await tester.enterText(_field('¿A quién le debes?'), '  Tío Jorge ');
      await tester.enterText(_money('¿Cuánto? (COP)'), '120000');
      await tester.enterText(_field('Nota (opcional)'), 'el almuerzo');
      await _tap(tester, find.text('Siguiente'));
      expect(find.text('PASO 2 DE 2 · CÓMO SE PAGA'), findsOneWidget);
      expect(find.text('¿Para cuándo? (opcional)'), findsOneWidget);
      expect(
        find.text('Esto no cambia lo que tienes en Mi plata hasta que registres un abono.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Guardar cuenta'));
      expect(repo.bodies.single, {
        'kind': 'payable',
        'person': 'Tío Jorge',
        'amount': 120000,
        'loanDate': '2026-11-23',
        'dueDate': null,
        'installments': null,
        'frequency': null,
        'note': 'el almuerzo',
      });
      expect(find.byType(DebtSheet), findsNothing);
      // La pestaña salta al lado de la cuenta nueva (Debts.jsx:326-330).
      expect(find.text('Prueba QA'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('«Siguiente» revisa solo el paso 1: los mensajes de la web y el foco en el primero', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      await _tap(tester, find.text('Siguiente'));
      expect(find.text('Escribe el nombre'), findsOneWidget);
      expect(find.text('Ingresa un monto'), findsOneWidget);
      expect(find.text('PASO 1 DE 2 · QUIÉN Y CUÁNTO'), findsOneWidget);
      expect(_focused(tester, _field('¿Quién te debe?')), isTrue);
      expect(repo.bodies, isEmpty);
    });

    testWidgets('en cuotas: de 2 a 60, la primera cuota y la vista previa', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      await tester.enterText(_field('¿Quién te debe?'), 'Laura');
      await tester.enterText(_money('¿Cuánto? (COP)'), '90000');
      await _tap(tester, find.text('Siguiente'));
      await _tap(tester, find.text('En cuotas'));
      expect(find.text('¿Cuántas cuotas?'), findsOneWidget);
      expect(find.text('Cada mes'), findsOneWidget);
      await tester.enterText(_field('¿Cuántas cuotas?'), '1');
      await _tap(tester, find.text('Guardar cuenta'));
      expect(find.text('De 2 a 60 cuotas'), findsOneWidget);
      expect(find.text('Elige la fecha de la primera cuota'), findsOneWidget);
      expect(repo.bodies, isEmpty);
    });

    testWidgets('un 422 vuelve al paso de su primer campo con error y le pone el foco', (tester) async {
      repo.onCreate = (_) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        serverMessage: 'Datos inválidos',
        fields: {'person': 'Debe tener entre 1 y 60 caracteres'},
      );
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      await tester.enterText(_field('¿Quién te debe?'), 'Laura');
      await tester.enterText(_money('¿Cuánto? (COP)'), '1000');
      await _tap(tester, find.text('Siguiente'));
      await _tap(tester, find.text('Guardar cuenta'));
      expect(find.text('PASO 1 DE 2 · QUIÉN Y CUÁNTO'), findsOneWidget);
      expect(find.text('Debe tener entre 1 y 60 caracteres'), findsOneWidget);
      expect(_focused(tester, _field('¿Quién te debe?')), isTrue);
    });

    testWidgets('un 422 de un campo sin lugar en la hoja (kind) sale en el aviso general', (tester) async {
      repo.onCreate = (_) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        serverMessage: 'Datos inválidos',
        fields: {'kind': 'Debe ser: receivable, payable'},
      );
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      await tester.enterText(_field('¿Quién te debe?'), 'Laura');
      await tester.enterText(_money('¿Cuánto? (COP)'), '1000');
      await _tap(tester, find.text('Siguiente'));
      await _tap(tester, find.text('Guardar cuenta'));
      expect(find.byType(DebtSheet), findsOneWidget);
      expect(find.text('Debe ser: receivable, payable'), findsOneWidget);
    });

    testWidgets('en duda sin confirmar: la hoja se cierra y queda el aviso para revisar', (tester) async {
      repo.onCreate = (_) async => throw const ApiException(
        code: ApiCodes.unconfirmed,
        serverMessage: 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.',
      );
      await _pump(tester);
      await _tap(tester, find.text('Agregar'));
      await tester.enterText(_field('¿Quién te debe?'), 'Laura');
      await tester.enterText(_money('¿Cuánto? (COP)'), '1000');
      await _tap(tester, find.text('Siguiente'));
      await _tap(tester, find.text('Guardar cuenta'));
      expect(find.byType(DebtSheet), findsNothing);
      expect(
        find.text('No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.'),
        findsOneWidget,
      );
      // Se borra con la siguiente acción.
      await _tap(tester, find.text('Agregar'));
      expect(
        find.text('No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.'),
        findsNothing,
      );
    });
  });

  group('editar', () {
    testWidgets('TRAMPA: con cuotas se precarga y se manda firstDueDate, nunca el dueDate leído', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.byTooltip('Editar la cuenta de Prueba QA'));
      expect(find.text('Editar cuenta'), findsOneWidget);
      expect(find.text('¿Quién debe?'), findsNothing, reason: 'el lado no se cambia al editar');
      await _tap(tester, find.text('Siguiente'));
      expect(find.text('1 dic'), findsOneWidget, reason: 'la primera cuota, no la próxima (1 ene)');
      expect(find.text('3 cuotas de ${_m(100000)} · la última el 1 feb 2027'), findsOneWidget);
      await _tap(tester, find.text('Guardar cambios'));
      final body = repo.bodies.single;
      expect(repo.calls, contains('update ${_qa['id']}'));
      expect(body['dueDate'], '2026-12-01');
      expect(body.containsKey('kind'), isFalse);
      expect(body.containsKey('reminder'), isFalse);
      expect((body['amount'], body['installments'], body['frequency']), (300000, 3, 'monthly'));
    });

    testWidgets('B4: el monto no puede quedar igual o por debajo de lo abonado', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.byTooltip('Editar la cuenta de Prueba QA'));
      await tester.enterText(_money('¿Cuánto? (COP)'), '100000');
      await _tap(tester, find.text('Siguiente'));
      expect(find.text('Tiene que ser mayor que lo que ya se abonó (${_m(100000)})'), findsOneWidget);
      expect(repo.bodies, isEmpty);
    });

    testWidgets('409 (ya saldada): la hoja se cierra, la lista recarga y sale el mensaje del servidor', (
      tester,
    ) async {
      repo.onUpdate = (_, _) async => throw const ApiException(
        code: 'ALREADY_SETTLED',
        status: 409,
        serverMessage: 'Esta cuenta ya está saldada',
      );
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar la cuenta de Laura Gómez'));
      await _tap(tester, find.text('Siguiente'));
      await _tap(tester, find.text('Guardar cambios'));
      expect(find.byType(DebtSheet), findsNothing);
      expect(find.text('Esta cuenta ya está saldada'), findsOneWidget);
    });

    testWidgets('«Abonos»: borrar uno con confirmación en línea; la hoja muestra la cuenta como quedó', (
      tester,
    ) async {
      repo.onDeletePayment = (_, _) async => debtOf(debtJson(paid: 0, payments: const []));
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.byTooltip('Editar la cuenta de Prueba QA'));
      expect(find.text('Abonos'), findsOneWidget);
      expect(find.text('23 nov'), findsWidgets);
      await _tap(tester, find.text('Borrar abono'));
      expect(
        find.text('¿Borrar el abono de ${_m(100000)}? También se borra el movimiento que se anotó con él.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Sí, borrar'));
      expect(repo.calls, contains('deletePayment ${_qa['id']} b4ed7bf7-78f4-4264-87b0-e92d109905f8'));
      expect(find.byType(DebtSheet), findsOneWidget, reason: 'la hoja sigue abierta, como la web');
      expect(find.text('Abonos'), findsNothing);
    });

    testWidgets('borrar un abono de una cuenta ya saldada (404): se cierra con el mensaje, no «borrado»', (
      tester,
    ) async {
      repo.onDeletePayment = (_, _) async =>
          throw const ApiException(code: 'NOT_FOUND', status: 404, serverMessage: 'Abono no encontrado');
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.byTooltip('Editar la cuenta de Prueba QA'));
      await _tap(tester, find.text('Borrar abono'));
      await _tap(tester, find.text('Sí, borrar'));
      expect(find.byType(DebtSheet), findsNothing);
      expect(find.text('Abono no encontrado'), findsOneWidget);
    });

    testWidgets('«Borrar cuenta»: confirmación en línea con el texto de la web y DELETE', (tester) async {
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar la cuenta de Laura Gómez'));
      await _tap(tester, find.text('Borrar cuenta'));
      expect(find.text('¿Borrar la cuenta de Laura Gómez? No se puede deshacer.'), findsOneWidget);
      await _tap(tester, find.text('Cancelar'));
      expect(repo.calls.where((c) => c.startsWith('delete ')), isEmpty);
      await _tap(tester, find.text('Borrar cuenta'));
      await _tap(tester, find.text('Sí, borrar'));
      expect(repo.calls, contains('delete d2'));
      expect(find.byType(DebtSheet), findsNothing);
    });

    testWidgets('guardar y borrar a la vez: la hoja se cierra una vez y la persona sigue en Cuentas', (
      tester,
    ) async {
      final put = Completer<void>();
      final del = Completer<void>();
      repo.onUpdate = (_, _) => put.future;
      repo.onDelete = (_) => del.future;
      // Con animaciones: el segundo cierre llega mientras la hoja sale.
      await _pump(tester, animate: true);
      await _tap(tester, find.byTooltip('Editar la cuenta de Laura Gómez'));
      await _tap(tester, find.text('Siguiente'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pump();
      await tester.ensureVisible(find.text('Borrar cuenta'));
      await tester.pump();
      await tester.tap(find.text('Borrar cuenta'));
      await tester.pump();
      await tester.ensureVisible(find.text('Sí, borrar'));
      await tester.pump();
      await tester.tap(find.text('Sí, borrar'));
      await tester.pump();
      expect(repo.calls.where((c) => c.startsWith('update ') || c.startsWith('delete ')), hasLength(2));
      put.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      del.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DebtsScreen), findsOneWidget);
      expect(find.byType(DebtSheet), findsNothing);
      expect(find.text('INICIO'), findsNothing);
    });

    testWidgets('borrar la cuenta y cerrar la hoja con atrás antes de que responda: sigue en Cuentas', (
      tester,
    ) async {
      final del = Completer<void>();
      repo.onDelete = (_) => del.future;
      await _pump(tester, animate: true);
      await _tap(tester, find.byTooltip('Editar la cuenta de Laura Gómez'));
      await _tap(tester, find.text('Borrar cuenta'));
      await tester.tap(find.text('Sí, borrar'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      del.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DebtsScreen), findsOneWidget);
      expect(find.text('INICIO'), findsNothing);
    });
  });

  group('abono y saldar', () {
    testWidgets('el abono propone la próxima cuota, «Todo lo que falta» y la casilla marcada', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.text('Registrar abono'));
      expect(find.byType(DebtPaymentSheet), findsOneWidget);
      expect(find.text('Le debes a Prueba QA ${_m(200000)} · cuota 2 de 3.'), findsOneWidget);
      expect(find.text('¿Cuánto pagaste?'), findsOneWidget);
      expect(tester.widget<TextField>(_money('¿Cuánto pagaste?')).controller!.text, '100.000');
      expect(find.text('¿Cuándo?'), findsOneWidget);
      expect(find.text('23 nov'), findsOneWidget, reason: 'hoy por defecto');
      expect(find.text('Anotar el gasto en Movimientos'), findsOneWidget);
      expect(find.text('Así tu saldo de hoy queda bien.'), findsOneWidget);
      await _tap(tester, find.text('Todo lo que falta (${_m(200000)})'));
      expect(tester.widget<TextField>(_money('¿Cuánto pagaste?')).controller!.text, '200.000');
      await _tap(
        tester,
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      expect(repo.bodies.single, {'amount': 200000, 'date': '2026-11-23', 'createTransaction': true});
      expect(find.byType(DebtPaymentSheet), findsNothing);
    });

    testWidgets('no pasa de lo pendiente; sin la casilla no anota el movimiento', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Registrar abono'));
      expect(find.text('Laura Gómez te debe ${_m(60000)}.'), findsOneWidget);
      expect(find.textContaining('Todo lo que falta'), findsNothing, reason: 'ya propone todo');
      await tester.enterText(_money('¿Cuánto te pagó?'), '60001');
      final save = find
          .descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono'))
          .last;
      await _tap(tester, save);
      expect(find.text('No puede pasar de lo que falta (${_m(60000)})'), findsOneWidget);
      expect(repo.bodies, isEmpty);
      await tester.enterText(_money('¿Cuánto te pagó?'), '20000');
      await _tap(tester, find.text('Anotar el ingreso en Movimientos'));
      await _tap(tester, save);
      expect(repo.bodies.single, {'amount': 20000, 'date': '2026-11-23', 'createTransaction': false});
    });

    testWidgets('abono en duda sin confirmar: la hoja se cierra y queda el aviso (no se repite a ciegas)', (
      tester,
    ) async {
      repo.onPay = (_, _, _, _) async => throw const ApiException(
        code: ApiCodes.unconfirmed,
        serverMessage: 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.',
      );
      await _pump(tester);
      await _tap(tester, find.text('Registrar abono'));
      await _tap(
        tester,
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      expect(find.byType(DebtPaymentSheet), findsNothing);
      expect(
        find.text('No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.'),
        findsOneWidget,
      );
      expect(repo.count('pay'), 1);
    });

    testWidgets('409 al abonar: se cierra y sale el mensaje del servidor', (tester) async {
      repo.onPay = (_, _, _, _) async => throw const ApiException(
        code: 'ALREADY_SETTLED',
        status: 409,
        serverMessage: 'Esta cuenta ya está saldada',
      );
      await _pump(tester);
      await _tap(tester, find.text('Registrar abono'));
      await _tap(
        tester,
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      expect(find.byType(DebtPaymentSheet), findsNothing);
      expect(find.text('Esta cuenta ya está saldada'), findsOneWidget);
    });

    testWidgets('409 al saldar (la saldaron en otro lado): se cierra y sale el mensaje del servidor', (
      tester,
    ) async {
      repo.onSettle = (_, _) async => throw const ApiException(
        code: 'ALREADY_SETTLED',
        status: 409,
        serverMessage: 'Esta cuenta ya está saldada',
      );
      await _pump(tester);
      await _tap(tester, find.text('Ya me pagó todo'));
      await _tap(tester, find.text('Ya me pagó todo').last);
      expect(find.byType(SettleSheet), findsNothing);
      expect(find.text('Esta cuenta ya está saldada'), findsOneWidget);
    });

    for (final (sheet, open, box, save) in [
      ('saldar', 'Ya me pagó todo', 'Registrar el ingreso en Movimientos', 'Ya me pagó todo'),
      ('abonar', 'Registrar abono', 'Anotar el ingreso en Movimientos', 'Registrar abono'),
    ]) {
      testWidgets('al $sheet, la casilla no cambia mientras guarda: el envío ya salió con ella', (
        tester,
      ) async {
        final gate = Completer<void>();
        repo.onSettle = (_, _) => gate.future;
        repo.onPay = (_, _, _, _) => gate.future;
        await _pump(tester);
        await _tap(tester, find.text(open));
        await tester.tap(find.text(save).last);
        await tester.pump();
        await tester.tap(find.text(box), warnIfMissed: false);
        await tester.pump();
        // No salió (sin conexión): la hoja sigue y se puede repetir.
        gate.completeError(const ApiException(code: ApiCodes.network));
        await tester.pumpAndSettle();
        repo.onSettle = (_, _) async {};
        repo.onPay = (_, _, _, _) async {};
        await _tap(tester, find.text(save).last);
        expect([for (final b in repo.bodies) b['createTransaction']], [true, true]);
      });
    }

    testWidgets('«Todo lo que falta» es un botón que el lector puede activar', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.text('Registrar abono'));
      final node = tester.getSemantics(find.text('Todo lo que falta (${_m(200000)})'));
      expect(node.label, 'Todo lo que falta (${_m(200000)})');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('tras abonar, la pantalla muestra la carga (no la cifra vieja) hasta que llega la lista', (
      tester,
    ) async {
      final gate = Completer<void>();
      var paid = false;
      repo.onList = () async {
        if (paid) await gate.future;
        return debtsOf([_qa, _laura]);
      };
      repo.onPay = (_, _, _, _) async => paid = true;
      await _pump(tester);
      await _tap(tester, find.text('Registrar abono'));
      await tester.tap(
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DebtPaymentSheet), findsNothing);
      expect(
        find.text('Laura Gómez'),
        findsNothing,
        reason: '«Registrar abono» volvería a proponer lo abonado',
      );
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Laura Gómez'), findsOneWidget);
    });

    testWidgets('«Ya pagué todo»: lo que faltaba, la casilla y saldar SIN fecha', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.text('Ya pagué todo'));
      expect(find.text('Le pagaste a Prueba QA lo que faltaba: ${_m(200000)}.'), findsOneWidget);
      expect(find.text('Registrar el gasto en Movimientos'), findsOneWidget);
      expect(
        find.text('Así tu saldo de hoy queda bien. Va en Otros; puedes cambiar la categoría después.'),
        findsOneWidget,
      );
      // El botón de la hoja (el título dice lo mismo).
      await _tap(tester, find.text('Ya pagué todo').last);
      expect(repo.bodies.single, {'createTransaction': true});
      expect(repo.calls, contains('settle ${_qa['id']}'));
    });

    testWidgets('el abono con montos ocultos: el encabezado y «Todo lo que falta» sin cifras', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: true);
      await _tap(tester, find.text('Debo · 1'));
      await _tap(tester, find.text('Registrar abono'));
      expect(find.textContaining('200.000'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Todo lo que falta \\(Monto oculto\\)')), findsOneWidget);
      // El monto precargado sí se ve: es un campo para editar (como la web).
      expect(tester.widget<TextField>(_money('¿Cuánto pagaste?')).controller!.text, '100.000');
      // El error dice «Monto oculto», no la cifra ni la máscara (va dentro del campo, también al lector).
      await tester.enterText(_money('¿Cuánto pagaste?'), '300000');
      await _tap(
        tester,
        find.descendant(of: find.byType(DebtPaymentSheet), matching: find.text('Registrar abono')).last,
      );
      expect(find.text('No puede pasar de lo que falta (Monto oculto)'), findsOneWidget);
      handle.dispose();
    });
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho, letra al doble, tema $name: lista, saldadas y hojas sin desbordes', (
      tester,
    ) async {
      final long = 'Una persona con un nombre muy largo que llega a sesenta letr'.padRight(60, 'x');
      final note = 'n' * 200;
      repo.onList = () async => debtsOf([
        for (var i = 0; i < 30; i++) ...[
          debtJson(
            id: 'p$i',
            person: long,
            note: note,
            amount: 9999999999,
            paid: 9999999,
            installments: 60,
            paidInstallments: 59,
            nextInstallment: {'number': 60, 'date': '2026-11-${(i % 9) + 10}', 'amount': 9999999999},
          ),
          onceJson(id: 'r$i', person: long, note: note, amount: 9999999999, dueDate: '2027-03-01'),
          onceJson(
            id: 's$i',
            person: long,
            amount: 9999999999,
            settledAt: '2026-11-20T10:00:00Z',
            transactionId: 'm$i',
          ),
        ],
      ]);
      await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Saldadas'), 400, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull, reason: 'saldadas');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 100000));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Debo · 30'));
      expect(tester.takeException(), isNull, reason: 'Debo');
      for (final open in ['Registrar abono', 'Ya pagué todo']) {
        await _tap(tester, find.text(open).first);
        expect(tester.takeException(), isNull, reason: open);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await _tap(tester, find.byTooltip('Editar la cuenta de $long').first);
      expect(tester.takeException(), isNull, reason: 'editar');
      await _tap(tester, find.text('Siguiente'));
      expect(tester.takeException(), isNull, reason: 'paso 2 con 60 cuotas');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Agregar').first);
      expect(tester.takeException(), isNull, reason: 'agregar');
    });
  }

  group('campo de fecha', () {
    Future<void> pumpField(WidgetTester tester, String? value) => tester.pumpWidget(
      ProviderScope(
        overrides: [clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10))],
        child: MaterialApp(
          home: Scaffold(
            body: DebtDateField(label: '¿Cuándo?', value: value, onChanged: (_) {}),
          ),
        ),
      ),
    );

    testWidgets('el lector oye el nombre del campo en el mismo botón que abre el calendario', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpField(tester, '2026-11-23');
      final node = tester.getSemantics(find.text('23 nov'));
      expect(node.getSemanticsData().label, allOf(contains('¿Cuándo?'), contains('23 nov')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    for (final value in ['2206-01-01', '1999-05-01']) {
      testWidgets('el calendario abre con una fecha del servidor fuera de 2000–2100 ($value)', (
        tester,
      ) async {
        await pumpField(tester, value);
        await tester.tap(find.byType(TextButton).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
      });
    }
  });
}
