import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../application/money_providers.dart';
import '../../domain/commitment_rules.dart';
import 'income_overview_card.dart' show moneyOf;
import 'paid_button.dart';

/// El aviso de pagos pendientes de Mi plata (PendingPayments.jsx en modo `notice`): el primero de
/// `plan.pending` que no se cerró, con «1 de {N}», «Ya lo pagué» y la X. Solo con un plan listo y
/// vigente (sin conexión estaría viejo), como la web. Lo cerrado se guarda por cuenta y solo en este
/// teléfono; el mes siguiente vuelve a avisar (la clave lleva la fecha). Sin aviso no ocupa espacio:
/// el espacio de arriba va dentro.
class PendingPaymentNotice extends ConsumerStatefulWidget {
  const PendingPaymentNotice({super.key});

  @override
  ConsumerState<PendingPaymentNotice> createState() => _PendingPaymentNoticeState();
}

class _PendingPaymentNoticeState extends ConsumerState<PendingPaymentNotice> {
  /// El error de «Ya lo pagué» y de qué pago (`{id}-{date}`): no se queda pegado al siguiente.
  (String, String)? _error;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final today = ref.watch(todayProvider);
    final plan = blockOf(ref.watch(homePlanProvider(ref.watch(accountProvider))));
    // Mientras no se sepa qué se cerró no sale nada: no se ve un aviso que la persona ya quitó.
    final dismissed = ref.watch(dismissedPaymentsProvider).value;
    final value = plan.failed ? null : plan.value;
    if (value == null || !value.ready || dismissed == null) return const SizedBox.shrink();
    final visible = [
      for (final payment in value.pending)
        if (!dismissed.contains(dismissKey(payment.id, payment.date))) payment,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();

    final payment = visible.first;
    final key = dismissKey(payment.id, payment.date);
    final money = moneyOf(ref);
    // Las fechas AAAA-MM-DD se comparan como texto.
    final title =
        '${payment.name} ${payment.date.compareTo(isoDay(today)) < 0 ? t('venció el') : t('vence el')} '
        '${dayAndMonth(payment.date, region)}';
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s5),
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, RindeSpace.s2, RindeSpace.s1, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: RindeSpace.s2),
                      child: MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (visible.length > 1)
                              Text(
                                '${t('1 de')} ${visible.length}',
                                style: RindeType.caption.w(FontWeight.w500).copyWith(color: p.inkMuted),
                              ),
                            Text(title, style: RindeType.lead.w(FontWeight.w600).copyWith(color: p.ink)),
                            MoneyText(
                              money(payment.amount),
                              money: money,
                              style: RindeType.lead.copyWith(color: p.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.read(dismissedPaymentsProvider.notifier).dismiss(key),
                    tooltip: t('Cerrar el aviso de {name}', {'name': payment.name}),
                    style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                    icon: RindeIcon(RindeIcons.x, size: 16, color: p.ink.withValues(alpha: 0.7)),
                  ),
                ],
              ),
              // El del mes siguiente (fecha fija) no se marca: solo se avisa.
              if (payableNow(payment.date, today)) ...[
                const SizedBox(height: RindeSpace.s2),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PaidButton(
                    key: ValueKey(key),
                    id: payment.id,
                    name: payment.name,
                    amount: payment.amount,
                    date: payment.date,
                    onError: (error) {
                      if (mounted) setState(() => _error = error == null ? null : (key, error));
                    },
                  ),
                ),
              ],
              if (_error case (final of, final error) when of == key) ...[
                const SizedBox(height: RindeSpace.s2),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: RindeSpace.s3),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
