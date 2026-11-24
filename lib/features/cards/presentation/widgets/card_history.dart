import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../data/card_models.dart';
import '../../../../design/widgets/confirm_inline.dart';

/// «Compras y pagos» del detalle (CardDetail.jsx:28-71,102-106): compras con su descripción, pagos
/// en verde con «−» (y «Eliminar pago» en línea) y «Ajuste con el banco −{x}». Lo arma el servidor.
class CardHistory extends ConsumerWidget {
  const CardHistory({
    super.key,
    required this.movements,
    required this.money,
    required this.onDeletePayment,
    required this.errorText,
  });

  final List<CardMovement> movements;
  final HomeMoney money;

  /// Borra el pago (lanza si falla); el error se muestra dentro de la confirmación.
  final Future<void> Function(String paymentId) onDeletePayment;
  final String Function(Object error) errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);

    if (movements.isEmpty) {
      return Text(t('Aún no hay movimientos.'), style: RindeType.body.copyWith(color: p.inkMuted));
    }
    return Semantics(
      container: true,
      label: t('Historial de la tarjeta'),
      child: HomeSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, m) in movements.indexed)
              DecoratedBox(
                // Como key={`${m.kind}-${m.id}`} de la web (CardDetail.jsx:107): si la lista cambia con
                // una confirmación abierta, esta sigue con SU pago y no borra el de al lado.
                key: ValueKey('${m.kind.wire}-${m.id}'),
                decoration: BoxDecoration(
                  border: i > 0 ? Border(top: BorderSide(color: p.line)) : null,
                ),
                child: _HistoryRow(
                  movement: m,
                  money: money,
                  region: region,
                  onDeletePayment: onDeletePayment,
                  errorText: errorText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({
    required this.movement,
    required this.money,
    required this.region,
    required this.onDeletePayment,
    required this.errorText,
  });

  final CardMovement movement;
  final HomeMoney money;
  final Region region;
  final Future<void> Function(String paymentId) onDeletePayment;
  final String Function(Object error) errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final m = movement;
    final interestNote = t('Los intereses los calcula tu banco a la fecha de corte.');
    final title = switch (m.kind) {
      CardMovementKind.purchase => m.description ?? '',
      CardMovementKind.payment => t('Pago'),
      CardMovementKind.adjustment => t('Ajuste con el banco {v1}{money}', {
        'v1': m.amount < 0 ? '−' : '+',
        'money': money(m.amount.abs()),
      }),
    };
    final installments = (m.installments ?? 1) > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MoneyText(
                        title,
                        money: money,
                        style: RindeType.bodyMedium.copyWith(color: p.ink),
                      ),
                      Text(
                        [
                          dayAndMonth(m.date, region),
                          if (installments) ' · ${t('a')} ${m.installments} ${t('cuotas')}*',
                        ].join(),
                        style: RindeType.small.copyWith(color: p.inkMuted),
                      ),
                      if (installments)
                        Text('* $interestNote', style: RindeType.caption.copyWith(color: p.inkMuted)),
                    ],
                  ),
                ),
                if (m.kind != CardMovementKind.adjustment) ...[
                  const SizedBox(width: RindeSpace.s3),
                  // Como mucho media fila: con letra grande el monto se achica en vez de desbordar.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                    child: MoneyText(
                      '${m.kind == CardMovementKind.payment ? '−' : ''}${money(m.amount)}',
                      money: money,
                      fit: true,
                      style: RindeType.body.tabular.copyWith(
                        color: m.kind == CardMovementKind.payment ? p.positive : p.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (m.kind == CardMovementKind.payment)
            ConfirmInline(
              compact: true,
              label: t('Eliminar pago'),
              question: t('¿Eliminar este pago? Lo usado vuelve a subir.'),
              confirmLabel: t('Sí, eliminar'),
              cancelLabel: t('Cancelar'),
              onConfirm: () => onDeletePayment(m.id),
              errorText: errorText,
            ),
        ],
      ),
    );
  }
}
