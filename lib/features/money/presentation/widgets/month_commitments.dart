import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../../home/presentation/widgets/load_error_notice.dart';
import '../../application/money_providers.dart';
import '../../domain/commitment_rules.dart';
import 'income_overview_card.dart' show moneyOf;

/// «Pagos fijos del mes» de Mi plata (MiPlataMobile.jsx): los de este mes por día, tachados los de un
/// día ya pasado (como la web, sin mirar si se pagaron: eso lo dice Pagos del mes). «Ver calendario»
/// va a Calendario y la lista, o el vacío, a Pagos del mes.
class MonthCommitments extends ConsumerWidget {
  const MonthCommitments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final today = ref.watch(todayProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(moneyProfileProvider(account));
    // Al recargar por un cambio (de cuenta, de plata) lo anterior ya no responde a lo que se pide.
    final profile = async.isReloading ? null : async.value;
    final money = moneyOf(ref);
    void open() => context.push(Routes.payments);

    final Widget body;
    if (profile == null && async.hasError && !async.isLoading) {
      body = LoadErrorNotice(onRetry: () => ref.invalidate(moneyProfileProvider(account)));
    } else if (profile == null) {
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
      // A igual día, el orden del servidor.
      final fixed = [...commitmentsOfMonth(profile.commitments, today).indexed]
        ..sort((a, b) {
          final byDay = a.$2.dayOfMonth.compareTo(b.$2.dayOfMonth);
          return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
        });
      if (fixed.isEmpty) {
        body = HomeTap(
          onTap: open,
          radius: RindeRadius.brX2,
          child: HomeSurface(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${t('Agrega lo que pagas cada mes (arriendo, internet, PILA) y te avisamos antes.')} ',
                  ),
                  TextSpan(
                    text: t('Agregar'),
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.brand),
                  ),
                ],
              ),
              style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
            ),
          ),
        );
      } else {
        final lastDay = DateTime(today.year, today.month + 1, 0).day;
        final month = shortMonthName(today.month, region);
        body = HomeSurface(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (_, c) in fixed)
                _Row(
                  // Un día 31 en un mes de 30 cae el último día, como lo cuenta el servidor.
                  label: '${math.min(c.dayOfMonth, lastDay)} $month · ${c.name}',
                  amount: money(c.amount),
                  money: money,
                  past: c.dayOfMonth < today.day,
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeLink(
                  label: t('Editar pagos fijos'),
                  style: RindeType.meta.w(FontWeight.w600).copyWith(color: p.brand),
                  onTap: open,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: RindeSpace.s2,
          children: [
            HomeSectionTitle(t('Pagos fijos del mes')),
            HomeLink(
              label: t('Ver calendario'),
              style: RindeType.meta.w(FontWeight.w600).copyWith(color: p.brand),
              onTap: () => context.push(Routes.calendar),
            ),
          ],
        ),
        const SizedBox(height: RindeSpace.s1),
        body,
      ],
    );
  }
}

/// Una fila: «{día} {mes} · {nombre}» y el monto; con el día ya pasado, tachada.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.amount, required this.money, required this.past});

  final String label;
  final String amount;
  final HomeMoney money;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final value = MoneyText(
      amount,
      money: money,
      fit: true,
      style: RindeType.small.w(FontWeight.w600).copyWith(color: p.ink),
    );
    final text = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: RindeType.small.copyWith(
        color: past ? p.inkMuted : p.ink.withValues(alpha: 0.8),
        decoration: past ? TextDecoration.lineThrough : null,
        decorationColor: p.ink.withValues(alpha: 0.3),
      ),
    );
    final stacked = largeText(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, value])
            : LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: RindeSpace.s3),
                    // El monto nunca se corta: como mucho ocupa media fila y, si no cabe, se achica.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                      child: value,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
