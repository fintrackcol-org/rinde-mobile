import 'dart:async';

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
import '../../../design/widgets/confirm_inline.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/vacas_providers.dart';
import '../application/vacas_writer.dart';
import '../data/vaca_models.dart';
import '../domain/vaca_rules.dart';
import 'vacas_screens.dart' show VacaArrival;
import 'widgets/contribution_sheet.dart';
import 'widgets/invite_sheet.dart';
import 'widgets/vaca_sheet.dart';
import 'widgets/vaca_widgets.dart';

/// `/app/vacas/:id` (FT-0015) y `/app/metas/:id` (VacaDetail.jsx, variante de celular): el avance con
/// «Aportar» e «Invitar», miembros y aportes en pestañas, «¿Van a tiempo?» y las opciones. Una meta
/// personal es la misma pantalla sin miembros, invitaciones ni recordatorios. Qué se puede hacer lo
/// dice el servidor (`role`, `isMe`); la app solo esconde lo que no aplica. Se vuelve a pedir al
/// entrar y al bajar la pantalla (la web, además, cada 15 s).
class VacaDetailScreen extends ConsumerStatefulWidget {
  const VacaDetailScreen({super.key, required this.vacaId, required this.inMetas, this.arrival});

  final String vacaId;

  /// Se sabe por la ruta antes de cargar, para que «Volver» lleve al lugar correcto.
  final bool inMetas;
  final VacaArrival? arrival;

  @override
  ConsumerState<VacaDetailScreen> createState() => _VacaDetailScreenState();
}

class _VacaDetailScreenState extends ConsumerState<VacaDetailScreen> {
  String? _notice;
  var _noticeTone = RindeBannerTone.success;
  late var _tab = widget.inMetas ? 'aportes' : 'miembros';

  (Session?, String) get _key => (ref.read(accountProvider), widget.vacaId);
  late bool _stale = ref.read(vacaDetailProvider(_key).exists);
  String get _home => widget.inMetas ? Routes.goals : Routes.vacas;

