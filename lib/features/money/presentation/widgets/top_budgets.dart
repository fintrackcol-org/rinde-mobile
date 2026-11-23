import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/data/home_models.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../../home/presentation/widgets/load_error_notice.dart';
import 'income_overview_card.dart' show moneyOf;

/// Cuántos presupuestos se ven en Mi plata; los demás, con «+ n presupuestos más».
const _shown = 3;

/// Los presupuestos que más se están usando (MiPlataMobile.jsx). Las filas y «Ver y editar» van a
/// Presupuestos: la app aún no tiene el detalle de uno (`/app/presupuestos/{categoría}`).
class TopBudgets extends ConsumerWidget {
  const TopBudgets({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(homeBudgetsProvider(account));
    final names = ref.watch(homeCategoryNamesProvider(account)).value ?? const <String, String>{};
    // Al recargar por un cambio (de cuenta, de mes) lo anterior ya no responde a lo que se pide.
    final budgets = async.isReloading ? null : async.value;
    void open() => context.push(Routes.budgets);

    final Widget body;
    if (budgets == null && async.hasError && !async.isLoading) {
      body = LoadErrorNotice(onRetry: () => ref.invalidate(homeBudgetsProvider(account)));
    } else if (budgets == null) {
      body = Semantics(
        container: true,
        label: t('Cargando…'),
        child: const ExcludeSemantics(
          child: HomeSurface(
            padding: EdgeInsets.all(RindeSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RindeSkeleton(width: double.infinity, height: 14),
                SizedBox(height: RindeSpace.s3),
                RindeSkeleton(width: 180, height: 14),
              ],
            ),
          ),
        ),
      );
    } else {
      // De más a menos consumo; a igual porcentaje, el orden del servidor.
      final top = [...budgets.indexed]
        ..sort((a, b) {
          final byUse = b.$2.percentage.compareTo(a.$2.percentage);
          return byUse != 0 ? byUse : a.$1.compareTo(b.$1);
        });
      final more = top.length - _shown;
      body = HomeSurface(
        padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: RindeSpace.s2),
                child: Text(
                  t('Aún no tienes presupuestos. Ponle un tope a lo que más gastas.'),
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
              ),
            for (final (_, b) in top.take(_shown))
              _BudgetRow(budget: b, label: names[b.category] ?? b.category, onTap: open),
            if (more > 0)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeLink(
                  label: '+ $more ${more == 1 ? t('presupuesto más') : t('presupuestos más')}',
                  style: RindeType.meta.w(FontWeight.w500).copyWith(color: p.brand),
                  onTap: open,
                ),
              ),
            // La recarga falló: lo de arriba es lo último que llegó.
            if (async.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: RindeSpace.s2),
                child: Text(
                  t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: RindeSpace.s2,
          children: [
            HomeSectionTitle(t('Presupuestos')),
            HomeLink(
              label: t('Ver y editar'),
              style: RindeType.meta.w(FontWeight.w600).copyWith(color: p.brand),
              onTap: open,
            ),
          ],
        ),
        const SizedBox(height: RindeSpace.s1),
        body,
      ],
    );
  }
}

/// Una fila: nombre, «{consumido} de {tope} · {n} %» y el medidor.
class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.budget, required this.label, required this.onTap});

  final BudgetStatus budget;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final b = budget;
    final level = b.displayLevel;
    final percent = b.percentage.round();
    final consumed = money(b.consumed);
    final rest = ' ${t('de')} ${money(b.amount)} · $percent %';
    final fill = switch (level) {
      BudgetLevel.none => p.brand,
      BudgetLevel.warning => p.caution,
      BudgetLevel.exceeded => p.negative,
    };
    return HomeTap(
      onTap: onTap,
      radius: RindeRadius.brXl,
      label: money.spoken('$label, $consumed$rest'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RindeSpace.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: RindeSpace.s3,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RindeType.control.w(FontWeight.w600).copyWith(color: p.ink),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: consumed,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: level == BudgetLevel.exceeded ? p.negative : p.ink,
                        ),
                      ),
                      TextSpan(text: rest),
                    ],
                  ),
                  style: RindeType.meta.tabular.copyWith(color: p.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: RindeSpace.s2),
            // El medidor: hasta el 100 %, aunque se haya pasado (el número dice cuánto).
            Container(
              height: 4,
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: p.ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(RindeRadius.pill),
              ),
              child: FractionallySizedBox(
                widthFactor: (b.percentage.clamp(0, 100)) / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(RindeRadius.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
