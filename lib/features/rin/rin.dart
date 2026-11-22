import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'rin_motion.dart';
import 'rin_painter.dart';

export 'rin_motion.dart' show RinEmotion, RinGesture;

/// Rin, la mascota de Rinde: una criaturita ovalada y blandita, con la moneda del logo en la antena
/// y una franja alrededor del cuerpo, parada sobre su pila de billetes. Porte de
/// `components/rin/Rin.jsx` + `rin.css` del frontend web.
///
/// Tres capas que no se pisan, como en la web: la postura de la emoción (transición interpolada,
/// interrumpible a medio camino), el gesto en curso y la vida en reposo (respirar, parpadear,
/// mirar y mecer la antena).
///
/// Rin nunca se estira: sube o baja porque su pila gana o pierde billetes.
class Rin extends StatefulWidget {
  const Rin({
    super.key,
    this.emotion = RinEmotion.tranquilo,
    this.gesture,
    this.gestureKey,
    this.level = 0,
    this.tidy = 0,
    this.compact = false,
    this.semanticLabel,
    this.animate = true,
  });

  final RinEmotion emotion;

  /// Al cambiar a un valor no nulo, el gesto se reproduce una vez y Rin vuelve a la postura de su
  /// emoción. Portados: saludar, celebrar, asentir y toque; los demás no hacen nada todavía.
  /// Con movimiento reducido o `animate: false` no hay gestos.
  final RinGesture? gesture;

  /// Para repetir el mismo gesto: cada vez que cambia (por ejemplo, un contador que sube en cada
  /// toque), [gesture] se vuelve a reproducir desde el principio aunque no haya cambiado.
  final Object? gestureKey;

  /// Billetes en la pila, de 0 a 6.
  final int level;

  /// Cuántos billetes ya están acomodados (desde abajo); los demás quedan torcidos.
  final int tidy;

  /// Solo Rin, sin pila (tamaños pequeños).
  final bool compact;

  /// Texto para lector de pantalla; sin él, el dibujo es decorativo.
  final String? semanticLabel;

  /// `false` quita los movimientos: sin reposo ni gestos, la postura cambia de una vez.
  final bool animate;

  @override
  State<Rin> createState() => _RinState();
}

class _RinState extends State<Rin> with TickerProviderStateMixin {
  /// Reloj de la vida en reposo, en segundos.
  final _seconds = ValueNotifier<double>(0);
  late final Ticker _clock = createTicker((elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6);
  late final _pose = AnimationController(vsync: this, duration: RinPose.transition);
  late final _gesture = AnimationController(vsync: this)..addStatusListener(_gestureEnded);
  late final _ticks = Listenable.merge([_seconds, _pose, _gesture]);

  late RinPose _from = _target();
  late RinPose _to = _from;
  RinGesture? _playing;
  bool _still = false;
  bool _started = false;

  RinPose _target() => RinPose.target(
    emotion: widget.emotion,
    gesture: _playing,
    level: widget.compact ? 0 : widget.level,
    tidy: widget.tidy,
  );

  RinPose _current() => RinPose.lerp(_from, _to, _pose.value * RinPose.transition.inMilliseconds);

  /// Movimiento reducido del sistema o `animate: false`: todo quieto y la postura final directa.
  void _syncMotion() {
    _still = !widget.animate || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (_still) {
      _clock.stop();
      _pose.stop();
      _gesture.stop();
      _playing = null;
      _from = _to = _target();
    } else if (!_clock.isActive) {
      _clock.start();
    }
  }

  /// Lleva la postura hacia la nueva meta desde donde esté ahora (como una transición CSS).
  void _retarget() {
    final target = _target();
    if (_still) {
      _from = _to = target;
      return;
    }
    _from = _current();
    _to = target;
    _pose.forward(from: 0);
  }

  void _play(RinGesture? gesture) {
    final duration = gesture?.duration;
    if (duration == null || _still) return;
    _playing = gesture;
    _gesture.duration = duration;
    _gesture.forward(from: 0);
    _retarget();
  }

  void _gestureEnded(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _playing = null;
      _retarget();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
    if (!_started) {
      _started = true;
      _play(widget.gesture);
    }
  }

  @override
  void didUpdateWidget(Rin old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) _syncMotion();
    if (widget.gesture != old.gesture || widget.gestureKey != old.gestureKey) _play(widget.gesture);
    if (widget.emotion != old.emotion ||
        widget.level != old.level ||
        widget.tidy != old.tidy ||
        widget.compact != old.compact) {
      _retarget();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _pose.dispose();
    _gesture.dispose();
    _seconds.dispose();
    super.dispose();
  }

  RinFrame _frame() {
    if (_still) return RinFrame(pose: _to);
    final at = _playing == null ? 0.0 : _gesture.value * _gesture.duration!.inMicroseconds / 1e6;
    return RinFrame.alive(_current(), _seconds.value, widget.emotion, gesture: _playing, at: at);
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.compact ? RinPainter.compactViewBox : RinPainter.viewBox;
    final drawing = AspectRatio(
      aspectRatio: box.width / box.height,
      child: ListenableBuilder(
        listenable: _ticks,
        builder: (context, _) => CustomPaint(
          painter: RinPainter(frame: _frame(), compact: widget.compact),
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: drawing);
    return Semantics(container: true, image: true, label: label, child: drawing);
  }
}
