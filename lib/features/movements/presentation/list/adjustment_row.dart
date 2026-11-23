import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/data/money_models.dart';
import '../../domain/movement.dart';
import 'movement_dates.dart';

/// Mete las correcciones de saldo entre los movimientos, cada una al inicio de su día
/// (`withAdjustments` de MovementList.jsx). Con páginas por cargar ([complete] false) solo entran las
/// de los días ya visibles: las demás llegan con «Ver más». Los dos vienen del más nuevo al más viejo.
List<Object> withAdjustments(
  List<Movement> movements,
  List<BalanceAdjustment> adjustments, {
  required bool complete,
}) {
  final oldest = movements.isEmpty ? null : movements.last.date;
  final shown = [
    for (final a in adjustments)
      if (complete || (oldest != null && a.date.compareTo(oldest) >= 0)) a,
  ];
  final out = <Object>[];
  var next = 0;
  for (final m in movements) {
    // El ajuste va antes que los movimientos de su mismo día.
    while (next < shown.length && shown[next].date.compareTo(m.date) >= 0) {
      out.add(shown[next++]);
    }
    out.add(m);
  }
  out.addAll(shown.skip(next));
  return out;
}

/// «+$ 50.000» / «−$ 50.000»; oculto, solo la máscara.
String _signed(num diff, HomeMoney money) =>
    money.hidden ? money(diff.abs()) : '${diff >= 0 ? '+' : '−'}${money(diff.abs())}';

/// Corrección de saldo en la lista (AdjustmentRow.jsx). No es ingreso ni gasto: va en gris y el signo
/// dice si la plata subió o bajó. Al tocarla, el saldo de antes y el de después.
class AdjustmentRow extends StatelessWidget {
  const AdjustmentRow({super.key, required this.adjustment, required this.money, required this.t});

  final BalanceAdjustment adjustment;
  final HomeMoney money;
  final Tr t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final diff = adjustment.difference;
    final subtitle = '${t('Ajuste ·')} ${diff >= 0 ? t('no es un ingreso') : t('no es un gasto')}';
    final amount = _signed(diff, money);
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Ajuste de saldo'), style: RindeType.bodyMedium.copyWith(color: p.ink)),
        Text(subtitle, style: RindeType.small.copyWith(color: p.inkMuted)),
      ],
    );
    final amountText = Text(
      amount,
      style: RindeType.bodyMedium.w(FontWeight.w600).tabular.copyWith(color: p.inkMuted),
    );
    final spoken = [
      t('Ajuste de saldo'),
      subtitle,
      '${diff >= 0 ? t('El saldo subió ') : t('El saldo bajó ')}${money.hidden ? money.hiddenLabel : money(diff.abs())}',
    ].join(', ');
    void open() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      builder: (_) => AdjustmentSheet(adjustment: adjustment),
    );
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: open,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RindeRadius.brX2,
          side: BorderSide(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
                    child: RindeIcon(RindeIcons.scale, color: p.inkMuted),
                  ),
                  const SizedBox(width: RindeSpace.s3),
                  // Con letra grande el monto baja a su propia línea, como en MovementRow.
                  Expanded(
                    child: big
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              texts,
                              Align(alignment: AlignmentDirectional.centerEnd, child: amountText),
                            ],
                          )
                        : texts,
                  ),
                  if (!big) ...[const SizedBox(width: RindeSpace.s3), amountText],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja del ajuste: cuándo se corrigió y el saldo de antes, el de después y la diferencia.
class AdjustmentSheet extends ConsumerWidget {
  const AdjustmentSheet({super.key, required this.adjustment});

  final BalanceAdjustment adjustment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final money = HomeMoney(
      format: formatFor(region),
      hidden: ref.watch(hiddenAmountsProvider),
      hiddenLabel: t('Monto oculto'),
    );
    final a = adjustment;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: RindeSpace.s4,
        children: [
          Text(label, style: RindeType.body.copyWith(color: p.inkMuted)),
          MoneyText(
            value,
            money: money,
            style: RindeType.body.w(strong ? FontWeight.w600 : FontWeight.w500).copyWith(color: p.ink),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 0, RindeSpace.s4, RindeSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t('Ajuste de saldo'), style: RindeType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: RindeSpace.s1),
            Text(
              t('Corregiste tu saldo el {date}. No cuenta como ingreso ni como gasto.', {
                'date': shortDate(parseIsoDay(a.date), region),
              }),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: RindeSpace.s2),
            row(t('Saldo antes'), money(a.before)),
            Divider(height: 1, color: p.line),
            row(t('Saldo después'), money(a.after), strong: true),
            Divider(height: 1, color: p.line),
            row(t('Diferencia'), _signed(a.difference, money)),
          ],
        ),
      ),
    );
  }
}
