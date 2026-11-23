import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../shell/presentation/rinde_tab_scaffold.dart';
import '../tour_anchors.dart';
import 'tour_steps.dart';

const _pad = 6.0; // aire entre el elemento y el borde del hueco
const _gap = 12.0; // entre el hueco y la tarjeta
const _margin = 12.0; // entre la tarjeta y los bordes
const _dim = Color(0x8C000000); // negro al 55 %

/// Ancho de la tarjeta: 360 o lo que deje la pantalla.
double coachCardWidth(Size screen, EdgeInsets safe) =>
    math.max(0, math.min(360, screen.width - safe.horizontal - _margin * 2));

/// Esquina superior izquierda de la tarjeta: debajo del hueco si cabe; si no, encima; si tampoco,
/// pegada abajo. Sin hueco, en el centro. Nunca bajo la barra de estado ni la de navegación.
Offset placeCoachCard({
  required Size screen,
  required Size card,
  required Rect? hole,
  required EdgeInsets safe,
}) {
  final top = safe.top + _margin;
  final bottom = screen.height - safe.bottom - _margin;
  final left = safe.left + _margin;
  final right = screen.width - safe.right - _margin;
  if (hole == null) {
    return Offset((left + right - card.width) / 2, math.max(top, (top + bottom - card.height) / 2));
  }
  final below = hole.bottom + _gap;
  final above = hole.top - _gap - card.height;
  return Offset(
    math.max(left, math.min(hole.center.dx - card.width / 2, right - card.width)),
    below + card.height <= bottom
        ? below
        : above >= top
        ? above
        : math.max(top, bottom - card.height),
  );
}

/// Radio del hueco: el del elemento resaltado si tiene esquinas redondeadas; si no, 16.
double _radiusOf(RenderObject? node, Size size) {
  // El que redondea suele ser un hijo del mismo tamaño que el elemento marcado.
  RenderObject? box = node;
  while (box is RenderBox && box.size == size) {
    final RenderObject current = box;
    final BorderRadiusGeometry? corners = switch (current) {
      RenderClipRRect(:final borderRadius) => borderRadius,
      RenderDecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle)) => BorderRadius.circular(
        size.shortestSide,
      ),
      RenderDecoratedBox(decoration: BoxDecoration(:final borderRadius)) => borderRadius,
      RenderPhysicalShape(clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(:final borderRadius))) =>
        borderRadius,
      _ => null,
    };
    final radius = corners?.resolve(TextDirection.ltr).topLeft.x ?? 0;
    if (radius > 0) return radius + _pad;
    box = current is RenderObjectWithChildMixin<RenderBox> ? current.child : null;
  }
  return 16;
}

/// Tutorial sobre la app real (CoachTour.jsx de Rinde Web): el fondo se oscurece y queda resaltado
/// solo lo que se explica, con una tarjeta corta. Recorrido corto, una pregunta y el largo. Siempre
/// se puede cerrar: Omitir, tocar fuera, «atrás» o terminar. `completed` = llegó al final.
class CoachTour extends ConsumerStatefulWidget {
  const CoachTour({super.key, required this.anchors, required this.onClose});

  final TourAnchors anchors;
  final void Function(bool completed) onClose;

  @override
  ConsumerState<CoachTour> createState() => _CoachTourState();
}

