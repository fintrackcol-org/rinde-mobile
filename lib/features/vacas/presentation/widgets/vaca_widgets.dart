import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/money_text.dart' show moneyValue;
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_line.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart' show clockProvider, todayProvider;
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../movements/presentation/list/movement_dates.dart' show relativeDay;
import '../../application/vacas_providers.dart';
import '../../application/vacas_writer.dart';
import '../../data/vaca_models.dart';
import '../../domain/vaca_rules.dart';

/// Pastilla de estado (chip de VACA_STATUS y MEMBER_STATUS de la web).
class VacaChip extends StatelessWidget {
  const VacaChip(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(RindeRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Text(label, style: RindeType.caption.w(FontWeight.w600).copyWith(color: color)),
    ),
  );
}

Color vacaStatusColor(RindePalette p, VacaStatus s) => switch (s) {
  VacaStatus.active => p.brand,
  VacaStatus.completed => p.positive,
  VacaStatus.expired => p.negative,
};

Color memberStatusColor(RindePalette p, MemberStatus s) => switch (s) {
  MemberStatus.done => p.positive,
  MemberStatus.onTime => p.brand,
  MemberStatus.late => p.caution,
  MemberStatus.pending => p.inkMuted,
};

/// La barra de avance con lo que oye el lector («62,5 %: $ 650.000 de $ 1.200.000»).
class VacaProgress extends StatelessWidget {
  const VacaProgress({super.key, required this.percentage, required this.label, required this.valueText});

  final num percentage;
  final String label;
  final String valueText;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: valueText,
    child: RindeLine(value: percentage / 100),
  );
}

/// Miembros con su cuota y su avance (MemberList.jsx). Las acciones de administrador (cuota, rol,
/// sacar) solo salen si el servidor dice que quien mira administra; el servidor igual las valida.
class VacaMemberList extends ConsumerWidget {
  const VacaMemberList({super.key, required this.vaca, required this.money, required this.onNotice});

