import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/presentation/demo_panel.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';

/// Marco de una pantalla que se abre encima de otra, sin barra de pestañas: franja demo, botón de
/// salida de 48 y título. Abierta sin pantalla anterior (un enlace directo), atrás lleva a
/// [fallback] en vez de cerrar la app (el `backPath` de la web).
class PushedFrame extends ConsumerWidget {
  const PushedFrame({
    super.key,
    required this.child,
    this.title,
    this.closeLabel,
    this.back = true,
    this.fallback = Routes.app,
  });

  final Widget child;

  /// null: solo el botón (el título va en el contenido).
  final String? title;

  /// Lo que dice el botón al lector; por defecto «Volver».
  final String? closeLabel;

  /// true: flecha al principio. false: «X» al final (cerrar sin guardar).
  final bool back;
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = ref.watch(trProvider);
    final demo = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.demo ?? false));
    void leave() => context.canPop() ? context.pop() : context.go(fallback);
    final close = IconButton(
      onPressed: leave,
      tooltip: closeLabel ?? t('Volver'),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: RindeIcon(back ? RindeIcons.chevronLeft : RindeIcons.x, size: 24, color: p.ink),
    );
    final heading = title == null
        ? null
        : Expanded(
            child: Semantics(
              header: true,
              child: Text(title!, style: RindeType.headline.copyWith(color: p.ink)),
            ),
          );
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(fallback);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: p.canvas,
          body: Column(
            children: [
              // También aquí se dice que es una demostración.
              if (demo) DemoStrip(onTap: () => showDemoPanel(context)),
              Expanded(
                child: SafeArea(
                  top: !demo,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RindeSpace.s1, RindeSpace.s2, RindeSpace.s1, 0),
                        child: Row(
                          children: back
                              ? [
                                  close,
                                  if (heading != null) ...[const SizedBox(width: RindeSpace.s1), heading],
                                ]
                              : [const SizedBox(width: RindeSpace.s3), heading ?? const Spacer(), close],
                        ),
                      ),
                      Expanded(child: child),
                    ],
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
