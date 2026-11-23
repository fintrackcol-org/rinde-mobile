// Pagos del mes (bloque 4C): la pantalla /app/mi-plata/pagos con «Tu sueldo», sus estados, los
// grupos, «Ya lo pagué», el formulario de pago y su borrado; y en Mi plata el aviso de pendientes y
// «Pagos fijos del mes». Con montos ocultos, letra al doble en 320 de ancho, claro y oscuro, en y pt.
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
import 'package:rinde_mobile/design/widgets/rinde_skeleton.dart';
import 'package:rinde_mobile/design/widgets/rinde_text_field.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/money/presentation/payments_screen.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/month_commitments.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/pending_payment_notice.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/data/movements_repository.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_money_repository.dart';
import '../../support/fake_movements_repository.dart';
import '../../support/home_fixtures.dart';

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

const _arriendo = Commitment(id: 'c1', name: 'Arriendo', amount: 900000, dayOfMonth: 5);
const _internet = Commitment(id: 'c2', name: 'Internet', amount: 65000, dayOfMonth: 10);
const _netflix = Commitment(id: 'c3', name: 'Netflix', amount: 26900, dayOfMonth: 28, kind: 'subscription');
const _seguro = Commitment(
  id: 'c4',
  name: 'Seguro',
  amount: 1200000,
  dayOfMonth: 5,
  kind: 'subscription',
  frequency: 'yearly',
  month: 3,
);

MoneyProfile _profile({
  List<Commitment> commitments = const [_arriendo, _internet, _netflix, _seguro],
  int? version,
}) => MoneyProfile(
  welcomeDone: true,
  incomeType: 'fecha_fija',
  payDays: const [15, 30],
  balance: 500000,
  balanceAt: '2026-11-01T05:00:00.000Z',
  money: 412300,
  commitments: commitments,
  subscriptionCount: 2,
  subscriptionsMonthly: 126900,
  version: version,
);

const _payments = [
  CalendarPayment(id: 'c1', name: 'Arriendo', amount: 900000, date: '2026-11-05', status: 'pagado'),
  CalendarPayment(id: 'c2', name: 'Internet', amount: 65000, date: '2026-11-10', status: 'atrasado'),
  CalendarPayment(
    id: 'c3',
    name: 'Netflix',
    amount: 26900,
    date: '2026-11-28',
    status: 'pendiente',
    subscription: true,
  ),
];

late FakeMoneyRepository repo;
late FakeHomeRepository home;
late FakeMovementsRepository movements;
late MemoryJsonListStore queue;
late MemoryJsonListStore dismissed;

Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String route = Routes.payments,
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
      GoRoute(path: Routes.myMoney, builder: (_, _) => const MyMoneyScreen()),
      GoRoute(path: Routes.payments, builder: (_, _) => const MoneyPaymentsScreen()),
      for (final path in [Routes.calendar, Routes.plan, Routes.budgets, Routes.fixBalance])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('RUTA $path')),
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
        moneyRepositoryProvider.overrideWithValue(repo),
        homeRepositoryProvider.overrideWithValue(home),
        movementsRepositoryProvider.overrideWithValue(movements),
        pendingStoreProvider.overrideWithValue(queue),
        dismissedStoreProvider.overrideWithValue(dismissed),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
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
  return ProviderScope.containerOf(tester.element(find.text('INICIO', skipOffstage: false)));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder get _paid => find.text('Ya lo pagué');

/// El campo de la hoja con esa etiqueta visible.
Finder _field(String label) => find.descendant(
  of: find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is RindeTextField || w is RindeMoneyField),
      )
      .first,
  matching: find.byType(EditableText),
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester, String label) =>
    tester.widget<EditableText>(_field(label)).focusNode.hasFocus;

