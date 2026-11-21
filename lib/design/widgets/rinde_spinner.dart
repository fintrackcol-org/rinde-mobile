import 'package:flutter/widgets.dart';

import 'rinde_icon.dart';

/// Spinner de Rinde Web: el ícono loader-circle girando. Con movimiento reducido queda quieto.
class RindeSpinner extends StatefulWidget {
  const RindeSpinner({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  @override
  State<RindeSpinner> createState() => _RindeSpinnerState();
}

class _RindeSpinnerState extends State<RindeSpinner> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: RindeIcon(RindeIcons.loader, size: widget.size, color: widget.color),
  );
}
