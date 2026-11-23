import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../domain/income_sources.dart';
import 'income_kind_icon.dart';
import 'pay_days_field.dart';

/// Lo que tardan en abrirse las preguntas de una fuente (OPEN_MS de la web, `duration-300`).
const incomeOpenDuration = Duration(milliseconds: 300);

/// Una fila de «¿Cómo te entra la plata?» (IncomeSourcesFields.jsx): casilla con ícono, título y
/// descripción; al marcarla se abren debajo sus preguntas y la fila se acerca a la vista.
///
/// Diferencia con la web: al desmarcar, las preguntas se cierran con la misma animación en vez de
/// desaparecer de golpe. Lo escrito ya se borró del borrador (como en la web); mientras se cierran se
/// ve lo último que había, sin poder tocarlo.
class IncomeSourceTile extends StatefulWidget {
  const IncomeSourceTile({
    super.key,
    required this.kind,
    required this.form,
    required this.format,
    required this.t,
    required this.onToggle,
    required this.onChanged,
    this.errors = const {},
  });

  final IncomeKind kind;

  /// null = sin marcar.
  final IncomeSourceForm? form;
  final MoneyFormat format;
  final Tr t;
  final VoidCallback onToggle;
  final ValueChanged<IncomeSourceForm> onChanged;

  /// Problemas del servidor por campo (`amount`, `low`, `high`, `lastMonths`), para marcarlos en su
  /// casilla. La bienvenida no los usa.
  final Map<String, String> errors;

  @override
  State<IncomeSourceTile> createState() => _IncomeSourceTileState();
}

class _IncomeSourceTileState extends State<IncomeSourceTile> with SingleTickerProviderStateMixin {
  late final _open = AnimationController(
    vsync: this,
    duration: incomeOpenDuration,
    value: widget.form != null ? 1 : 0,
  );
  late final _size = CurvedAnimation(
    parent: _open,
    curve: RindeMotion.out,
    reverseCurve: RindeMotion.out.flipped,
  );

