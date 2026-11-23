import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_line.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../application/home_providers.dart';
import '../../domain/home_dates.dart';
import '../../domain/home_view.dart';
import 'home_money.dart';
import 'home_tap.dart';

enum HeroSkin {
  /// Fondo violeta con texto blanco.
  violet,

  /// No alcanza: fondo negativo suave, texto ink y la cifra en rojo.
  negative,

  /// Sin cifra por un fallo: superficie neutra.
  neutral,
}

/// La tarjeta grande del Inicio (FreeCard y MoneyCard de MobileHome.jsx). Solo dibuja lo que trae
/// [hero]: aquí no se calcula ninguna cifra.
class HeroCard extends ConsumerWidget {
  const HeroCard({super.key, required this.hero, required this.money, required this.onRetry});

  final HomeHero hero;
  final HomeMoney money;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final region = ref.watch(appRegionProvider);
    final p = context.palette;
    final seeMore = t(', ver Mi plata');
    void open() => context.push(Routes.myMoney);
    String myMoney() => '${t('Mi plata ·')} ${monthName(ref.watch(todayProvider).month, region)}';
    Text muted(String text) => Text(text, style: const TextStyle(color: RindeBrand.onVioletMuted));

    switch (hero) {
      case HeroLoading():
        return Semantics(
          container: true,
          label: t('Cargando…'),
          child: const ExcludeSemantics(
            child: HeroFrame(
              skin: HeroSkin.violet,
              gap: RindeSpace.s3,
              children: [
                SizedBox(
                  height: 16,
                  child: Align(alignment: Alignment.centerLeft, child: _Bone(132, 12)),
                ),
                SizedBox(
                  height: 44,
                  child: Align(alignment: Alignment.centerLeft, child: _Bone(208, 36)),
                ),
                SizedBox(
                  height: 10,
                  child: Align(alignment: Alignment.centerLeft, child: _Bone(240, 4)),
                ),
                SizedBox(
                  height: 18,
                  child: Align(alignment: Alignment.centerLeft, child: _Bone(176, 12)),
                ),
              ],
            ),
          ),
        );

      case HeroPlan(:final plan, :final tone):
        final amounts = {'money': money(plan.money), 'pending': money(plan.pendingTotal)};
        final (title, amount, detail) = switch (tone) {
          PlanTone.negative => (
            t('Estás en negativo · estimado'),
            money(plan.money),
            t('Tus gastos superan lo que tienes. ¿Anotaste algo mal?'),
          ),
          // Lo que falta, en positivo: un número bajo cero nunca se pinta como plata para gastar.
          PlanTone.short => (
            t('Te faltan · estimado'),
            money(plan.shortfall),
            t('para tus pagos. Tienes {money} y vencen {pending}.', amounts),
          ),
          PlanTone.free => (
            t('Libre para gastar · estimado'),
            money(plan.free),
            t('De {money} que tienes, {pending} ya están apartados para pagos.', amounts),
          ),
        };
        final free = tone == PlanTone.free;
        final perDay = free && plan.mode == 'daily' && plan.perDay != null && plan.nextPay != null
            ? t('Más o menos {amount} al día hasta el {date}', {
                'amount': money(plan.perDay!),
                'date': dayAndMonth(plan.nextPay!, region),
              })
            : null;
        final fg = free ? RindeBrand.white : p.ink;
        return HeroFrame(
          skin: free ? HeroSkin.violet : HeroSkin.negative,
          onTap: open,
          label: money.spoken('$title: $amount. ${perDay == null ? '' : '$perDay. '}$detail$seeMore'),
          children: [
            HeroEyebrow(title, color: free ? RindeBrand.white : p.ink.withValues(alpha: 0.85), chevron: fg),
            MoneyText(
              amount,
              money: money,
              fit: true,
              style: RindeType.amount.copyWith(color: free ? RindeBrand.white : p.negative),
            ),
            if (perDay != null)
              MoneyText(
                perDay,
                money: money,
                style: RindeType.lead.w(FontWeight.w600).copyWith(color: fg),
              ),
            MoneyText(
              detail,
              money: money,
              style: RindeType.meta.copyWith(
                color: free ? RindeBrand.onVioletMuted : p.ink.withValues(alpha: 0.85),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s1),
                decoration: BoxDecoration(
                  // La web usa blanco al 15 %: con texto de 13 queda en 4,3:1. Al 10 % llega a 4,7:1.
                  color: free ? RindeBrand.white.withValues(alpha: 0.10) : p.wash,
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                ),
                child: Text(
                  t('¿De dónde sale?'),
                  style: RindeType.meta.w(FontWeight.w600).copyWith(color: fg),
                ),
              ),
            ),
          ],
        );

