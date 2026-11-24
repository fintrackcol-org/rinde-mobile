import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_circle_actions.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show homeCategoryNamesProvider;
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../movements/presentation/list/movement_row.dart';
import '../../shell/presentation/pushed_frame.dart';
import '../application/plan_providers.dart';
import '../domain/plan_rules.dart';
import 'widgets/budget_sheet.dart';
import 'widgets/plan_widgets.dart';

/// `/app/presupuestos/{categoría}?mes=AAAA-MM` (BudgetDetail.jsx): cuánto lleva un presupuesto, sus
/// gastos del mes, «Anotar» con esa categoría y «Modificar presupuesto» (cambiar el límite o
/// eliminarlo). Sin pantalla anterior, atrás va a Presupuestos.
class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({super.key, required this.category, required this.month});

  final String category;
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(budgetsMonthProvider((account, month)));
    final names = ref.watch(homeCategoryNamesProvider(account)).value ?? const <String, String>{};
    final name = names[category] ?? category;
    final money = moneyOf(ref);
    final budget = async.value?.where((b) => b.category == category).firstOrNull;

    final Widget body;
    if (async.hasError && !async.isLoading && !async.hasValue) {
      body = RindeBanner(
        message: moneyErrorText(async.error!, t),
        action: RindeTextLink(
          label: t('Reintentar'),
          onPressed: () => ref.invalidate(budgetsMonthProvider((account, month))),
        ),
      );
    } else if (!async.hasValue || async.isReloading) {
      body = Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (budget == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
        child: Text(
          t('Este presupuesto ya no existe.'),
          textAlign: TextAlign.center,
          style: RindeType.body.copyWith(color: p.inkMuted),
        ),
      );
    } else {
      body = _Detail(budget: budget, name: name, month: month, money: money);
    }

    return PushedFrame(
      title: name,
      fallback: Routes.budgets,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
        children: [body],
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.budget, required this.name, required this.month, required this.money});

  final BudgetStatus budget;
  final String name;
  final String month;
  final HomeMoney money;

  Future<void> _edit(BuildContext context) async {
    final result = await showBudgetSheet(context, month: month, initial: budget, canDelete: true);
    if (result == BudgetSheetResult.deleted && context.mounted) {
      context.canPop() ? context.pop() : context.go(Routes.budgets);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final b = budget;
    final over = b.level == BudgetLevel.exceeded && !atLimit(b);
    final status = over
        ? t('Te pasaste por {money} de {amount}', {'money': money(budgetOver(b)), 'amount': money(b.amount)})
        : t('Quedan {money} de {amount}', {'money': money(b.left), 'amount': money(b.amount)});
    final movements = ref.watch(budgetMovementsProvider((account, b.category, month)));
    final names = ref.watch(homeCategoryNamesProvider(account)).value ?? const <String, String>{};

    final Widget list;
    if (movements.hasError && !movements.isLoading) {
      list = RindeBanner(
        message: moneyErrorText(movements.error!, t),
        action: RindeTextLink(
          label: t('Reintentar'),
          onPressed: () => ref.invalidate(budgetMovementsProvider((account, b.category, month))),
        ),
      );
    } else if (!movements.hasValue) {
      list = Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (movements.value!.items.isEmpty) {
      list = Text(
        t('Aún no hay movimientos en este presupuesto.'),
        style: RindeType.small.copyWith(color: p.inkMuted),
      );
    } else {
      list = HomeSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: [
            for (final (i, m) in movements.value!.items.indexed) ...[
              if (i > 0) Divider(height: 1, color: p.ink.withValues(alpha: 0.1)),
              MovementRow(
                movement: m,
                category: movementCategoryName(m, names, t),
                money: money,
                t: t,
                onTap: () => context.push(Routes.movement(m.id)),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('Vas en'),
          style: RindeType.control.w(FontWeight.w400).copyWith(color: p.ink.withValues(alpha: 0.7)),
        ),
        Text('${b.percentage.round()} %', style: RindeType.display.tabular.copyWith(color: p.ink)),
        const SizedBox(height: RindeSpace.s3),
        Semantics(
          label: t('Consumo de {name}', {'name': name}),
          value: '${b.percentage.clamp(0, 100).round()} %',
          child: PlanBar(
            share: (b.percentage / 100).clamp(0, 1).toDouble(),
            color: budgetColor(context, b.displayLevel),
          ),
        ),
        const SizedBox(height: RindeSpace.s2),
        MoneyText(
          status,
          money: money,
          style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: RindeSpace.s5),
        RindeCircleActions(
          label: t('Acciones del presupuesto'),
          actions: [
            RindeCircleAction(
              label: t('Anotar'),
              icon: RindeIcons.plus,
              primary: true,
              onTap: () => context.push('${Routes.record}?categoria=${Uri.encodeQueryComponent(b.category)}'),
            ),
            RindeCircleAction(
              label: t('Modificar presupuesto'),
              icon: RindeIcons.pencil,
              onTap: () => _edit(context),
            ),
          ],
        ),
        const SizedBox(height: RindeSpace.s6),
        Semantics(
          header: true,
          child: Text('${t('Movimientos de')} $name', style: RindeType.title.copyWith(color: p.ink)),
        ),
        const SizedBox(height: RindeSpace.s2),
        list,
      ],
    );
  }
}
