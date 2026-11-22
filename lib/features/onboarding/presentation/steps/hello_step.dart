import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_logo.dart';
import '../../../../design/widgets/rinde_motion.dart';
import '../../../rin/rin.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_flow.dart';

/// Posición 0: saludo con Rin (components/onboarding/WelcomeIntro.jsx). Pantalla completa, sin marco
/// ni barra de avance: la marca, Rin que saluda una vez, la promesa y dos caminos (empezar o después).
class HelloStep extends ConsumerStatefulWidget {
  const HelloStep({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  ConsumerState<HelloStep> createState() => _HelloStepState();
}

class _HelloStepState extends ConsumerState<HelloStep> {
  bool _waving = false;
  late final List<Timer> _timers;

  @override
  void initState() {
    super.initState();
    // Rin saluda una sola vez al llegar (450 ms) y vuelve a quedarse tranquilo (2100 ms), como la web.
    _timers = [
      Timer(const Duration(milliseconds: 450), () => setState(() => _waving = true)),
      Timer(const Duration(milliseconds: 2100), () => setState(() => _waving = false)),
    ];
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = onboardingControllerProvider(widget.mode);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final t = ref.watch(trProvider);
    final p = context.palette;
    final busy = state.busy != null;
    final name = state.userName;
    final error = state.error?.resolve(t);

    // Escenario de Rin según el alto de la pantalla (clamp de la web en dvh): en un celular bajito se
    // encoge en vez de montarse sobre el texto.
    final height = MediaQuery.sizeOf(context).height;
    final stage = (height * 0.30).clamp(160.0, 256.0);
    final disc = (height * 0.28).clamp(152.0, 240.0);
    final rin = (height * 0.26).clamp(144.0, 224.0);

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        minimum: const EdgeInsets.only(top: RindeSpace.s5, bottom: RindeSpace.s3),
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Rise(
                          index: 0,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: RindeLogo(color: p.ink),
                          ),
                        ),
                        Expanded(
                          child: _Rise(
                            index: 1,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: stage),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // El piso de Rin: un disco suave de la marca, sin degradados ni brillo.
                                  Container(
                                    width: disc,
                                    height: disc,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: p.brandSoft),
                                  ),
                                  SizedBox(
                                    height: rin,
                                    width: rin * 200 / 290,
                                    child: Rin(
                                      emotion: _waving ? RinEmotion.feliz : RinEmotion.tranquilo,
                                      gesture: _waving ? RinGesture.saludar : null,
                                      level: 1,
                                      tidy: 1,
                                      semanticLabel: t('Rin, la mascota de Rinde, te saluda'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (name != null && name.isNotEmpty)
                          _Rise(
                            index: 2,
                            child: Text(
                              t('Hola, {name}', {'name': name}),
                              style: RindeType.control.copyWith(color: p.brand),
                            ),
                          ),
                        const SizedBox(height: RindeSpace.s1),
                        _Rise(
                          index: 3,
                          child: Semantics(
                            header: true,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: t('Tu plata tiene una historia.')),
                                  const TextSpan(text: ' '),
                                  TextSpan(
                                    text: t('Entendámosla juntos.'),
                                    style: TextStyle(color: p.inkSubtle),
                                  ),
                                ],
                              ),
                              // 32 ya es grande: con texto grande del sistema crece hasta 1,3x para que
                              // «Entendámosla» no se parta a 320 de ancho (el resto de textos sí escala).
                              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                              style: RindeType.headline.copyWith(
                                fontSize: 32,
                                height: 1.1,
                                letterSpacing: -0.025 * 32,
                                color: p.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: RindeSpace.s3),
                        _Rise(
                          index: 4,
                          child: Text(
                            t('Descubre cómo organizar tu dinero y tomar mejores decisiones.'),
                            style: RindeType.body.copyWith(color: p.inkMuted),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _Rise(
                          index: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                                ),
                                const SizedBox(height: RindeSpace.s2),
                              ],
                              RindeButton(label: t('Empezar'), onPressed: busy ? null : controller.start),
                              const SizedBox(height: RindeSpace.s1),
                              // Ghost de 16 px como la web (h-11), pero con el área táctil de 48.
                              ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                                child: RindeButton(
                                  label: t('Ahora no'),
                                  variant: RindeButtonVariant.ghost,
                                  size: RindeButtonSize.md,
                                  loading: state.busy == OnboardingBusy.later,
                                  onPressed: busy ? null : controller.later,
                                ),
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
          ],
        ),
      ),
    );
  }
}

/// Entrada escalonada `animate-rise` de la web: 0,42 s desde 10 px abajo, `animationDelay n*50ms`.
class _Rise extends StatelessWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => RindeFadeUp(
    offset: 10,
    duration: RindeMotion.rise,
    delay: Duration(milliseconds: index * 50),
    child: child,
  );
}
