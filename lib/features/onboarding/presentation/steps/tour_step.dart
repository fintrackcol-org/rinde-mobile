import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../rin/rin.dart';
import '../../domain/onboarding_flow.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../tour/tour_scenes.dart';
import '../widgets/onboarding_shell.dart';

/// Posiciones 2-6: un paso del recorrido «Cómo funciona» (HowItWorksTour.jsx, FT-0048). Arriba, un
/// escenario con una pantalla de Rinde animada y rotulada como ejemplo (no anota nada); abajo, qué
/// es y para qué sirve. Se avanza con el botón del marco o deslizando; nunca avanza solo. El ejemplo
/// se puede repetir.
class TourStep extends ConsumerStatefulWidget {
  const TourStep({super.key, required this.index, required this.onNext, required this.onBack});

  /// 0..4.
  final int index;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<TourStep> createState() => _TourStepState();
}

class _TourStepState extends ConsumerState<TourStep> {
  /// Deslizar más de esto (px, estricto) cambia de paso. La velocidad no cuenta, como en la web.
  static const _swipe = 60.0;

  /// «Repetir el ejemplo»: cambia la llave y la ilustración se monta de nuevo desde cero.
  var _run = 0;

  /// Lo que lleva movido el dedo en este arrastre.
  var _drag = 0.0;
  var _dragging = false;

  /// Escena 5: llegó la respuesta de Rinde (Rin asiente).
  var _replied = false;

  void _replay() => setState(() {
    _run++;
    _replied = false;
  });

  void _endDrag() {
    final offset = _drag;
    setState(() {
      _drag = 0;
      _dragging = false;
    });
    if (offset < -_swipe) {
      widget.onNext();
    } else if (offset > _swipe) {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final example = TourExample(ref.watch(appRegionProvider), t);
    final still = MediaQuery.disableAnimationsOf(context);
    final p = context.palette;
    final (title, text, illustration) = _scene(example);
    final last = widget.index == OnboardingSteps.tourLength - 1;

    // Como la web (288-320) en celulares normales; más bajo en pantallas cortas para que el texto no
    // quede lejos. Es un mínimo: si el ejemplo necesita más (texto grande), crece en vez de recortar.
    final stageMin = (MediaQuery.sizeOf(context).height - 440).clamp(216.0, 320.0);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX3),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: stageMin),
                child: Padding(
                  // Arriba quedan 56 para la etiqueta y el botón de repetir.
                  padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 56, RindeSpace.s4, RindeSpace.s6),
                  child: Center(
                    child: KeyedSubtree(key: ValueKey((_run, still)), child: illustration),
                  ),
                ),
              ),
              Positioned(
                left: RindeSpace.s4,
                top: RindeSpace.s4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(RindeRadius.pill)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: RindeSpace.s1),
                    child: Text(
                      t('Ejemplo'),
                      style: RindeType.caption.w(FontWeight.w500).copyWith(color: p.brand),
                    ),
                  ),
                ),
              ),
              if (!still)
                Positioned(
                  right: RindeSpace.s1,
                  top: RindeSpace.s1,
                  child: IconButton(
                    onPressed: _replay,
                    tooltip: t('Repetir el ejemplo'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(RindeSize.tapTarget, RindeSize.tapTarget),
                      foregroundColor: p.brand,
                    ),
                    icon: RindeIcon(RindeIcons.rotateCcw, size: 16, color: p.brand),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: RindeSpace.s6),
        Row(
          children: [
            // Decisión del dueño: Rin acompaña cada paso, pequeño y tranquilo junto al contador.
            SizedBox(
              height: 32,
              child: Rin(compact: true, gesture: last && _replied ? RinGesture.asentir : null),
            ),
            const SizedBox(width: RindeSpace.s2),
            Expanded(
              child: Text(
                t('Cómo funciona · {step} de {total}', {
                  'step': widget.index + 1,
                  'total': OnboardingSteps.tourLength,
                }),
                style: RindeType.small.w(FontWeight.w500).copyWith(color: p.brand),
              ),
            ),
          ],
        ),
        const SizedBox(height: RindeSpace.s1),
        StepTitle(title, subtitle: text),
        if (last) ...[
          const SizedBox(height: RindeSpace.s3),
          // TEXTO NUEVO
          Text(
            t('Se activa por cuenta: pídelo en Cuenta.'),
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
        ],
      ],
    );

    // Sin arrastre con movimiento reducido; Atrás y Siguiente del marco son siempre la alternativa.
    if (still) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      // Cuenta desde el primer contacto, como el offset de framer (si no, se pierde la holgura).
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => setState(() {
        _drag = 0;
        _dragging = true;
      }),
      onHorizontalDragUpdate: (details) => setState(() => _drag += details.delta.dx),
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: () => setState(() {
        _drag = 0;
        _dragging = false;
      }),
      // Sigue al dedo a una quinta parte (dragElastic 0,2) y vuelve a su sitio al soltar.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _drag * 0.2),
        duration: _dragging ? Duration.zero : RindeMotion.rise,
        curve: RindeMotion.out,
        child: content,
        builder: (context, dx, child) => Transform.translate(offset: Offset(dx, 0), child: child),
      ),
    );
  }

  (String, String, Widget) _scene(TourExample example) {
    final t = example.t;
    return switch (widget.index) {
      0 => (
        t('Empieza con tu plata de hoy'),
        t(
          'Dinos cuánta plata tienes hoy (banco, Nequi y efectivo). Desde ahí sumamos y restamos lo que anotes.',
        ),
        BalanceScene(example: example),
      ),
      1 => (
        t('Anota hablando'),
        example.inThousands
            ? t(
                'Di “gasolina 40 mil” o “corte 25 mil” y Rinde lo anota con su categoría. También puedes escribirlo.',
              )
            : t(
                'Di “gasolina 40” o “corte 25” y Rinde lo anota con su categoría. También puedes escribirlo.',
              ),
        VoiceScene(example: example),
      ),
      2 => (
        t('Mi plata te dice cuánto puedes gastar'),
        t(
          'Con tus pagos del mes y el día en que te pagan, te decimos cuánto te alcanza hoy sin quedarte corto.',
        ),
        PlanScene(example: example),
      ),
      3 => (
        t('Vacas con tus amigos'),
        t('Junten plata para un plan, vean quién ya aportó y recuérdenle al que falta.'),
        VacaScene(example: example),
      ),
      _ => (
        t('También por WhatsApp'),
        t('Escríbele a Rinde desde WhatsApp para anotar o preguntar cómo vas, sin abrir la app.'),
        WhatsappScene(
          example: example,
          onReplied: () {
            if (mounted) setState(() => _replied = true);
          },
        ),
      ),
    };
  }
}
