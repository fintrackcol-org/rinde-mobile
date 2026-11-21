import 'package:flutter/widgets.dart';

import '../tokens/rinde_layout.dart';

/// Entrada `fade-up` / `rise` de Rinde Web: aparece subiendo unos píxeles.
/// Con movimiento reducido se muestra directo.
class RindeFadeUp extends StatelessWidget {
  const RindeFadeUp({
    super.key,
    required this.child,
    this.offset = 24,
    this.duration = RindeMotion.fadeUp,
    this.delay = Duration.zero,
  });

  final Widget child;
  final double offset;
  final Duration duration;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final total = duration + delay;
    final start = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: RindeMotion.out),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * offset), child: child),
      ),
    );
  }
}
