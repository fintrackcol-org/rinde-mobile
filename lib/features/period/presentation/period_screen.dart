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
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../movements/application/movements_controller.dart' show movementCategoriesProvider;
import '../../movements/domain/movement.dart';
import '../../movements/presentation/list/movement_dates.dart';
import '../../movements/presentation/list/movement_row.dart';
import '../../movements/presentation/list/period_bar.dart';
import '../../plan/presentation/widgets/plan_widgets.dart' show PlanBar;
import '../../shell/presentation/pushed_frame.dart';
import '../application/period_providers.dart';
import '../data/period_models.dart';

/// `/app/ingresos` y `/app/gastos` (PeriodDetail.jsx): la pregunta que responden, el total del periodo
/// en grande con su promedio diario, lo otro y el balance, por categoría, el Kakeibo (gastos) y la lista
/// filtrable por categoría. Arranca en el mes actual.
class PeriodScreen extends ConsumerStatefulWidget {
  const PeriodScreen({super.key, required this.type});

  final MovementType type;

  @override
  ConsumerState<PeriodScreen> createState() => _PeriodScreenState();
}

class _PeriodScreenState extends ConsumerState<PeriodScreen> {
  MovementPeriod _period = MovementPeriod.month;
  late DateTime _date = ref.read(todayProvider);

  /// '' = todas; 'sin_clasificar' o la clave de una categoría.
  String _category = '';

  bool get _income => widget.type == MovementType.income;

