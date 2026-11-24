import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_line.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart' show HomeLink, HomeSurface;
import '../../data/debt_models.dart';
import '../../domain/debt_rules.dart';

/// El avatar con las iniciales (Avatar de Debts.jsx). Decorativo: el nombre va al lado.
class DebtAvatar extends StatelessWidget {
  const DebtAvatar({super.key, required this.name, required this.kind});

  final String name;
  final DebtKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final receivable = kind == DebtKind.receivable;
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(RindeSpace.s1),
        decoration: BoxDecoration(
          color: receivable ? p.brandSoft : p.caution.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        // Con la letra grande las iniciales se achican: el círculo no crece.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            debtInitials(name),
            style: RindeType.small.w(FontWeight.w600).copyWith(color: receivable ? p.brand : p.ink),
          ),
        ),
      ),
    );
  }
}

/// Una cuenta pendiente (DebtCard de Debts.jsx): cuánto falta, la línea de avance, cómo va, la
/// próxima cuota (vencida, en rojo y con el texto «Venció…»), el último abono y los botones.
class DebtCard extends ConsumerWidget {
  const DebtCard({
    super.key,
    required this.debt,
    required this.money,
    required this.today,
    required this.onPay,
    required this.onSettle,
    required this.onEdit,
  });

  final Debt debt;
  final HomeMoney money;

  /// AAAA-MM-DD del teléfono, como `todayIso()` de la web.
  final String today;

  /// null: desactivado (la lista está vieja: sus montos ya no son verdad).
  final VoidCallback? onPay;
  final VoidCallback? onSettle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final words = debtWords(t, debt.kind);
    final next = debt.nextInstallment;
    final due = next == null ? null : debtDueText(t, next.date, today, region);
    final last = debt.payments.firstOrNull;
    final late = due?.late ?? false;

    return HomeSurface(
      radius: RindeRadius.brX3,
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DebtAvatar(name: debt.person, kind: debt.kind),
              const SizedBox(width: RindeSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt.person, style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink)),
                    if (debt.note case final note? when note.isNotEmpty)
                      Text(note, style: RindeType.small.copyWith(color: p.inkMuted)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: t('Editar la cuenta de {person}', {'person': debt.person}),
                style: IconButton.styleFrom(minimumSize: const Size(RindeSize.button, RindeSize.button)),
                icon: RindeIcon(RindeIcons.pencil, size: 18, color: p.ink),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s4),
          Text(
            words.left.toUpperCase(),
            semanticsLabel: words.left,
            style: RindeType.eyebrow.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s1),
          MoneyText(
            money(debt.pending),
            money: money,
            fit: true,
            style: RindeType.display.copyWith(fontSize: 30, height: 36 / 30, color: p.ink),
          ),
          const SizedBox(height: RindeSpace.s3),
          RindeLine(value: debt.amount > 0 ? (debt.paid / debt.amount).toDouble() : 0),
          const SizedBox(height: RindeSpace.s2),
          MoneyText(
            debtProgressText(t, debt, money.call),
            money: money,
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          if (next != null && due != null) ...[
            const SizedBox(height: RindeSpace.s3),
            DecoratedBox(
              decoration: BoxDecoration(
                color: late ? p.negative.withValues(alpha: 0.1) : p.wash,
                borderRadius: RindeRadius.brXl,
              ),
              child: Padding(
                padding: const EdgeInsets.all(RindeSpace.s3),
                child: _NextInstallment(
                  prefix: debt.installments == null ? '' : t('Cuota {number}: ', {'number': next.number}),
                  amount: money(next.amount),
                  // Como la web: «· vence el 15 dic», «· venció hace 3 días» con minúscula inicial; solo la
                  // primera letra, para no dejar «dec» en inglés.
                  suffix: ' · ${due.text[0].toLowerCase()}${due.text.substring(1)}',
                  money: money,
                  style: late
                      ? RindeType.small.w(FontWeight.w500).copyWith(color: p.negative)
                      : RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.8)),
                ),
              ),
            ),
          ],
          if (last != null) ...[
            const SizedBox(height: RindeSpace.s2),
            MoneyText(
              '${t('Último abono:')} ${money(last.amount)} ${t('el')} ${debtShortDate(last.date, today, region)}',
              money: money,
              style: RindeType.caption.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: RindeSpace.s4),
          RindeButton(label: t('Registrar abono'), onPressed: onPay),
          const SizedBox(height: RindeSpace.s1),
          TextButton(
            onPressed: onSettle,
            style: TextButton.styleFrom(
              foregroundColor: p.brand,
              minimumSize: const Size(double.infinity, RindeSize.button),
              textStyle: RindeType.bodyMedium,
            ),
            child: Text(words.settleAll, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// «Cuota 2: **$20.000** · vence el 15 dic», con el monto en negrita y la máscara para el lector.
class _NextInstallment extends StatelessWidget {
  const _NextInstallment({
    required this.prefix,
    required this.amount,
    required this.suffix,
    required this.money,
    required this.style,
  });

  final String prefix;
  final String amount;
  final String suffix;
  final HomeMoney money;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: prefix),
        TextSpan(
          text: amount,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextSpan(text: suffix),
      ],
    ),
    semanticsLabel: money.spoken('$prefix$amount$suffix'),
    style: style.tabular,
  );
}

/// Una cuenta saldada (SettledRow de Debts.jsx): compacta, con «ver el movimiento» SOLO si se saldó
/// con «Ya me pagó todo» / «Ya pagué todo» y la casilla (si la saldó un abono no hay enlace) y el
/// monto tachado.
class SettledDebtRow extends ConsumerWidget {
  const SettledDebtRow({super.key, required this.debt, required this.money, required this.onOpenMovement});

  final Debt debt;
  final HomeMoney money;
  final ValueChanged<String> onOpenMovement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final muted = p.ink.withValues(alpha: 0.6);
    return Opacity(
      opacity: 0.8,
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s3),
        child: Row(
          children: [
            DebtAvatar(name: debt.person, kind: debt.kind),
            const SizedBox(width: RindeSpace.s3),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debt.person,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RindeType.bodyMedium.copyWith(color: p.ink),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(t('Saldada'), style: RindeType.small.copyWith(color: muted)),
                      if (debt.transactionId case final id?) ...[
                        Text(' · ', style: RindeType.small.copyWith(color: muted)),
                        HomeLink(
                          label: t('ver el movimiento'),
                          underline: true,
                          style: RindeType.small.copyWith(color: muted),
                          onTap: () => onOpenMovement(id),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: RindeSpace.s3),
            Flexible(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: MoneyText(
                  money(debt.amount),
                  money: money,
                  fit: true,
                  style: RindeType.bodyMedium
                      .w(FontWeight.w600)
                      .copyWith(color: muted, decoration: TextDecoration.lineThrough, decorationColor: muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
