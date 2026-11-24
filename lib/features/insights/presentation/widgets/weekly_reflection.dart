import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/domain/home_dates.dart' show dayAndMonth;
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart' show HomeSurface, HomeTap;
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../period/data/period_models.dart' show kakeiboGroups;
import '../../../period/presentation/period_screen.dart' show kakeiboColors, kakeiboLabels;
import '../../application/insights_providers.dart';
import '../../data/insights_repository.dart';

/// Las 4 emociones de un gasto (reflection.js de la web), en su orden.
const _emotions = [
  ('valio_la_pena', 'Valió la pena', RindeIcons.laugh),
  ('normal', 'Normal', RindeIcons.meh),
  ('no_lo_necesitaba', 'No lo necesitaba', RindeIcons.annoyed),
  ('me_arrepiento', 'Me arrepiento', RindeIcons.frown),
];

/// --app-chart-other de la web: «Sin grupo» en la barra.
Color _otherColor(Brightness b) => b == Brightness.dark ? const Color(0xFF6C6A78) : const Color(0xFFA3A1AE);

/// «Tu semana en Kakeibo» (WeeklyReflection.jsx, FT-0070): en qué grupos se fue la plata, cómo se
/// sintió la persona con sus gastos, los que no la convencieron y hasta 3 preguntas para pensar. Las
/// cifras son del servidor; aquí solo se reparten en la barra.
class WeeklyReflectionCard extends ConsumerWidget {
  const WeeklyReflectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(reflectionProvider(account));
    final data = async.value;
    final money = moneyOf(ref);

    final range = data == null || data.from.length != 10 || data.to.length != 10
        ? t('De lunes a domingo')
        : t('Del {from} al {to}', {
            // Sin repetir el mes si es el mismo: «Del 9 al 15 de noviembre».
            'from': data.from.substring(0, 7) == data.to.substring(0, 7)
                ? '${int.tryParse(data.from.substring(8)) ?? data.from.substring(8)}'
                : dayAndMonth(data.from, region),
            'to': dayAndMonth(data.to, region),
          });