  @override
  void initState() {
    super.initState();
    final t = ref.read(trProvider);
    _notice = switch (widget.arrival) {
      VacaArrival.created when widget.inMetas => t(
        'Meta creada. Aporta cuando quieras: cada aporte queda en tus movimientos.',
      ),
      VacaArrival.created => t('Vaca creada. Invita a los demás con el enlace o el código.'),
      VacaArrival.joined => t('¡Ya eres parte de la vaca!'),
      VacaArrival.movedToMetas => t('Listo: ahora está en tus Metas, con todos tus aportes.'),
      null => null,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_stale) {
        ref.invalidate(vacaDetailProvider(_key), asReload: true);
        setState(() => _stale = false);
      }
      // Recién creada, la vaca abre «Invitar» (VacaDetail.jsx).
      if (widget.arrival == VacaArrival.created && !widget.inMetas) {
        unawaited(showInviteSheet(context, vacaId: widget.vacaId));
      }
    });
  }

  void _setNotice(String? notice, {RindeBannerTone tone = RindeBannerTone.success}) {
    if (mounted) {
      setState(() {
        _notice = notice;
        _noticeTone = tone;
      });
    }
  }

  void _leave() => context.canPop() ? context.pop() : context.go(_home);

  Future<void> _contribute(Vaca vaca) async {
    _setNotice(null);
    final saved = await showContributionSheet(context, vaca: vaca);
    if (saved == null || !mounted) return;
    setState(() => _tab = 'aportes');
    _setNotice(
      ref.read(trProvider)('Aporte de {amount} registrado. También quedó en tus movimientos.', {
        'amount': pesos(moneyOf(ref), saved),
      }),
    );
  }

  Future<void> _deleteContribution(String contributionId) async {
    _setNotice(null);
    await ref.read(vacasWriterProvider).deleteContribution(widget.vacaId, contributionId);
    _setNotice(ref.read(trProvider)('Aporte borrado, junto con su gasto.'));
  }

  Future<void> _toMetas() async {
    final meta = await ref.read(vacasWriterProvider).makePersonal(widget.vacaId);
    if (mounted) context.pushReplacement(Routes.goal(meta.id), extra: VacaArrival.movedToMetas);
  }

  Future<void> _options(Vaca vaca) async {
    _setNotice(null);
    final t = ref.read(trProvider);
    // TEXTO NUEVO: «la meta» y «la vaca» (la web los deja sin traducir dentro de «Opciones de {noun}»).
    final noun = vaca.personal ? t('la meta') : t('la vaca');
    final writer = ref.read(vacasWriterProvider);
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                t('Opciones de {noun}', {'noun': noun}),
                style: RindeType.title.copyWith(color: sheet.palette.ink),
              ),
            ),
            const SizedBox(height: RindeSpace.s4),
            if (vaca.admin) ...[
              RindeButton(
                label: vaca.personal ? t('Editar nombre, meta y plazo') : t('Editar nombre, meta y reparto'),
                variant: RindeButtonVariant.outline,
                leading: RindeIcon(RindeIcons.pencil, size: 16, color: sheet.palette.ink),
                onPressed: () => Navigator.of(sheet).pop('edit'),
              ),
              const SizedBox(height: RindeSpace.s3),
            ],
            if (!vaca.personal) ...[
              ConfirmInline(
                label: t('Salirme de la vaca'),
                question: t(
                  'Tus aportes seguirán contando para el grupo y sus gastos quedan en tus movimientos.',
                ),
                confirmLabel: t('Sí, salirme'),
                cancelLabel: t('Cancelar'),
                errorText: (e) => moneyErrorText(e, t),
                onConfirm: () async {
                  await writer.leave(vaca.id);
                  if (sheet.mounted) Navigator.of(sheet).pop('gone');
                },
              ),
              const SizedBox(height: RindeSpace.s3),
            ],
            if (vaca.admin)
              ConfirmInline(
                label: t('Eliminar {noun}', {'noun': noun}),
                question: vaca.personal
                    ? t('Se borra la meta. Los gastos de tus aportes quedan en tus movimientos.')
                    : t(
                        'Se borra para todos los miembros. Los gastos de los aportes quedan en los movimientos de cada uno.',
                      ),
                confirmLabel: t('Sí, eliminar'),
                cancelLabel: t('Cancelar'),
                errorText: (e) => moneyErrorText(e, t),
                onConfirm: () async {
                  await writer.delete(vaca.id);
                  if (sheet.mounted) Navigator.of(sheet).pop('gone');
                },
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'gone') return _leave();
    if (result == 'edit') {
      final saved = await showVacaSheet(context, initial: vaca);
      if (saved != null) _setNotice(t('Cambios guardados.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final key = (ref.watch(accountProvider), widget.vacaId);
    final async = _stale ? const AsyncLoading<Vaca>() : ref.watch(vacaDetailProvider(key));
    final vaca = async.value;
    final error = async.error;
    final gone = error is ApiException && error.status == 404;
    final money = moneyOf(ref);

    final children = <Widget>[];
    if (gone && !async.isLoading) {
      children.add(
        RindeStateView(
          icon: RindeIcons.circleAlert,
          title: widget.inMetas ? t('Esta meta ya no está disponible') : t('Esta vaca ya no está disponible'),
          message: widget.inMetas ? t('Se eliminó.') : t('Se eliminó o ya no eres miembro.'),
          actions: [
            RindeButton(
              label: widget.inMetas ? t('Ir a mis metas') : t('Ir a mis vacas'),
              variant: RindeButtonVariant.outline,
              onPressed: () => context.go(_home),
            ),
          ],
        ),
      );
    } else if (vaca == null && async.hasError && !async.isLoading) {
      children.add(
        RindeBanner(
          message: moneyErrorText(error!, t),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(vacaDetailProvider(key)),
          ),
        ),
      );
    } else if (vaca == null) {
      children.add(
        Semantics(
          container: true,
          label: t('Cargando…'),
          child: const ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RindeSkeleton(width: 200, height: 28),
                SizedBox(height: RindeSpace.s4),
                RindeSkeleton(width: double.infinity, height: 220, radius: RindeRadius.x2),
              ],
            ),
          ),
        ),
      );
    } else {
      if (async.hasError) {
        children.addAll([
          RindeBanner(
            message: moneyErrorText(error!, t),
            action: RindeTextLink(
              label: t('Reintentar'),
              onPressed: () => ref.invalidate(vacaDetailProvider(key)),
            ),
          ),
          const SizedBox(height: RindeSpace.s2),
          Text(
            t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s4),
        ]);
      }
      children.addAll(_content(t, p, vaca, money));
    }

    return PushedFrame(
      fallback: _home,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () => ref.refresh(vacaDetailProvider(key).future).then<void>((_) {}, onError: (_) {}),
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

  List<Widget> _content(Tr t, RindePalette p, Vaca vaca, HomeMoney money) {
    final region = ref.watch(appRegionProvider);
    final format = formatFor(region);
    final today = isoDay(ref.watch(todayProvider));
    final personal = vaca.personal;
    final noun = personal ? t('la meta') : t('la vaca');
    final pr = vaca.projection;
    // FT-0066: una vaca de un solo integrante, del que la creó, probablemente es una meta. No se
    // sugiere recién creada ni con invitaciones pendientes.
    final soloVaca =
        !personal &&
        vaca.admin &&
        vaca.membersCount == 1 &&
        widget.arrival != VacaArrival.created &&
        vaca.invitations.isEmpty;
    final tab = personal ? 'aportes' : _tab;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(vaca.name, style: RindeType.headline.copyWith(color: p.ink)),
                ),
                if (vaca.description case final description?)
                  Text(description, style: RindeType.body.copyWith(color: p.inkMuted)),
                const SizedBox(height: RindeSpace.s2),
                VacaChip(vacaStatusLabel(t, vaca.status), color: vacaStatusColor(p, vaca.status)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _options(vaca),
            tooltip: t('Opciones de {noun}', {'noun': noun}),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: RindeIcon(RindeIcons.ellipsis, size: 20, color: p.ink),
          ),
        ],
      ),
      const SizedBox(height: RindeSpace.s4),
      if (_notice case final notice?) ...[
        Semantics(
          container: true,
          liveRegion: true,
          label: money.spoken(notice),
          excludeSemantics: true,
          child: RindeBanner(tone: _noticeTone, message: notice),
        ),
        const SizedBox(height: RindeSpace.s4),
      ],
      if (soloVaca) ...[
        DecoratedBox(
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${t('¿Es solo tuya?')} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: t(
                          'Nadie más está en esta vaca. Pásala a Metas: guardas tu avance y deja de pedirte que invites gente.',
                        ),
                      ),
                    ],
                  ),
                  style: RindeType.small.copyWith(color: p.ink),
                ),
                const SizedBox(height: RindeSpace.s2),
                ConfirmInline(
                  compact: true,
                  label: t('Pasar a Metas'),
                  question: t(
                    'Se cancelan las invitaciones pendientes y ya no podrás invitar a nadie. Tus aportes se conservan.',
                  ),
                  confirmLabel: t('Sí, pasar a Metas'),
                  cancelLabel: t('Cancelar'),
                  errorText: (e) => moneyErrorText(e, t),
                  onConfirm: _toMetas,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s4),
      ],
      HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s5),
        child: Semantics(
          container: true,
          label: t('Avance de {noun}', {'noun': noun}),
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: MoneyText(
                      '${pesos(money, vaca.total)} ${t('de')} ${pesos(money, vaca.goal)}',
                      money: money,
                      style: RindeType.figure.tabular.copyWith(color: p.ink),
                    ),
                  ),
                  Text(
                    formatPercent(vaca.percentage, format),
                    style: RindeType.title.tabular.copyWith(color: p.ink),
                  ),
                ],
              ),
              const SizedBox(height: RindeSpace.s3),
              VacaProgress(
                percentage: vaca.percentage,
                label: t('Avance de {name}', {'name': vaca.name}),
                valueText: formatPercent(vaca.percentage, format),
              ),
              const SizedBox(height: RindeSpace.s4),
              _StatGrid(
                children: [
                  if (!personal)
                    _Stat(
                      label: t('Tu parte'),
                      value: pesos(money, vaca.myContributed),
                      hint:
                          '${t('de')} ${pesos(money, vaca.myQuota)} · ${memberStatusLabel(t, vaca.myStatus)}',
                      money: money,
                    ),
                  _Stat(
                    label: personal ? t('Te falta') : t('Le falta al grupo'),
                    value: pesos(money, pr.remaining),
                    money: money,
                  ),
                  _Stat(
                    label: t('Ritmo por día'),
                    // Es el promedio de lo aportado: sin aportes, «$ 0» no dice nada.
                    value: vaca.total > 0 ? pesos(money, pr.averagePerDay) : '—',
                    hint: vaca.total == 0
                        ? t('Aparece con el primer aporte')
                        : pr.estimatedDate == null
                        ? null
                        : t('{v1} hacia el {estimatedDate}', {
                            'v1': personal ? t('Terminas') : t('Terminan'),
                            'estimatedDate': vacaDate(pr.estimatedDate!, today, region),
                          }),
                    money: money,
                  ),
                  _Stat(
                    label: t('Plazo'),
                    value: deadlineText(t, vaca, today, region, withDate: false),
                    hint: pr.neededPerWeek != null
                        ? t('Hacen falta {neededPerWeek} por semana', {
                            'neededPerWeek': pesos(money, pr.neededPerWeek!),
                          })
                        : vaca.deadline == null
                        ? null
                        : vacaDate(vaca.deadline!, today, region),
                    money: money,
                  ),
                ],
              ),
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: t('Aportar'),
                leading: const RindeIcon(RindeIcons.handCoins, size: 16, color: RindeBrand.white),
                onPressed: () => _contribute(vaca),
              ),
              if (!personal) ...[
                const SizedBox(height: RindeSpace.s2),
                RindeButton(
                  label: t('Invitar'),
                  variant: RindeButtonVariant.outline,
                  leading: RindeIcon(RindeIcons.users, size: 16, color: p.ink),
                  onPressed: () {
                    _setNotice(null);
                    showInviteSheet(context, vacaId: vaca.id);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: RindeSpace.s5),
      if (!personal) ...[
        RindeSegmented<String>(
          options: {
            'miembros': '${t('Miembros')} (${vaca.membersCount})',
            'aportes': '${t('Aportes')} (${vaca.contributions.length})',
          },
          value: tab,
          semanticLabel: t('Miembros y aportes'),
          onChanged: (value) => setState(() => _tab = value),
        ),
        const SizedBox(height: RindeSpace.s3),
      ] else ...[
        HomeSectionTitle(t('Aportes')),
        const SizedBox(height: RindeSpace.s2),
      ],
      if (tab == 'miembros') ...[
        Text(
          vaca.split == 'igual'
              ? t('La meta se reparte en partes iguales.')
              : t('Cada miembro tiene una cuota a medida.'),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
        const SizedBox(height: RindeSpace.s2),
        VacaMemberList(vaca: vaca, money: money, onNotice: _setNotice),
      ] else
        VacaContributionList(vaca: vaca, money: money, onDelete: _deleteContribution),
      const SizedBox(height: RindeSpace.s6),
      HomeSectionTitle(personal ? t('¿Vas a tiempo?') : t('¿Van a tiempo?')),
      const SizedBox(height: RindeSpace.s3),
      VacaAdviceCard(vaca: vaca, money: money),
    ];
  }
}

/// Las cifras del resumen en dos columnas, cada fila con la altura de la más alta.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: RindeSpace.s2),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: RindeSpace.s2),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Una cifra del resumen (Stat de VacaDetail.jsx).
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.money, this.hint});

  final String label;
  final String value;
  final String? hint;
  final HomeMoney money;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.05), borderRadius: RindeRadius.brXl),
      child: Padding(
        padding: const EdgeInsets.all(RindeSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RindeType.caption.copyWith(color: p.inkMuted)),
            MoneyText(
              value,
              money: money,
              style: RindeType.bodyMedium.w(FontWeight.w600).tabular.copyWith(color: p.ink),
            ),
            if (hint case final hint?)
              MoneyText(
                hint,
                money: money,
                style: RindeType.caption.copyWith(color: p.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}
