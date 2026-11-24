import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show homeCategoryNamesProvider, todayProvider;
import '../../home/data/home_models.dart';
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/plan_providers.dart';
import '../domain/plan_rules.dart';
import 'widgets/budget_sheet.dart';
import 'widgets/plan_widgets.dart';

/// `/app/presupuestos` (Budgets.jsx, variante del celular): los topes del mes con lo que lleva cada
/// uno según el servidor, el aviso más importante y «Nuevo presupuesto». Cada fila abre su detalle,
/// donde se cambia o se borra. Sin pantalla anterior, atrás va a Planear.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  late String _month = isoMonth(ref.read(todayProvider));
  String? _notice;

  void _changeMonth(int delta) => setState(() {
    _month = shiftMonth(_month, delta);
    _notice = null;
  });

  Future<void> _create(List<BudgetStatus> budgets) async {
    setState(() => _notice = null);
    final names = ref.read(homeCategoryNamesProvider(ref.read(accountProvider))).value ?? const {};
    final before = {for (final b in budgets) b.category};
    final result = await showBudgetSheet(context, month: _month, used: before.toList());
    if (result != BudgetSheetResult.created || !mounted) return;
    // La categoría nueva es la que no estaba: la hoja no la devuelve.
    // Ya quedó guardado: si la relectura falla, solo no sale el aviso.
    final created =
        (await ref
                .read(budgetsMonthProvider((ref.read(accountProvider), _month)).future)
                .catchError((_) => const <BudgetStatus>[]))
            .where((b) => !before.contains(b.category))
            .firstOrNull;
    if (!mounted || created == null) return;
    final t = ref.read(trProvider);
    setState(
      () => _notice = t('Presupuesto de {v1} creado.', {'v1': names[created.category] ?? created.category}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(budgetsMonthProvider((account, _month)));
    final budgets = async.isReloading ? null : async.value;
    final names = ref.watch(homeCategoryNamesProvider(account)).value ?? const <String, String>{};
    final money = moneyOf(ref);
    final monthLabel = budgetMonthLabel(_month, region);

    Widget arrow(RindeIcons icon, String label, int delta) => IconButton(
      onPressed: () => _changeMonth(delta),
      tooltip: label,
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      icon: RindeIcon(icon, size: 16, color: p.ink.withValues(alpha: 0.7)),
    );

    final alert = budgets == null ? null : budgetAlert(budgets, names, t, region);
    final children = <Widget>[
      Row(
        children: [
          arrow(RindeIcons.chevronLeft, t('Mes anterior'), -1),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                capitalized(monthLabel),
                style: RindeType.control.w(FontWeight.w400).copyWith(color: p.ink.withValues(alpha: 0.7)),
              ),
            ),
          ),
          arrow(RindeIcons.chevronRight, t('Mes siguiente'), 1),
        ],
      ),
      const SizedBox(height: RindeSpace.s5),
      if (budgets != null && budgets.isNotEmpty) ...[
        _BudgetsTotal(budgets: budgets, money: money),
        const SizedBox(height: RindeSpace.s4),
      ],
      if (alert != null) ...[
        PlanAlert(message: alert.message, negative: alert.exceeded, icon: RindeIcons.triangleAlert),
        const SizedBox(height: RindeSpace.s4),
      ],
      RindeButton(
        label: t('Nuevo presupuesto'),
        leading: const RindeIcon(RindeIcons.plus, size: 18, color: RindeBrand.white),
        onPressed: budgets == null ? null : () => _create(budgets),
      ),
      const SizedBox(height: RindeSpace.s4),
      if (_notice case final notice?) ...[
        Semantics(
          liveRegion: true,
          child: Text(notice, style: RindeType.small.copyWith(color: p.positive)),
        ),
        const SizedBox(height: RindeSpace.s2),
      ],
      if (async.hasError && !async.isLoading)
        RindeBanner(
          message: moneyErrorText(async.error!, t),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(budgetsMonthProvider((account, _month))),
          ),
        ),
      if (budgets == null && !async.hasError)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
          child: Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted)),
        )
      else if (budgets != null && budgets.isEmpty && !async.hasError)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
          child: Text(
            '${t('No tienes presupuestos en')} $monthLabel'
            '${t('. Crea uno para ver cuánto llevas gastado en esa categoría.')}',
            textAlign: TextAlign.center,
            style: RindeType.body.copyWith(color: p.inkMuted),
          ),
        )
      else if (budgets != null)
        HomeSurface(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (final (i, b) in budgets.indexed) ...[
                if (i > 0) Divider(height: 1, color: p.ink.withValues(alpha: 0.1)),
                _BudgetRow(
                  budget: b,
                  name: names[b.category] ?? b.category,
                  money: money,
                  onTap: () => context.push(Routes.budget(b.category, _month)),
                ),
              ],
            ],
          ),
        ),
    ];

    return PushedFrame(
      title: t('Tus presupuestos'),
      fallback: Routes.plan,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () =>
            ref.refresh(budgetsMonthProvider((account, _month)).future).then<void>((_) {}, onError: (_) {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 0, RindeSpace.s4, RindeSpace.s6),
          children: children,
        ),
      ),
    );
  }
}

