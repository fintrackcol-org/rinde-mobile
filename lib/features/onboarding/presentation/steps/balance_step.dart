import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/money_text.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../rin/rin.dart';
import '../../application/onboarding_controller.dart';
import '../../data/onboarding_repository.dart';
import '../../domain/onboarding_flow.dart';
import '../widgets/onboarding_shell.dart';

/// Posición 8: saldo (Welcome.jsx, BALANCE). Lo escrito va crudo al borrador del controlador;
/// vacío = no lo dijo (se envía null, no 0).
class BalanceStep extends ConsumerWidget {
  const BalanceStep({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider(mode));
    final controller = ref.read(onboardingControllerProvider(mode).notifier);
    final t = ref.watch(trProvider);
    final p = context.palette;
    // La región guardada, como getRegion() en la web: si se omitió País o la moneda quedó bloqueada,
    // el borrador dice otro país pero la plata sigue en la moneda de la cuenta.
    final region = ref.watch(appRegionProvider);
    final format = formatFor(region);
    final balance = state.draft.balance;

    final hint = describeAmount(
      balance,
      inPesos: region.currency == 'COP',
      decimal: format.decimal,
      translate: (text, [vars = const {}]) => t(text, vars),
    );
    final message = hint == null
        ? null
        : t(hint.text, {
            ...hint.vars,
            if (hint.vars['unit'] == ' de pesos') 'unit': t(' de pesos'),
            if (hint.vars.containsKey('MAX_AMOUNT')) 'MAX_AMOUNT': format.money(maxAmount),
          });

    // MODO DEMOSTRACIÓN: la propuesta sale de totales sintéticos, no de la persona. Se marca mientras
    // el campo tenga exactamente ese valor (si lo escribe igual, sigue marcado: no se distingue).
    final proposal = state.isDemo ? ref.watch(welcomeStatusProvider).value?.balanceProposal : null;
    final demoValue = proposal != null && balance.isNotEmpty && balance == '$proposal';
    // TEXTO NUEVO (solo demostración, sin traducir como la etiqueta DEMO).
    const demoLabel = 'Dato de demostración';
    final label = t('Total aproximado');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(t('¿Cuánta plata tienes hoy, más o menos?')),
        const SizedBox(height: RindeSpace.s3),
        RinNote(
          rin: const Rin(compact: true, emotion: RinEmotion.pensativo),
          text: t('Desde ese número sumamos y restamos lo que anotes: así tu saldo es el de verdad.'),
        ),
        const SizedBox(height: RindeSpace.s5),
        ExcludeSemantics(
          child: Wrap(
            spacing: RindeSpace.s2,
            runSpacing: RindeSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: RindeType.label.copyWith(color: p.inkLabel)),
              if (demoValue)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.caution.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(RindeRadius.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s2, vertical: 2),
                    child: Text(
                      demoLabel,
                      style: RindeType.caption.w(FontWeight.w600).copyWith(color: p.caution),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeMoneyField(
          value: balance,
          onChanged: controller.setBalance,
          format: format,
          semanticLabel: demoValue ? '$label. $demoLabel' : label,
          autofocus: true,
          textInputAction: TextInputAction.done,
          message: message,
          messageTone: hint?.tone ?? RindeMoneyMessageTone.info,
          helper: t(
            'Suma banco, Nequi y efectivo. No tiene que ser exacto y lo puedes corregir cuando quieras.',
          ),
        ),
      ],
    );
  }
}