  void _setPeriod(MovementPeriod period, DateTime date) => setState(() {
    _period = period;
    _date = date;
    _category = '';
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final today = ref.watch(todayProvider);
    final account = ref.watch(accountProvider);
    final money = moneyOf(ref);
    final income = _income;
    final title = income ? t('Ingresos') : t('Gastos');
    final label = periodLabel(_period, _date, today, region, t);
    final range = periodRange(_period, _date);
    final from = isoDay(range.from), to = isoDay(range.to);
    final summaryKey = (account, _period, isoDay(_date));
    final summary = ref.watch(periodSummaryProvider(summaryKey));
    final current = summary.hasValue && !summary.isReloading ? summary.value : null;
    final names = ref.watch(movementCategoriesProvider(account)).value?.names ?? const <String, String>{};
    final totals = current == null ? null : (income ? current.income : current.expense);
    String amount(num? value) => current == null || value == null ? '…' : money(value);

    final chips = [
      for (final r in totals?.byCategory ?? const <CategoryTotal>[])
        if (r.total > 0) r.category ?? 'sin_clasificar',
    ];
    String chipName(String key) => key == ''
        ? t('Todas')
        : key == 'sin_clasificar'
        ? t('Sin clasificar')
        : (names[key] ?? key);

    final Widget figures;
    if (summary.hasError && !summary.isLoading) {
      figures = RindeBanner(
        message: moneyErrorText(summary.error!, t),
        action: RindeTextLink(
          label: t('Reintentar'),
          onPressed: () => ref.invalidate(periodSummaryProvider(summaryKey)),
        ),
      );
    } else {
      final total = totals?.total;
      final days = current == null ? null : elapsedDays(current.from, current.to, today);
      final rows = [
        if (income)
          (t('Gastos'), current?.expense.total, p.negative)
        else
          (t('Ingresos'), current?.income.total, p.positive),
        if ((current?.savings ?? 0) > 0) (t('Ahorro'), current!.savings, p.ink),
        (t('Balance'), current?.balance, p.ink),
      ];
      figures = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoneyText(
            total == null
                ? '…'
                : '${total > 0 && !money.hidden ? (income ? '+ ' : '− ') : ''}${money(total)}',
            money: money,
            fit: true,
            style: RindeType.amount.copyWith(color: income ? p.positive : p.ink),
          ),
          if (days != null && total != null && total > 0) ...[
            const SizedBox(height: RindeSpace.s1),
            MoneyText(
              '${t('En')} ${days == 1 ? t('1 día') : t('{days} días', {'days': days})} ${t('· promedio')} '
              '${money((total / days).round())} ${t('al día')}',
              money: money,
              style: RindeType.meta.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: RindeSpace.s4),
          HomeSurface(
            padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
            child: Column(
              children: [
                for (final (i, (name, value, tone)) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: p.ink.withValues(alpha: 0.1)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: RindeType.control.copyWith(color: p.ink.withValues(alpha: 0.7)),
                          ),
                        ),
                        MoneyText(
                          amount(value),
                          money: money,
                          style: RindeType.control.w(FontWeight.w600).copyWith(color: tone),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final query = MovementQuery(
      type: widget.type,
      from: from,
      to: to,
      // Como la web: «Sin clasificar» no filtra en el servidor.
      category: _category == '' || _category == 'sin_clasificar' ? null : _category,
      pageSize: 50,
    );
    final list = ref.watch(periodMovementsProvider((account, query)));
    final empty = income ? t('No hay ingresos en este periodo.') : t('No hay gastos en este periodo.');

    final Widget movements;
    if (list.hasError && !list.isLoading) {
      movements = RindeBanner(
        message: movementErrorText(list.error, t),
        action: RindeTextLink(
          label: t('Reintentar'),
          onPressed: () => ref.invalidate(periodMovementsProvider((account, query))),
        ),
      );
    } else if (!list.hasValue || list.isReloading) {
      movements = Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (list.value!.items.isEmpty) {
      movements = Text(empty, style: RindeType.small.copyWith(color: p.inkMuted));
    } else {
      movements = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          for (final m in list.value!.items)
            MovementRow(
              movement: m,
              // withDay de la web: el día va junto a la categoría.
              category: '${movementCategoryName(m, names, t)} · ${relativeDay(m.date, today, region, t)}',
              money: money,
              t: t,
              onTap: () => context.push(Routes.movement(m.id)),
            ),
        ],
      );
    }

    Widget heading(String text) => Semantics(
      header: true,
      child: Text(text, style: RindeType.title.copyWith(color: p.ink)),
    );

    return PushedFrame(
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () async {
          ref.invalidate(periodSummaryProvider(summaryKey));
          ref.invalidate(periodMovementsProvider((account, query)));
          ref.invalidate(periodKakeiboProvider((account, from, to)));
          await ref.read(periodSummaryProvider(summaryKey).future).then((_) {}, onError: (_) {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: [
            Text(_capitalized('$title · $label'), style: RindeType.meta.copyWith(color: p.inkMuted)),
            Semantics(
              header: true,
              child: Text(
                income ? t('¿De dónde entró tu plata?') : t('¿En qué se fue tu plata?'),
                style: RindeType.headline.copyWith(color: p.ink),
              ),
            ),
            const SizedBox(height: RindeSpace.s4),
            PeriodBar(
              t: t,
              period: _period,
              label: label,
              atCurrent: isCurrentPeriod(_period, _date, today),
              onPeriod: (period) => _setPeriod(period, today),
              onShift: (delta) => _setPeriod(_period, shiftPeriod(_period, _date, delta)),
            ),
            const SizedBox(height: RindeSpace.s4),
            figures,
            const SizedBox(height: RindeSpace.s5),
            heading(income ? t('De dónde entró') : t('Por categoría')),
            const SizedBox(height: RindeSpace.s2),
            _ByCategory(totals: totals, names: names, money: money, empty: empty, t: t),
            if (!income && current != null) ...[
              const SizedBox(height: RindeSpace.s5),
              _Kakeibo(from: current.from, to: current.to, money: money),
            ],
            const SizedBox(height: RindeSpace.s5),
            heading(income ? t('Todos los ingresos') : t('Todos los gastos')),
            const SizedBox(height: RindeSpace.s2),
            if (chips.length > 1) ...[
              Semantics(
                container: true,
                label: t('Filtrar por categoría'),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: RindeSpace.s2,
                    children: [
                      for (final key in ['', ...chips])
                        FilterPill(
                          label: chipName(key),
                          selected: _category == key,
                          onTap: () => setState(() => _category = key),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s3),
            ],
            movements,
            const SizedBox(height: RindeSpace.s5),
            RindeButton(
              label: t('Ver todos los movimientos'),
              variant: RindeButtonVariant.soft,
              onPressed: () => context.go(Routes.movements),
            ),
          ],
        ),
      ),
    );
  }
}

/// `first-letter:uppercase` de la web.
String _capitalized(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// ExpenseByCategory.jsx: de mayor a menor, con monto y porcentaje en texto (el color nunca es la única
/// pista); con más de 6, las 5 primeras y «Otras N categorías».
class _ByCategory extends StatelessWidget {
  const _ByCategory({
    required this.totals,
    required this.names,
    required this.money,
    required this.empty,
    required this.t,
  });

  final TypeTotals? totals;
  final Map<String, String> names;
  final HomeMoney money;
  final String empty;
  final Tr t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = totals == null ? const <CategoryRow>[] : categoryRows(totals!.byCategory);
    String name(CategoryRow r) => r.key == 'otras'
        ? t('Otras {length} categorías', {'length': r.others})
        : r.category == null
        ? t('Sin clasificar')
        : (names[r.category] ?? r.category!);
    return HomeSurface(
      padding: const EdgeInsets.all(14),
      child: totals == null
          ? Text(t('Cargando…'), style: RindeType.small.copyWith(color: p.inkMuted))
          : rows.isEmpty
          ? Text(empty, style: RindeType.small.copyWith(color: p.inkMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                for (final r in rows)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RindeType.control.copyWith(color: p.ink),
                            ),
                          ),
                          const SizedBox(width: RindeSpace.s3),
                          MoneyText(
                            '${money(r.total)} · ${r.percentage.round()} %',
                            money: money,
                            style: RindeType.control.w(FontWeight.w600).copyWith(color: p.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      PlanBar(share: (r.percentage < 2 ? 2 : r.percentage) / 100, color: p.brand),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// «¿Podías evitarlo? · Kakeibo» (KakeiboSplit.jsx): la barra de los 4 grupos del periodo con sus
/// porcentajes en texto y una idea sobre los deseos. Sin todos los gastos del periodo no se muestra.
class _Kakeibo extends ConsumerWidget {
  const _Kakeibo({required this.from, required this.to, required this.money});

  final String from;
  final String to;
  final HomeMoney money;

  /// --app-chart-cat-1 a 4 de la web (validados para daltonismo), claro y oscuro.
  static const _light = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100)];
  static const _dark = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500)];
  static const _labels = ['Necesidad', 'Deseo', 'Cultura', 'Imprevisto'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final page = ref.watch(periodKakeiboProvider((ref.watch(accountProvider), from, to))).value;
    if (page == null || page.hasMore) return const SizedBox.shrink();
    final split = splitByKakeibo(page.items);
    final colors = p.brightness == Brightness.dark ? _dark : _light;
    final wish = split.totals['deseo']!;
    final ungrouped = split.ungrouped;
    final note = StringBuffer(
      wish > 0
          ? t('En deseos llevas {total}. Bajarlos un 10 % te deja {money} más.', {
              'total': money(wish),
              'money': money((wish * 0.1).round()),
            })
          : t('Este periodo no tienes gastos marcados como deseo.'),
    );
    if (ungrouped > 0) {
      note.write(
        t(' {v1} grupo.', {
          // TEXTO NUEVO: la web deja el plural sin traducir.
          'v1': ungrouped == 1
              ? t('1 gasto no tiene')
              : t('{ungrouped} gastos no tienen', {'ungrouped': ungrouped}),
        }),
      );
    }
    final share = [for (final g in kakeiboGroups) split.shares[g]!];

    return HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              t('¿Podías evitarlo? · Kakeibo').toUpperCase(),
              style: RindeType.eyebrow.copyWith(color: p.inkMuted),
            ),
          ),
          const SizedBox(height: RindeSpace.s3),
          if (split.grouped == 0)
            Text(
              t(
                'Aún no tienes gastos con grupo Kakeibo. Ábrelos y elige si fueron necesidad, deseo, cultura o un imprevisto.',
              ),
              style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
            )
          else ...[
            Semantics(
              image: true,
              label: [for (final (i, l) in _labels.indexed) '${t(l)} ${share[i].round()} %'].join(', '),
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      spacing: 2,
                      children: [
                        for (final (i, s) in share.indexed)
                          if (s > 0)
                            Expanded(
                              flex: (s * 100).round().clamp(1, 10000),
                              child: ColoredBox(color: colors[i]),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: RindeSpace.s3),
            Wrap(
              runSpacing: RindeSpace.s2,
              children: [
                for (final (i, l) in _labels.indexed)
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: t(l),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(text: ' ${share[i].round()} %'),
                              ],
                            ),
                            style: RindeType.meta.copyWith(color: p.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: RindeSpace.s3),
            MoneyText(
              note.toString(),
              money: money,
              style: RindeType.meta.copyWith(color: p.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