  final Vaca vaca;
  final HomeMoney money;
  final ValueChanged<String> onNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return HomeSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, m) in vaca.members.indexed)
            DecoratedBox(
              key: ValueKey(m.userId),
              decoration: BoxDecoration(
                border: i > 0 ? Border(top: BorderSide(color: p.line)) : null,
              ),
              child: _MemberRow(vaca: vaca, member: m, money: money, onNotice: onNotice),
            ),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({required this.vaca, required this.member, required this.money, required this.onNotice});

  final Vaca vaca;
  final VacaMember member;
  final HomeMoney money;
  final ValueChanged<String> onNotice;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool _managing = false;
  bool _editing = false;
  bool _busy = false;
  String? _error;
  late String _quota = widget.member.customQuota == null ? '' : '${widget.member.customQuota!.round()}';

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _editing = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, ref.read(trProvider)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(Map<String, dynamic> body) => _run(() async {
    await ref.read(vacasWriterProvider).updateMember(widget.vaca.id, widget.member.userId, body);
    widget.onNotice(ref.read(trProvider)('Miembro actualizado.'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final m = widget.member;
    final money = widget.money;
    final format = formatFor(ref.watch(appRegionProvider));
    final custom = widget.vaca.split == 'personalizado';
    final canManage = widget.vaca.admin && (custom || !m.isMe);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.isMe ? '${m.name} ${t('(tú)')}' : m.name,
                  style: RindeType.bodyMedium.copyWith(color: p.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canManage)
                IconButton(
                  onPressed: () => setState(() => _managing = !_managing),
                  tooltip: t('Gestionar a {name}', {'name': m.name}),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: RindeIcon(
                    _managing ? RindeIcons.chevronDown : RindeIcons.pencil,
                    size: 18,
                    color: p.inkMuted,
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (m.admin) VacaChip(t('Admin'), color: p.inkMuted),
              VacaChip(memberStatusLabel(t, m.status), color: memberStatusColor(p, m.status)),
            ],
          ),
          const SizedBox(height: RindeSpace.s2),
          MoneyText(
            '${pesos(money, m.contributed)} ${t('de')} ${pesos(money, m.quota)}'
            '${m.customQuota != null ? t(' (a medida)') : ''}',
            money: money,
            style: RindeType.small.tabular.copyWith(color: p.ink),
          ),
          if (m.remaining > 0)
            MoneyText(
              '${t('Le faltan')} ${pesos(money, m.remaining)}',
              money: money,
              style: RindeType.small.tabular.copyWith(color: p.inkMuted),
            ),
          const SizedBox(height: RindeSpace.s2),
          VacaProgress(
            percentage: m.percentage,
            label: t('Avance de {name}', {'name': m.name}),
            valueText: t('{percentage} de su cuota', {'percentage': formatPercent(m.percentage, format)}),
          ),
          if (_managing) ...[
            const SizedBox(height: RindeSpace.s2),
            Wrap(
              spacing: RindeSpace.s2,
              runSpacing: RindeSpace.s2,
              children: [
                if (custom && !_editing)
                  RindeButton(
                    // TEXTO ajustado: la web dice «Cuota», que en la app ya es la cuota de un crédito.
                    label: '${t('Cuota de')} ${m.name}',
                    variant: RindeButtonVariant.outline,
                    size: RindeButtonSize.sm,
                    expand: false,
                    onPressed: !_busy ? () => setState(() => _editing = true) : null,
                  ),
                if (!m.isMe)
                  RindeButton(
                    label: m.admin ? t('Quitar admin') : t('Hacer admin'),
                    variant: RindeButtonVariant.outline,
                    size: RindeButtonSize.sm,
                    expand: false,
                    onPressed: !_busy ? () => _update({'role': m.admin ? 'miembro' : 'admin'}) : null,
                  ),
              ],
            ),
            if (!m.isMe) ...[
              const SizedBox(height: RindeSpace.s2),
              ConfirmInline(
                compact: true,
                label: t('Sacar'),
                question: t('¿Sacar de la vaca?'),
                confirmLabel: t('Sí, sacar'),
                cancelLabel: t('No'),
                errorText: (e) => moneyErrorText(e, t),
                onConfirm: () async {
                  await ref.read(vacasWriterProvider).removeMember(widget.vaca.id, m.userId);
                  widget.onNotice(t('Miembro retirado de la vaca. Sus aportes siguen contando.'));
                },
              ),
            ],
          ],
          if (_editing) ...[
            const SizedBox(height: RindeSpace.s2),
            RindeMoneyField(
              value: _quota,
              format: format,
              label: '${t('Cuota de')} ${m.name}',
              semanticLabel: '${t('Cuota de')} ${m.name}',
              enabled: !_busy,
              onChanged: (raw) => setState(() => _quota = raw),
            ),
            const SizedBox(height: RindeSpace.s2),
            Wrap(
              spacing: RindeSpace.s2,
              runSpacing: RindeSpace.s2,
              children: [
                RindeButton(
                  label: t('Guardar cuota'),
                  size: RindeButtonSize.sm,
                  expand: false,
                  loading: _busy,
                  onPressed: moneyValue(_quota) == null ? null : () => _update({'quota': moneyValue(_quota)}),
                ),
                if (m.customQuota != null)
                  RindeButton(
                    label: t('Usar la calculada'),
                    variant: RindeButtonVariant.outline,
                    size: RindeButtonSize.sm,
                    expand: false,
                    onPressed: _busy ? null : () => _update({'quota': null}),
                  ),
                RindeButton(
                  label: t('Cancelar'),
                  variant: RindeButtonVariant.ghost,
                  size: RindeButtonSize.sm,
                  expand: false,
                  onPressed: _busy ? null : () => setState(() => _editing = false),
                ),
              ],
            ),
          ],
          if (_error case final error?)
            Semantics(
              liveRegion: true,
              child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
            ),
        ],
      ),
    );
  }
}

/// Historial de aportes (ContributionList.jsx), del más reciente al más antiguo. Solo quien hizo un
/// aporte puede borrarlo, y con él su gasto: el servidor lo marca con `isMe`.
class VacaContributionList extends ConsumerWidget {
  const VacaContributionList({super.key, required this.vaca, required this.money, required this.onDelete});

