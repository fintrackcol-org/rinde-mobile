import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../data/card_models.dart';
import '../../domain/card_rules.dart';

/// Pastilla «Vencida · actualiza la fecha» o «Vence pronto» bajo una tarjeta (ExpiryBadge.jsx).
/// Nada si el plástico no vence pronto. El estado va escrito, no solo en el color.
class ExpiryBadge extends ConsumerWidget {
  const ExpiryBadge({super.key, required this.expiry});

  final CardExpiry? expiry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final notice = expiryNotice(t, expiry);
    if (notice == null) return const SizedBox.shrink();
    final color = notice.expired ? p.negative : p.ink;
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: notice.expired ? p.negative.withValues(alpha: 0.1) : p.caution.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(RindeRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: RindeSpace.s1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RindeIcon(RindeIcons.calendarClock, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(notice.text, style: RindeType.small.w(FontWeight.w500).copyWith(color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
