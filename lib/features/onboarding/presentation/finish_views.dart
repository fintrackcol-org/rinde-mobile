import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../rin/rin.dart';
import '../application/onboarding_controller.dart';
import '../data/demo_onboarding_repository.dart';

/// Cierre real (el servidor confirmó): Rin celebra un momento y se entra a la app. La web va directo
/// a /app sin mensaje; aquí hay una pausa corta para que la confirmación se vea.
class CelebrationView extends ConsumerStatefulWidget {
  const CelebrationView({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends ConsumerState<CelebrationView> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Una sola vez. Con movimiento reducido Rin queda quieto y se sigue antes.
    _timer ??= Timer(
      Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 700 : 1600),
      widget.onDone,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Íconos de la barra de estado según el fondo (claros sobre oscuro y al revés).
      value: (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(RindeSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
                        ),
                        const SizedBox(
                          height: 190,
                          child: Rin(
                            emotion: RinEmotion.emocionado,
                            gesture: RinGesture.celebrar,
                            level: 3,
                            tidy: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: RindeSpace.s6),
                  Semantics(
                    liveRegion: true,
                    header: true,
                    // TEXTO NUEVO: la web no confirma al terminar.
                    child: Text(
                      t('¡Listo!'),
                      textAlign: TextAlign.center,
                      style: RindeType.headline.copyWith(fontSize: 28, height: 1.25, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// MODO DEMOSTRACIÓN: fin del recorrido sin servidor. Muestra tal cual lo que la demo "recibió".
/// Los textos son de desarrollo (como la etiqueta DEMO): en español y sin traducir.
class DemoFinishedView extends StatelessWidget {
  const DemoFinishedView({
    super.key,
    required this.outcome,
    required this.calls,
    required this.onRestart,
    required this.onExit,
  });
  final OnboardingOutcome outcome;
  final List<DemoCall> calls;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  static String _endpoint(DemoOperation op) => switch (op) {
    DemoOperation.status => 'GET /money-profile · GET /transactions',
    DemoOperation.region => 'PATCH /users/me',
    DemoOperation.welcome => 'POST /money-profile/welcome',
    DemoOperation.sources => 'PUT /money-profile/sources',
  };

  static String _body(DemoCall call) {
    // TEXTO NUEVO (desarrollo).
    if (call.body == null) return '(sin cuerpo)';
    // La API real manda las fuentes dentro de {sources} (ApiOnboardingRepository.saveSources).
    final body = call.operation == DemoOperation.sources ? {'sources': call.body} : call.body;
    return const JsonEncoder.withIndent('  ').convert(body);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      fontSize: 13,
      height: 1.45,
      color: p.ink.withValues(alpha: 0.85),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Íconos de la barra de estado según el fondo (claros sobre oscuro y al revés).
      value: (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        RindeSpace.s4,
                        RindeSpace.s6,
                        RindeSpace.s4,
                        RindeSpace.s4,
                      ),
                      children: [
                        // TEXTO NUEVO (desarrollo).
                        Text(
                          'MODO DEMOSTRACIÓN · SIN BACKEND',
                          style: RindeType.caption
                              .w(FontWeight.w700)
                              .copyWith(color: RindeBrand.destructive, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: RindeSpace.s2),
                        Semantics(
                          header: true,
                          // TEXTO NUEVO (desarrollo).
                          child: Text(
                            outcome == OnboardingOutcome.demoSkipped
                                ? 'Bienvenida omitida (demostración)'
                                : 'Demostración terminada',
                            style: RindeType.headline.copyWith(fontSize: 28, height: 1.25, color: p.ink),
                          ),
                        ),
                        const SizedBox(height: RindeSpace.s2),
                        // TEXTO NUEVO (desarrollo).
                        Text(
                          'No se envió nada a ningún servidor. Esto es lo que se habría enviado:',
                          style: RindeType.body.copyWith(color: p.inkMuted),
                        ),
                        const SizedBox(height: RindeSpace.s5),
                        // TEXTO NUEVO (desarrollo).
                        if (calls.isEmpty)
                          Text('Ninguna llamada.', style: RindeType.small.copyWith(color: p.inkMuted)),
                        for (final (i, call) in calls.indexed) ...[
                          if (i > 0) const SizedBox(height: RindeSpace.s3),
                          RindeCard(
                            padding: const EdgeInsets.all(RindeSpace.s4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _endpoint(call.operation),
                                  style: RindeType.label.w(FontWeight.w600).copyWith(color: p.ink),
                                ),
                                const SizedBox(height: RindeSpace.s2),
                                SelectableText(_body(call), style: mono),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RindeSpace.s4,
                      RindeSpace.s3,
                      RindeSpace.s4,
                      RindeSpace.s3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // TEXTO NUEVO (desarrollo).
                        RindeButton(label: 'Reiniciar demostración', onPressed: onRestart),
                        const SizedBox(height: RindeSpace.s2),
                        // TEXTO NUEVO (desarrollo).
                        RindeButton(
                          label: 'Ir al inicio',
                          variant: RindeButtonVariant.outline,
                          onPressed: onExit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
