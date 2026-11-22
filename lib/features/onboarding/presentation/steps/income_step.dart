import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../rin/rin.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/income_sources.dart';
import '../../domain/onboarding_flow.dart';
import '../income/income_source_tile.dart';
import '../widgets/onboarding_shell.dart';

/// Posición 7: ¿Cómo te entra la plata? (Welcome.jsx:250-256 + components/money/IncomeSourcesFields.jsx).
/// Varias fuentes a la vez, todo opcional: «Seguir» siempre avanza. Las respuestas viven en el borrador
/// del controlador; esta pantalla solo las dibuja.
///
/// Los montos usan el formato de la región ya guardada (appRegionProvider), igual que MoneyInput de la
/// web (regionFormats()): en «Solo las preguntas» no se pasa por País, y si se omitió País la región del
/// borrador nunca llegó al servidor.
class IncomeStep extends ConsumerStatefulWidget {
  const IncomeStep({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  ConsumerState<IncomeStep> createState() => _IncomeStepState();
}

class _IncomeStepState extends ConsumerState<IncomeStep> {
  /// Rin asiente y se alegra un momento cada vez que se marca una fuente.
  int _nods = 0;
  bool _happy = false;
  Timer? _calm;

  void _react() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _calm?.cancel();
    setState(() {
      _nods++;
      _happy = true;
    });
    _calm = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _happy = false);
    });
  }

  @override
  void dispose() {
    _calm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = onboardingControllerProvider(widget.mode);
    final sources = ref.watch(provider.select((s) => s.draft.sources));
    final controller = ref.read(provider.notifier);
    final format = formatFor(ref.watch(appRegionProvider));
    final t = ref.watch(trProvider);
    final p = context.palette;
    ref.listen(provider.select((s) => s.draft.sources.length), (before, now) {
      if (before != null && now > before) _react();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(t('¿Cómo te entra la plata?')),
        const SizedBox(height: RindeSpace.s5),
        Semantics(
          container: true,
          label: t('Cómo te entra la plata (puedes elegir varias)'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Elige todas las que apliquen. Los montos son aproximados: más o menos está bien.'),
                style: RindeType.body.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s3),
              Material(
                color: p.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: RindeRadius.brX3,
                  side: BorderSide(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final kind in IncomeKind.values) ...[
                      if (kind.index > 0)
                        Divider(height: 1, thickness: 1, color: p.ink.withValues(alpha: 0.08)),
                      IncomeSourceTile(
                        kind: kind,
                        form: sources[kind],
                        format: format,
                        t: t,
                        onToggle: () => controller.toggleSource(kind),
                        onChanged: controller.updateSource,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: RindeSpace.s5),
        RinNote(
          rin: Rin(
            compact: true,
            emotion: _happy ? RinEmotion.feliz : RinEmotion.tranquilo,
            gesture: _nods > 0 ? RinGesture.asentir : null,
            gestureKey: _nods,
          ),
          text: t(
            'Con esto sé cuándo te entra plata y te aviso antes de que quedes corto. Es para planear: no se anota como ingreso.',
          ),
        ),
      ],
    );
  }
}
