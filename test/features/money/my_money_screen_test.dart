// Mi plata, bloque 4A: la tarjeta «Cómo te entra la plata» y su hoja (vista y edición), con todos
// sus estados, errores por campo, la PILA, montos ocultos y letra al doble en 320 de ancho.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/rendering.dart' show RenderParagraph;
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
import 'package:rinde_mobile/design/widgets/rinde_feedback.dart';
import 'package:rinde_mobile/design/widgets/rinde_money_field.dart';
import 'package:rinde_mobile/design/widgets/rinde_skeleton.dart';
import 'package:rinde_mobile/features/auth/application/session_controller.dart';
import 'package:rinde_mobile/features/auth/data/auth_models.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/income_overview_card.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/money_shortcuts.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/money_left_card.dart';
import 'package:rinde_mobile/features/money/presentation/widgets/top_budgets.dart';
import 'package:rinde_mobile/features/movements/application/movement_saver.dart';
import 'package:rinde_mobile/features/onboarding/data/draft_store.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/onboarding/domain/onboarding_draft.dart';

import '../../support/fake_home_repository.dart';
import '../../support/fake_money_repository.dart';
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

const _headline = 'En un mes normal te entran';
const _empty = 'Cuéntanos cómo y cuánto te entra, aunque sea más o menos.';
const _emptyWarning = 'Si guardas sin ninguna, dejamos de calcular cuánto tienes libre.';
const _pilaDone = 'Listo: quedó en tus pagos del mes (día 10). Cambia el día si tu planilla vence otro.';
const _stale = 'Lo que ves puede estar desactualizado: es lo último que llegó.';

late FakeMoneyRepository repo;
late FakeHomeRepository home;

const _destinations = [
  Routes.fixBalance,
  Routes.expenses,
  Routes.budgets,
  Routes.calendar,
  Routes.debts,
  Routes.cards,
  Routes.toConfirm,
  Routes.insights,
  Routes.export,
  Routes.renta,
  Routes.liquidity,
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  bool hidden = false,
  Region region = kDefaultRegion,
  DraftStore? drafts,
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
      // Los demás destinos: un marcador con su ruta.
      for (final path in _destinations)
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
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        initialHiddenAmountsProvider.overrideWithValue(hidden),
        initialRegionProvider.overrideWithValue(region),
        translationsProvider.overrideWithValue(_translations()),
        draftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
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
  unawaited(router.push(Routes.myMoney));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('INICIO', skipOffstage: false)));
}

/// Las traducciones que lleva la app (assets/l10n).
Translations _translations() => Translations({
  for (final language in const ['en', 'pt'])
    language: (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    ),
});

/// Solo dentro de «Cómo te entra la plata»: arriba están la plata y los presupuestos.
Finder _inCard(Finder finder) => find.descendant(of: find.byType(IncomeOverviewCard), matching: finder);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Abre la hoja en modo edición y deja el botón «Guardar» a la vista.
Future<void> _edit(WidgetTester tester) async {
  await _tap(tester, find.text('Ver más'));
  await _tap(tester, find.text('Cambiar cómo te entra la plata'));
  await tester.ensureVisible(find.text('Guardar'));
  await tester.pumpAndSettle();
}

const _sueldo = IncomeSource(id: 's', kind: IncomeKind.sueldo, amount: 2500000, payDays: [15, 30]);

