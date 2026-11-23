import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../auth/application/session_controller.dart';
import '../../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;

/// La bienvenida quedó a medias en este teléfono: mientras no termine, Mi plata no escribe (ver
/// `MoneyWriter`) y aquí se ofrece terminarla por la misma ruta con que la retoma la entrada. Al
/// terminarla, la bienvenida invalida [pendingSourcesProvider] y el aviso se va. Sin aviso no ocupa nada.
class WelcomePendingBanner extends ConsumerWidget {
  const WelcomePendingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingSourcesProvider(ref.watch(accountProvider))).value ?? false;
    if (!pending) return const SizedBox.shrink();
    final t = ref.watch(trProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: RindeSpace.s4),
      child: RindeBanner(
        tone: RindeBannerTone.info,
        // TEXTO NUEVO
        message: t('Primero terminemos de guardar tu bienvenida.'),
        action: RindeTextLink(
          // TEXTO NUEVO
          label: t('Terminar'),
          onPressed: () => context.go(Routes.onboardingQuestions),
        ),
      ),
    );
  }
}
