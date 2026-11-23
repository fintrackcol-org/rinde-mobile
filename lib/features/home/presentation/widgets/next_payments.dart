import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../application/home_providers.dart';
import '../../data/home_models.dart';
import '../../domain/home_dates.dart';
import 'home_money.dart';
import 'home_tap.dart';

/// «Lo próximo» (NextPayments de MobileHome.jsx): los pagos fijos que vienen, con cuándo y cuánto.
/// A diferencia de la web, un pago con la fecha pasada dice que venció.
class NextPayments extends ConsumerWidget {
  const NextPayments({super.key, required this.payments, required this.money});

  final List<PendingPayment> payments;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final region = ref.watch(appRegionProvider);
    final today = isoDay(ref.watch(todayProvider));
    final p = context.palette;
    final title = HomeSectionTitle(t('Lo próximo'));
    final link = HomeLink(
      label: t('Ver pagos'),
      style: RindeType.small.w(FontWeight.w500).copyWith(color: p.brand),
      onTap: () => context.push(Routes.payments),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (largeText(context)) ...[
          title,
          Align(alignment: AlignmentDirectional.centerStart, child: link),
        ] else
          Row(
            children: [
              Expanded(child: title),
              link,
            ],
          ),
        HomeSurface(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
          child: Column(
            children: [
              for (final (i, payment) in payments.indexed)
                _Row(
                  key: ValueKey('${payment.id}-${payment.date}'),
                  name: payment.name,
                  // Las fechas AAAA-MM-DD se comparan como texto.
                  overdue: payment.date.compareTo(today) < 0,
                  date: payment.date.compareTo(today) < 0
                      ? t('Venció el {date}', {'date': dayAndMonth(payment.date, region)})
                      : dayAndMonth(payment.date, region),
                  amount: money(payment.amount),
                  money: money,
                  divider: i > 0,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.name,
    required this.overdue,
    required this.date,
    required this.amount,
    required this.money,
    required this.divider,
  });

  final String name;
  final bool overdue;
  final String date;
  final String amount;
  final HomeMoney money;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stacked = largeText(context);
    final value = MoneyText(
      amount,
      money: money,
      fit: true,
      style: RindeType.body.w(FontWeight.w600).copyWith(color: p.ink),
    );
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: p.line)) : null,
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: RindeType.lead.w(FontWeight.w600).copyWith(color: p.ink),
                    ),
                    Text(date, style: RindeType.meta.copyWith(color: overdue ? p.negative : p.inkMuted)),
                    // Con la letra agrandada baja: al lado, la fecha se partía a mitad de palabra.
                    if (stacked) value,
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: RindeSpace.s3),
                // El monto nunca se corta: como mucho ocupa media fila y, si no cabe, se achica.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                  child: value,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
