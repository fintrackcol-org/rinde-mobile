import 'package:flutter/widgets.dart';

/// Bloque que late mientras carga un dato (`animate-pulse` sobre `bg-current opacity-20` de la web):
/// toma el color del texto de alrededor y va de 20 % a 50 %. Con movimiento reducido queda quieto.
/// Es decorativo: quien lo usa anuncia «Cargando…» con su propio Semantics.
class RindeSkeleton extends StatefulWidget {
  const RindeSkeleton({super.key, required this.width, required this.height, this.radius = 6});

  final double width;
  final double height;
  final double radius;

  @override
  State<RindeSkeleton> createState() => _RindeSkeletonState();
}

class _RindeSkeletonState extends State<RindeSkeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  late final _opacity = Tween(
    begin: 0.2,
    end: 0.5,
  ).animate(CurvedAnimation(parent: _controller, curve: const Cubic(0.4, 0, 0.6, 1)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: DefaultTextStyle.of(context).style.color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    ),
  );
}
