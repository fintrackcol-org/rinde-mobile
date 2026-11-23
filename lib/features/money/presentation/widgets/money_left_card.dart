import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_line.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/domain/home_dates.dart';
import '../../../home/domain/home_view.dart' show UnknownReason;
import '../../../home/presentation/widgets/balance_links.dart';
import '../../../home/presentation/widgets/hero_card.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/load_error_notice.dart';
import '../../application/money_providers.dart';
import '../../domain/money_view.dart';
import 'income_overview_card.dart' show moneyOf;

/// «¿Hasta cuándo te alcanza?» de Mi plata (MiPlataMobile.jsx): lo que te queda este mes, hasta cuándo
/// alcanza a tu ritmo, ingresos y gastos, la salida a corregir el saldo y el aviso del primer pago que
/// no alcanza. Dibuja lo que decide [myMoneyViewProvider]: aquí no se calcula ninguna cifra.
class MoneyLeftSection extends ConsumerWidget {
  const MoneyLeftSection({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final today = ref.watch(todayProvider);
    final view = ref.watch(myMoneyViewProvider);
    final money = moneyOf(ref);
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    final title = '${t('Lo que te queda ·')} ${monthName(today.month, region)}';
    Text muted(String text) => Text(text, style: const TextStyle(color: RindeBrand.onVioletMuted));
    final dash = ExcludeSemantics(child: Text('—', style: RindeType.amount));

    final card = switch (view.left) {
      MoneyLeftLoading() => Semantics(
        container: true,
        label: t('Cargando…'),
        child: const ExcludeSemantics(
          child: HeroFrame(
            skin: HeroSkin.violet,
            gap: RindeSpace.s3,
            children: [
              Align(alignment: Alignment.centerLeft, child: RindeSkeleton(width: 132, height: 12)),
              Align(alignment: Alignment.centerLeft, child: RindeSkeleton(width: 208, height: 36)),
              Align(alignment: Alignment.centerLeft, child: RindeSkeleton(width: 240, height: 12)),
            ],
          ),
        ),
      ),
      MoneyLeftValue(money: final value, :final runway) => HeroFrame(
        skin: HeroSkin.violet,
        gap: RindeSpace.s3,
        children: [
          HeroEyebrow(title, color: RindeBrand.white),
          MoneyText(
            money(value),
            money: money,
            fit: true,
            style: RindeType.amount.copyWith(color: RindeBrand.white),
          ),
          if (runway != null) ...[
            RindeLine(
              value: (today.day + math.min(runway.days, lastDay - today.day)) / lastDay,
              tone: RindeLineTone.brand,
            ),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: RindeSpace.s2,
                children: [
                  muted('1 ${shortMonthName(today.month, region)}'),
                  Text(
                    runway.lasts
                        ? t('Alcanza todo el mes')
                        : t('Alcanza {r}', {
                            'r': t('hasta el {getDate} {v2}', {
                              'getDate': runway.until.day,
                              'v2': shortMonthName(runway.until.month, region),
                            }),
                          }),
                    style: RindeType.meta.w(FontWeight.w600).copyWith(color: RindeBrand.white),
                  ),
                  muted('$lastDay ${shortMonthName(today.month, region)}'),
                ],
              ),
            ),
          ],
          if (view.totals case final totals?)
            MoneyText(
              '${runway == null ? '' : t('Gastas en promedio {pace} al día. ', {'pace': money(runway.pace)})}'
              '${t('Ingresos')} ${money(totals.income)} ${t('· Gastos')} ${money(totals.expense)}.',
              money: money,
              style: RindeType.meta.copyWith(color: RindeBrand.onVioletMuted),
            ),
        ],
      ),
      // La raya dice «no hay cifra»; el porqué va escrito al lado. Nunca un cero.
      MoneyLeftUnknown(reason: UnknownReason.noBalance) => HeroFrame(
        skin: HeroSkin.violet,
        gap: RindeSpace.s3,
        children: [
          HeroEyebrow(title, color: RindeBrand.white),
          dash,
          muted(t('Anota tu primer ingreso para saber hasta cuándo te alcanza.')),
        ],
      ),
      MoneyLeftUnknown(:final reason) => HeroFrame(
        skin: HeroSkin.neutral,
        gap: RindeSpace.s1,
        children: [
          HeroEyebrow(title, color: p.inkMuted),
          dash,
          Text(
            reason == UnknownReason.offline
                ? t('No pudimos traer tu plata porque no hay conexión.')
                : t('No pudimos traer tu plata.'),
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ],
      ),
    };

    final warn = view.warn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(t('¿Hasta cuándo te alcanza?'), style: RindeType.headline.copyWith(color: p.ink)),
        ),
        const SizedBox(height: RindeSpace.s4),
        card,
        if (view.negative) ...[const SizedBox(height: 6), const NegativeBalanceNote()],
        if (view.loadError) ...[const SizedBox(height: RindeSpace.s3), LoadErrorNotice(onRetry: onRetry)],
        if (view.stale)
          Padding(
            padding: const EdgeInsets.only(top: RindeSpace.s2),
            child: Semantics(
              liveRegion: true,
              child: Text(
                t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
            ),
          ),
        // En Mi plata la web siempre dice «Corrígela», haya dicho o no su saldo.
        const BalanceLinks(reviewExpenses: false, balanceSet: true),
        if (warn != null) ...[
          const SizedBox(height: RindeSpace.s1),
          _Warn(
            // Un día 31 en un mes de 30 vence el último día, como lo cuenta el servidor.
            day:
                '${t('Ojo con el')} ${math.min(warn.dayOfMonth, lastDay)} ${t('de')} '
                '${monthName(today.month, region)}.',
            detail:
                '${t('Vence')} ${warn.name} (${money(warn.amount)}'
                '${t(') y a este ritmo no alcanza. Anota los ingresos que esperas o baja algún presupuesto.')}',
            money: money,
          ),
        ],
      ],
    );
  }
}

/// «Ojo con el …»: punto violeta y la frase, en negrita la fecha.
class _Warn extends StatelessWidget {
  const _Warn({required this.day, required this.detail, required this.money});

  final String day;
  final String detail;
  final HomeMoney money;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = RindeType.small.copyWith(color: p.ink);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: day, style: style.w(FontWeight.w600)),
                    TextSpan(text: ' $detail'),
                  ],
                ),
                style: style.tabular,
                semanticsLabel: money.spoken('$day $detail'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
