import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';

enum AuthMode { login, register }

/// Selector "Iniciar sesión | Crear cuenta" (AuthSwitch de AuthLayout.jsx): dos opciones de 44,
/// indicador blanco/15 que se desliza en 240 ms. Reemplaza la pantalla para no apilar historial.
class AuthSwitch extends ConsumerWidget {
  const AuthSwitch({super.key, required this.mode});
  final AuthMode mode;

  /// Marca de navegación: la pantalla llegó desde el selector (solo entonces se desliza).
  static const switched = 'auth-switch';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final slide = GoRouterState.of(context).extra == switched && !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: t('Entrar o crear cuenta'),
      child: Container(
        padding: const EdgeInsets.all(RindeSpace.s1),
        decoration: BoxDecoration(
          color: RindeBrand.white.withValues(alpha: 0.05),
          borderRadius: RindeRadius.brXl,
          border: Border.all(color: RindeBrand.white.withValues(alpha: 0.1)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                // Al cambiar de pantalla, el indicador llega deslizándose desde la otra opción.
                tween: Tween(
                  begin: slide ? (mode == AuthMode.login ? 1 : 0) : (mode == AuthMode.login ? 0 : 1),
                  end: mode == AuthMode.login ? 0 : 1,
                ),
                duration: RindeMotion.page,
                curve: RindeMotion.screen,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: 0.5,
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RindeBrand.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(RindeRadius.segment),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _Option(
                  label: t('Iniciar sesión'),
                  selected: mode == AuthMode.login,
                  onTap: () => context.pushReplacement(Routes.login, extra: switched),
                ),
                _Option(
                  label: t('Crear cuenta'),
                  selected: mode == AuthMode.register,
                  onTap: () => context.pushReplacement(Routes.register, extra: switched),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: selected ? null : onTap,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(RindeRadius.segment),
        // 44 como la web, pero crece con el texto grande del sistema.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RindeSize.button),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: RindeType.control.copyWith(
                color: selected ? RindeBrand.white : RindeBrand.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