class _CoachTourState extends ConsumerState<CoachTour> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: RindeMotion.page);
  late final _move = CurvedAnimation(parent: _controller, curve: RindeMotion.segment);
  final _focus = FocusNode(debugLabel: 'tutorial', skipTraversal: true);
  final _bodyKey = GlobalKey();
  final _flowKey = GlobalKey();
  final _spot = _CardSpot();

  int _index = 0;
  RRect? _hole;

  /// Desde dónde viene el hueco en la animación del paso (null = aparece).
  RRect? _fromHole;
  bool _closed = false;

  CoachStep get _step => coachSteps(ref.read(trProvider))[_index];

  RRect? get _shownHole =>
      _hole == null || _fromHole == null ? _hole : RRect.lerp(_fromHole, _hole, _move.value);

  @override
  void initState() {
    super.initState();
    // Flow solo se repinta al moverse: sin esto, el lector deja la tarjeta donde estaba antes.
    _controller.addListener(() => _flowKey.currentContext?.findRenderObject()?.markNeedsSemanticsUpdate());
  }

  @override
  void didUpdateWidget(CoachTour oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El Inicio cambió debajo (sin conexión, un bloque que llegó tarde): lo resaltado pudo moverse.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Al abrir, y al girar la pantalla o cambiar el tamaño de letra: lo resaltado cambió de sitio.
    // Se mide cuando la pantalla ya se acomodó.
    MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final opening = _controller.isDismissed;
      _locate(animate: opening);
      if (opening) _focusCard();
    });
  }

  @override
  void dispose() {
    _move.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close(bool completed) {
    if (_closed) return;
    _closed = true;
    widget.onClose(completed);
  }

  void _go(int index) {
    setState(() {
      _fromHole = _shownHole;
      _spot.from = _spot.shown;
      _index = index;
    });
    _locate(animate: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCard());
  }

  /// El foco (y el lector de pantalla) entran a la tarjeta al abrir y en cada paso.
  void _focusCard() {
    if (!mounted) return;
    _focus.requestFocus();
    _bodyKey.currentContext?.findRenderObject()?.sendSemanticsEvent(const FocusSemanticEvent());
  }

  /// Trae a la vista lo que se explica y lo mide.
  void _locate({bool animate = false}) {
    if (!mounted) return;
    final target = _step.target;
    final anchor = target == null ? null : widget.anchors.key(target).currentContext;
    final rect = target == null ? null : widget.anchors.rectOf(target);
    if (anchor != null && rect != null) {
      final area = _visibleArea(anchor);
      if (rect.top < area.top || rect.bottom > area.bottom) {
        // Lo que hubo que desplazar se mide después del cuadro, ya en su sitio.
        Scrollable.ensureVisible(anchor, alignment: 0.5);
        WidgetsBinding.instance
          ..addPostFrameCallback((_) => _measure(animate: animate))
          ..ensureVisualUpdate();
        return;
      }
    }
    _measure(animate: animate);
  }

  /// Donde se alcanza a ver [anchor]: su lista (empieza bajo la franja DEMO) sin lo que tapa la barra
  /// flotante. Lo de la propia barra no está en una lista: le sirve toda la pantalla segura.
  Rect _visibleArea(BuildContext anchor) {
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final list = Scrollable.maybeOf(anchor)?.context.findRenderObject();
    if (list is RenderBox) {
      // Se cuenta desde abajo de la pantalla: con el aviso de error la lista ya termina sobre la barra.
      final covered = EdgeInsets.only(bottom: RindeTabScaffold.bottomInset(context));
      return covered.deflateRect(screen).intersect(list.localToGlobal(Offset.zero) & list.size);
    }
    return MediaQuery.viewPaddingOf(context).deflateRect(screen);
  }

  void _measure({bool animate = false}) {
    if (!mounted) return;
    final target = _step.target;
    final anchor = target == null ? null : widget.anchors.key(target).currentContext;
    final rect = target == null ? null : widget.anchors.rectOf(target);
    final box = context.findRenderObject();
    RRect? hole;
    if (anchor != null && rect != null && box is RenderBox && box.hasSize) {
      // Lo que no cabe se resalta solo hasta donde se ve.
      final shown = rect.inflate(_pad).intersect(_visibleArea(anchor));
      if (!shown.isEmpty) {
        final radius = _radiusOf(anchor.findRenderObject(), rect.size);
        final local = box.globalToLocal(shown.topLeft) & shown.size;
        hole = RRect.fromRectAndRadius(local, Radius.circular(math.min(radius, local.shortestSide / 2)));
      }
    }
    if (!animate && hole == _hole) return;
    setState(() => _hole = hole);
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final steps = coachSteps(t);
    final step = steps[_index];
    final last = _index == steps.length - 1;
    final section = [
      for (var i = 0; i < steps.length; i++)
        if (steps[i].section == step.section) i,
    ];
    final at = section.indexOf(_index);
    final vars = {'v1': at + 1, 'length': section.length};
    final label = switch (step.section) {
      TourSection.corto => t('Paso {v1} de {length}', vars),
      TourSection.largo => t('Lo demás · {v1} de {length}', vars),
      TourSection.pregunta => '',
    };
    final tone = step.section == TourSection.largo ? RindeBrand.success : p.brand;

    // Los botones de la tarjeta miden 44 en la web; aquí 48, el área táctil mínima.
    Widget button(
      String label,
      VoidCallback onPressed, [
      RindeButtonVariant variant = RindeButtonVariant.primary,
      RindeButtonSize size = RindeButtonSize.md,
    ]) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
      child: RindeButton(label: label, onPressed: onPressed, variant: variant, size: size, expand: false),
    );
    void next() => last ? _close(true) : _go(_index + 1);

    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in section)
          Container(
            width: i == _index ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.only(right: RindeSpace.s1),
            decoration: BoxDecoration(
              color: i <= _index ? tone : p.lineStrong,
              borderRadius: BorderRadius.circular(RindeRadius.pill),
            ),
          ),
      ],
    );
    // Con letra grande los puntos suben a su propia línea: «Siguiente» necesita todo el ancho.
    final dotsAbove = label.isNotEmpty && MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: RindeRadius.brX3,
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(color: Color(0x26141414), offset: Offset(0, 20), blurRadius: 60)],
      ),
      child: Material(
        type: MaterialType.transparency,
        // Con letra muy grande la tarjeta se desplaza por dentro. La llave: cada paso abre arriba.
        child: SingleChildScrollView(
          key: ValueKey(_index),
          padding: const EdgeInsets.all(RindeSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    // liveRegion: el lector anuncia en qué paso va.
                    child: label.isEmpty
                        ? const SizedBox.shrink()
                        : Semantics(
                            container: true,
                            liveRegion: true,
                            label: label,
                            child: ExcludeSemantics(
                              child: Text(
                                label.toUpperCase(),
                                style: RindeType.eyebrow.copyWith(color: p.brand),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: RindeSpace.s3),
                  button(t('Omitir'), () => _close(false), RindeButtonVariant.ghost, RindeButtonSize.sm),
                ],
              ),
              Semantics(
                key: _bodyKey,
                container: true,
                namesRoute: true,
                child: Focus(
                  focusNode: _focus,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(step.title, style: RindeType.title.copyWith(color: p.ink)),
                      const SizedBox(height: RindeSpace.s1),
                      Text(step.text, style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              if (dotsAbove) ...[
                Align(alignment: AlignmentDirectional.centerStart, child: dots),
                const SizedBox(height: RindeSpace.s3),
              ],
              Row(
                children: [
                  if (label.isNotEmpty && !dotsAbove) ...[dots, const SizedBox(width: RindeSpace.s1)],
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: RindeSpace.s2,
                      runSpacing: RindeSpace.s2,
                      children: step.section == TourSection.pregunta
                          ? [
                              button(t('Ya entendí'), () => _close(true), RindeButtonVariant.outline),
                              button(t('Ver lo demás'), next),
                            ]
                          : [
                              if (_index > 0)
                                button(t('Atrás'), () => _go(_index - 1), RindeButtonVariant.ghost),
                              button(last ? t('Listo') : t('Siguiente'), next),
                            ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(false);
      },
      // El tutorial se repinta solo: mover el hueco no vuelve a pintar el Inicio.
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Lo que queda debajo no existe para el lector de pantalla mientras el tutorial está abierto.
            BlockSemantics(
              child: Semantics(
                button: true,
                label: t('Cerrar el tutorial'),
                onTap: () => _close(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  // Tocar el fondo lo cierra: no se obliga a terminarlo.
                  onTap: () => _close(false),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DimPainter(move: _move, from: _fromHole, hole: _hole),
                  ),
                ),
              ),
            ),
            Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: Actions(
                // Esc en un teclado físico.
                actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _close(false))},
                child: FocusScope(
                  // Flow mueve la tarjeta con una transformación al pintar: cambiar de paso no
                  // recalcula el layout en cada cuadro.
                  child: Flow(
                    key: _flowKey,
                    delegate: _CardFlow(
                      move: _move,
                      hole: _hole?.outerRect,
                      safe: MediaQuery.viewPaddingOf(context),
                      spot: _spot,
                    ),
                    children: [card],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dónde se pintó la tarjeta la última vez y desde dónde viene en la animación del paso.
class _CardSpot {
  Offset? shown;
  Offset? from;
}

class _CardFlow extends FlowDelegate {
  _CardFlow({required this.move, required this.hole, required this.safe, required this.spot})
    : super(repaint: move);

  final Animation<double> move;
  final Rect? hole;
  final EdgeInsets safe;
  final _CardSpot spot;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: coachCardWidth(constraints.biggest, safe))
          .copyWith(maxHeight: math.max(0, constraints.maxHeight - safe.vertical - _margin * 2));

  @override
  void paintChildren(FlowPaintingContext context) {
    final target = placeCoachCard(
      screen: context.size,
      card: context.getChildSize(0)!,
      hole: hole,
      safe: safe,
    );
    final from = spot.from;
    final at = from == null ? target : Offset.lerp(from, target, move.value)!;
    spot.shown = at;
    // Al abrir aparece; entre pasos se desliza.
    context.paintChild(
      0,
      transform: Matrix4.translationValues(at.dx, at.dy, 0),
      opacity: from == null ? move.value : 1,
    );
  }

  @override
  bool shouldRelayout(_CardFlow old) => old.safe != safe;

  @override
  bool shouldRepaint(_CardFlow old) => old.hole != hole || old.safe != safe;
}

/// El fondo oscuro con el hueco de lo que se explica y su aro blanco.
class _DimPainter extends CustomPainter {
  _DimPainter({required this.move, required this.from, required this.hole}) : super(repaint: move);

  final Animation<double> move;
  final RRect? from;
  final RRect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final to = hole;
    final shown = to == null || from == null ? to : RRect.lerp(from, to, move.value)!;
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (shown != null) dim.addRRect(shown);
    canvas.drawPath(dim, Paint()..color = _dim);
    if (shown == null) return;
    // Un hueco nuevo se aclara en vez de aparecer de golpe.
    final appear = from == null ? move.value : 1.0;
    if (appear < 1) canvas.drawRRect(shown, Paint()..color = _dim.withValues(alpha: 0.55 * (1 - appear)));
    canvas.drawRRect(
      shown.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = RindeBrand.white.withValues(alpha: 0.9 * appear),
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.from != from || old.hole != hole;
}
