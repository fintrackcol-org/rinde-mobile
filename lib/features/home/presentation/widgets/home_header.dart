import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_logo.dart';
import '../../application/home_providers.dart';
import 'home_tap.dart';
import '../../../auth/application/session_controller.dart';

/// Encabezado del Inicio (MobileHome.jsx): el nombre a la izquierda; avisos y ocultar montos a la derecha.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final hidden = ref.watch(hiddenAmountsProvider);
    // Si los avisos no llegan no hay insignia: nunca se inventa un número.
    final unread = ref.watch(homeUnreadProvider(ref.watch(accountProvider))).value ?? 0;
    final iconColor = p.ink.withValues(alpha: 0.7);
    const circle = BorderRadius.all(Radius.circular(RindeRadius.pill));
    return Row(
      children: [
        Semantics(
          label: t('Rinde'),
          image: true,
          child: RindeWordmark(height: 28, color: p.ink),
        ),
        const Spacer(),
        HomeTap(
          onTap: () => context.push(Routes.notifications),
          label: unread == 0
              ? t('Notificaciones')
              : t('Notificaciones, {unread} sin leer', {'unread': unread}),
          radius: circle,
          child: SizedBox.square(
            dimension: RindeSize.tapTarget,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RindeIcon(RindeIcons.bell, size: 22, color: iconColor),
                if (unread > 0)
                  PositionedDirectional(
                    end: 4,
                    top: 4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.brandSolid, borderRadius: circle),
                      // La insignia no crece con el texto del sistema: el número lo dice la etiqueta.
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textScaler: TextScaler.noScaling,
                        style: RindeType.caption
                            .w(FontWeight.w700)
                            .copyWith(color: RindeBrand.white, fontSize: 11, height: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        HomeTap(
          onTap: ref.read(hiddenAmountsProvider.notifier).toggle,
          label: hidden ? t('Mostrar montos') : t('Ocultar montos'),
          toggled: hidden,
          radius: circle,
          child: SizedBox.square(
            dimension: RindeSize.tapTarget,
            child: Center(
              child: RindeIcon(hidden ? RindeIcons.eyeOff : RindeIcons.eye, size: 22, color: iconColor),
            ),
          ),
        ),
      ],
    );
  }
}