  final Vaca vaca;
  final HomeMoney money;
  final Future<void> Function(String contributionId) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final now = ref.watch(clockProvider)();
    if (vaca.contributions.isEmpty) {
      return Text(
        vaca.personal
            ? t('Todavía no hay aportes. Aparta lo que puedas y regístralo aquí.')
            : t('Todavía no hay aportes. ¡Sé el primero en poner tu parte!'),
        style: RindeType.body.copyWith(color: p.inkMuted),
      );
    }
    return HomeSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in vaca.contributions.indexed)
            DecoratedBox(
              key: ValueKey(c.id),
              decoration: BoxDecoration(
                border: i > 0 ? Border(top: BorderSide(color: p.line)) : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.isMe ? t('Tú') : c.name,
                            style: RindeType.bodyMedium.copyWith(color: p.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        MoneyText(
                          '+${pesos(money, c.amount)}',
                          money: money,
                          style: RindeType.bodyMedium.w(FontWeight.w600).tabular.copyWith(color: p.positive),
                        ),
                      ],
                    ),
                    Text(
                      [relativeDay(c.date, now, region, t), ?c.note].join(' · '),
                      style: RindeType.small.copyWith(color: p.inkMuted),
                    ),
                    if (c.isMe)
                      ConfirmInline(
                        compact: true,
                        label: t('Borrar aporte de {amount}', {'amount': pesos(money, c.amount)}),
                        question: t('¿Borrar el aporte y su gasto?'),
                        confirmLabel: t('Sí, borrar'),
                        cancelLabel: t('No'),
                        errorText: (e) => moneyErrorText(e, t),
                        onConfirm: () => onDelete(c.id),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «¿Vas a tiempo?» (AdviceCard.jsx): la lectura del ritmo, el consejo del servidor (IA con totales o
/// reglas) y, para quien administra una vaca, el recordatorio a los atrasados.
class VacaAdviceCard extends ConsumerStatefulWidget {
  const VacaAdviceCard({super.key, required this.vaca, required this.money});

  final Vaca vaca;
  final HomeMoney money;

  @override
  ConsumerState<VacaAdviceCard> createState() => _VacaAdviceCardState();
}

class _VacaAdviceCardState extends ConsumerState<VacaAdviceCard> {
  bool _busy = false;
  String? _message;
  String? _error;

  Future<void> _remind() async {
    final t = ref.read(trProvider);
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final (:reminded, :delivered) = await ref.read(vacasWriterProvider).remind(widget.vaca.id);
      if (!mounted) return;
      setState(
        () => _message = reminded == 0
            ? t('Nadie está atrasado: no hizo falta recordar.')
            : t('Recordamos a {v1}{v2}.', {
                // TEXTO NUEVO: «{n} miembros» (la web lo deja sin traducir).
                'v1': reminded == 1 ? t('1 miembro') : t('{n} miembros', {'n': reminded}),
                'v2': delivered == 0
                    ? t(', pero no tienen las notificaciones activas en ningún dispositivo')
                    : '',
              }),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final vaca = widget.vaca;
    final region = ref.watch(appRegionProvider);
    final today = isoDay(ref.watch(todayProvider));
    final reading = projectionText(t, vaca, widget.money, today, region);
    final advice = ref.watch(vacaAdviceProvider((ref.watch(accountProvider), vaca.id, vaca.total)));
    final others = vaca.members.where((m) => !m.isMe).toList();
    final behind = others.where((m) => m.remaining > 0 && m.status != MemberStatus.onTime).length;
    final tone = switch (reading.tone) {
      VacaTone.positive => p.positive,
      VacaTone.caution => p.caution,
      VacaTone.neutral => p.ink.withValues(alpha: 0.7),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RindeIcon(RindeIcons.trendingUp, size: 20, color: tone),
            ),
            const SizedBox(width: RindeSpace.s2),
            Expanded(
              child: MoneyText(
                reading.text,
                money: widget.money,
                style: RindeType.bodyMedium.copyWith(color: tone),
              ),
            ),
          ],
        ),
        const SizedBox(height: RindeSpace.s4),
        DecoratedBox(
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RindeIcon(RindeIcons.sparkles, size: 16, color: p.brand),
                    const SizedBox(width: RindeSpace.s2),
                    Expanded(
                      child: Text(
                        vaca.personal ? t('Consejo para ti') : t('Consejo para el grupo'),
                        style: RindeType.small.w(FontWeight.w600).copyWith(color: p.brand),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RindeSpace.s2),
                switch (advice) {
                  AsyncData(:final value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value.advice, style: RindeType.body.copyWith(color: p.ink)),
                      const SizedBox(height: RindeSpace.s2),
                      Text(
                        vaca.personal
                            ? (value.fromAi
                                  ? t('Generado con IA solo con los totales de tu meta.')
                                  : t('Calculado con los datos de tu meta.'))
                            : (value.fromAi
                                  ? t('Generado con IA solo con los totales del grupo (sin nombres).')
                                  : t('Calculado con los datos del grupo.')),
                        style: RindeType.caption.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                  AsyncError() => Text(
                    t('No pudimos traer el consejo ahora.'),
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                  _ => Row(
                    children: [
                      RindeSpinner(size: 16, color: p.inkMuted),
                      const SizedBox(width: RindeSpace.s2),
                      Expanded(
                        child: Text(t('Pensando…'), style: RindeType.small.copyWith(color: p.inkMuted)),
                      ),
                    ],
                  ),
                },
              ],
            ),
          ),
        ),
        if (!vaca.personal && vaca.admin && vaca.status != VacaStatus.completed) ...[
          const SizedBox(height: RindeSpace.s4),
          if (behind > 0 || _message != null)
            RindeButton(
              label: t('Recordar a quienes les falta'),
              variant: RindeButtonVariant.outline,
              leading: RindeIcon(RindeIcons.bell, size: 16, color: p.ink),
              loading: _busy,
              onPressed: _remind,
            )
          else
            Text(
              others.isEmpty
                  ? t(
                      'Aún no hay más miembros: cuando alguien se una, desde aquí le puedes recordar su aporte.',
                    )
                  : t('Los demás van al día o ya cumplieron.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          if (_message case final message?)
            Semantics(
              liveRegion: true,
              child: Text(message, style: RindeType.small.copyWith(color: p.positive)),
            ),
          if (_error case final error?)
            Semantics(
              liveRegion: true,
              child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
            ),
        ],
      ],
    );
  }
}
