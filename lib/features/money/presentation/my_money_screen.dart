import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart';
import '../../shell/presentation/pushed_frame.dart';
import '../application/money_providers.dart';
import 'widgets/income_overview_card.dart';

/// `/app/mi-plata` (MiPlata.jsx, variante de celular). Se abre encima, sin barra; sin pantalla
/// anterior, atrás va al Inicio (backPath de la web). Cada parte es su propia sección: la plata y los
/// accesos (4B) van arriba de «Cómo te entra la plata» y los pagos del mes (4C) aparte.
class MyMoneyScreen extends ConsumerWidget {
  const MyMoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    const sections = <Widget>[IncomeOverviewCard()];

    // Termina cuando todo respondió, bien o mal: cada sección muestra su propio estado.
    Future<void> refresh() {
      ref.read(todayProvider.notifier).sync();
      return ref.refresh(incomeOverviewProvider(account).future).then<void>((_) {}, onError: (_) {});
    }

    return PushedFrame(
      title: t('Mi plata'),
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: refresh,
        child: ListView(
          // Siempre se puede halar para recargar, aunque todo quepa en la pantalla.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s4, RindeSpace.s4, RindeSpace.s6),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, section) in sections.indexed) ...[
                      if (i > 0) const SizedBox(height: RindeSpace.s4),
                      section,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
