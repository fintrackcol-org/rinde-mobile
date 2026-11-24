import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/domain/home_dates.dart' show monthName;
import '../../home/presentation/widgets/home_tap.dart' show HomeSectionTitle, HomeSurface, HomeTap;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/insights_providers.dart';
import 'widgets/assistant_sheet.dart';
import 'widgets/weekly_reflection.dart';

/// Texto de un error de Consejos: [offline] sin conexión, [unavailable] si la IA no respondió y, en
/// lo demás, el mensaje del servidor (también el de los límites por minuto y por día).
String insightsErrorText(Object e, Tr t, {required String offline, required String unavailable}) {
  if (e is ApiException) {
    if (e.isNetwork) return t(offline);
    if (e.code == ApiCodes.aiUnavailable) return t(unavailable);
    if (e.code == ApiCodes.rateLimited && e.serverMessage != null) return e.serverMessage!;
  }
  return moneyErrorText(e, t);
}

/// formatMonth de la web: «noviembre de 2026».
String _monthTitle(String month, Region region) {
  final parts = month.split('-');
  if (parts.length != 2) return '';
  final name = monthName(int.tryParse(parts[1])?.clamp(1, 12) ?? 1, region);
  return region.language == 'en' ? '$name ${parts[0]}' : '$name de ${parts[0]}';
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// `/app/insights` (Insights.jsx, variante de celular): los consejos de la IA del servidor de la
/// semana o del mes, la reflexión de la semana, el acceso a Renta y DIAN y el chat con el asistente.
/// Sin pantalla anterior, atrás va a Mi plata (backPath de la web).
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(insightsProvider(account));
    final data = async.value;
    final error = data == null && !async.isLoading ? async.error : null;
    final noHistory = error is ApiException && error.code == ApiCodes.insufficientHistory;

    final title = data == null
        ? t('Este mes')
        : data.period == 'week'
        ? t('Esta semana')
        : _monthTitle(data.month, region);

    final Widget insights;
    if (data == null && error == null) {
      insights = Text(t('Analizando tus movimientos…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (noHistory) {
      insights = _NoHistory(message: error.serverMessage ?? '');
    } else if (error != null) {
      insights = Semantics(
        liveRegion: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              insightsErrorText(
                error,
                t,
                offline:
                    'Sin conexión. Los insights necesitan internet; vuelve a intentarlo cuando regreses.',
                unavailable:
                    'Nuestro asistente no está disponible ahora mismo. Inténtalo de nuevo en unos minutos.',
              ),
              style: RindeType.small.copyWith(color: p.negative),
            ),
            RindeTextLink(label: t('Reintentar'), onPressed: () => ref.invalidate(insightsProvider(account))),
          ],
        ),
      );
    } else {
      insights = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          for (final insight in data!.insights)
            HomeSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      insight.title,
                      style: RindeType.control.w(FontWeight.w600).copyWith(color: p.ink),
                    ),
                  ),
                  const SizedBox(height: RindeSpace.s1),
                  Text(insight.detail, style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7))),
                ],
              ),
            ),
        ],
      );
    }

    return PushedFrame(
      title: t('Consejos'),
      fallback: Routes.myMoney,
      child: Stack(
        children: [
          RefreshIndicator(
            color: p.brandSolid,
            backgroundColor: p.surface,
            onRefresh: () async {
              ref
                ..invalidate(insightsProvider(account))
                ..invalidate(reflectionProvider(account));
              await ref.read(insightsProvider(account).future).then((_) {}, onError: (_) {});
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // Abajo queda libre la caja para preguntar.
              padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, 96),
              children: [
                Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeSectionTitle(_capitalized(title)),
                      const SizedBox(height: RindeSpace.s2),
                      insights,
                    ],
                  ),
                ),
                const SizedBox(height: RindeSpace.s6),
                const WeeklyReflectionCard(),
                const SizedBox(height: RindeSpace.s6),
                HomeSectionTitle(t('Para tener en cuenta')),
                const SizedBox(height: RindeSpace.s2),
                HomeTap(
                  onTap: () => context.push(Routes.renta),
                  child: HomeSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
                            alignment: Alignment.center,
                            child: RindeIcon(RindeIcons.landmark, color: p.brand),
                          ),
                          const SizedBox(width: RindeSpace.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t('Renta y DIAN'), style: RindeType.control.copyWith(color: p.ink)),
                                Text(
                                  t('Averigua si te toca declarar y cuándo'),
                                  style: RindeType.meta.copyWith(color: p.ink.withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                          ),
                          RindeIcon(RindeIcons.chevronRight, size: 18, color: p.inkMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: RindeSpace.s3,
            right: RindeSpace.s3,
            bottom: RindeSpace.s3,
            child: HomeTap(
              onTap: () => showAssistantSheet(context),
              radius: BorderRadius.circular(RindeRadius.pill),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                  border: Border.all(color: p.lineStrong),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('Pregunta sobre tu plata'),
                          style: RindeType.body.copyWith(color: p.inkMuted),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: p.brandSolid, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const RindeIcon(RindeIcons.arrowUp, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sin una semana de historial no hay consejos con IA (estado vacío de MonthHighlights.jsx).
class _NoHistory extends ConsumerWidget {
  const _NoHistory({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
      child: Column(
        children: [
          Text(
            t('Todavía no hay suficiente historial'),
            textAlign: TextAlign.center,
            style: RindeType.bodyMedium.copyWith(color: p.ink),
          ),
          const SizedBox(height: RindeSpace.s1),
          Text(
            message,
            textAlign: TextAlign.center,
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: RindeSpace.s4),
          RindeButton(
            label: t('Registrar un movimiento'),
            expand: false,
            size: RindeButtonSize.md,
            onPressed: () => context.push(Routes.record),
          ),
        ],
      ),
    );
  }
}
