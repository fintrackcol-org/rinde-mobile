import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_skeleton.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../../home/presentation/widgets/load_error_notice.dart';
import '../../application/money_providers.dart';
import '../../data/money_models.dart';
import '../../domain/income_rules.dart';
import 'income_sheet.dart';

/// El único camino de un monto de Mi plata a la pantalla: oculto, no sale ni un dígito.
HomeMoney moneyOf(WidgetRef ref) {
  final t = ref.watch(trProvider);
  return HomeMoney(
    format: formatFor(ref.watch(appRegionProvider)),
    hidden: ref.watch(hiddenAmountsProvider),
    hiddenLabel: t('Monto oculto'),
  );
}

/// «Llevas X de Y; te faltan N días de trabajo, unos Z por día.» (IncomeOverview.jsx). Los pedazos
/// son los textos de la web, en su orden.
String workDayLine(WorkDay w, Tr t, FormatMoney money) {
  final out = StringBuffer('${t('Llevas')} ${money(w.earned)} ${t('de')} ${money(w.target)}');
  if (w.daysLeft > 0) {
    out.write(
      '${t('; te faltan')} ${w.daysLeft} ${t('días de trabajo, unos')} ${money(w.perDay)} ${t('por día.')}',
    );
  }
  if (w.extraToday > 0) {
    out.write(
      t(' Hoy hiciste {extraToday} de más: apártalos para mañana o al colchón.', {
        'extraToday': money(w.extraToday),
      }),
    );
  }
  return out.toString();
}

/// «Cómo te entra la plata» (components/money/IncomeOverview.jsx): la frase del mes normal y el
/// flaco; el detalle va en una hoja para que la tarjeta siga siendo corta.
class IncomeOverviewCard extends ConsumerWidget {
  const IncomeOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(incomeOverviewProvider(account));
    final money = moneyOf(ref);
    // Al recargar por un cambio (de cuenta, de día) lo anterior ya no responde a lo que se pide.
    final income = async.isReloading ? null : async.value;

    if (income == null && !async.isLoading && async.hasError) {
      return LoadErrorNotice(onRetry: () => ref.invalidate(incomeOverviewProvider(account)));
    }

    final title = HomeSectionTitle(t('Cómo te entra la plata'));
    if (income == null) {
      // Un solo anuncio: el título y los esqueletos no se leen.
      return Semantics(
        container: true,
        label: t('Cargando…'),
        child: ExcludeSemantics(
          child: RindeCard(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: p.ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: RindeSpace.s3),
                  const RindeSkeleton(width: double.infinity, height: 14),
                  const SizedBox(height: RindeSpace.s2),
                  const RindeSkeleton(width: 180, height: 14),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final headline = incomeHeadline(income, t, money.call);
    return RindeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El enlace baja a su propia línea si no cabe al lado (letra grande, celular angosto).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: RindeSpace.s2,
            children: [
              title,
              HomeLink(
                label: headline != null ? t('Ver más') : t('Configurar'),
                onTap: () => showIncomeSheet(context, edit: headline == null),
              ),
            ],
          ),
          MoneyText(
            headline ?? t('Cuéntanos cómo y cuánto te entra, aunque sea más o menos.'),
            money: money,
            style: RindeType.body.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          if (income.estimated) ...[
            const SizedBox(height: RindeSpace.s1),
            Text(
              t('Estimado con lo que nos contaste.'),
              style: RindeType.caption.copyWith(color: p.inkMuted),
            ),
          ],
          // Sin meta (sin ritmo y sin montos dichos) la línea sería solo ceros: no sale.
          if (income.workDay case final workDay? when workDay.target > 0) ...[
            const SizedBox(height: RindeSpace.s2),
            MoneyText(
              workDayLine(workDay, t, money.call),
              money: money,
              style: RindeType.small.copyWith(color: p.ink),
            ),
          ],
          // La recarga falló: lo de arriba es lo último que llegó.
          if (async.hasError) ...[
            const SizedBox(height: RindeSpace.s2),
            Semantics(
              liveRegion: true,
              child: Text(
                t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
