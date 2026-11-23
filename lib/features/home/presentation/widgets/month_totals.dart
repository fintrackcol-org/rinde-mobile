import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router también exporta un «Block» (el de onEnter).
import 'package:go_router/go_router.dart' hide Block;
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../application/home_providers.dart';
import '../../data/home_models.dart';
import '../../domain/home_dates.dart';
import '../../domain/home_view.dart';
import 'home_money.dart';
import 'home_tap.dart';

/// «Este mes» (MobileHome.jsx): ingresos y gastos del mes, cada uno lleva a su detalle, y lo que
/// espera confirmación (FT-0047).
class MonthSection extends ConsumerWidget {
  const MonthSection({super.key, required this.totals, required this.toConfirm, required this.money});

  final Block<MonthTotals> totals;
  final int toConfirm;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final period = monthName(ref.watch(todayProvider).month, ref.watch(appRegionProvider));
    final value = totals.value;
    final income = _Total(
      label: t('Ingresos'),
      more: t(', ver ingresos de {period}', {'period': period}),
      text: value == null ? null : '+ ${money(value.income)}',
      failed: totals.failed,
      color: p.positive,
      money: money,
      onTap: () => context.push(Routes.income),
    );
    final expense = _Total(
      label: t('Gastos'),
      more: t(', ver gastos de {period}', {'period': period}),
      text: value == null ? null : money(value.expense),
      failed: totals.failed,
      color: p.ink,
      money: money,
      onTap: () => context.push(Routes.expenses),
    );
    final stacked = largeText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionTitle(t('Este mes')),
        const SizedBox(height: RindeSpace.s3),
        if (stacked) ...[
          income,
          const SizedBox(height: RindeSpace.s3),
          expense,
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: income),
                const SizedBox(width: RindeSpace.s3),
                Expanded(child: expense),
              ],
            ),
          ),
        if (toConfirm > 0) ...[
          const SizedBox(height: RindeSpace.s3),
          HomeTap(
            onTap: () => context.push(Routes.toConfirm),
            child: HomeSurface(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(
                  children: [
                    RindeIcon(RindeIcons.inbox, color: p.brand),
                    const SizedBox(width: RindeSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Por confirmar'),
                            style: RindeType.lead.w(FontWeight.w600).copyWith(color: p.ink),
                          ),
                          Text(
                            toConfirm == 1
                                ? t('1 pago que llegó solo')
                                : t('{count} pagos que llegaron solos', {'count': toConfirm}),
                            style: RindeType.meta.copyWith(color: p.inkMuted),
                          ),
                          if (stacked) _review(t, p),
                        ],
                      ),
                    ),
                    if (!stacked) ...[const SizedBox(width: RindeSpace.s3), _review(t, p)],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _review(Tr t, RindePalette p) =>
      Text(t('Revisar'), style: RindeType.small.w(FontWeight.w600).copyWith(color: p.brand));
}

/// Ingresos o gastos del mes (`Total` de MobileHome.jsx).
class _Total extends ConsumerWidget {
  const _Total({
    required this.label,
    required this.more,
    required this.text,
    required this.failed,
    required this.color,
    required this.money,
    required this.onTap,
  });

  final String label;

  /// «, ver ingresos de noviembre», solo para el lector de pantalla.
  final String more;

  /// La cifra ya escrita, o null si no ha llegado.
  final String? text;
  final bool failed;
  final Color color;
  final HomeMoney money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final text = this.text;
    // La cifra se achica para caber entera: un monto cortado no sirve.
    final style = text == null || text.length <= 11
        ? RindeType.figure
        : text.length <= 14
        ? RindeType.figureMd
        : RindeType.figureSm;
    // Sin cifra: si falló se dice (raya), si viene en camino late. Nunca un cero.
    final spoken = text != null
        ? money.spoken(text)
        : failed
        ? t('No se pudo cargar')
        : t('Cargando…');
    return HomeTap(
      onTap: onTap,
      label: '$label: $spoken$more',
      child: HomeSurface(
        padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(label.toUpperCase(), style: RindeType.eyebrow.copyWith(color: p.inkMuted)),
                  ),
                ),
                RindeIcon(RindeIcons.chevronRight, size: 16, color: p.inkMuted),
              ],
            ),
            const SizedBox(height: 6),
            if (text != null)
              MoneyText(
                text,
                money: money,
                fit: true,
                style: style.copyWith(color: color),
              )
            else if (failed)
              Text('—', style: style.copyWith(color: p.inkMuted))
            else
              DefaultTextStyle.merge(
                style: style.copyWith(color: p.ink),
                child: const SizedBox(
                  height: 33,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: RindeSkeleton(width: 96, height: 22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