      case HeroMoney(money: final balance, :final runway, :final note):
        final title = myMoney();
        final amount = money(balance);
        final String? lasts;
        final String? until;
        if (runway != null) {
          lasts = runway.lasts
              ? t('Te alcanza para todo el mes')
              : t('Te alcanza {days} más', {
                  'days': runway.days == 1 ? t('1 día') : t('{days} días', {'days': runway.days}),
                });
          until = runway.lasts
              ? t('pasa el fin de mes')
              : t('hasta el {getDate} {v2}', {
                  'getDate': runway.until.day,
                  'v2': shortMonthName(runway.until.month, region),
                });
        } else {
          lasts = switch (note) {
            RunwayNote.calculating => t('Calculando hasta cuándo te alcanza…'),
            RunwayNote.needsData => t('Anota tu primer ingreso para saber hasta cuándo te alcanza.'),
            null => null,
          };
          until = null;
        }
        final details = [?lasts, ?until].join(', ');
        return HeroFrame(
          skin: HeroSkin.violet,
          gap: RindeSpace.s3,
          onTap: open,
          label: money.spoken('$title: $amount${details.isEmpty ? '' : '. $details'}$seeMore'),
          children: [
            HeroEyebrow(title, color: RindeBrand.white, chevron: RindeBrand.white),
            MoneyText(
              amount,
              money: money,
              fit: true,
              style: RindeType.amount.copyWith(color: RindeBrand.white),
            ),
            if (runway != null) ...[
              RindeLine(value: runway.coverage, tone: RindeLineTone.brand),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: RindeSpace.s3,
                  children: [
                    Text(lasts!, style: RindeType.meta.w(FontWeight.w600).copyWith(color: RindeBrand.white)),
                    muted(until!),
                  ],
                ),
              ),
            ] else if (lasts != null) ...[
              // Aún no se sabe el avance: riel a la mitad, sin moneda, en vez de una línea en cero.
              if (note == RunwayNote.calculating)
                const SizedBox(height: 10, child: Center(child: _HalfRail()))
              else
                const RindeLine(value: 0, tone: RindeLineTone.brand),
              muted(lasts),
            ],
          ],
        );

      case HeroUnknown(:final reason):
        final title = myMoney();
        // La raya dice «no hay cifra»; el porqué va escrito al lado. Nunca un cero.
        final dash = ExcludeSemantics(child: Text('—', style: RindeType.amount));
        if (reason == UnknownReason.noBalance) {
          final why = t('Todavía no sabemos cuánta plata tienes.');
          return HeroFrame(
            skin: HeroSkin.violet,
            gap: RindeSpace.s3,
            onTap: open,
            label: '$title. $why$seeMore',
            children: [
              HeroEyebrow(title, color: RindeBrand.white, chevron: RindeBrand.white),
              dash,
              muted(why),
            ],
          );
        }
        return HeroFrame(
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
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: HomeLink(label: t('Reintentar'), onTap: onRetry),
            ),
          ],
        );
    }
  }
}

class _Bone extends StatelessWidget {
  const _Bone(this.width, this.height);
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => RindeSkeleton(width: width, height: height);
}

/// Riel de «calculando» (MoneyCard): blanco al 30 % con la mitad llena.
class _HalfRail extends StatelessWidget {
  const _HalfRail();

  @override
  Widget build(BuildContext context) => Container(
    height: 4,
    alignment: AlignmentDirectional.centerStart,
    decoration: BoxDecoration(
      color: RindeBrand.white.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(RindeRadius.pill),
    ),
    child: FractionallySizedBox(
      widthFactor: 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: RindeBrand.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(RindeRadius.pill),
        ),
      ),
    ),
  );
}

/// Rótulo en mayúsculas de la tarjeta, con la flecha que dice que se puede tocar. También lo usa la
/// tarjeta de Mi plata.
class HeroEyebrow extends StatelessWidget {
  const HeroEyebrow(this.text, {super.key, required this.color, this.chevron});
  final String text;
  final Color color;
  final Color? chevron;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(text.toUpperCase(), style: RindeType.eyebrow.copyWith(color: color)),
      ),
      if (chevron != null) RindeIcon(RindeIcons.chevronRight, color: chevron),
    ],
  );
}

/// Marco de la tarjeta grande (violeta, negativo o neutro). También lo usa la tarjeta de Mi plata.
class HeroFrame extends StatelessWidget {
  const HeroFrame({
    super.key,
    required this.skin,
    required this.children,
    this.gap = RindeSpace.s2,
    this.onTap,
    this.label,
  });

  final HeroSkin skin;
  final List<Widget> children;
  final double gap;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final violet = skin == HeroSkin.violet;
    final body = ClipRRect(
      borderRadius: RindeRadius.brX3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: switch (skin) {
            HeroSkin.violet => p.brandSolid,
            HeroSkin.negative => p.negative.withValues(alpha: 0.1),
            HeroSkin.neutral => p.surface,
          },
          borderRadius: RindeRadius.brX3,
          border: skin == HeroSkin.neutral ? Border.all(color: p.line) : null,
        ),
        child: Stack(
          children: [
            if (violet)
              PositionedDirectional(
                end: -64,
                top: -64,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // La web usa blanco al 15 %: donde cruza el rótulo quedaba en 3,7:1. Al 8 %, 4,9:1.
                    border: Border.all(color: RindeBrand.white.withValues(alpha: 0.08), width: 32),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(RindeSpace.s5),
              child: DefaultTextStyle.merge(
                style: RindeType.meta.copyWith(color: violet ? RindeBrand.white : p.ink),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: gap), child],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final tap = onTap;
    if (tap == null) return body;
    return HomeTap(onTap: tap, label: label, radius: RindeRadius.brX3, scale: 0.99, child: body);
  }
}
