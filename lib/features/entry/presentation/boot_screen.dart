import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/widgets/rinde_logo.dart';

/// Lo que se ve mientras se lee la sesión guardada (normalmente un instante).
/// Negro con el isotipo, igual que el fondo de arranque de Rinde Web y del sistema.
class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: RindeBrand.black,
    child: Center(
      child: Semantics(label: ref.watch(trProvider)('Rinde, cargando'), child: const RindeLogoMark(size: 56)),
    ),
  );
}
