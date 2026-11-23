// Mi plata, bloque 4A: la tarjeta «Cómo te entra la plata» y su hoja (vista y edición), con todos
// sus estados, errores por campo, la PILA, montos ocultos y letra al doble en 320 de ancho.
import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/app/routes.dart';
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
import 'package:rinde_mobile/features/home/data/home_repository.dart';
import 'package:rinde_mobile/features/money/application/money_providers.dart';
import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/money/presentation/my_money_screen.dart';
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
      expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
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
    expect(find.textContaining('••••••'), findsOneWidget);
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
}
