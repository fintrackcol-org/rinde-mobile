import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import 'auth_switch.dart';

/// Separador + "Continuar con Google" (SocialAuth.jsx).
///
/// BLOQUEADO: el backend solo acepta id_token cuya audiencia sea el cliente OAuth web. Para
/// Android/iOS hace falta crear los clientes nativos en Google Cloud (SHA-1 del keystore) y pedir
/// el token con `serverClientId` = cliente web. Hasta entonces se muestra deshabilitado con
/// "Próximamente", exactamente como la web cuando no tiene VITE_GOOGLE_CLIENT_ID.
class GoogleSection extends StatelessWidget {
  const GoogleSection({super.key, required this.mode});
  final AuthMode mode;

  @override
  Widget build(BuildContext context) {
    final muted = RindeBrand.white.withValues(alpha: 0.55);
    final line = Expanded(child: Container(height: 1, color: RindeBrand.white.withValues(alpha: 0.1)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            line,
            const SizedBox(width: RindeSpace.s4),
            // Ocupa lo que necesita (hasta el 70 % del ancho); con texto muy grande baja de línea.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
              child: Text(
                (mode == AuthMode.register ? 'O regístrate con Google' : 'O entra con Google').toUpperCase(),
                textAlign: TextAlign.center,
                style: RindeType.caption.copyWith(color: muted, letterSpacing: 0.3),
              ),
            ),
            const SizedBox(width: RindeSpace.s4),
            line,
          ],
        ),
        const SizedBox(height: RindeSpace.s6),
        Semantics(
          button: true,
          enabled: false,
          label: 'Continuar con Google. Próximamente',
          excludeSemantics: true,
          child: Opacity(
            opacity: 0.5,
            child: Container(
              constraints: const BoxConstraints(minHeight: RindeSize.buttonLg),
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s2),
              decoration: BoxDecoration(
                borderRadius: RindeRadius.brXl,
                border: Border.all(color: RindeBrand.white.withValues(alpha: 0.15)),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RindeSpace.s2,
                runSpacing: RindeSpace.s1,
                children: [
                  SvgPicture.asset(
                    'assets/brand/google-g.svg',
                    width: 16,
                    height: 16,
                    excludeFromSemantics: true,
                  ),
                  Text('Continuar con Google', style: RindeType.bodyMedium.copyWith(color: RindeBrand.white)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: RindeBrand.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(RindeRadius.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s2, vertical: 2),
                      child: Text(
                        'Próximamente',
                        style: RindeType.caption.copyWith(color: RindeBrand.white.withValues(alpha: 0.7)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