    final Widget body;
    if (data == null && async.hasError && !async.isLoading) {
      body = Semantics(
        liveRegion: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(moneyErrorText(async.error!, t), style: RindeType.small.copyWith(color: p.negative)),
            RindeTextLink(
              label: t('Reintentar'),
              onPressed: () => ref.invalidate(reflectionProvider(account)),
            ),
          ],
        ),
      );
    } else if (data == null) {
      body = Text(t('Cargando tu semana…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (data.expenses.count == 0) {
      body = Text(
        t(
          'Aún no tienes gastos esta semana. Cuando anotes uno, elige cómo te sentiste y aquí verás tu reflexión.',
        ),
        style: RindeType.control.w(FontWeight.w400).copyWith(color: p.ink.withValues(alpha: 0.7)),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RindeSpace.s5,
        children: [
          _KakeiboBar(data: data, money: money),
          _Feelings(data: data),
          if (data.regrets.isNotEmpty) _Regrets(regrets: data.regrets, money: money),
          if (data.questions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RindeSpace.s2,
              children: [
                _Subtitle(t('Para pensar')),
                for (final q in data.questions)
                  DecoratedBox(
                    decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: RindeIcon(RindeIcons.circleHelp, size: 16, color: p.brand),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              q,
                              style: RindeType.control.w(FontWeight.w400).copyWith(color: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    return HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(t('Tu semana en Kakeibo'), style: RindeType.title.copyWith(color: p.ink)),
          ),
          Text(
            '$range ${t('· cómo gastaste y cómo te sentiste')}',
            style: RindeType.meta.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s5),
          body,
        ],
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: RindeType.control.w(FontWeight.w600).copyWith(color: context.palette.ink)),
  );
}

/// Barra apilada de los grupos Kakeibo, con la lista de montos debajo (no depende del color).
class _KakeiboBar extends ConsumerWidget {
  const _KakeiboBar({required this.data, required this.money});

  final WeekReflection data;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final colors = [...kakeiboColors(p.brightness), _otherColor(p.brightness)];
    final total = data.expenses.total;
    final rows = [
      for (final (i, key) in kakeiboGroups.indexed)
        (label: t(kakeiboLabels[i]), value: data.kakeibo[key] ?? (count: 0, total: 0), color: colors[i]),
      (label: t('Sin grupo'), value: data.withoutKakeibo, color: colors.last),
    ];
    double share(CountTotal v) => total > 0 ? v.total / total * 100 : 0;
    final visible = rows.where((r) => r.value.total > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          image: true,
          label: t('Gastos de la semana por grupo: {join}', {
            'join': [for (final r in visible) '${r.label} ${share(r.value).round()} %'].join(', '),
          }),
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RindeRadius.pill),
              child: SizedBox(
                height: 12,
                child: Row(
                  spacing: 2,
                  children: [
                    for (final r in visible)
                      Expanded(
                        flex: (share(r.value) * 100).round().clamp(1, 10000),
                        child: ColoredBox(color: r.color),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s3),
        for (final r in rows)
          if (r.label != t('Sin grupo') || r.value.count > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: RindeSpace.s2),
                  Expanded(
                    child: Text(
                      r.label,
                      style: RindeType.control
                          .w(FontWeight.w400)
                          .copyWith(color: r.value.total == 0 ? p.inkSubtle : p.ink),
                    ),
                  ),
                  MoneyText(
                    money(r.value.total),
                    money: money,
                    style: RindeType.control.copyWith(color: r.value.total == 0 ? p.inkSubtle : p.ink),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${share(r.value).round()} %',
                      textAlign: TextAlign.right,
                      style: RindeType.meta.copyWith(color: p.inkMuted, fontFeatures: RindeType.tabular),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Cuántos gastos hubo con cada emoción, y qué parte de la semana tiene emoción.
class _Feelings extends ConsumerWidget {
  const _Feelings({required this.data});
  final WeekReflection data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final count = data.expenses.count;
    final note = StringBuffer(
      // TEXTO NUEVO: la web deja «gasto tiene» y «gastos tienen» sin traducir.
      '${data.withEmotion} ${t('de')} $count ${count == 1 ? t('gasto tiene') : t('gastos tienen')} ${t('emoción.')}',
    );
    if (data.withEmotion < count) note.write(t(' Puedes ponerla desde el detalle de cada gasto.'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Subtitle(t('Cómo te sentiste')),
        const SizedBox(height: RindeSpace.s2),
        Row(
          spacing: RindeSpace.s2,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, label, icon) in _emotions)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final n = data.emotions[key]?.count ?? 0;
                    final color = n == 0 ? p.ink.withValues(alpha: 0.45) : p.ink;
                    return MergeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brX2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s1, vertical: 10),
                          child: Column(
                            spacing: RindeSpace.s1,
                            children: [
                              RindeIcon(icon, size: 24, color: color),
                              Text('$n', style: RindeType.title.copyWith(color: color, height: 1)),
                              Text(
                                t(label),
                                textAlign: TextAlign.center,
                                style: RindeType.caption.copyWith(color: color, fontSize: 11, height: 1.2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: RindeSpace.s2),
        Text(note.toString(), style: RindeType.meta.copyWith(color: p.inkMuted)),
      ],
    );
  }
}

/// Hasta 3 gastos que no la convencieron, del más grande; cada uno abre su detalle.
class _Regrets extends ConsumerWidget {
  const _Regrets({required this.regrets, required this.money});

  final List<Regret> regrets;
  final HomeMoney money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Subtitle(t('Lo que no te convenció')),
        const SizedBox(height: RindeSpace.s2),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: RindeRadius.brXl,
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in regrets.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                Builder(
                  builder: (context) {
                    final emotion = _emotions.where((e) => e.$1 == r.emotion).firstOrNull;
                    return HomeTap(
                      onTap: () => context.push(Routes.movement(r.id)),
                      radius: RindeRadius.brXl,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RindeSpace.s3,
                            vertical: RindeSpace.s2,
                          ),
                          child: Row(
                            children: [
                              if (emotion != null) ...[
                                RindeIcon(emotion.$3, color: p.inkMuted),
                                const SizedBox(width: RindeSpace.s3),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: RindeType.control.copyWith(color: p.ink),
                                    ),
                                    if (emotion != null)
                                      Text(t(emotion.$2), style: RindeType.meta.copyWith(color: p.inkMuted)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: RindeSpace.s2),
                              MoneyText(
                                '−${money(r.amount)}',
                                money: money,
                                style: RindeType.control.copyWith(color: p.ink),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