/// «Topes del mes»: cuánto suman los topes y cuánto va, con la línea de avance.
class _BudgetsTotal extends ConsumerWidget {
  const _BudgetsTotal({required this.budgets, required this.money});

  final List<BudgetStatus> budgets;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final total = budgetsTotal(budgets);
    final percent = (total.share * 100).round();
    return HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Topes del mes').toUpperCase(), style: RindeType.eyebrow.copyWith(color: p.inkMuted)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: RindeSpace.s3,
            children: [
              MoneyText(
                money(total.limit),
                money: money,
                style: RindeType.figure.copyWith(color: p.ink),
              ),
              MoneyText(
                '${t('llevas')} ${money(total.spent)} · $percent %',
                money: money,
                style: RindeType.meta.copyWith(color: p.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: t('Gastado de todos los topes'),
            value: '$percent %',
            child: PlanBar(share: total.share, color: p.brand, height: 4),
          ),
        ],
      ),
    );
  }
}

/// CompactRow de BudgetList.jsx: toda la fila abre el presupuesto.
class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.budget, required this.name, required this.money, required this.onTap});

  final BudgetStatus budget;
  final String name;
  final HomeMoney money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final b = budget;
    final level = b.displayLevel;
    final over = b.level == BudgetLevel.exceeded && !atLimit(b);
    final color = budgetColor(context, level);
    final status = over
        ? t('Te pasaste por {formatMoney} de {amount}', {
            'formatMoney': money(budgetOver(b)),
            'amount': money(b.amount),
          })
        : t('Quedan {formatMoney} de {amount}', {'formatMoney': money(b.left), 'amount': money(b.amount)});
    return HomeTap(
      onTap: onTap,
      radius: RindeRadius.brXl,
      label: t('{name}: {percentage}. Ver detalle', {
        'name': name,
        'percentage': budgetPercent(b.percentage, region),
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RindeSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: RindeType.bodyMedium.copyWith(color: p.ink)),
                ),
                Text(
                  '${b.percentage.round()} %',
                  style:
                      (level == BudgetLevel.none
                              ? RindeType.body.copyWith(color: p.ink.withValues(alpha: 0.7))
                              : RindeType.body.w(FontWeight.w600).copyWith(color: color))
                          .tabular,
                ),
              ],
            ),
            const SizedBox(height: RindeSpace.s2),
            PlanBar(share: (b.percentage / 100).clamp(0, 1).toDouble(), color: color),
            const SizedBox(height: RindeSpace.s2),
            MoneyText(
              status,
              money: money,
              style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
