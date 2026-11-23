import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app.dart' show themeModeProvider;
import '../../../app/routes.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart';
import '../application/onboarding_controller.dart';
import '../data/demo_onboarding_repository.dart';
import '../data/draft_store.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_flow.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND — solo desarrollo.
//  TEXTO NUEVO: todos los textos de este archivo son nuevos, en español y sin traducir (como la
//  etiqueta DemoBadge): nunca los ve alguien con una compilación de tienda.
// ─────────────────────────────────────────────────────────────────────────────

const demoWarning = 'MODO DEMOSTRACIÓN · SIN BACKEND: nada se envía a ningún servidor.';

/// Panel «DEMO»: latencia, fallas a propósito, reiniciar y salir. Con [mode] es el de la bienvenida;
/// sin él se abrió desde el Inicio o las pestañas y además deja cambiar la región y el tema.
Future<void> showDemoPanel(BuildContext context, {OnboardingMode? mode}) =>
    _showDemoSheet<void>(context, _DemoPanel(mode: mode));

/// Elegir un escenario sintético desde la pantalla de entrada. Devuelve null si se cierra.
Future<DemoScenario?> showDemoScenarioSheet(BuildContext context) =>
    _showDemoSheet<DemoScenario>(context, const _ScenarioSheet());

Future<T?> _showDemoSheet<T>(BuildContext context, Widget body) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // El fondo lo pinta el contenido con el tema del momento: el panel cambia el tema estando abierto.
  backgroundColor: Colors.transparent,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(RindeRadius.x3)),
  ),
  builder: (context) => ColoredBox(
    // Canvas y no surface: en la pantalla pública surface es casi transparente.
    color: context.palette.canvas,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        RindeSpace.s5,
        RindeSpace.s5,
        RindeSpace.s5,
        RindeSpace.s5 + MediaQuery.paddingOf(context).bottom,
      ),
      child: body,
    ),
  ),
);

class _ScenarioSheet extends StatelessWidget {
  const _ScenarioSheet();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('Probar sin servidor'),
        const SizedBox(height: RindeSpace.s3),
        const _Warning(),
        const SizedBox(height: RindeSpace.s5),
        for (final scenario in DemoScenario.values) ...[
          RindeButton(
            label: scenario.label,
            variant: RindeButtonVariant.outline,
            onPressed: () => Navigator.of(context).pop(scenario),
          ),
          const SizedBox(height: RindeSpace.s2),
        ],
      ],
    );
  }
}

class _DemoPanel extends ConsumerWidget {
  const _DemoPanel({required this.mode});

  /// null = abierto desde el Inicio o las pestañas.
  final OnboardingMode? mode;

  static final _latencies = {
    Duration.zero: '0',
    Duration(milliseconds: 700): '0,7 s',
    Duration(seconds: 2): '2 s',
  };

  static const _failures = <DemoFailure?, String>{
    null: 'Ninguna',
    DemoFailure.network: 'Sin conexión',
    DemoFailure.server: 'Error del servidor',
  };

  static const _operations = <(Enum, String, String)>[
    (DemoOperation.region, 'Guardar país e idioma', 'PATCH /users/me'),
    (DemoOperation.welcome, 'Guardar la bienvenida', 'POST /money-profile/welcome'),
    (DemoOperation.sources, 'Guardar las fuentes de ingreso', 'PUT /money-profile/sources'),
    (DemoOperation.status, 'Leer el estado de la bienvenida', 'GET /money-profile'),
  ];

  static const _homeOperations = <(Enum, String, String)>[
    (DemoHomeOperation.plan, 'Leer el plan', 'GET /money-profile/plan'),
    (DemoHomeOperation.summary, 'Leer los ingresos y gastos del mes', 'GET /transactions/summary'),
    (
      DemoHomeOperation.secondary,
      'Leer presupuestos, tarjetas, pagos por confirmar y avisos',
      'GET /budgets · /cards · /pending-payments · /notifications · /categories',
    ),
    (DemoOperation.status, 'Leer la plata y el estado de la bienvenida', 'GET /money-profile'),
  ];