  /// Lo último que se vio, para dibujar las preguntas mientras se cierran.
  late IncomeSourceForm? _shown = widget.form;
  Timer? _revealTimer;
  bool _pressed = false;

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _open.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && widget.form == null && _shown != null) {
        setState(() => _shown = null);
      }
    });
  }

  @override
  void didUpdateWidget(IncomeSourceTile old) {
    super.didUpdateWidget(old);
    if (widget.form != null) _shown = widget.form;
    final opened = old.form == null && widget.form != null;
    final closed = old.form != null && widget.form == null;
    if (!opened && !closed) return;
    if (_reduce) {
      if (closed) _shown = null;
      _open.value = opened ? 1 : 0;
    } else {
      opened ? _open.forward() : _open.reverse();
    }
    if (opened) {
      _revealTimer?.cancel();
      // Como la web: cuando terminan de abrirse, la fila se acerca sin quedar bajo el botón.
      if (_reduce) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
      } else {
        _revealTimer = Timer(incomeOpenDuration, _reveal);
      }
    }
  }

  /// scrollIntoView({block: 'nearest'}): lo mínimo para que se vea la fila entera; si no cabe, su borde
  /// de arriba. El marco deja el botón fuera de la zona que se desplaza, así que nunca queda debajo.
  void _reveal() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box is! RenderBox || !box.attached || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final rect = Rect.fromLTRB(0, -RindeSpace.s3, box.size.width, box.size.height + RindeSpace.s3);
    final bottom = viewport.getOffsetToReveal(box, 1, rect: rect).offset;
    final top = viewport.getOffsetToReveal(box, 0, rect: rect).offset;
    final target = math
        .min(math.max(position.pixels, bottom), top)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    if (_reduce) {
      position.jumpTo(target);
    } else {
      unawaited(position.animateTo(target, duration: RindeMotion.page, curve: RindeMotion.out));
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _size.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = widget.t;
    final checked = widget.form != null;
    final tone = incomeTone(widget.kind);
    final reduce = _reduce;
    final fast = reduce ? Duration.zero : RindeMotion.fast;
    final shown = _shown;

    return AnimatedContainer(
      duration: reduce ? Duration.zero : RindeMotion.base,
      color: checked ? p.brandSoft.withValues(alpha: p.brandSoft.a * 0.5) : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              checked: checked,
              child: InkWell(
                onTap: widget.onToggle,
                onHighlightChanged: reduce ? null : (v) => setState(() => _pressed = v),
                focusColor: RindeBrand.violet.withValues(alpha: 0.12),
                child: AnimatedScale(
                  scale: _pressed ? 0.985 : 1,
                  duration: fast,
                  child: Padding(
                    padding: const EdgeInsets.all(RindeSpace.s4),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: tone.background, borderRadius: RindeRadius.brX2),
                          child: IncomeKindIcon(widget.kind),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t(widget.kind.title), style: RindeType.bodyMedium.copyWith(color: p.ink)),
                              Text(
                                t(widget.kind.description),
                                style: RindeType.small.copyWith(color: p.inkMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: RindeSpace.s3),
                        AnimatedContainer(
                          duration: fast,
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Relleno violeta fijo: el visto blanco necesita #6142FF también en oscuro.
                            color: checked ? p.brandSolid : Colors.transparent,
                            borderRadius: BorderRadius.circular(RindeRadius.sm),
                            border: Border.all(
                              // 0,5 y no 0,25 (web): el borde sin marcar necesita 3:1 contra el fondo.
                              color: checked ? p.brandSolid : p.ink.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: AnimatedOpacity(
                            opacity: checked ? 1 : 0,
                            duration: fast,
                            child: AnimatedScale(
                              scale: checked ? 1 : 0.75,
                              duration: fast,
                              child: const RindeIcon(RindeIcons.checkBold, size: 16, color: RindeBrand.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (shown != null)
            SizeTransition(
              sizeFactor: _size,
              alignment: Alignment.topCenter,
              // Mientras se cierra no se puede tocar ni escribir: el campo enfocado suelta el teclado.
              child: ExcludeFocus(
                excluding: !checked,
                child: IgnorePointer(
                  ignoring: !checked,
                  child: ExcludeSemantics(
                    excluding: !checked,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RindeSpace.s4,
                        RindeSpace.s1,
                        RindeSpace.s4,
                        RindeSpace.s4,
                      ),
                      child: _KindQuestions(
                        form: shown,
                        format: widget.format,
                        t: t,
                        onChanged: widget.onChanged,
                        errors: widget.errors,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Las preguntas de cada tipo, todas opcionales (KindQuestions). Montos crudos, placeholder «0» y sin
/// mensajes bajo el campo. Dentro de una fuente, el teclado pasa al siguiente monto.
class _KindQuestions extends StatelessWidget {
  const _KindQuestions({
    required this.form,
    required this.format,
    required this.t,
    required this.onChanged,
    required this.errors,
  });
  final IncomeSourceForm form;
  final MoneyFormat format;
  final Tr t;
  final ValueChanged<IncomeSourceForm> onChanged;
  final Map<String, String> errors;

  Widget _amount(
    String field,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    TextInputAction action = TextInputAction.done,
  }) => RindeMoneyField(
    key: ValueKey('income-${form.kind.name}-$field'),
    label: label,
    semanticLabel: label,
    value: value,
    onChanged: onChanged,
    format: format,
    textInputAction: action,
    // Los meses llegan como un solo campo (`lastMonths`): se marca el primero.
    errorText: errors[field == 'month-0' ? 'lastMonths' : field],
  );

  Widget _payDays() => PayDaysField(
    legend: t('¿Qué días te pagan? (opcional)'),
    payDays: form.payDays,
    onChanged: (payDays) => onChanged(form.copyWith(payDays: payDays)),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const gap = SizedBox(height: RindeSpace.s4);
    final List<Widget> children = switch (form.kind) {
      IncomeKind.sueldo => [
        _amount(
          'amount',
          t('¿Cuánto te pagan al mes?'),
          form.amount,
          (v) => onChanged(form.copyWith(amount: v)),
        ),
        gap,
        _payDays(),
      ],
      IncomeKind.comisiones => [
        _amount(
          'amount',
          t('Tu base fija al mes'),
          form.amount,
          (v) => onChanged(form.copyWith(amount: v)),
          action: TextInputAction.next,
        ),
        gap,
        _Columns(
          gap: RindeSpace.s3,
          children: [
            _amount(
              'low',
              t('Comisión en un mes malo'),
              form.low,
              (v) => onChanged(form.copyWith(low: v)),
              action: TextInputAction.next,
            ),
            _amount('high', t('En un mes bueno'), form.high, (v) => onChanged(form.copyWith(high: v))),
          ],
        ),
        gap,
        _payDays(),
      ],
      IncomeKind.proyectos => [
        Text(
          t('¿Cuánto te entró los últimos 3 meses? Más o menos.'),
          style: RindeType.label.copyWith(color: p.inkLabel),
        ),
        const SizedBox(height: RindeSpace.s2),
        _Columns(
          gap: RindeSpace.s2,
          children: [
            for (final (i, label) in [t('Este mes'), t('Hace 1 mes'), t('Hace 2')].indexed)
              _amount(
                'month-$i',
                label,
                form.lastMonths[i],
                (v) => onChanged(form.copyWith(lastMonths: [...form.lastMonths]..[i] = v)),
                action: i < 2 ? TextInputAction.next : TextInputAction.done,
              ),
          ],
        ),
      ],
      IncomeKind.diario => [
        Text(t('¿Cuántos días trabajas a la semana?'), style: RindeType.label.copyWith(color: p.ink)),
        const SizedBox(height: 6),
        RindeSegmented<String>(
          semanticLabel: t('Días que trabajas a la semana'),
          options: {for (final d in workDayOptions) d: d},
          value: form.workDays,
          onChanged: (v) => onChanged(form.copyWith(workDays: v)),
        ),
        gap,
        _amount(
          'amount',
          t('¿Cuánto haces en un día normal?'),
          form.amount,
          (v) => onChanged(form.copyWith(amount: v)),
        ),
      ],
      IncomeKind.mesada => [
        _amount(
          'amount',
          t('¿Cuánto te dan cada vez?'),
          form.amount,
          (v) => onChanged(form.copyWith(amount: v)),
        ),
        gap,
        RindeSegmented<String>(
          semanticLabel: t('Cada cuánto'),
          options: {for (final e in mesadaFrequencies.entries) e.key: t(e.value)},
          value: form.frequency,
          onChanged: (v) => onChanged(form.copyWith(frequency: v)),
        ),
      ],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// grid-cols-2 / grid-cols-3 de la web. Si las columnas quedan angostas para un monto (celular chico o
/// texto grande), se apilan en vez de cortar las cifras.
class _Columns extends StatelessWidget {
  const _Columns({required this.gap, required this.children});
  final double gap;
  final List<Widget> children;

  /// Lo que ocupa «2.500.000» con su relleno, a texto normal.
  static const _minColumn = 108.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final n = children.length;
      final column = (constraints.maxWidth - gap * (n - 1)) / n;
      if (column < MediaQuery.textScalerOf(context).scale(_minColumn)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: RindeSpace.s4), child],
          ],
        );
      }
      return Row(
        // Las etiquetas pueden ocupar dos líneas: los campos quedan alineados abajo.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: child),
          ],
        ],
      );
    },
  );
}
