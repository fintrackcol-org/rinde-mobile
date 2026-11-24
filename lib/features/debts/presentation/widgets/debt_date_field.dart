import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../domain/debt_rules.dart' show debtShortDate;

/// Un campo de fecha de las hojas de Cuentas (el `<input type="date">` de la web): la etiqueta, la
/// fecha elegida (o «—») que abre el calendario y, si es opcional, la X que la quita. [lastIsToday]:
/// como el `max` de la web, no deja elegir días futuros.
class DebtDateField extends ConsumerWidget {
  const DebtDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.optional = false,
    this.lastIsToday = false,
    this.enabled = true,
    this.error,
    this.focusNode,
  });

  final String label;

  /// AAAA-MM-DD o null.
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool optional;
  final bool lastIsToday;
  final bool enabled;
  final String? error;
  final FocusNode? focusNode;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final current = value == null ? today : DateTime.parse(value!);
    final initial = lastIsToday && current.isAfter(today) ? today : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // El servidor acepta cualquier año (uno mal escrito en la web): el calendario debe poder abrirlo.
      firstDate: initial.isBefore(DateTime(2000)) ? initial : DateTime(2000),
      lastDate: lastIsToday ? today : (initial.isAfter(DateTime(2100)) ? initial : DateTime(2100)),
      helpText: label,
    );
    if (picked != null) onChanged(isoDay(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(label, style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Un solo nodo: el lector oye «¿Cuándo?, 23 nov, botón», no la fecha suelta.
            MergeSemantics(
              child: Semantics(
                label: label,
                child: TextButton.icon(
                  focusNode: focusNode,
                  onPressed: enabled ? () => _pick(context, ref) : null,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: RindeIcon(RindeIcons.calendarRange, size: 18, color: p.brand),
                  label: Text(
                    // Con el año si no es este (una primera cuota puede caer el otro año).
                    value == null ? '—' : debtShortDate(value!, isoDay(ref.watch(clockProvider)()), region),
                    style: RindeType.bodyMedium.copyWith(color: p.brand),
                  ),
                ),
              ),
            ),
            if (optional && value != null)
              IconButton(
                onPressed: enabled ? () => onChanged(null) : null,
                tooltip: t('Quitar {v1}', {'v1': label}),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: RindeIcon(RindeIcons.x, size: 18, color: p.inkMuted),
              ),
          ],
        ),
        if (error case final error?)
          Semantics(
            liveRegion: true,
            child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
          ),
      ],
    );
  }
}