void main() {
  setUp(() {
    repo = FakeMoneyRepository();
    repo.onProfile = () async => _profile();
    repo.onCalendar = (_) async => _payments;
    home = FakeHomeRepository();
    movements = FakeMovementsRepository();
    queue = MemoryJsonListStore();
    dismissed = MemoryJsonListStore();
  });

  group('la pantalla', () {
    testWidgets('mientras carga: esqueleto «Cargando…», sin cifras', (tester) async {
      final handle = tester.ensureSemantics();
      repo.onProfile = () => Completer<MoneyProfile>().future;
      await _pump(tester);
      expect(find.text('Pagos del mes'), findsOneWidget);
      expect(find.byType(RindeSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.text('Agregar pago'), findsNothing);
      handle.dispose();
    });

    testWidgets('si falla el perfil: el error con «Reintentar» lo vuelve a pedir', (tester) async {
      var fail = true;
      repo.onProfile = () async {
        if (fail) throw serverError;
        return _profile();
      };
      await _pump(tester);
      expect(find.text('Algo salió mal. Inténtalo de nuevo.'), findsOneWidget);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Tu sueldo'), findsOneWidget);
      expect(repo.count('profile'), 2);
    });

    testWidgets('si falla el calendario: el resto se ve y su bloque dice el error con «Reintentar»', (
      tester,
    ) async {
      var fail = true;
      repo.onCalendar = (_) async {
        if (fail) throw offlineError;
        return _payments;
      };
      await _pump(tester);
      expect(find.text('Tu sueldo'), findsOneWidget);
      expect(find.text('No pudimos conectar con el servidor. Revisa tu conexión.'), findsOneWidget);
      expect(find.text('Agregar pago'), findsOneWidget);
      expect(find.text('Falta por pagar'), findsNothing);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.text('Falta por pagar'), findsOneWidget);
      expect(repo.count('calendar'), 2);
      expect(repo.calls.where((c) => c.startsWith('calendar')).toSet(), {'calendar 2026-11'});
    });

    testWidgets('vacío: el texto de la web y «Agregar pago»', (tester) async {
      repo.onProfile = () async => _profile(commitments: const []);
      repo.onCalendar = (_) async => const [];
      await _pump(tester);
      expect(
        find.text(
          'Agrega lo que pagas cada mes (arriendo, internet) y tus suscripciones (Netflix, Spotify).',
        ),
        findsOneWidget,
      );
      expect(find.text('Agregar pago'), findsOneWidget);
      expect(find.text('Por pagar'), findsNothing);
    });

    testWidgets('totales, suscripciones, grupos, «· atrasado» escrito, «Pagado», lápices y otros meses', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text(_m(91900)), findsOneWidget);
      expect(find.text(_m(900000)), findsOneWidget);
      expect(find.text('Suscripciones: ${_m(126900)} al mes (2)'), findsOneWidget);
      for (final title in ['Por pagar', 'Pagados', 'En otros meses']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      // «Atrasado» se dice con texto, no solo con el color.
      expect(find.textContaining('· atrasado'), findsOneWidget);
      expect(find.text('${_m(26900)} · 28 de noviembre · suscripción'), findsOneWidget);
      expect(find.text('Pagado'), findsOneWidget);
      expect(_paid, findsNWidgets(2));
      for (final name in ['Arriendo', 'Internet', 'Netflix', 'Seguro']) {
        expect(find.byTooltip('Editar $name'), findsOneWidget, reason: name);
      }
      expect(find.text('${_m(1200000)} · cada año, el 5 de marzo · suscripción'), findsOneWidget);
    });

    testWidgets('«Ya lo pagué»: un gasto con el nombre exacto; mientras guarda, todos esperan', (
      tester,
    ) async {
      final answer = Completer<void>();
      movements.onCreate = (input, localId) async {
        await answer.future;
        return movementOf(
          't-$localId',
          amount: input.amount,
          description: input.description,
          date: input.date,
        );
      };
      await _pump(tester);
      await tester.tap(_paid.first);
      await tester.pump();
      // El que guarda muestra el spinner; el otro (Netflix) está desactivado y no responde.
      RindeButton button(Finder label) =>
          tester.widget<RindeButton>(find.ancestor(of: label, matching: find.byType(RindeButton)));
      expect((button(_paid.first).loading, button(_paid.last).onPressed), (true, null));
      await tester.tap(_paid.last, warnIfMissed: false);
      await tester.pump();
      expect(movements.localIds, hasLength(1));
      answer.complete();
      await tester.pumpAndSettle();
      expect(movements.calls.where((c) => c.startsWith('create')), hasLength(1));
      // Se vuelve a pedir el calendario (y con él, si ya quedó pagado).
      expect(repo.count('calendar'), 2);
    });

    testWidgets('ya pagado: mientras llega el calendario nuevo, otro toque no anota otro gasto', (
      tester,
    ) async {
      final fresh = Completer<List<CalendarPayment>>();
      var reads = 0;
      repo.onCalendar = (_) => ++reads == 1 ? Future.value(_payments) : fresh.future;
      await _pump(tester);
      await tester.tap(_paid.first);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // El gasto ya se guardó, pero lo de antes sigue diciendo «Por pagar».
      expect(movements.localIds, hasLength(1));
      await tester.tap(_paid.first, warnIfMissed: false);
      await tester.tap(_paid.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(movements.localIds, hasLength(1));
      fresh.complete([
        for (final p in _payments)
          p.id == 'c2'
              ? const CalendarPayment(
                  id: 'c2',
                  name: 'Internet',
                  amount: 65000,
                  date: '2026-11-10',
                  status: 'pagado',
                )
              : p,
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Pagado'), findsNWidgets(2));
      expect(_paid, findsOneWidget);
    });

    testWidgets('sin conexión: entra a la cola y la fila dice «Pendiente de sincronizar» sin botón', (
      tester,
    ) async {
      movements.onCreate = (_, _) async => throw offlineError;
      await _pump(tester);
      expect(_paid, findsNWidgets(2));
      await _tap(tester, _paid.first);
      expect(find.text('Pendiente de sincronizar'), findsOneWidget);
      expect(_paid, findsOneWidget);
      final saved = jsonDecode(queue.data['a']!) as List;
      expect(saved, hasLength(1));
      expect((saved.single as Map)['input']['description'], 'Internet');
    });

    testWidgets('el error de «Ya lo pagué» se muestra en la página', (tester) async {
      movements.onCreate = (_, _) async =>
          throw const ApiException(code: 'X', status: 422, serverMessage: 'No');
      await _pump(tester);
      await _tap(tester, _paid.first);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('montos ocultos: ni un dígito de los montos', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: true);
      for (final digits in ['91.900', '900.000', '126.900', '26.900', '65.000', '1.200.000']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      expect(find.bySemanticsLabel(RegExp('Monto oculto')), findsWidgets);
      handle.dispose();
    });

    for (final (region, title, pending) in [
      (const Region(country: 'US', currency: 'USD', language: 'en'), 'Monthly payments', 'Left to pay'),
      (const Region(country: 'BR', currency: 'BRL', language: 'pt'), 'Pagamentos do mês', 'Falta pagar'),
    ]) {
      testWidgets('en ${region.language} con ${region.currency}', (tester) async {
        await _pump(tester, region: region);
        expect(find.text(title), findsOneWidget);
        expect(find.text(pending), findsOneWidget);
        expect(find.text(formatFor(region).money(91900)), findsOneWidget);
      });
    }

    for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
      testWidgets('320 de ancho, letra al doble, tema $name, 30 pagos de 60 letras y 10 dígitos', (
        tester,
      ) async {
        final long = 'Un pago con un nombre larguísimo que llega a los sesenta car';
        expect(long.length, 60);
        repo.onProfile = () async => _profile(
          commitments: [
            for (var i = 0; i < 30; i++)
              Commitment(
                id: 'p$i',
                name: '${long.substring(0, 58)}$i'.padRight(60, 'x'),
                amount: 9999999999,
                dayOfMonth: 1 + i,
              ),
          ],
        );
        repo.onCalendar = (_) async => [
          for (var i = 0; i < 30; i++)
            CalendarPayment(
              id: 'p$i',
              name: '${long.substring(0, 58)}$i'.padRight(60, 'x'),
              amount: 9999999999,
              date: '2026-11-${(1 + i).toString().padLeft(2, '0')}',
              status: const ['pagado', 'atrasado', 'pendiente'][i % 3],
              subscription: i.isEven,
            ),
        ];
        await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Agregar pago'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Agregar pago'));
        await _tap(tester, find.text('Una vez al año'));
        await tester.ensureVisible(find.text('Guardar pago'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('«Tu sueldo»', () {
    testWidgets('cuenta real sin version: el resumen y dónde cambiarlo, sin «Cambiar»', (tester) async {
      await _pump(tester);
      expect(find.text('Con fecha fija, los días 15 y 30'), findsOneWidget);
      expect(find.text('Por ahora cámbialo en la web de Rinde, con tu misma cuenta.'), findsOneWidget);
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Configurar'), findsNothing);
    });

    testWidgets('con version: «Cambiar», un día como mínimo y PUT con el saldo releído', (tester) async {
      repo.onProfile = () async => _profile(version: 4);
      await _pump(tester);
      expect(find.text('Por ahora cámbialo en la web de Rinde, con tu misma cuenta.'), findsNothing);
      await _tap(tester, find.text('Cambiar'));
      for (final day in [15, 30]) {
        await _tap(tester, find.bySemanticsLabel('Día $day'));
      }
      await _tap(tester, find.text('Guardar'));
      expect(find.text('Elige al menos un día de pago.'), findsOneWidget);
      expect(repo.count('saveProfile'), 0);

      await _tap(tester, find.text('Sin fecha fija'));
      await _tap(tester, find.text('Guardar'));
      expect(repo.sentProfiles.single, {
        'incomeType': 'sin_fecha',
        'payDays': <int>[],
        'balance': 500000,
        'expectedVersion': 4,
      });
      expect(find.text('Guardar'), findsNothing);
    });
  });

  testWidgets('«Tu sueldo»: si cambió en otro dispositivo, se dice y se sigue editando', (tester) async {
    var reads = 0;
    repo.onProfile = () async => ++reads == 1
        ? _profile(version: 4)
        : MoneyProfile(welcomeDone: true, incomeType: 'sin_fecha', balance: 500000, version: 5);
    await _pump(tester);
    await _tap(tester, find.text('Cambiar'));
    await _tap(tester, find.text('Sin fecha fija'));
    await _tap(tester, find.text('Guardar'));
    expect(repo.count('saveProfile'), 0);
    expect(find.text('Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });

  group('el formulario de un pago', () {
    testWidgets('los cuatro mensajes de la web, en orden, cada uno en su campo y con el foco', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tap(tester, find.text('Agregar pago'));
      expect(find.text('Nuevo pago'), findsOneWidget);
      expect(find.text('Eliminar pago'), findsNothing);
      Future<void> save() => _tap(tester, find.text('Guardar pago'));

      await save();
      expect(find.text('Escribe el nombre del pago.'), findsOneWidget);
      expect(_focused(tester, 'Nombre'), isTrue);

      await _type(tester, 'Nombre', 'Seguro');
      await save();
      expect(find.text('Escribe cuánto pagas por Seguro.'), findsOneWidget);
      expect(_focused(tester, 'Monto'), isTrue);

      await _type(tester, 'Monto', '1200000');
      for (final day in ['', '0', '32']) {
        await _type(tester, 'Día', day);
        await save();
        expect(find.text('Escribe un día entre 1 y 31 para Seguro.'), findsOneWidget, reason: day);
        expect(_focused(tester, 'Día'), isTrue);
      }
      await _type(tester, 'Día', '5');
      await _tap(tester, find.text('Una vez al año'));
      await save();
      expect(find.text('Elige en qué mes se cobra Seguro.'), findsOneWidget);
      expect(repo.count('createCommitment'), 0);

      await _tap(tester, find.byType(DropdownButtonFormField<int>));
      await _tap(tester, find.text('marzo').last);
      await _tap(tester, find.text('Suscripción'));
      await save();
      expect(repo.sentCommitments.single, {
        'name': 'Seguro',
        'amount': 1200000,
        'dayOfMonth': 5,
        'kind': 'subscription',
        'frequency': 'yearly',
        'month': 3,
      });
      expect(find.text('Nuevo pago'), findsNothing);
      handle.dispose();
    });

    testWidgets('el nombre no pasa de 60 letras', (tester) async {
      await _pump(tester);
      await _tap(tester, find.text('Agregar pago'));
      await _type(tester, 'Nombre', 'a' * 61);
      await _type(tester, 'Monto', '10');
      await _type(tester, 'Día', '1');
      await _tap(tester, find.text('Guardar pago'));
      expect(repo.sentCommitments.single['name'], 'a' * 60);
    });

    Future<void> fill(WidgetTester tester) async {
      await _tap(tester, find.text('Agregar pago'));
      await _type(tester, 'Nombre', 'Arriendo');
      await _type(tester, 'Monto', '900000');
      await _type(tester, 'Día', '5');
      await _tap(tester, find.text('Guardar pago'));
    }

    testWidgets('409 COMMITMENT_EXISTS: en el campo «Nombre»', (tester) async {
      repo.onCreateCommitment = (_) async => throw const ApiException(
        code: 'COMMITMENT_EXISTS',
        status: 409,
        serverMessage: 'Ya tienes un compromiso con ese nombre',
      );
      await _pump(tester);
      await fill(tester);
      expect(find.text('Ya tienes un compromiso con ese nombre'), findsOneWidget);
      expect(_focused(tester, 'Nombre'), isTrue);
      expect(find.text('Nuevo pago'), findsOneWidget);
    });

    testWidgets('409 COMMITMENT_LIMIT: en un aviso, no en un campo', (tester) async {
      repo.onCreateCommitment = (_) async => throw const ApiException(
        code: 'COMMITMENT_LIMIT',
        status: 409,
        serverMessage: 'Puedes tener hasta 30 compromisos',
      );
      await _pump(tester);
      await fill(tester);
      expect(find.text('Puedes tener hasta 30 compromisos'), findsOneWidget);
      expect(_focused(tester, 'Nombre'), isFalse);
    });

    testWidgets('422 por campo: el problema del servidor en «Monto»', (tester) async {
      repo.onCreateCommitment = (_) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        fields: {'amount': 'Es demasiado grande'},
      );
      await _pump(tester);
      await fill(tester);
      expect(find.text('Es demasiado grande'), findsOneWidget);
      expect(_focused(tester, 'Monto'), isTrue);
    });

    testWidgets('401: «Tu sesión venció…»', (tester) async {
      repo.onCreateCommitment = (_) async =>
          throw const ApiException(code: ApiCodes.unauthorized, status: 401);
      await _pump(tester);
      await fill(tester);
      expect(find.text('Tu sesión venció. Inicia sesión de nuevo.'), findsOneWidget);
    });

    testWidgets('editar: precargado, PUT completo y la lista se vuelve a pedir', (tester) async {
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar Internet'));
      expect(find.text('Editar pago'), findsOneWidget);
      await _type(tester, 'Monto', '70000');
      await _tap(tester, find.text('Guardar pago'));
      expect(repo.sentUpdates.single.$1, 'c2');
      expect(repo.sentUpdates.single.$2, {
        'name': 'Internet',
        'amount': 70000,
        'dayOfMonth': 10,
        'kind': 'fixed',
        'frequency': 'monthly',
        'month': null,
      });
      expect(find.text('Editar pago'), findsNothing);
      expect((repo.count('profile') >= 3, repo.count('calendar')), (true, 2));
    });

    testWidgets('después de guardar, mientras llega el perfil nuevo, el lápiz no abre el pago de antes', (
      tester,
    ) async {
      final fresh = Completer<MoneyProfile>();
      var reads = 0;
      // 1: la pantalla; 2: la comprobación previa; 3: la recarga de después de guardar.
      repo.onProfile = () => ++reads <= 2 ? Future.value(_profile()) : fresh.future;
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar Internet'));
      await _type(tester, 'Monto', '70000');
      await _tap(tester, find.text('Guardar pago'));
      IconButton pencil() => tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip('Editar Internet'), matching: find.byType(IconButton)),
      );
      expect(pencil().onPressed, isNull);
      fresh.complete(
        _profile(
          commitments: const [
            _arriendo,
            Commitment(id: 'c2', name: 'Internet', amount: 70000, dayOfMonth: 10),
            _netflix,
            _seguro,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(pencil().onPressed, isNotNull);
    });

    testWidgets('mientras guarda, arrastrarla no la cierra: el 409 se ve en «Nombre»', (tester) async {
      final gate = Completer<void>();
      repo.onCreateCommitment = (_) async {
        await gate.future;
        throw const ApiException(
          code: 'COMMITMENT_EXISTS',
          status: 409,
          serverMessage: 'Ya tienes un compromiso con ese nombre',
        );
      };
      await _pump(tester);
      await _tap(tester, find.text('Agregar pago'));
      await _type(tester, 'Nombre', 'Arriendo');
      await _type(tester, 'Monto', '900000');
      await _type(tester, 'Día', '5');
      await tester.ensureVisible(find.text('Guardar pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar pago'));
      await tester.pump();
      final top = tester.getTopLeft(find.byType(BottomSheet));
      await tester.flingFrom(top + const Offset(195, 12), const Offset(0, 600), 3000);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text('Nuevo pago'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ya tienes un compromiso con ese nombre'), findsOneWidget);
    });

    testWidgets('modo oscuro: «Eliminar pago» de la confirmación, blanco sobre rojo a 4,5:1 o más', (
      tester,
    ) async {
      await _pump(tester, theme: RindeTheme.dark);
      await _tap(tester, find.byTooltip('Editar Internet'));
      await _tap(tester, find.text('Eliminar pago'));
      final style = tester
          .widget<FilledButton>(
            find.ancestor(of: find.text('Eliminar pago').last, matching: find.byType(FilledButton)),
          )
          .style!;
      final under = style.backgroundColor!.resolve({})!;
      final text = style.foregroundColor!.resolve({})!;
      expect((text.computeLuminance() + 0.05) / (under.computeLuminance() + 0.05), greaterThanOrEqualTo(4.5));
    });

    testWidgets('editar uno que ya no existe (404): la hoja se cierra y se recarga', (tester) async {
      var calls = 0;
      repo.onProfile = () async => ++calls == 1 ? _profile() : _profile(commitments: const [_arriendo]);
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar Internet'));
      await _type(tester, 'Monto', '70000');
      await _tap(tester, find.text('Guardar pago'));
      expect(find.text('Editar pago'), findsNothing);
      expect(repo.count('updateCommitment'), 0);
      expect(find.byTooltip('Editar Internet'), findsNothing);
    });

    testWidgets('editar uno que cambió en otro lado: no se envía; la hoja se cierra y se avisa', (
      tester,
    ) async {
      var calls = 0;
      repo.onProfile = () async => ++calls == 1
          ? _profile()
          : _profile(
              commitments: const [Commitment(id: 'c2', name: 'Internet', amount: 80000, dayOfMonth: 10)],
            );
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar Internet'));
      await _type(tester, 'Monto', '70000');
      await _tap(tester, find.text('Guardar pago'));
      expect(repo.count('updateCommitment'), 0);
      expect(find.text('Editar pago'), findsNothing);
      expect(find.text('Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.'), findsOneWidget);
    });

    testWidgets('eliminar: se confirma con los textos nuevos y entonces DELETE', (tester) async {
      await _pump(tester);
      await _tap(tester, find.byTooltip('Editar Internet'));
      await _tap(tester, find.text('Eliminar pago'));
      expect(find.text('¿Eliminar Internet?'), findsOneWidget);
      expect(
        find.text('Se borra el pago y su aviso. Los gastos que ya anotaste no cambian.'),
        findsOneWidget,
      );
      // Cancelar no borra nada.
      await _tap(tester, find.text('Cancelar').last);
      expect(repo.deleted, isEmpty);
      await _tap(tester, find.text('Eliminar pago'));
      await _tap(tester, find.text('Eliminar pago').last);
      expect(repo.deleted, ['c2']);
      expect(find.text('Editar pago'), findsNothing);
      expect(find.text('¿Eliminar Internet?'), findsNothing);
    });
  });

  group('Mi plata', () {
    Finder inNotice(Finder f) => find.descendant(of: find.byType(PendingPaymentNotice), matching: f);

    testWidgets('el aviso: «1 de N», venció/vence y la X lo cierra solo en este teléfono, por cuenta', (
      tester,
    ) async {
      await _pump(tester, route: Routes.myMoney);
      expect(inNotice(find.text('1 de 3')), findsOneWidget);
      expect(inNotice(find.text('PILA venció el 13 de noviembre')), findsOneWidget);
      await _tap(tester, inNotice(find.byTooltip('Cerrar el aviso de PILA')));
      expect(inNotice(find.text('1 de 2')), findsOneWidget);
      expect(inNotice(find.text('Plan celular venció el 15 de noviembre')), findsOneWidget);
      expect(jsonDecode(dismissed.data['a']!), ['pila-2026-11-13']);
    });

    testWidgets('montos ocultos: ni el aviso ni los pagos fijos muestran un dígito', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, route: Routes.myMoney, hidden: true);
      for (final digits in ['228.000', '900.000', '65.000', '26.900']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      expect(inNotice(find.textContaining('••••••')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('el del mes siguiente se avisa pero sin «Ya lo pagué»', (tester) async {
      home.onPlan = () async => planOf(
        pending: const [PendingPayment(id: 'c2', name: 'Internet', amount: 65000, date: '2026-12-02')],
      );
      await _pump(tester, route: Routes.myMoney);
      expect(inNotice(find.text('Internet vence el 2 de diciembre')), findsOneWidget);
      expect(inNotice(_paid), findsNothing);
    });

    for (final (name, plan) in <(String, Future<MoneyPlan> Function())>[
      ('sin plan listo', () async => const MoneyPlan.notReady()),
      ('con el plan caído', () async => throw offlineError),
    ]) {
      testWidgets('$name no hay aviso', (tester) async {
        home.onPlan = plan;
        await _pump(tester, route: Routes.myMoney);
        expect(find.byType(PendingPaymentNotice), findsOneWidget);
        expect(inNotice(find.textContaining('venc')), findsNothing);
        expect(inNotice(_paid), findsNothing);
      });
    }

    testWidgets('«Ya lo pagué» del aviso anota el gasto con el nombre y vuelve a pedir el plan', (
      tester,
    ) async {
      await _pump(tester, route: Routes.myMoney);
      await _tap(tester, inNotice(_paid));
      expect(movements.calls.where((c) => c.startsWith('create')), hasLength(1));
      expect(home.count('plan'), 2);
    });

    testWidgets('ya pagado desde el aviso: mientras llega el plan nuevo, otro toque no anota otro gasto', (
      tester,
    ) async {
      final fresh = Completer<MoneyPlan>();
      var reads = 0;
      home.onPlan = () => ++reads == 1 ? Future.value(planOf()) : fresh.future;
      await _pump(tester, route: Routes.myMoney);
      await tester.ensureVisible(inNotice(_paid));
      await tester.pumpAndSettle();
      await tester.tap(inNotice(_paid));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(movements.localIds, hasLength(1));
      await tester.tap(inNotice(_paid), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(movements.localIds, hasLength(1));
      fresh.complete(planOf(pending: pendingPayments.skip(1).toList()));
      await tester.pumpAndSettle();
      expect(inNotice(find.textContaining('PILA')), findsNothing);
      expect(movements.localIds, hasLength(1));
    });

    testWidgets('el error de «Ya lo pagué» es de ese pago: al cerrarlo no pasa al siguiente', (tester) async {
      movements.onCreate = (_, _) async =>
          throw const ApiException(code: 'X', status: 422, serverMessage: 'Falló PILA');
      await _pump(tester, route: Routes.myMoney);
      await _tap(tester, inNotice(_paid));
      expect(inNotice(find.text('Falló PILA')), findsOneWidget);
      await _tap(tester, inNotice(find.byTooltip('Cerrar el aviso de PILA')));
      expect(inNotice(find.textContaining('Plan celular')), findsOneWidget);
      expect(inNotice(find.text('Falló PILA')), findsNothing);
    });

    testWidgets('«Pagos fijos del mes»: los de este mes por día, y «Editar pagos fijos» va a Pagos', (
      tester,
    ) async {
      await _pump(tester, route: Routes.myMoney);
      final section = find.byType(MonthCommitments);
      Finder inSection(Finder f) => find.descendant(of: section, matching: f);
      expect(inSection(find.text('5 nov · Arriendo')), findsOneWidget);
      expect(inSection(find.text('10 nov · Internet')), findsOneWidget);
      expect(inSection(find.text('28 nov · Netflix')), findsOneWidget);
      // El anual de marzo no es de este mes.
      expect(inSection(find.textContaining('Seguro')), findsNothing);
      await _tap(tester, inSection(find.text('Editar pagos fijos')));
      expect(find.byType(MoneyPaymentsScreen), findsOneWidget);
    });

    testWidgets(
      '«Pagos fijos del mes» vacío: el texto de la web lleva a Pagos; «Ver calendario» al calendario',
      (tester) async {
        repo.onProfile = () async => _profile(commitments: const []);
        await _pump(tester, route: Routes.myMoney);
        final section = find.byType(MonthCommitments);
        await _tap(tester, find.descendant(of: section, matching: find.text('Ver calendario')));
        expect(find.text('RUTA ${Routes.calendar}'), findsOneWidget);
        GoRouter.of(tester.element(find.text('RUTA ${Routes.calendar}'))).pop();
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.descendant(
            of: section,
            matching: find.textContaining('Agrega lo que pagas cada mes (arriendo, internet, PILA)'),
          ),
        );
        expect(find.byType(MoneyPaymentsScreen), findsOneWidget);
      },
    );
  });
}
