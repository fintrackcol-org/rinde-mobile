import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../auth/application/session_controller.dart';
import '../application/onboarding_controller.dart';
import '../data/demo_onboarding_repository.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_flow.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODO DEMOSTRACIÓN / SIN BACKEND — solo desarrollo.
//  TEXTO NUEVO: todos los textos de este archivo son nuevos, en español y sin traducir (como la
//  etiqueta DemoBadge): nunca los ve alguien con una compilación de tienda.
// ─────────────────────────────────────────────────────────────────────────────

const demoWarning = 'MODO DEMOSTRACIÓN · SIN BACKEND: nada se envía a ningún servidor.';

/// Panel «DEMO» de la bienvenida: latencia, fallas a propósito, reiniciar y salir.
Future<void> showDemoPanel(BuildContext context, {required OnboardingMode mode}) =>
    _showDemoSheet<void>(context, _DemoPanel(mode: mode));

/// Elegir un escenario sintético desde la pantalla de entrada. Devuelve null si se cierra.
Future<DemoScenario?> showDemoScenarioSheet(BuildContext context) =>
    _showDemoSheet<DemoScenario>(context, const _ScenarioSheet());

Future<T?> _showDemoSheet<T>(BuildContext context, Widget body) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Canvas y no surface: en la pantalla pública surface es casi transparente.
  backgroundColor: context.palette.canvas,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(RindeRadius.x3)),
  ),
  builder: (context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      RindeSpace.s5,
      RindeSpace.s5,
      RindeSpace.s5,
      RindeSpace.s5 + MediaQuery.paddingOf(context).bottom,
    ),
    child: body,
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
  final OnboardingMode mode;

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

  static const _operations = [
    (DemoOperation.region, 'Guardar país e idioma', 'PATCH /users/me'),
    (DemoOperation.welcome, 'Guardar la bienvenida', 'POST /money-profile/welcome'),
    (DemoOperation.sources, 'Guardar las fuentes de ingreso', 'PUT /money-profile/sources'),
    (DemoOperation.status, 'Leer el estado de la bienvenida', 'GET /money-profile'),
  ];

  /// Como el cierre de la demostración: la cuenta sintética vuelve a cero y se empieza en el saludo.
  Future<void> _restart(BuildContext context) async {
    // El contenedor y no `ref`: sigue sirviendo aunque la hoja se cierre a mitad.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(onboardingRepositoryProvider);
    if (repo is DemoOnboardingRepository) await repo.reset();
    container.invalidate(welcomeStatusProvider);
    await container.read(onboardingControllerProvider(mode).notifier).restartDemo();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _exit(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    await container.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final controls = ref.watch(demoControlsProvider);
    final notifier = ref.read(demoControlsProvider.notifier);
    final repo = ref.watch(onboardingRepositoryProvider);

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
        for (final (op, label, endpoint) in _operations) ...[
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
        const SizedBox(height: RindeSpace.s8),
        RindeButton(
          label: 'Reiniciar demostración',
          variant: RindeButtonVariant.outline,
          onPressed: () => _restart(context),
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