  /// Países de prueba: peso sin decimales, dólar, real, euro y libra, en los tres idiomas.
  static const _countries = ['CO', 'US', 'BR', 'ES', 'GB'];

  /// La cuenta sintética vuelve a estar recién creada. En la bienvenida completa se empieza en el saludo;
  /// desde el Inicio o desde «solo las preguntas» decide la entrada (una cuenta nueva vuelve a la
  /// bienvenida completa).
  Future<void> _restart(BuildContext context) async {
    // El contenedor y no `ref`: sigue sirviendo aunque la hoja se cierre a mitad.
    final container = ProviderScope.containerOf(context, listen: false);
    final router = GoRouter.maybeOf(context);
    final userId = container.read(sessionControllerProvider).value?.session?.user.id;
    final mode = this.mode;
    final repo = container.read(onboardingRepositoryProvider);
    if (repo is DemoOnboardingRepository) await repo.reset();
    // Tampoco queda una bienvenida a medias de la cuenta anterior.
    if (userId != null) await container.read(draftStoreProvider).clear(userId);
    container.invalidate(pendingSourcesProvider);
    invalidateHome(container.invalidate);
    if (mode != null) await container.read(onboardingControllerProvider(mode).notifier).restartDemo();
    if (context.mounted) Navigator.of(context).pop();
    if (mode != OnboardingMode.full) router?.go(Routes.app);
  }

  Future<void> _exit(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    await container.read(sessionControllerProvider.notifier).signOut();
  }

