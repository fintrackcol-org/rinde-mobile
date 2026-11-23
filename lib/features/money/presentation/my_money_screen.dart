import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart';
import '../../shell/presentation/pushed_frame.dart';
import '../application/money_providers.dart';
import 'widgets/income_overview_card.dart';
import 'widgets/money_left_card.dart';
import 'widgets/money_shortcuts.dart';
import 'widgets/month_commitments.dart';
import 'widgets/pending_payment_notice.dart';
import 'widgets/top_budgets.dart';
import 'widgets/welcome_pending_banner.dart';

/// `/app/mi-plata` (MiPlata.jsx, variante de celular). Se abre encima, sin barra; sin pantalla
/// anterior, atrás va al Inicio (backPath de la web). Cada parte es su propia sección, en el orden de
/// la web; cada una muestra su propio estado de carga y error.
class MyMoneyScreen extends ConsumerWidget {
  const MyMoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;

    // Todo lo de la pantalla. Termina cuando todo respondió, bien o mal.
    Future<void> refresh() {
      ref.read(todayProvider.notifier).sync();
      // Que el día nuevo llegue antes de refrescar: así se suelta lo del mes pasado.
      ref.read(todayProvider);
      final account = ref.read(accountProvider);
      Future<void> again<T>(FutureProviderFamily<T, Session?> provider) =>
          ref.refresh(provider(account).future).then<void>((_) {}, onError: (_) {});
      // Los nombres no se esperan (como en el Inicio).
      ref.invalidate(homeCategoryNamesProvider(account));
      return Future.wait([
        again(moneyProfileProvider),
        again(homePlanProvider),
        again(homeTotalsProvider),
        again(homeBudgetsProvider),
        again(incomeOverviewProvider),
      ]);
    }

    final sections = <Widget>[
      MoneyLeftSection(onRetry: refresh),
      const TopBudgets(),
      const MonthCommitments(),
      const IncomeOverviewCard(),
      const MoneyShortcuts(),
    ];

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
                    const WelcomePendingBanner(),
                    for (final (i, section) in sections.indexed) ...[
                      if (i > 0) const SizedBox(height: RindeSpace.s5),
                      section,
                      // El aviso de pagos pendientes, bajo «Ojo con el…» (los `children` de la web).
                      // Sin aviso no ocupa nada: su espacio de arriba va dentro.
                      if (i == 0) const PendingPaymentNotice(),
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
