import 'package:material_ui/material_ui.dart';

import '../../../design/tokens/rinde_colors.dart';
import '../../../design/widgets/rinde_logo.dart';

/// Lo que se ve mientras se lee la sesión guardada (normalmente un instante).
/// Negro con el isotipo, igual que el fondo de arranque de Rinde Web y del sistema.
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: RindeBrand.black,
    child: Center(
      child: Semantics(label: 'Rinde, cargando', child: const RindeLogoMark(size: 56)),
    ),
  );
}
