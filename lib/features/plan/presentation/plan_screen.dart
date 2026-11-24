import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../money/presentation/widgets/money_shortcuts.dart' show ShortcutGrid;
import '../../shell/presentation/rinde_tab_scaffold.dart';

/// Pestaña Planear (Planear.jsx): «Inicio es hoy, Movimientos lo que ya pasó, Planear lo que viene».
/// Metas todavía no está en la app: abre «En desarrollo».
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return RindeTabScaffold(
      current: RindeTab.plan,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          RindeSpace.s4,
          RindeSpace.s6,
          RindeSpace.s4,
          RindeTabScaffold.bottomInset(context),
        ),
        children: [
          Semantics(
            header: true,
            child: Text(t('Planear'), style: RindeType.headline.copyWith(color: p.ink)),
          ),
          const SizedBox(height: RindeSpace.s1),
          Text(
            t('Lo que viene y lo que quieres lograr.'),
            style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: RindeSpace.s5),
          ShortcutGrid(
            title: t('Tus planes'),
            items: [
              (Routes.payments, t('Pagos fijos'), t('Lo que se repite cada mes'), RindeIcons.repeat),
              (Routes.calendar, t('Calendario'), t('Qué toca pagar y cuándo'), RindeIcons.calendarDays),
              (Routes.budgets, t('Presupuestos'), t('Topes por categoría'), RindeIcons.target),
              (Routes.goals, t('Metas'), t('Para qué estás ahorrando'), RindeIcons.flag),
              (Routes.debts, t('Deudas'), t('Lo que te deben y debes'), RindeIcons.handCoins),
              (Routes.cards, t('Tarjetas'), t('Cupo y fechas de pago'), RindeIcons.creditCard),
            ],
          ),
        ],
      ),
    );
  }
}
