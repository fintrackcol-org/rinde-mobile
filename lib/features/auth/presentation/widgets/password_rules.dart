import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../domain/auth_validators.dart';

/// Requisitos de la contraseña nueva en vivo (PasswordRules.jsx): cada uno se pone verde al
/// cumplirse. Son las mismas reglas de AuthValidators.newPassword, así que todas en verde = válida.
class PasswordRules extends ConsumerWidget {
  const PasswordRules({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : RindeMotion.fast;
    return Semantics(
      container: true,
      label: t('Requisitos de la contraseña'),
      child: Wrap(
        spacing: RindeSpace.s4,
        runSpacing: RindeSpace.s1,
        children: [
          for (final rule in AuthValidators.passwordRules(password))
            Semantics(
              container: true,
              // En la web va como texto oculto "(cumplido)" / "(pendiente)".
              label: '${t(rule.label)} ${rule.met ? t('(cumplido)') : t('(pendiente)')}',
              excludeSemantics: true,
              child: AnimatedDefaultTextStyle(
                duration: duration,
                style: RindeType.caption.copyWith(
                  color: rule.met ? RindeBrand.success : RindeBrand.white.withValues(alpha: 0.55),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sin color propio: toma el del texto, así el check cambia junto con la etiqueta.
                    const RindeIcon(RindeIcons.checkBold, size: 14),
                    const SizedBox(width: RindeSpace.s1),
                    Text(t(rule.label)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
