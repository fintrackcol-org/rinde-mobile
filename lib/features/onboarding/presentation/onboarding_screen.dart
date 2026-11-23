import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../application/onboarding_controller.dart';
import '../data/demo_onboarding_repository.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_flow.dart';
import 'demo_panel.dart';
import 'finish_views.dart';
import 'steps/balance_step.dart';
import 'steps/country_step.dart';
import 'steps/hello_step.dart';
import 'steps/income_step.dart';
import 'steps/payments_step.dart';
import 'steps/tour_step.dart';
import 'widgets/onboarding_shell.dart';
import '../../home/application/home_providers.dart' show invalidateHome;

/// Bienvenida con sesión (pages/app/Welcome.jsx). Dos modos de entrada explícitos (rutas propias):
/// completa y solo las tres preguntas de plata.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final AppLifecycleListener _lifecycle;

  OnboardingProvider get _provider => onboardingControllerProvider(widget.mode);
  OnboardingController get _controller => ref.read(_provider.notifier);

  @override
  void initState() {
    super.initState();
    // Llamada, otra app, cierre: el borrador se escribe en el acto (no solo al terminar la espera).
    _lifecycle = AppLifecycleListener(onHide: () => _controller.flush(), onPause: () => _controller.flush());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _leave() {
    // El idioma de la vista previa no sale de la bienvenida: vuelve el de la región guardada.
    ref.invalidate(displayLanguageProvider);
    context.go(Routes.app);
  }

  void _onBack() {
    if (_controller.back()) return;
    if (widget.mode != OnboardingMode.questions) return;
    // Salió sin terminar: en esta sesión la entrada ya no la devuelve aquí (si no, con las fuentes
    // pendientes no podría llegar al Inicio).
    ref.read(resumeDeferredProvider.notifier).defer();
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final t = ref.watch(trProvider);

    // Ya la hizo: no se vuelve a mostrar (la web sí la repite).
    ref.listen(_provider.select((s) => s.alreadyDone), (_, done) {
      if (done) _leave();
    });

    if (!state.ready) {
      return const Scaffold(body: Center(child: RindeSpinner(size: 28)));
    }

    final outcome = state.outcome;
    if (outcome == OnboardingOutcome.saved || outcome == OnboardingOutcome.skipped) {
      return CelebrationView(onDone: _leave);
    }
    if (outcome == OnboardingOutcome.demoSaved || outcome == OnboardingOutcome.demoSkipped) {
      final repo = ref.read(onboardingRepositoryProvider);
      return DemoFinishedView(
        outcome: outcome!,
        calls: repo is DemoOnboardingRepository ? repo.calls : const [],
        onRestart: () async {
          if (repo is DemoOnboardingRepository) await repo.reset();
          if (!mounted) return;
          invalidateHome(ref.invalidate);
          await _controller.restartDemo();
          if (!mounted) return;
          ref.invalidate(pendingSourcesProvider);
          if (widget.mode == OnboardingMode.questions) _leave();
        },
        onExit: _leave,
      );
    }

    final screen = _screen(state, t);
    if (!state.isDemo) return screen;
    // MODO DEMOSTRACIÓN: franja propia arriba (no tapa nada); la pantalla pierde el margen superior
    // porque la franja ya ocupa la barra de estado.
    return Column(
      children: [
        DemoStrip(onTap: () => showDemoPanel(context, mode: widget.mode)),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: screen),
        ),
      ],
    );
  }

  Widget _screen(OnboardingState state, Tr t) {
    final position = state.position;

    // Saludo: pantalla propia, sin marco. Atrás del sistema sale de la app (como la web, no hay Atrás).
    if (position == OnboardingSteps.hello) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (context.palette.brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        child: HelloStep(mode: widget.mode),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: OnboardingShell(
        step: state.step,
        total: state.total,
        direction: state.direction,
        busy: state.busy != null,
        error: state.error?.resolve(t),
        onBack: _onBack,
        onSkip: _controller.skip,
        labels: OnboardingShellLabels(
          back: t('Atrás'),
          skip: t('Omitir'),
          progress: t('Avance de la bienvenida'),
          stepOf: (step, total) => t('Paso {step} de {total}', {'step': step, 'total': total}),
        ),
        action: _action(state, t),
        child: _content(position),
      ),
    );
  }

  Widget _content(int position) {
    if (position == OnboardingSteps.country) return CountryStep(mode: widget.mode);
    if (OnboardingSteps.isTour(position)) {
      return TourStep(index: position - OnboardingSteps.tour, onNext: _controller.next, onBack: _onBack);
    }
    if (position == OnboardingSteps.income) return IncomeStep(mode: widget.mode);
    if (position == OnboardingSteps.balance) return BalanceStep(mode: widget.mode);
    return PaymentsStep(mode: widget.mode);
  }

  Widget _action(OnboardingState state, Tr t) {
    final position = state.position;
    if (position == OnboardingSteps.country) {
      return RindeButton(
        label: t('Seguir'),
        loading: state.busy == OnboardingBusy.region,
        onPressed: state.busy != null ? null : _controller.saveRegion,
      );
    }
    if (position == OnboardingSteps.payments) {
      return RindeButton(
        label: t('Ver mi plata'),
        loadingLabel: t('Guardando…'),
        loading: state.busy == OnboardingBusy.finishing,
        onPressed: state.busy != null ? null : _controller.finish,
      );
    }
    return RindeButton(
      label: t(position < OnboardingSteps.income ? 'Siguiente' : 'Seguir'),
      onPressed: state.busy != null ? null : _controller.next,
    );
  }
}

// Alias corto del tipo del proveedor con argumento.
typedef OnboardingProvider = NotifierProvider<OnboardingController, OnboardingState>;

/// Mientras carga el estado de la bienvenida, el fondo del tema (sin destellos).
class OnboardingLoading extends StatelessWidget {
  const OnboardingLoading({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.canvas,
    child: const Center(child: RindeSpinner(size: 28)),
  );
}
