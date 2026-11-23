import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../rin/rin.dart';
import '../../../rin/rin_motion.dart' show RinPose;
import 'home_tap.dart';

/// Estado vacío del Inicio (dashboard/DashboardEmpty.jsx): quien aún no anota nada ve una sola acción
/// clara. En vez de la «r» de la web saluda Rin, una vez por sesión de la app; es su única aparición
/// en el Inicio.
class HomeEmpty extends ConsumerWidget {
  const HomeEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return HomeSurface(
      radius: RindeRadius.brX3,
      padding: const EdgeInsets.all(RindeSpace.s6),
      child: Column(
        children: [
          const _GreetingRin(),
          const SizedBox(height: RindeSpace.s5),
          Semantics(
            header: true,
            child: Text(
              t('Todavía no has anotado nada este mes'),
              textAlign: TextAlign.center,
              style: RindeType.title.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: RindeSpace.s2),
          Text(
            t(
              'Empieza con lo que gastaste hoy, aunque sea un tinto. Pon cuánto fue y en qué, y Rinde lo organiza.',
            ),
            textAlign: TextAlign.center,
            style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: RindeSpace.s6),
          RindeButton(
            label: t('Anotar mi primer gasto'),
            pill: true,
            expand: false,
            leading: const RindeIcon(RindeIcons.plus, size: 16, color: RindeBrand.white),
            onPressed: () => context.push(Routes.recordExpense),
          ),
          const SizedBox(height: RindeSpace.s2),
          HomeLink(label: t('O anota lo que te entró'), onTap: () => context.push(Routes.recordIncome)),
          HomeLink(
            label: t('O conecta WhatsApp y anota desde el chat'),
            onTap: () => context.push(Routes.account),
          ),
        ],
      ),
    );
  }
}

/// Si Rin ya saludó. Vive lo que la app abierta, no lo que la pestaña ni la tarjeta.
final _greetedProvider = Provider((ref) => _Greeted());

class _Greeted {
  bool value = false;
}

/// Rin saluda la primera vez y luego se queda quieto: en reposo pediría un cuadro tras otro sin parar.
class _GreetingRin extends ConsumerStatefulWidget {
  const _GreetingRin();

  @override
  ConsumerState<_GreetingRin> createState() => _GreetingRinState();
}

class _GreetingRinState extends ConsumerState<_GreetingRin> {
  late bool _moving;
  Timer? _rest;

  @override
  void initState() {
    super.initState();
    final greeted = ref.read(_greetedProvider);
    _moving = !greeted.value;
    greeted.value = true;
    if (!_moving) return;
    // Lo que dura el saludo más lo que tarda en bajar el brazo.
    _rest = Timer(RinGesture.saludar.duration! + RinPose.transition, () => setState(() => _moving = false));
  }

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }

  // Decorativo: sin etiqueta. Con movimiento reducido Rin queda quieto (lo resuelve él). `compact`:
  // sin billetes la pila no dibuja nada y dejaba un hueco encima de él.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      height: 96,
      child: Rin(compact: true, gesture: RinGesture.saludar, animate: _moving),
    ),
  );
}
