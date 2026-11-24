import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_line.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../../design/widgets/rinde_text_field.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show homeTotalsProvider, todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/application/money_providers.dart' show moneyProfileProvider;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/money_shortcuts.dart' show ShortcutGrid;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/vacas_providers.dart';
import '../data/vaca_models.dart';
import '../domain/vaca_rules.dart';
import 'widgets/contribution_sheet.dart';
import 'widgets/vaca_sheet.dart';
import 'widgets/vaca_widgets.dart';

/// Aviso que el detalle muestra al abrirse (el `state` de la navegación de la web).
enum VacaArrival { created, joined, movedToMetas }

/// Lo común a Metas y Vacas: la misma lista (GET /vacas) filtrada, pedida otra vez al entrar (la copia
/// puede ser de antes de un aporte hecho en otro lado), con la carga, el error con «Reintentar» y lo
/// último que llegó si falla la recarga.
mixin _VacasList<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  late bool _stale = ref.read(vacasProvider(ref.read(accountProvider)).exists);
  String? notice;

  @override
  void initState() {
    super.initState();
    if (_stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(vacasProvider(ref.read(accountProvider)), asReload: true);
        setState(() => _stale = false);
      });
    }
  }

  void setNotice(String? value) {
    if (mounted) setState(() => notice = value);
  }

  Widget frame({
    required String title,
    required String lead,
    required List<Widget> Function(List<Vaca>) body,
  }) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = _stale ? const AsyncLoading<List<Vaca>>() : ref.watch(vacasProvider(account));
    final data = async.value;
    final money = moneyOf(ref);
    Widget retry() => RindeBanner(
      message: moneyErrorText(async.error!, t),
      action: RindeTextLink(label: t('Reintentar'), onPressed: () => ref.invalidate(vacasProvider(account))),
    );
    final children = <Widget>[
      Semantics(
        header: true,
        child: Text(title, style: RindeType.headline.copyWith(color: p.ink)),
      ),
      const SizedBox(height: RindeSpace.s1),
      Text(lead, style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7))),
      const SizedBox(height: RindeSpace.s5),
      if (notice case final notice?) ...[
        Semantics(
          container: true,
          liveRegion: true,
          label: money.spoken(notice),
          excludeSemantics: true,
          child: RindeBanner(tone: RindeBannerTone.success, message: notice),
        ),
        const SizedBox(height: RindeSpace.s4),
      ],
      if (data == null && async.hasError && !async.isLoading)
        retry()
      else if (data == null)
        Semantics(
          container: true,
          label: t('Cargando…'),
          child: const ExcludeSemantics(
            child: Column(
              children: [
                RindeSkeleton(width: double.infinity, height: 160, radius: RindeRadius.x3),
                SizedBox(height: RindeSpace.s3),
                RindeSkeleton(width: double.infinity, height: 160, radius: RindeRadius.x3),
              ],
            ),
          ),
        )
      else ...[
        if (async.hasError) ...[retry(), const SizedBox(height: RindeSpace.s4)],
        ...body(data),
      ],
    ];
    return PushedFrame(
      fallback: Routes.plan,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () => ref.refresh(vacasProvider(account).future).then<void>((_) {}, onError: (_) {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 672),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/app/metas` (Metas.jsx, variante de celular): el colchón, las metas personales con su plan y
/// «Apartar plata», «Nueva meta» y los accesos «En grupo». Aportar deja el gasto de ahorro en
/// Movimientos y saca la plata de Mi plata. Sin pantalla anterior, atrás va a Planear.
class MetasScreen extends ConsumerStatefulWidget {
  const MetasScreen({super.key});

  @override
  ConsumerState<MetasScreen> createState() => _MetasScreenState();
}

class _MetasScreenState extends ConsumerState<MetasScreen> with _VacasList {
  ({num? balance, num? income, num? expense, num fixed}) _money() {
    final account = ref.watch(accountProvider);
    final profile = ref.watch(moneyProfileProvider(account)).value;
    final totals = ref.watch(homeTotalsProvider(account)).value;
    return (
      balance: profile?.money,
      income: totals?.income,
      expense: totals?.expense,
      fixed: monthlyFixed(profile?.commitments ?? const []),
    );
  }

  Future<void> _create({String? name, num? goal}) async {
    setNotice(null);
    final plata = _money();
    final income = plata.income ?? 0;
    final day = ref.read(todayProvider).day;
    final meta = await showVacaSheet(
      context,
      personal: true,
      prefillName: name,
      prefillGoal: goal,
      weeklyIncome: income > 0 ? (income / (day / 7 < 1 ? 1 : day / 7)).round() : null,
    );
    if (meta != null && mounted) unawaited(context.push(Routes.goal(meta.id), extra: VacaArrival.created));
  }

  Future<void> _save(Vaca meta) async {
    setNotice(null);
    final plata = _money();
    final saved = await showContributionSheet(
      context,
      vaca: meta,
      quick: true,
      balance: plata.balance,
      monthExpense: plata.expense,
    );
    if (saved != null && mounted) {
      setNotice(
        ref.read(trProvider)('Apartaste {value}. También quedó en tus movimientos.', {
          'value': pesos(moneyOf(ref), saved),
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final plata = _money();
    return frame(
      title: t('¿Para qué estás ahorrando?'),
      lead: t('Cada peso que apartas sale de tu plata disponible.'),
      body: (all) {
        final metas = all.where((v) => v.personal).toList();
        final cushionMeta = metas.where(isCushionGoal).firstOrNull;
        final others = metas.where((m) => m != cushionMeta).toList();
        return [
          _CushionCard(
            fixed: plata.fixed,
            meta: cushionMeta,
            onCreate: () => _create(name: t('Fondo de emergencia'), goal: plata.fixed * 3),
          ),
          const SizedBox(height: RindeSpace.s4),
          if (others.isEmpty)
            HomeSurface(
              radius: RindeRadius.brX3,
              padding: const EdgeInsets.all(RindeSpace.s5),
              child: Text(
                t(
                  'Ponle nombre y fecha a lo que quieres (la moto, el semestre, un viaje) y Rinde te dice cuánto apartar cada semana.',
                ),
                style: RindeType.body.copyWith(color: context.palette.ink.withValues(alpha: 0.7)),
              ),
            )
          else
            Semantics(
              container: true,
              label: t('Mis metas'),
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, meta) in others.indexed) ...[
                    if (i > 0) const SizedBox(height: RindeSpace.s4),
                    _MetaCard(meta: meta, onSave: () => _save(meta)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: RindeSpace.s4),
          RindeButton(
            label: t('Nueva meta'),
            leading: const RindeIcon(RindeIcons.plus, size: 16, color: RindeBrand.white),
            onPressed: _create,
          ),
          const SizedBox(height: RindeSpace.s8),
          // Negocios (el otro acceso de la web) todavía no está en la app.
          ShortcutGrid(
            title: t('En grupo'),
            items: [(Routes.vacas, t('Vacas'), t('Ahorrar con amigos'), RindeIcons.users)],
          ),
        ];
      },
    );
  }
}

/// El colchón (lienzo «Metas»): 3 meses de gastos fijos y cuántos días se aguanta hoy sin ingresos.
class _CushionCard extends ConsumerWidget {
  const _CushionCard({required this.fixed, required this.meta, required this.onCreate});

  final num fixed;
  final Vaca? meta;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final money = moneyOf(ref);
    const white = RindeBrand.white;
    final muted = white.withValues(alpha: 0.75);
    final saved = meta?.total ?? 0;
    final c = cushion(fixed: fixed, saved: saved);
    final eyebrow = Text(
      t('Tu colchón').toUpperCase(),
      style: RindeType.eyebrow.copyWith(color: RindeBrand.success),
    );
    Widget card(List<Widget> children) => DecoratedBox(
      decoration: const BoxDecoration(color: RindeBrand.obsidian, borderRadius: RindeRadius.brX3),
      child: Padding(
        padding: const EdgeInsets.all(RindeSpace.s5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
    if (c == null) {
      return card([
        eyebrow,
        const SizedBox(height: RindeSpace.s1),
        Text(t('Fondo de emergencia'), style: RindeType.title.copyWith(color: white)),
        const SizedBox(height: RindeSpace.s2),
        Text(
          t(
            'Anota tus pagos fijos en Mi plata y te decimos cuánto necesitas para aguantar 3 meses sin ingresos.',
          ),
          style: RindeType.small.copyWith(color: muted),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: RindeTextLink(
            label: t('Anotar pagos fijos'),
            color: RindeBrand.success,
            onPressed: () => context.push(Routes.payments),
          ),
        ),
      ]);
    }
    final goal = meta?.goal ?? c.goal;
    final days = c.days == 1 ? t('1 día') : t('{days} días', {'days': c.days});
    final body = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eyebrow,
                const SizedBox(height: RindeSpace.s1),
                Text(meta?.name ?? t('Fondo de emergencia'), style: RindeType.title.copyWith(color: white)),
              ],
            ),
          ),
          VacaChip(t('Meta: 3 meses'), color: white),
        ],
      ),
      const SizedBox(height: RindeSpace.s3),
      MoneyText(
        '${pesos(money, saved)} ${t('de')} ${pesos(money, goal)}',
        money: money,
        style: RindeType.figure.tabular.copyWith(color: white),
      ),
      const SizedBox(height: RindeSpace.s2),
      RindeLine(value: goal > 0 ? saved / goal : 0, tone: RindeLineTone.brand),
      const SizedBox(height: RindeSpace.s3),
      MoneyText(
        '${saved > 0 ? '${t('Hoy aguantas')} $days ${t('sin ingresos.')} ' : t('Aún no tienes colchón. ')}'
        '${t('La meta es 3 meses de tus gastos fijos (')}${pesos(money, fixed)} ${t('al mes).')}',
        money: money,
        style: RindeType.small.copyWith(color: muted),
      ),
    ];
    final current = meta;
    if (current != null) {
      return HomeTap(
        onTap: () => context.push(Routes.goal(current.id)),
        radius: RindeRadius.brX3,
        child: card(body),
      );
    }
    return card([
      ...body,
      const SizedBox(height: RindeSpace.s4),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: RindeButton(
          label: t('Crear mi colchón'),
          variant: RindeButtonVariant.onBrand,
          expand: false,
          pill: true,
          onPressed: onCreate,
        ),
      ),
    ]);
  }
}

/// Tarjeta de una meta: para cuándo, cuánto lleva, si va a tiempo, qué hacer y «Apartar plata».
class _MetaCard extends ConsumerWidget {
  const _MetaCard({required this.meta, required this.onSave});

  final Vaca meta;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final region = ref.watch(appRegionProvider);
    final today = isoDay(ref.watch(todayProvider));
    final chip = paceChip(t, meta);
    final days = meta.projection.daysLeft ?? 0;
    final when = meta.deadline != null
        ? t('Para el {deadline}{v2}', {
            'deadline': vacaDate(meta.deadline!, today, region),
            'v2': days > 0
                ? ' · ${days == 1 ? t('Falta 1 día') : t('Faltan {days} días', {'days': days})}'
                : '',
          })
        : deadlineText(t, meta, today, region, withDate: false);
    return HomeSurface(
      radius: RindeRadius.brX3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeTap(
            onTap: () => context.push(Routes.goal(meta.id)),
            radius: const BorderRadius.vertical(top: Radius.circular(RindeRadius.x3)),
            scale: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(RindeSpace.s5, RindeSpace.s5, RindeSpace.s5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meta.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: RindeType.title.copyWith(color: p.ink),
                            ),
                            Text(when, style: RindeType.small.copyWith(color: p.inkMuted)),
                          ],
                        ),
                      ),
                      if (chip != null) VacaChip(chip.label, color: chip.good ? p.positive : p.brand),
                    ],
                  ),
                  const SizedBox(height: RindeSpace.s4),
                  MoneyText(
                    '${pesos(money, meta.total)} ${t('de')} ${pesos(money, meta.goal)}',
                    money: money,
                    style: RindeType.figure.tabular.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: RindeSpace.s2),
                  VacaProgress(
                    percentage: meta.goal > 0 ? meta.total / meta.goal * 100 : 0,
                    label: t('Avance:'),
                    valueText: formatPercent(meta.percentage, formatFor(region)),
                  ),
                  const SizedBox(height: RindeSpace.s3),
                  MoneyText(
                    metaAdvice(t, meta, money, today, region),
                    money: money,
                    style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(RindeSpace.s5, RindeSpace.s3, RindeSpace.s5, RindeSpace.s5),
            child: meta.status == VacaStatus.active
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: RindeButton(
                      label: t('Apartar plata'),
                      variant: RindeButtonVariant.outline,
                      expand: false,
                      pill: true,
                      onPressed: onSave,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// `/app/vacas` (Vacas.jsx, FT-0014): las vacas en grupo del usuario. «Nueva vaca» pregunta primero
/// si es solo para él (FT-0066: entonces se crea en Metas) y «Tengo un código» lleva a la invitación.
class VacasScreen extends ConsumerStatefulWidget {
  const VacasScreen({super.key});

  @override
  ConsumerState<VacasScreen> createState() => _VacasScreenState();
}

class _VacasScreenState extends ConsumerState<VacasScreen> with _VacasList {
  Future<void> _create() async {
    setNotice(null);
    final vaca = await showVacaSheet(context, askWho: true);
    if (vaca == null || !mounted) return;
    unawaited(
      context.push(vaca.personal ? Routes.goal(vaca.id) : Routes.vaca(vaca.id), extra: VacaArrival.created),
    );
  }

  Future<void> _code() async {
    setNotice(null);
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.surface,
      builder: (_) => const _JoinByCode(),
    );
    if (code != null && mounted) unawaited(context.push(Routes.vacaJoin(code)));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return frame(
      title: t('Vacas'),
      lead: t('Junten plata en grupo para una meta.'),
      body: (all) {
        final vacas = all.where((v) => !v.personal).toList();
        return [
          Wrap(
            spacing: RindeSpace.s2,
            runSpacing: RindeSpace.s2,
            children: [
              RindeButton(
                label: t('Nueva vaca'),
                leading: const RindeIcon(RindeIcons.plus, size: 16, color: RindeBrand.white),
                size: RindeButtonSize.md,
                expand: false,
                onPressed: _create,
              ),
              RindeButton(
                label: t('Tengo un código'),
                variant: RindeButtonVariant.ghost,
                leading: RindeIcon(RindeIcons.keyRound, size: 16, color: p.ink),
                size: RindeButtonSize.md,
                expand: false,
                onPressed: _code,
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s5),
          if (vacas.isEmpty)
            HomeSurface(
              radius: RindeRadius.brX3,
              padding: const EdgeInsets.all(RindeSpace.s5),
              child: Column(
                children: [
                  RindeIcon(RindeIcons.users, size: 40, color: p.brand),
                  const SizedBox(height: RindeSpace.s3),
                  Text(
                    t('Aún no tienes vacas'),
                    textAlign: TextAlign.center,
                    style: RindeType.title.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: RindeSpace.s1),
                  Text(
                    t(
                      'Crea una para el paseo, el regalo o el mercado del mes e invita a los demás. Rinde reparte la meta y les dice si van a tiempo.',
                    ),
                    textAlign: TextAlign.center,
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                  const SizedBox(height: RindeSpace.s4),
                  RindeButton(label: t('Crear mi primera vaca'), expand: false, onPressed: _create),
                ],
              ),
            )
          else
            Semantics(
              container: true,
              label: t('Mis vacas'),
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, vaca) in vacas.indexed) ...[
                    if (i > 0) const SizedBox(height: RindeSpace.s4),
                    _VacaCard(vaca: vaca),
                  ],
                ],
              ),
            ),
        ];
      },
    );
  }
}

/// Tarjeta de una vaca: avance del grupo y lo que le falta al usuario.
class _VacaCard extends ConsumerWidget {
  const _VacaCard({required this.vaca});

  final Vaca vaca;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final region = ref.watch(appRegionProvider);
    final today = isoDay(ref.watch(todayProvider));
    final format = formatFor(region);
    return HomeTap(
      onTap: () => context.push(Routes.vaca(vaca.id)),
      radius: RindeRadius.brX2,
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vaca.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
                      ),
                      Text(
                        '${vaca.membersCount} · ${deadlineText(t, vaca, today, region, withDate: false)}',
                        style: RindeType.small.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
                VacaChip(vacaStatusLabel(t, vaca.status), color: vacaStatusColor(p, vaca.status)),
              ],
            ),
            const SizedBox(height: RindeSpace.s4),
            MoneyText(
              '${pesos(money, vaca.total)} ${t('de')} ${pesos(money, vaca.goal)}',
              money: money,
              style: RindeType.figureMd.tabular.copyWith(color: p.ink),
            ),
            const SizedBox(height: RindeSpace.s2),
            VacaProgress(
              percentage: vaca.percentage,
              label: t('Avance de {name}', {'name': vaca.name}),
              valueText: formatPercent(vaca.percentage, format),
            ),
            const SizedBox(height: RindeSpace.s3),
            Row(
              children: [
                Expanded(
                  child: MoneyText(
                    '${t('Tu parte:')} ${pesos(money, vaca.myContributed)} ${t('de')} ${pesos(money, vaca.myQuota)}',
                    money: money,
                    style: RindeType.small.tabular.copyWith(color: p.inkMuted),
                  ),
                ),
                VacaChip(memberStatusLabel(t, vaca.myStatus), color: memberStatusColor(p, vaca.myStatus)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «Unirme a una vaca» (JoinByCode.jsx): devuelve el código limpio para abrir su invitación.
class _JoinByCode extends ConsumerStatefulWidget {
  const _JoinByCode();

  @override
  ConsumerState<_JoinByCode> createState() => _JoinByCodeState();
}

class _JoinByCodeState extends ConsumerState<_JoinByCode> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _clean => _code.text.trim().toUpperCase();
  bool get _valid => RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(_clean);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    void submit() {
      if (_valid) Navigator.of(context).pop(_clean);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t('Unirme a una vaca'), style: RindeType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: RindeSpace.s1),
            Text(
              t('Escribe el código que te compartieron.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: RindeSpace.s4),
            RindeTextField(
              label: t('Código de invitación'),
              controller: _code,
              hint: t('Ej. K7M2QX'),
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: RindeSpace.s4),
            RindeButton(label: t('Ver la invitación'), onPressed: _valid ? submit : null),
          ],
        ),
      ),
    );
  }
}
