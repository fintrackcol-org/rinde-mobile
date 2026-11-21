import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../design/theme/rinde_theme.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_logo.dart';
import '../../../../design/widgets/rinde_motion.dart';
import 'auth_switch.dart';

/// Estructura de las pantallas de acceso (AuthLayout.jsx): siempre oscura, brillo violeta arriba,
/// logo a la izquierda y "Volver" a la derecha, columna centrada de máximo 400.
/// Se desplaza con el teclado abierto y respeta las zonas seguras.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.mode,
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Subtítulo con formato (p. ej. el correo en negrita). Reemplaza a [subtitle].
  final Widget? subtitleWidget;
  final RindeIcons? icon;

  /// Con valor, muestra el selector "Iniciar sesión | Crear cuenta".
  final AuthMode? mode;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: RindeTheme.public,
      child: Builder(
        builder: (context) {
          final p = context.palette;
          return PopScope(
            canPop: context.canPop(),
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) context.go(Routes.welcome);
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
              child: Scaffold(
                backgroundColor: RindeBrand.black,
                body: Stack(
                  children: [
                    // Brillo: círculo violeta al 20 % muy difuminado (bg-violet/20 blur-[140px]).
                    const Positioned(top: -160, left: 0, right: 0, child: _Glow()),
                    SafeArea(
                      child: Column(
                        children: [
                          const _Header(),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, viewport) => SingleChildScrollView(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(
                                  RindeSpace.s4,
                                  RindeSpace.s6,
                                  RindeSpace.s4,
                                  RindeSpace.s10,
                                ),
                                child: ConstrainedBox(
                                  // Alto del área visible menos el padding vertical: centra si sobra espacio.
                                  constraints: BoxConstraints(
                                    minHeight: (viewport.maxHeight - RindeSpace.s6 - RindeSpace.s10).clamp(
                                      0,
                                      double.infinity,
                                    ),
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: RindeSpace.authColumn),
                                      child: RindeFadeUp(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            if (mode != null) ...[
                                              AuthSwitch(mode: mode!),
                                              const SizedBox(height: RindeSpace.s8),
                                            ],
                                            if (icon != null) ...[
                                              Center(child: RindeIconTile(icon!)),
                                              const SizedBox(height: RindeSpace.s5),
                                            ],
                                            Semantics(
                                              header: true,
                                              child: Text(
                                                title,
                                                textAlign: TextAlign.center,
                                                style: RindeType.display.copyWith(color: p.ink),
                                              ),
                                            ),
                                            if (subtitleWidget != null) ...[
                                              const SizedBox(height: RindeSpace.s2),
                                              subtitleWidget!,
                                            ] else if (subtitle != null) ...[
                                              const SizedBox(height: RindeSpace.s2),
                                              Text(
                                                subtitle!,
                                                textAlign: TextAlign.center,
                                                style: RindeType.small.copyWith(
                                                  color: p.ink.withValues(alpha: 0.55),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: RindeSpace.s8),
                                            ...children,
                                            if (footer != null) ...[
                                              const SizedBox(height: RindeSpace.s8),
                                              footer!,
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 560,
        height: 560,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Un degradado radial imita el blur de la web sin el costo de un filtro de desenfoque.
          gradient: RadialGradient(
            colors: [
              RindeBrand.violet.withValues(alpha: 0.28),
              RindeBrand.violet.withValues(alpha: 0.10),
              RindeBrand.violet.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const RindeLogo(),
            const Spacer(),
            // "Volver": regresa a la bienvenida (en la web, a la landing).
            Semantics(
              button: true,
              label: 'Volver al inicio',
              onTap: () => context.go(Routes.welcome),
              excludeSemantics: true,
              child: Material(
                color: RindeBrand.white.withValues(alpha: 0.05),
                shape: StadiumBorder(side: BorderSide(color: RindeBrand.white.withValues(alpha: 0.15))),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  // Siempre a la bienvenida, aunque se haya llegado pasando por otras pantallas.
                  onTap: () => context.go(Routes.welcome),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RindeIcon(RindeIcons.arrowLeft, size: 16, color: p.ink.withValues(alpha: 0.9)),
                          const SizedBox(width: RindeSpace.s2),
                          Text(
                            'Volver',
                            style: RindeType.label.copyWith(color: p.ink.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
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