  /// Cambia la región de la cuenta sintética sin pasar por la bienvenida. No se guarda en el
  /// dispositivo; sí en la demostración, para que siga al reabrir la app.
  Future<void> _setRegion(BuildContext context, String country) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final userId = container.read(sessionControllerProvider).value?.session?.user.id;
    if (userId == null) return;
    final region = regionForCountry(country);
    // Sin conexión o con una falla puesta seguirían en pantalla los montos de la otra moneda.
    container.read(demoControlsProvider.notifier).reconnect();
    final before = await container.read(demoStateStoreProvider).read(userId);
    if ((before.region ?? kDefaultRegion).currency != region.currency) {
      await _dropProposal(container.read(draftStoreProvider), userId, before);
    }
    await container.read(demoStateStoreProvider).update(userId, (state) => state.withRegion(region));
    await container.read(appRegionProvider.notifier).set(region, persist: false);
    // Los montos fijos cambian de escala con la moneda: los anteriores no se muestran mientras llegan.
    invalidateHome((provider) => container.invalidate(provider, asReload: true));
  }

  /// La propuesta de saldo que quedó en el borrador es de la otra escala: se quita solo si nadie la
  /// cambió ni la envió. Lo que escribió la persona no se toca.
  Future<void> _dropProposal(DraftStore drafts, String userId, DemoState before) async {
    final proposal = demoWelcomeStatus(DemoScenario.fromUserId(userId), before).balanceProposal;
    final draft = await drafts.read(userId);
    if (proposal == null || draft is! Map<String, dynamic> || draft['sentWelcome'] != null) return;
    if (draft['balance'] == '$proposal') await drafts.write(userId, {...draft, 'balance': ''});
  }

  void _showTour(BuildContext context, WidgetRef ref) {
    final router = GoRouter.maybeOf(context);
    ref.read(tourRequestedProvider.notifier).request();
    Navigator.of(context).pop();
    // El tutorial vive en el Inicio.
    router?.go(Routes.app);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final controls = ref.watch(demoControlsProvider);
    final notifier = ref.read(demoControlsProvider.notifier);
    final repo = ref.watch(onboardingRepositoryProvider);
    final home = mode == null;
    // Guardando no se reinicia: la respuesta en camino volvería a escribir sobre lo que se borró.
    final saving = !home && ref.watch(onboardingControllerProvider(mode!).select((s) => s.busy != null));
    final region = ref.watch(appRegionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('Panel de demostración'),
        const SizedBox(height: RindeSpace.s3),
        const _Warning(),
        if (repo is DemoOnboardingRepository) ...[
          const SizedBox(height: RindeSpace.s3),
          Text('Escenario: ${repo.scenario.label}', style: RindeType.small.copyWith(color: p.inkMuted)),
        ],
        const SizedBox(height: RindeSpace.s6),
        const _Label('Latencia de cada llamada'),
        const SizedBox(height: RindeSpace.s2),
        RindeSegmented<Duration>(
          semanticLabel: 'Latencia de cada llamada',
          options: _latencies,
          value: controls.latency,
          onChanged: notifier.setLatency,
        ),
        const SizedBox(height: RindeSpace.s6),
        const _Label('Simular falla en la próxima…'),
        for (final (op, label, endpoint) in home ? _homeOperations : _operations) ...[
          const SizedBox(height: RindeSpace.s4),
          Text(label, style: RindeType.small.copyWith(color: p.ink)),
          Text(endpoint, style: RindeType.caption.copyWith(color: p.inkMuted)),
          const SizedBox(height: RindeSpace.s2),
          RindeSegmented<DemoFailure?>(
            semanticLabel: 'Simular falla en la próxima: $label',
            options: _failures,
            value: controls.failures[op],
            onChanged: (failure) => notifier.failNext(op, failure),
          ),
        ],
        const SizedBox(height: RindeSpace.s6),
        const _Label('Conexión'),
        Text(
          'Apagada, todas las llamadas fallan hasta que la vuelvas a encender.',
          style: RindeType.caption.copyWith(color: p.inkMuted),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeSegmented<bool>(
          semanticLabel: 'Conexión',
          options: const {false: 'Encendida', true: 'Apagada'},
          value: controls.offline,
          onChanged: (offline) {
            notifier.setOffline(offline);
            // El Inicio se vuelve a pedir en el acto: se ve caer y volver sin tener que deslizar.
            if (home) invalidateHome(ref.invalidate);
          },
        ),
        if (home) ...[
          const SizedBox(height: RindeSpace.s6),
          const _Label('País, moneda e idioma'),
          Text(
            '${region.country} · ${region.currency} · ${region.language}',
            style: RindeType.caption.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s2),
          RindeSegmented<String>(
            semanticLabel: 'País, moneda e idioma',
            // El país elegido en la bienvenida puede no ser uno de los de prueba.
            options: {
              for (final code in {..._countries, region.country}) code: code,
            },
            value: region.country,
            onChanged: (country) => _setRegion(context, country),
          ),
          const SizedBox(height: RindeSpace.s6),
          const _Label('Tema'),
          const SizedBox(height: RindeSpace.s2),
          RindeSegmented<ThemeMode>(
            semanticLabel: 'Tema',
            options: const {ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
            value: ref.watch(themeModeProvider),
            onChanged: ref.read(themeModeProvider.notifier).set,
          ),
          const SizedBox(height: RindeSpace.s8),
          RindeButton(
            label: 'Ver el tutorial',
            variant: RindeButtonVariant.outline,
            onPressed: () => _showTour(context, ref),
          ),
          const SizedBox(height: RindeSpace.s2),
        ] else
          const SizedBox(height: RindeSpace.s8),
        RindeButton(
          label: 'Reiniciar demostración',
          variant: RindeButtonVariant.outline,
          onPressed: saving ? null : () => _restart(context),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeButton(
          label: 'Salir de la demostración',
          variant: RindeButtonVariant.ghost,
          onPressed: () => _exit(context),
        ),
      ],
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: RindeType.title.copyWith(color: context.palette.ink)),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: RindeType.label.copyWith(color: context.palette.ink));
}

/// Aviso fijo, en rojo de marca: que nadie confunda esto con datos guardados de verdad.
class _Warning extends StatelessWidget {
  const _Warning();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RindeBrand.destructive.withValues(alpha: 0.12),
        borderRadius: RindeRadius.brX2,
        border: Border.all(color: RindeBrand.destructive.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RindeSpace.s3),
        child: Text(demoWarning, style: RindeType.label.copyWith(color: p.negative)),
      ),
    );
  }
}
