import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_motion.dart';
import '../../domain/commitments.dart';
import '../../../../design/widgets/rinde_icon.dart';

/// Pastilla de «¿Qué pagas cada mes?» (Welcome.jsx:284-306): 44 de alto, radio completo, texto 15
/// medium. Elegida: brand-soft, borde brand y check. `dashed`: «Otro», borde punteado y sin estado.
/// El área táctil es de 48 (2 arriba y 2 abajo, transparentes).
class PaymentPill extends StatefulWidget {
  const PaymentPill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected,
    this.dashed = false,
    this.leading,
  });

  final String label;

  /// null = deshabilitada (tope de pagos).
  final VoidCallback? onTap;

  /// null = no se marca (aria-pressed solo en las sugerencias).
  final bool? selected;
  final bool dashed;
  final Widget? leading;

  @override
  State<PaymentPill> createState() => _PaymentPillState();
}

class _PaymentPillState extends State<PaymentPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = widget.selected ?? false;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final fg = selected ? p.brand : p.ink.withValues(alpha: 0.7);
    final border = selected ? p.brand : p.ink.withValues(alpha: widget.dashed ? 0.25 : 0.15);
    final duration = reduce ? Duration.zero : RindeMotion.fast;

    final pill = AnimatedContainer(
      duration: duration,
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
      decoration: BoxDecoration(
        color: selected ? p.brandSoft : p.brandSoft.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(RindeRadius.pill),
        border: widget.dashed ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[RindeIcon(RindeIcons.checkBold, size: 16, color: fg), const SizedBox(width: 6)],
          if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 6)],
          Flexible(
            child: Text(widget.label, style: RindeType.control.copyWith(color: fg)),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onTap != null,
      child: AnimatedOpacity(
        opacity: widget.onTap == null ? 0.5 : 1,
        duration: duration,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: AnimatedScale(
              scale: _pressed && !reduce ? 0.97 : 1,
              duration: duration,
              curve: RindeMotion.standard,
              child: widget.dashed
                  ? CustomPaint(foregroundPainter: _DashedStadiumPainter(border), child: pill)
                  : pill,
            ),
          ),
        ),
      ),
    );
  }
}

/// `border-dashed` de 1 px alrededor de una píldora.
class _DashedStadiumPainter extends CustomPainter {
  const _DashedStadiumPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadiumPainter old) => old.color != color;
}

/// Tarjeta de un pago (Welcome.jsx:309-358): nombre (fijo o editable), quitar, Monto y Día.
/// Lo escrito va directo al borrador por los callbacks; aquí solo viven los controladores de texto.
class PaymentCard extends ConsumerStatefulWidget {
  const PaymentCard({
    super.key,
    required this.item,
    required this.format,
    required this.highlighted,
    required this.onChanged,
    required this.onRemove,
  });

  final CommitmentItem item;
  final MoneyFormat format;

  /// Es el pago del error de «Ver mi plata».
  final bool highlighted;
  final void Function({String? name, String? amount, String? dayOfMonth}) onChanged;
  final VoidCallback onRemove;

  @override
  ConsumerState<PaymentCard> createState() => PaymentCardState();
}

class PaymentCardState extends ConsumerState<PaymentCard> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _day = TextEditingController(text: widget.item.dayOfMonth);
  final _nameFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _dayFocus = FocusNode();

  @override
  void didUpdateWidget(PaymentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El borrador manda: si el controlador no aceptó un cambio (o lo recortó), el campo lo refleja.
    if (_name.text != widget.item.name) _name.text = widget.item.name;
    if (_day.text != widget.item.dayOfMonth) _day.text = widget.item.dayOfMonth;
  }

  @override
  void dispose() {
    _name.dispose();
    _day.dispose();
    _nameFocus.dispose();
    _amountFocus.dispose();
    _dayFocus.dispose();
    super.dispose();
  }

  void focusName() => _nameFocus.requestFocus();

  /// Lleva la tarjeta a la vista y pone el foco en el campo que falta.
  void reveal() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.15,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : RindeMotion.page,
      curve: RindeMotion.screen,
    );
    final node = switch (readCommitment(widget.item).problem?.message) {
      'Escribe cuánto pagas por {cleanName}.' => _amountFocus,
      'Escribe un día entre 1 y 31 para {cleanName}.' => _dayFocus,
      _ => widget.item.custom ? _nameFocus : null,
    };
    node?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final item = widget.item;
    final name = item.name.trim();
    final labelStyle = RindeType.label.copyWith(color: p.inkLabel);
    final fieldStyle = RindeType.body.copyWith(color: p.ink);
    // El día crece con el texto grande para que «30» no se corte.
    final dayWidth = math.max(88.0, MediaQuery.textScalerOf(context).scale(56));

    return RindeFadeUp(
      offset: 10,
      duration: RindeMotion.rise,
      child: Container(
        padding: const EdgeInsets.all(RindeSpace.s4),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: RindeRadius.brX2,
          border: Border.all(
            color: widget.highlighted ? p.negative : p.line,
            width: widget.highlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: item.custom
                      ? Semantics(
                          label: t('Nombre del pago'),
                          child: TextField(
                            controller: _name,
                            focusNode: _nameFocus,
                            maxLength: commitmentNameMax,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            style: fieldStyle,
                            cursorColor: RindeBrand.violet,
                            onChanged: (v) => widget.onChanged(name: v),
                            // «Siguiente» del teclado va al monto (no al botón Quitar).
                            onEditingComplete: _amountFocus.requestFocus,
                            decoration: InputDecoration(
                              hintText: t('Nombre del pago'),
                              counterText: '',
                              semanticCounterText: '',
                            ),
                          ),
                        )
                      : Text(item.name, style: RindeType.bodyMedium.copyWith(color: p.ink)),
                ),
                const SizedBox(width: RindeSpace.s1),
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: t('Quitar {v1}', {'v1': name.isEmpty ? t('este pago') : name}),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(RindeSize.tapTarget, RindeSize.tapTarget),
                  ),
                  icon: RindeIcon(RindeIcons.x, size: 16, color: p.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: RindeSpace.s2),
            LayoutBuilder(
              builder: (context, box) {
                final amount = RindeMoneyField(
                  value: item.amount,
                  onChanged: (v) => widget.onChanged(amount: v),
                  format: widget.format,
                  label: t('Monto'),
                  semanticLabel: t('Monto'),
                  hint: '',
                  focusNode: _amountFocus,
                  textInputAction: TextInputAction.next,
                );
                final day = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(child: Text(t('Día'), style: labelStyle)),
                    const SizedBox(height: 6),
                    Semantics(
                      label: t('Día'),
                      child: TextField(
                        controller: _day,
                        focusNode: _dayFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        style: fieldStyle.tabular,
                        cursorColor: RindeBrand.violet,
                        onChanged: (v) => widget.onChanged(dayOfMonth: v),
                        decoration: const InputDecoration(hintText: '30'),
                      ),
                    ),
                  ],
                );
                // Con texto grande el monto no cabe al lado del día: van uno debajo del otro.
                final stack =
                    box.maxWidth - dayWidth - RindeSpace.s3 < MediaQuery.textScalerOf(context).scale(108);
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      amount,
                      const SizedBox(height: RindeSpace.s3),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(width: dayWidth, child: day),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: amount),
                    const SizedBox(width: RindeSpace.s3),
                    SizedBox(width: dayWidth, child: day),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