void main() {
  setUp(() {
    repo = FakeMoneyRepository();
    home = FakeHomeRepository();
  });

  group('la tarjeta', () {
    testWidgets('mientras carga: esqueleto que dice «Cargando…», sin cifras', (tester) async {
      final handle = tester.ensureSemantics();
      repo.onIncome = () => Completer<IncomeOverview>().future;
      await _pump(tester);
      expect(find.text('Mi plata'), findsOneWidget);
      expect(find.byType(RindeSkeleton), findsWidgets);
      expect(_inCard(find.bySemanticsLabel('Cargando…')), findsOneWidget);
      expect(_inCard(find.textContaining(r'$')), findsNothing);
      handle.dispose();
    });

    testWidgets('si falla: «No pudimos traer todos tus datos.» y «Reintentar» la vuelve a pedir', (
      tester,
    ) async {
      var fail = true;
      repo.onIncome = () async {
        if (fail) throw serverError;
        return incomeOf();
      };
      await _pump(tester);
      expect(find.text('No pudimos traer todos tus datos.'), findsOneWidget);
      fail = false;
      await _tap(tester, find.text('Reintentar'));
      expect(find.textContaining(_headline), findsOneWidget);
      expect(repo.count('income'), 2);
    });

    testWidgets('una recarga que falla deja lo último y avisa que puede estar desactualizado', (
      tester,
    ) async {
      final c = await _pump(tester);
      repo.onIncome = () async => throw offlineError;
      c.invalidate(incomeOverviewProvider);
      await tester.pumpAndSettle();
      expect(find.textContaining(_headline), findsOneWidget);
      expect(find.text('Lo que ves puede estar desactualizado: es lo último que llegó.'), findsOneWidget);
    });

    testWidgets('con mes normal y flaco: la frase y «Ver más»', (tester) async {
      await _pump(tester);
      expect(find.text('Cómo te entra la plata'), findsOneWidget);
      expect(
        find.text(
          'En un mes normal te entran ${_m(700000)}; en uno flaco, ${_m(650000)}. '
          'Planeamos con el flaco para que no te coja la tarde.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ver más'), findsOneWidget);
      expect(find.text('Estimado con lo que nos contaste.'), findsNothing);
    });

    testWidgets('estimado y por días: la nota y la meta del día, con los pedazos de la web', (tester) async {
      repo.onIncome = () async => incomeOf(
        normal: 2000000,
        lean: 2000000,
        estimated: true,
        workDay: const WorkDay(
          target: 3100000,
          earned: 1250000,
          daysLeft: 7,
          perDay: 264300,
          extraToday: 20000,
        ),
      );
      await _pump(tester);
      expect(find.text('Te entran unos ${_m(2000000)} al mes.'), findsOneWidget);
      expect(find.text('Estimado con lo que nos contaste.'), findsOneWidget);
      expect(
        find.text(
          'Llevas ${_m(1250000)} de ${_m(3100000)}; te faltan 7 días de trabajo, unos ${_m(264300)} por día.'
          ' Hoy hiciste ${_m(20000)} de más: apártalos para mañana o al colchón.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('por días sin meta (sin ritmo ni montos): no sale una línea de puros ceros', (tester) async {
      repo.onIncome = () async => incomeOf(
        sources: const [IncomeSource(id: 'd', kind: IncomeKind.diario, workDays: 5)],
        normal: 0,
        lean: 0,
        basis: 'none',
        workDay: const WorkDay(target: 0, earned: 0, daysLeft: 18, perDay: 0, extraToday: 0),
      );
      await _pump(tester);
      expect(find.text(_empty), findsOneWidget);
      expect(find.textContaining('Llevas'), findsNothing);
    });

    testWidgets('sin fuentes: «Cuéntanos…» y «Configurar» abre la hoja ya editando', (tester) async {
      repo.onIncome = () async => noIncome;
      await _pump(tester);
      expect(find.text(_empty), findsOneWidget);
      await _tap(tester, find.text('Configurar'));
      expect(
        find.text('Elige todas las que apliquen. Los montos son aproximados: más o menos está bien.'),
        findsOneWidget,
      );
      for (final kind in IncomeKind.values) {
        expect(find.text(kind.title), findsOneWidget, reason: kind.name);
      }
      // Sin ninguna marcada se avisa lo que se pierde; al marcar una, el aviso se va.
      expect(find.text(_emptyWarning), findsOneWidget);
      await _tap(tester, find.text('Sueldo fijo'));
      expect(find.text(_emptyWarning), findsNothing);
    });
  });

  group('la hoja en modo vista', () {
    testWidgets('las fuentes, el sueldo propio, el colchón (sin botones) y salud y pensión', (tester) async {
      repo.onIncome = () async => incomeOf(sources: const [_sueldo]);
      await _pump(tester);
      await _tap(tester, find.text('Ver más'));
      expect(find.text('Sueldo fijo'), findsOneWidget);
      expect(find.text('${_m(2500000)} al mes · días 15 y 30'), findsOneWidget);
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
      expect(find.text('Págate un sueldo'), findsOneWidget);
      expect(
        find.text(
          'Te sugerimos vivir con ${_m(600000)} al mes, aunque un mes te entre más. Lo que sobre va al colchón.',
        ),
        findsOneWidget,
      );
      expect(find.text('Colchón para meses flacos'), findsOneWidget);
      expect(
        find.text(
          'Para que un mes flaco no te coja la tarde, te sugerimos guardar ${_m(2250000)}. '
          'Si un mes viene flaco, usas de ahí: para eso es.',
        ),
        findsOneWidget,
      );
      // Crear el colchón y aportarle son del módulo de metas: aquí no hay botones.
      expect(find.text('Crear mi colchón'), findsNothing);
      expect(find.text('Aportar al colchón'), findsNothing);
      expect(
        find.text(
          'Como trabajas por tu cuenta, aparta unos ${_m(499008)} al mes: salud ${_m(218863)} y pensión '
          '${_m(280145)}, sobre el 40 % de lo que te entra (mínimo un salario mínimo).',
        ),
        findsOneWidget,
      );
      expect(find.text('Recordármelo cada mes'), findsOneWidget);
    });

    testWidgets('con la meta del colchón ya creada: cuánto lleva', (tester) async {
      repo.onIncome = () async => incomeOf(
        cushion: const Cushion(goal: 2250000, suggestedGoal: 2250000, saved: 300000, metaId: 'm1'),
      );
      await _pump(tester);
      await _tap(tester, find.text('Ver más'));
      expect(find.text('Llevas ${_m(300000)} de ${_m(2250000)}.'), findsOneWidget);
    });

    // El servidor redondea el sueldo propio a 50 000: un mes flaco chico da 0, no null.
    for (final ownSalary in [null, 0]) {
      testWidgets(
        'sin sugerencia de colchón ni seguridad social y sueldo $ownSalary: esos bloques no salen',
        (tester) async {
          repo.onIncome = () async => incomeOf(
            ownSalary: ownSalary,
            cushion: const Cushion(goal: 0, suggestedGoal: 0, saved: 0),
            socialSecurity: null,
          );
          await _pump(tester);
          await _tap(tester, find.text('Ver más'));
          expect(find.text('Colchón para meses flacos'), findsNothing);
          expect(find.text('Salud y pensión'), findsNothing);
          expect(find.text('Págate un sueldo'), findsNothing);
          expect(find.textContaining('Te sugerimos vivir con'), findsNothing);
        },
      );
    }

    // El servidor calcula la PILA en pesos con el salario mínimo de Colombia aunque la cuenta sea en otra
    // moneda: mostrarla daría una cifra falsa y «Recordármelo» crearía un pago enorme.
    for (final region in const [
      Region(country: 'US', currency: 'USD', language: 'es'),
      Region(country: 'CO', currency: 'USD', language: 'es'),
    ]) {
      testWidgets('en ${region.country} con ${region.currency}: «Salud y pensión» no sale', (tester) async {
        await _pump(tester, region: region);
        await _tap(tester, find.text('Ver más'));
        expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
        expect(find.text('Salud y pensión'), findsNothing);
        expect(find.text('Recordármelo cada mes'), findsNothing);
      });
    }

    testWidgets('«Recordármelo cada mes» manda lo mismo que la web y lo confirma', (tester) async {
      final c = await _pump(tester);
      c.listen(homePlanProvider(c.read(accountProvider)), (_, _) {});
      await tester.pumpAndSettle();
      final plans = home.count('plan');
      await _tap(tester, find.text('Ver más'));
      await _tap(tester, find.text('Recordármelo cada mes'));
      expect(repo.sentCommitments, [
        {'name': 'Seguridad social (PILA)', 'amount': 499008, 'dayOfMonth': 10},
      ]);
      expect(find.text(_pilaDone), findsOneWidget);
      expect(find.text('Recordármelo cada mes'), findsNothing);
      // El plan del Inicio se vuelve a pedir: ahora tiene ese pago.
      expect(home.count('plan'), plans + 1);
    });

    testWidgets('PILA con el nombre ya usado: el mensaje del servidor, nunca el de éxito', (tester) async {
      repo.onCreateCommitment = (_) async => throw const ApiException(
        code: 'COMMITMENT_EXISTS',
        status: 409,
        serverMessage: 'Ya tienes un compromiso con ese nombre',
      );
      await _pump(tester);
      await _tap(tester, find.text('Ver más'));
      await _tap(tester, find.text('Recordármelo cada mes'));
      expect(find.text('Ya tienes un compromiso con ese nombre'), findsOneWidget);
      expect(find.text(_pilaDone), findsNothing);
      expect(find.text('Recordármelo cada mes'), findsOneWidget);
    });
  });

  group('la hoja en modo edición', () {
    testWidgets('trae lo guardado; dos toques en «Guardar» mandan una sola vez y vuelve a la vista', (
      tester,
    ) async {
      final c = await _pump(tester);
      c.listen(homePlanProvider(c.read(accountProvider)), (_, _) {});
      await tester.pumpAndSettle();
      final plans = home.count('plan');
      await _edit(tester);
      // Los meses de proyectos guardados ya están escritos.
      expect(find.byType(RindeMoneyField), findsNWidgets(3));

      final answer = Completer<void>();
      repo.onSaveSources = (_) => answer.future;
      final at = tester.getCenter(find.text('Guardar'));
      await tester.tapAt(at);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pump();
      expect(repo.count('saveSources'), 1);
      expect(repo.sentSources.single, [
        {
          'kind': 'proyectos',
          'frequency': 'irregular',
          'payDays': <int>[],
          'amount': null,
          'low': null,
          'high': null,
          'lastMonths': [700000, 650000, 800000],
          'workDays': null,
        },
      ]);

      answer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
      // Mi plata y el plan del Inicio se vuelven a pedir.
      expect(repo.count('income'), 2);
      expect(home.count('plan'), plans + 1);
    });

    testWidgets('un 422 se marca en su casilla, sin aviso general', (tester) async {
      repo.onIncome = () async => incomeOf(sources: const [_sueldo]);
      repo.onSaveSources = (_) async => throw const ApiException(
        code: ApiCodes.validation,
        status: 422,
        fields: {'sources[0].amount': 'Debe ser un número desde 0'},
      );
      await _pump(tester);
      await _edit(tester);
      await _tap(tester, find.text('Guardar'));
      expect(
        find.descendant(of: find.byType(RindeMoneyField), matching: find.text('Debe ser un número desde 0')),
        findsOneWidget,
      );
      expect(find.byType(RindeBanner), findsNothing);
      // Sigue editando: nada se perdió.
      expect(find.text('Guardar'), findsOneWidget);
    });

    for (final (name, error, message) in [
      (
        'sesión vencida',
        const ApiException(code: ApiCodes.unauthorized, status: 401),
        ApiMessages.sessionExpired,
      ),
      ('sin conexión', offlineError, ApiMessages.network),
      (
        'un campo que la casilla no tiene',
        const ApiException(
          code: ApiCodes.validation,
          status: 422,
          fields: {'sources[0].payDays': 'Hasta 4 días entre 1 y 31'},
        ),
        'Hasta 4 días entre 1 y 31',
      ),
    ]) {
      testWidgets('$name: el aviso arriba del botón y sigue editando', (tester) async {
        repo.onIncome = () async => incomeOf(sources: const [_sueldo]);
        repo.onSaveSources = (_) async => throw error;
        await _pump(tester);
        await _edit(tester);
        await _tap(tester, find.text('Guardar'));
        expect(find.widgetWithText(RindeBanner, message), findsOneWidget);
        expect(find.text('Guardar'), findsOneWidget);
      });
    }

    testWidgets('«Cancelar» vuelve a la vista sin guardar; cerrar la hoja descarta lo editado', (
      tester,
    ) async {
      await _pump(tester);
      await _edit(tester);
      // Los 3 meses de proyectos; «Por días» suma su monto.
      expect(find.byType(RindeMoneyField), findsNWidgets(3));
      await _tap(tester, find.text('Por días o por apps'));
      expect(find.byType(RindeMoneyField), findsNWidgets(4));
      await _tap(tester, find.text('Cancelar'));
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
      // Al volver a cambiar, «Por días» ya no está marcada.
      await _tap(tester, find.text('Cambiar cómo te entra la plata'));
      expect(find.byType(RindeMoneyField), findsNWidgets(3));

      await _tap(tester, find.text('Por días o por apps'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsNothing);
      // Se abre otra vez en modo vista y sin lo que se había marcado.
      await _tap(tester, find.text('Ver más'));
      expect(find.text('Guardar'), findsNothing);
      await _tap(tester, find.text('Cambiar cómo te entra la plata'));
      expect(find.byType(RindeMoneyField), findsNWidgets(3));
      expect(repo.count('saveSources'), 0);
    });

    testWidgets('mientras guarda, Atrás no cierra la hoja', (tester) async {
      final answer = Completer<void>();
      repo.onSaveSources = (_) => answer.future;
      await _pump(tester);
      await _edit(tester);
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Cómo te entra la plata'), findsNWidgets(2));
      expect(find.text('Guardando…'), findsOneWidget);
      answer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
    });

    testWidgets('al guardar espera lo releído: la vista no muestra (ni «Cambiar» reenvía) lo que se quitó', (
      tester,
    ) async {
      final reread = Completer<IncomeOverview>();
      var reads = 0;
      repo.onIncome = () => ++reads == 1 ? Future.value(incomeOf()) : reread.future;
      await _pump(tester);
      await _edit(tester);
      await _tap(tester, find.text(IncomeKind.proyectos.title));
      await _tap(tester, find.text('Sueldo fijo'));
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump();
      expect(repo.count('saveSources'), 1);
      // Todavía no llega la relectura: sigue en «Guardando…», sin la vista vieja.
      expect(find.text('Guardando…'), findsOneWidget);
      expect(find.text('Cambiar cómo te entra la plata'), findsNothing);

      reread.complete(incomeOf(sources: const [_sueldo]));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
      expect(find.text('${_m(2500000)} al mes · días 15 y 30'), findsOneWidget);
      expect(find.text(IncomeKind.proyectos.title), findsNothing);
    });

    testWidgets('guardó pero la relectura falla: la hoja avisa que puede estar desactualizada', (
      tester,
    ) async {
      var reads = 0;
      repo.onIncome = () async {
        if (++reads > 1) throw offlineError;
        return incomeOf();
      };
      await _pump(tester);
      await _edit(tester);
      expect(find.text(_stale), findsNothing);
      await _tap(tester, find.text('Guardar'));
      expect(repo.count('saveSources'), 1);
      expect(find.text('Cambiar cómo te entra la plata'), findsOneWidget);
      // En la hoja y en la tarjeta de atrás.
      expect(find.text(_stale, skipOffstage: false), findsNWidgets(2));
    });

    testWidgets('con una bienvenida a medias no se guarda: primero hay que terminarla', (tester) async {
      final drafts = MemoryDraftStore();
      await drafts.write(
        'a',
        const OnboardingDraft(position: 9, country: 'CO', language: 'es', sentWelcome: 'llave').toJson(),
      );
      await _pump(tester, drafts: drafts);
      await _edit(tester);
      await _tap(tester, find.text('Guardar'));
      expect(
        find.widgetWithText(RindeBanner, 'Primero terminemos de guardar tu bienvenida.'),
        findsOneWidget,
      );
      expect(repo.count('saveSources'), 0);
      expect(find.text('Guardar'), findsOneWidget);
    });
  });

  testWidgets('montos ocultos: ni la tarjeta ni la hoja muestran un dígito', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, hidden: true);
    expect(find.textContaining('700'), findsNothing);
    expect(_inCard(find.textContaining('••••••')), findsOneWidget);
    await _tap(tester, find.text('Ver más'));
    for (final digits in ['700', '650', '600', '2.250', '499']) {
      expect(find.textContaining(digits), findsNothing, reason: digits);
    }
    expect(find.bySemanticsLabel(RegExp('Monto oculto')), findsWidgets);
    handle.dispose();
  });

  for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
    testWidgets('320 de ancho y letra al doble, tema $name: nada se desborda', (tester) async {
      repo.onIncome = () async => incomeOf(
        sources: const [
          _sueldo,
          IncomeSource(id: 'c', kind: IncomeKind.comisiones, amount: 9999999999, low: 1, high: 2),
          IncomeSource(id: 'p', kind: IncomeKind.proyectos, lastMonths: [9999999999, 9999999999, 9999999999]),
          IncomeSource(id: 'd', kind: IncomeKind.diario, amount: 9999999999, workDays: 7),
          IncomeSource(id: 'm', kind: IncomeKind.mesada, amount: 9999999999, frequency: 'semanal'),
        ],
        normal: 9999999999,
        lean: 999999999,
        estimated: true,
        workDay: const WorkDay(
          target: 9999999999,
          earned: 9999999999,
          daysLeft: 7,
          perDay: 9999999,
          extraToday: 1,
        ),
      );
      await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Ver más'));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Recordármelo cada mes'));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Cambiar cómo te entra la plata'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  group('¿Hasta cuándo te alcanza? (bloque 4B)', () {
    final money = find.byType(MoneyLeftSection);
    Finder inMoney(Finder finder) => find.descendant(of: money, matching: finder);

    testWidgets('plan listo: lo que te queda del plan (no del perfil), alcance, ritmo, ingresos y gastos', (
      tester,
    ) async {
      home.onPlan = () async => planOf(money: 412300);
      repo.onProfile = () async => const MoneyProfile(welcomeDone: true, money: 400000);
      await _pump(tester);
      expect(find.text('¿Hasta cuándo te alcanza?'), findsOneWidget);
      expect(find.text('LO QUE TE QUEDA · NOVIEMBRE'), findsOneWidget);
      expect(inMoney(find.text(_m(412300))), findsOneWidget);
      expect(find.text(_m(400000)), findsNothing);
      expect(find.text('Alcanza todo el mes'), findsOneWidget);
      expect(find.text('1 nov'), findsOneWidget);
      expect(find.text('30 nov'), findsOneWidget);
      // 287.700 gastados al día 22: 13.077 al día.
      expect(
        find.text('Gastas en promedio ${_m(13077)} al día. Ingresos ${_m(700000)} · Gastos ${_m(287700)}.'),
        findsOneWidget,
      );
      expect(find.textContaining('Ojo con el'), findsNothing);
      await _tap(tester, find.text('¿No es tu plata real? Corrígela'));
      expect(find.text('RUTA ${Routes.fixBalance}'), findsOneWidget);
    });

    testWidgets('sin plan, o con el plan fallando: la plata del perfil, sin aviso de error', (tester) async {
      repo.onProfile = () async => const MoneyProfile(welcomeDone: true, money: 400000);
      for (final plan in <Future<MoneyPlan> Function()>[
        () async => const MoneyPlan.notReady(),
        () async => throw serverError,
      ]) {
        home.onPlan = plan;
        await _pump(tester);
        expect(inMoney(find.text(_m(400000))), findsOneWidget);
        expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
      }
    });

    testWidgets('sin plan, tras anotar un movimiento: la plata del perfil se vuelve a pedir', (tester) async {
      home.onPlan = () async => const MoneyPlan.notReady();
      repo.onProfile = () async => const MoneyProfile(welcomeDone: true, money: 400000);
      final c = await _pump(tester);
      expect(inMoney(find.text(_m(400000))), findsOneWidget);
      repo.onProfile = () async => const MoneyProfile(welcomeDone: true, money: 350000);
      afterMovementChange(c);
      await tester.pumpAndSettle();
      expect(inMoney(find.text(_m(350000))), findsOneWidget);
    });

    for (final (region, question, more, budgets, fix, enough) in const [
      (
        Region(country: 'US', currency: 'USD', language: 'en'),
        'How long will your money last?',
        'More of your money',
        'Budgets',
        'Not your real money? Fix it',
        'Enough for the whole month',
      ),
      (
        Region(country: 'BR', currency: 'BRL', language: 'pt'),
        'Até quando o dinheiro dá?',
        'Mais do seu dinheiro',
        'Orçamentos',
        'Não é seu dinheiro real? Corrija',
        'Dá para o mês todo',
      ),
    ]) {
      testWidgets('en ${region.language} con ${region.currency}: sus textos y la plata en su formato', (
        tester,
      ) async {
        home.onPlan = () async => planOf(money: 412300);
        await _pump(tester, region: region);
        expect(find.text(question), findsOneWidget);
        expect(inMoney(find.text(formatFor(region).money(412300))), findsOneWidget);
        expect(find.text(enough), findsOneWidget);
        expect(find.text(fix), findsOneWidget);
        await tester.ensureVisible(find.text(more));
        expect(
          find.descendant(of: find.byType(MoneyShortcuts), matching: find.text(budgets)),
          findsOneWidget,
        );
        expect(find.text('¿Hasta cuándo te alcanza?'), findsNothing);
      });
    }

    testWidgets('sin ingresos ni gastos del mes: la cifra sin alcance ni línea', (tester) async {
      home.onPlan = () async => planOf(money: 412300);
      home.onTotals = (_) async => throw serverError;
      await _pump(tester);
      expect(inMoney(find.text(_m(412300))), findsOneWidget);
      expect(find.textContaining('Alcanza'), findsNothing);
      expect(find.textContaining('Gastas en promedio'), findsNothing);
    });

    testWidgets('plata desconocida: «—» y por qué, nunca un cero', (tester) async {
      home.onPlan = () async => const MoneyPlan.notReady();
      await _pump(tester);
      expect(inMoney(find.text('—')), findsOneWidget);
      expect(find.text('Anota tu primer ingreso para saber hasta cuándo te alcanza.'), findsOneWidget);
      expect(inMoney(find.text(_m(0))), findsNothing);
    });

    testWidgets('mientras carga: esqueleto que dice «Cargando…», sin cifras', (tester) async {
      final handle = tester.ensureSemantics();
      repo.onProfile = () => Completer<MoneyProfile>().future;
      home.onPlan = () => Completer<MoneyPlan>().future;
      await _pump(tester);
      expect(inMoney(find.bySemanticsLabel('Cargando…')), findsOneWidget);
      expect(inMoney(find.textContaining(r'$')), findsNothing);
      handle.dispose();
    });

    testWidgets('si el perfil falla: «—», «No pudimos traer tu plata.» y «Reintentar» lo vuelve a pedir', (
      tester,
    ) async {
      var fail = true;
      home.onPlan = () async => const MoneyPlan.notReady();
      repo.onProfile = () async {
        if (fail) throw serverError;
        return const MoneyProfile(welcomeDone: true, money: 400000);
      };
      await _pump(tester);
      expect(inMoney(find.text('—')), findsOneWidget);
      expect(find.text('No pudimos traer tu plata.'), findsOneWidget);
      expect(inMoney(find.text('No pudimos traer todos tus datos.')), findsOneWidget);
      fail = false;
      await _tap(tester, inMoney(find.text('Reintentar')));
      expect(inMoney(find.text(_m(400000))), findsOneWidget);
      expect(find.text('No pudimos traer todos tus datos.'), findsNothing);
    });

    testWidgets('sin conexión: lo dice, sin cifra', (tester) async {
      home.onPlan = () async => throw offlineError;
      repo.onProfile = () async => throw offlineError;
      await _pump(tester);
      expect(find.text('No pudimos traer tu plata porque no hay conexión.'), findsOneWidget);
    });

    testWidgets('negativa: la cifra con su signo y la nota que lleva a revisar los gastos', (tester) async {
      home.onPlan = () async => planOf(money: -35000);
      await _pump(tester);
      expect(inMoney(find.text(_m(-35000))), findsOneWidget);
      await _tap(tester, find.textContaining('Tus gastos superan lo que tienes. ¿Anotaste algo mal?'));
      expect(find.text('RUTA ${Routes.expenses}'), findsOneWidget);
    });

    testWidgets('«Ojo con el…»: el primer pago que a este ritmo no alcanza, con su día y su monto', (
      tester,
    ) async {
      home.onPlan = () async => planOf(money: 50000);
      repo.onProfile = () async => const MoneyProfile(
        welcomeDone: true,
        money: 50000,
        commitments: [
          Commitment(id: '1', name: 'Arriendo', amount: 900000, dayOfMonth: 5),
          Commitment(id: '2', name: 'Seguro', amount: 1200000, dayOfMonth: 27, frequency: 'yearly', month: 3),
          Commitment(id: '3', name: 'Internet', amount: 65000, dayOfMonth: 28),
        ],
      );
      await _pump(tester);
      expect(find.text('Alcanza hasta el 25 nov'), findsOneWidget);
      expect(
        find.text(
          'Ojo con el 28 de noviembre. Vence Internet (${_m(65000)}) y a este ritmo no alcanza. Anota los '
          'ingresos que esperas o baja algún presupuesto.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('un refresco que falla deja lo último y avisa que puede estar desactualizado', (
      tester,
    ) async {
      home.onPlan = () async => const MoneyPlan.notReady();
      repo.onProfile = () async => const MoneyProfile(welcomeDone: true, money: 400000);
      final c = await _pump(tester);
      repo.onProfile = () async => throw offlineError;
      c.invalidate(moneyProfileProvider);
      await tester.pumpAndSettle();
      expect(inMoney(find.text(_m(400000))), findsOneWidget);
      expect(inMoney(find.text(_stale)), findsOneWidget);
    });

    testWidgets('halar para recargar vuelve a pedir todo lo de la pantalla', (tester) async {
      await _pump(tester);
      (int, int, int, int, int) counts() => (
        repo.count('profile'),
        home.count('plan'),
        home.count('monthTotals'),
        home.count('budgets'),
        repo.count('income'),
      );
      expect(counts(), (1, 1, 1, 1, 1));
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1200);
      await tester.pumpAndSettle();
      expect(counts(), (2, 2, 2, 2, 2));
    });
  });

  group('presupuestos y «Más de tu plata» (bloque 4B)', () {
    const names = {
      'vivienda': 'Vivienda',
      'alimentacion': 'Alimentación',
      'transporte': 'Transporte',
      'salud': 'Salud',
    };
    final four = [
      budgetOf(BudgetLevel.warning, percentage: 89),
      budgetOf(
        BudgetLevel.exceeded,
        category: 'alimentacion',
        amount: 200000,
        consumed: 248000,
        percentage: 124,
      ),
      budgetOf(BudgetLevel.none, category: 'transporte', amount: 300000, consumed: 90000, percentage: 30),
      budgetOf(BudgetLevel.warning, category: 'salud', amount: 100000, consumed: 95000, percentage: 95),
    ];

    testWidgets('los 3 con más consumo, de más a menos, y «+ 1 presupuesto más»', (tester) async {
      home.onBudgets = () async => four;
      home.onCategoryNames = () async => names;
      await _pump(tester);
      final rows = [
        for (final name in ['Alimentación', 'Salud', 'Vivienda']) tester.getTopLeft(find.text(name)).dy,
      ];
      expect(rows, orderedEquals([...rows]..sort()));
      expect(find.text('Transporte'), findsNothing);
      expect(find.text('${_m(248000)} de ${_m(200000)} · 124 %'), findsOneWidget);
      expect(find.text('+ 1 presupuesto más'), findsOneWidget);
      await _tap(tester, find.text('Ver y editar'));
      expect(find.text('RUTA ${Routes.budgets}'), findsOneWidget);
    });

    testWidgets('sin presupuestos: la invitación; si fallan: el aviso con «Reintentar», nunca «Cargando…»', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Aún no tienes presupuestos. Ponle un tope a lo que más gastas.'), findsOneWidget);

      var fail = true;
      home.onBudgets = () async {
        if (fail) throw serverError;
        return four;
      };
      await _pump(tester);
      final section = find.byType(TopBudgets);
      expect(
        find.descendant(of: section, matching: find.text('No pudimos traer todos tus datos.')),
        findsOneWidget,
      );
      expect(find.descendant(of: section, matching: find.bySemanticsLabel('Cargando…')), findsNothing);
      fail = false;
      await _tap(tester, find.descendant(of: section, matching: find.text('Reintentar')));
      expect(find.text('+ 1 presupuesto más'), findsOneWidget);
    });

    testWidgets('«Más de tu plata»: los 9 accesos de la web, cada uno a su ruta', (tester) async {
      for (final (label, hint, route) in [
        ('Presupuestos', 'Topes por categoría', Routes.budgets),
        ('Calendario', 'Pagos fijos del mes', Routes.calendar),
        ('Cuentas', 'Lo que te deben y debes', Routes.debts),
        ('Tarjetas', 'Cupo y fechas de pago', Routes.cards),
        ('Por confirmar', 'Gastos que llegaron solos', Routes.toConfirm),
        ('Consejos', 'Tu semana y la IA', Routes.insights),
        ('Exportar', 'Excel o PDF', Routes.export),
        ('Renta y DIAN', 'Si te toca declarar', Routes.renta),
        ('Próximos días', 'Lo que entra y sale', Routes.liquidity),
      ]) {
        await _pump(tester);
        expect(find.text('Más de tu plata'), findsOneWidget);
        // «Pagos fijos del mes» también es el título de su sección (4C).
        final shortcut = find.descendant(of: find.byType(MoneyShortcuts), matching: find.text(hint));
        expect(shortcut, findsOneWidget, reason: label);
        await _tap(tester, shortcut);
        expect(find.text('RUTA $route'), findsOneWidget, reason: label);
      }
    });

    testWidgets('«Más de tu plata»: dos columnas solo si cada palabra cabe entera; ninguna se parte', (
      tester,
    ) async {
      final grid = find.byType(MoneyShortcuts);
      for (final (size, scale, twoColumns) in [
        (const Size(800, 1200), 1.0, true),
        (const Size(800, 1200), 1.3, false),
        (const Size(320, 568), 1.0, null),
        (const Size(360, 640), 1.3, null),
        (const Size(390, 844), 1.15, null),
      ]) {
        final at = '$size ×$scale';
        await _pump(tester, size: size, textScale: scale);
        await tester.ensureVisible(find.text('Más de tu plata'));
        await tester.pumpAndSettle();
        if (twoColumns != null) {
          double top(String label) =>
              tester.getTopLeft(find.descendant(of: grid, matching: find.text(label))).dy;
          expect(top('Calendario') == top('Presupuestos'), twoColumns, reason: at);
        }
        for (final element in find.descendant(of: grid, matching: find.byType(RichText)).evaluate()) {
          final text = element.renderObject! as RenderParagraph;
          expect(
            text.getMinIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(text.constraints.maxWidth + 0.01),
            reason: '$at: ${text.text.toPlainText()}',
          );
        }
      }
    });

    testWidgets('montos ocultos: la plata, el ritmo y los presupuestos sin un dígito', (tester) async {
      final handle = tester.ensureSemantics();
      home.onBudgets = () async => four;
      home.onCategoryNames = () async => names;
      await _pump(tester, hidden: true);
      for (final digits in ['412', '13.077', '287', '248', '200.000']) {
        expect(find.textContaining(digits), findsNothing, reason: digits);
      }
      // El porcentaje no es un monto: se ve.
      expect(find.textContaining('124 %'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Alimentación, .*Monto oculto')), findsOneWidget);
      handle.dispose();
    });

    for (final (name, theme) in [('claro', RindeTheme.light), ('oscuro', RindeTheme.dark)]) {
      testWidgets('320 de ancho y letra al doble con todo lleno, tema $name: nada se desborda', (
        tester,
      ) async {
        home.onPlan = () async => planOf(money: -9999999999);
        home.onTotals = (date) async => totalsOf(income: 9999999999, expense: 9999999999);
        home.onBudgets = () async => [
          for (final b in four)
            budgetOf(
              b.level,
              category: b.category,
              amount: 9999999999,
              consumed: 9999999999,
              percentage: 100,
            ),
        ];
        home.onCategoryNames = () async => {
          for (final key in names.keys) key: 'Una categoría con un nombre larguísimo de verdad $key',
        };
        repo.onProfile = () async => MoneyProfile(
          welcomeDone: true,
          money: -9999999999,
          commitments: [
            Commitment(
              id: '1',
              name: 'Un pago con un nombre larguísimo ' * 2,
              amount: 9999999999,
              dayOfMonth: 31,
            ),
          ],
        );
        await _pump(tester, size: const Size(320, 568), textScale: 2, theme: theme);
        expect(find.textContaining('Ojo con el 30 de noviembre.'), findsOneWidget);
        for (final target in [find.text('Más de tu plata'), find.text('Excel o PDF')]) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
