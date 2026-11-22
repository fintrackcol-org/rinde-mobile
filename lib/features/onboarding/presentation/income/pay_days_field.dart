import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../domain/income_sources.dart';

/// Días de pago (PayDaysField de components/money/IncomeFields.jsx): 31 días en 7 columnas, hasta 4,
/// ordenados (togglePayDay).
///
/// Diferencias con la web:
/// - Cada día ocupa toda su celda (el espacio entre botones también responde) y mide 48 de alto.
///   A lo ancho, 7 columnas no caben a 44 en un celular de 360: la celda mide lo que dé la columna.
/// - El quinto día no se ignora en silencio: aparece «Hasta 4 días.» hasta el siguiente cambio.
class PayDaysField extends ConsumerStatefulWidget {
  const PayDaysField({super.key, required this.legend, required this.payDays, required this.onChanged});
  final String legend;
  final List<int> payDays;
  final ValueChanged<List<int>> onChanged;

  @override
  ConsumerState<PayDaysField> createState() => _PayDaysFieldState();
}

class _PayDaysFieldState extends ConsumerState<PayDaysField> {
  bool _limitHit = false;

  void _toggle(int day) {
    final next = togglePayDay(widget.payDays, day);
    final blocked = identical(next, widget.payDays);
    setState(() => _limitHit = blocked);
    if (!blocked) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.legend, style: RindeType.label.copyWith(color: p.inkLabel)),
        const SizedBox(height: RindeSpace.s2 - 3),
        for (var week = 0; week < 5; week++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: week * 7 + i < 31
                      ? _DayButton(
                          day: week * 7 + i + 1,
                          label: t('Día {day}', {'day': week * 7 + i + 1}),
                          selected: widget.payDays.contains(week * 7 + i + 1),
                          reduce: reduce,
                          onTap: () => _toggle(week * 7 + i + 1),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        if (_limitHit) ...[
          const SizedBox(height: RindeSpace.s1),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                RindeIcon(RindeIcons.circleAlert, size: 16, color: p.caution),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // TEXTO NUEVO
                    t('Hasta {max} días.', {'max': maxPayDays}),
                    style: RindeType.small.w(FontWeight.w500).copyWith(color: p.caution),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: RindeSpace.s2 - 3),
        Text(
          t('Si eliges 31, en los meses cortos contamos el último día.'),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
      ],
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.day,
    required this.label,
    required this.selected,
    required this.reduce,
    required this.onTap,
  });

  final int day;
  final String label;
  final bool selected;
  final bool reduce;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: RindeRadius.brXl,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: RindeBrand.violet.withValues(alpha: 0.14),
        child: Padding(
          // La mitad del espacio entre botones (gap-1.5) a cada lado: no hay huecos muertos.
          padding: const EdgeInsets.all(3),
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : RindeMotion.fast,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? p.brandSoft : Colors.transparent,
              borderRadius: RindeRadius.brXl,
              border: Border.all(color: selected ? p.brand : p.ink.withValues(alpha: 0.12)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$day',
                maxLines: 1,
                style: RindeType.label.tabular.copyWith(
                  color: selected ? p.brand : p.ink.withValues(alpha: 0.7),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
