import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_logo.dart';
import '../../../design/widgets/rinde_motion.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/presentation/demo_panel.dart';
import '../../rin/rin.dart';

/// Primera pantalla sin sesión. Porte del cierre violeta de la landing
/// (`components/home/CallToAction.jsx`): Rin saluda e invita a crear la cuenta.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final size = MediaQuery.sizeOf(context);
    // Rin: h-[clamp(9rem,26dvh,14rem)]; el disco guarda la proporción de la web (size-24 bajo h-28).
    final rinHeight = (size.height * 0.26).clamp(144.0, 224.0);
    final discSize = rinHeight * 96 / 112;
    // Título: text-[clamp(2.5rem,12vw,3rem)] con leading 0.98 y tracking -0.04em.
    final titleSize = (size.width * 0.12).clamp(40.0, 48.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: RindeBrand.violet,
      ),
      child: Scaffold(
        backgroundColor: RindeBrand.violet,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 0, RindeSpace.s4, RindeSpace.s6),
                      child: Column(
                        children: [
                          const SizedBox(height: 64, child: Center(child: RindeLogo(onBrand: true))),
                          const Spacer(),
                          const SizedBox(height: RindeSpace.s4),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: discSize,
                                height: discSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: RindeBrand.white.withValues(alpha: 0.15),
                                ),
                              ),
                              SizedBox(
                                height: rinHeight,
                                width: rinHeight * 200 / 290,
                                // Rin se queda quieto solo con movimiento reducido del sistema.
                                child: Rin(
                                  emotion: RinEmotion.feliz,
                                  gesture: RinGesture.saludar,
                                  level: 1,
                                  tidy: 1,
                                  semanticLabel: t('Rin, la mascota de Rinde, te saluda'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: RindeSpace.s6),
                          _Rise(
                            index: 0,
                            child: Semantics(
                              header: true,
                              child: Text(
                                t('Empieza a controlar tus gastos hoy.'),
                                textAlign: TextAlign.center,
                                // El título ya es enorme: con texto grande del sistema crece hasta 1,3x
                                // para que las palabras no se partan a 320 de ancho.
                                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                                style: RindeType.hero.copyWith(
                                  fontSize: titleSize,
                                  height: 0.98,
                                  letterSpacing: -0.04 * titleSize,
                                  color: RindeBrand.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: RindeSpace.s5),
                          _Rise(
                            index: 1,
                            child: Text(
                              t('Crea tu cuenta en menos de un minuto. Sin tarjeta, sin letra pequeña.'),
                              textAlign: TextAlign.center,
                              style: RindeType.body.copyWith(color: RindeBrand.onVioletMuted),
                            ),
                          ),
                          const SizedBox(height: RindeSpace.s8),
                          const Spacer(),
                          _Rise(
                            index: 2,
                            child: RindeButton(
                              label: t('Crear cuenta gratis'),
                              variant: RindeButtonVariant.onBrand,
                              pill: true,
                              trailing: const RindeIcon(RindeIcons.arrowRight, size: 16),
                              onPressed: () => context.push(Routes.register),
                            ),
                          ),
                          const SizedBox(height: RindeSpace.s3),
                          _Rise(
                            index: 3,
                            child: RindeButton(
                              label: t('Ya tengo cuenta'),
                              variant: RindeButtonVariant.onBrandOutline,
                              pill: true,
                              onPressed: () => context.push(Routes.login),
                            ),
                          ),
                          const _DemoEntry(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// MODO DEMOSTRACIÓN (solo desarrollo, DEMO_MODE=true): entra con una cuenta sintética sin servidor.
/// En cualquier otra compilación no ocupa espacio.
class _DemoEntry extends ConsumerWidget {
  const _DemoEntry();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final scenario = await showDemoScenarioSheet(context);
    if (scenario == null || !context.mounted) return;
    await ref.read(sessionControllerProvider.notifier).signInDemo(scenario.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appConfigProvider).demoMode) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s2),
      child: TextButton(
        onPressed: () => _open(context, ref),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: RindeBrand.onVioletMuted,
          textStyle: RindeType.small.w(FontWeight.w500),
          shape: const StadiumBorder(),
        ),
        // TEXTO NUEVO (solo desarrollo)
        child: const Text('Probar sin servidor (demo)'),
      ),
    );
  }
}

/// Entrada escalonada `animate-rise` de la web: `animationDelay n*50ms`.
class _Rise extends StatelessWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => RindeFadeUp(
    offset: 10,
    duration: RindeMotion.rise,
    delay: Duration(milliseconds: index * 50),
    child: SizedBox(width: double.infinity, child: child),
  );
}
