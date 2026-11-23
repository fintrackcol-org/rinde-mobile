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
import '../../../auth/application/session_controller.dart';

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

    final hint = describeAmount(balance, format: format, inPesos: region.currency == 'COP', t: t);

    // MODO DEMOSTRACIÓN: la propuesta sale de totales sintéticos, no de la persona. Se marca mientras
    // el campo tenga exactamente ese valor (si lo escribe igual, sigue marcado: no se distingue).
    final proposal = state.isDemo
        ? ref.watch(welcomeStatusProvider(ref.watch(accountProvider))).value?.balanceProposal
        : null;
    final demoValue = proposal != null && balance.isNotEmpty && balance == '$proposal';
    // TEXTO NUEVO (solo demostración, sin traducir como la etiqueta DEMO).
    const demoLabel = 'Dato de demostración';
    final label = t('Total aproximado');
    // Al retomar un envío: si el servidor tiene otro saldo, que se vea antes de pisarlo.
    final saved = state.draft.sentWelcome == null
        ? null
        : ref.watch(welcomeStatusProvider(ref.watch(accountProvider))).value?.balance;
    final savedOther = saved != null && saved != moneyValue(balance) ? saved : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(t('¿Cuánta plata tienes hoy, más o menos?')),
        const SizedBox(height: RindeSpace.s3),
        RinNote(
          rin: const Rin(compact: true, emotion: RinEmotion.pensativo),
          text: t('Desde ese número sumamos y restamos lo que anotes: así tu saldo es el de verdad.'),
        ),
        if (savedOther != null) ...[
          const SizedBox(height: RindeSpace.s3),
          Semantics(
            liveRegion: true,
            child: Text(
              t(
                'Rinde tiene guardado {amount}. «Omitir» lo deja así; «Seguir» lo cambia por lo que escribas.',
                {'amount': format.money(savedOther)},
              ),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
        ],
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
          message: hint?.message,
          messageTone: hint?.tone ?? RindeMoneyMessageTone.info,
          helper: t(
            'Suma banco, Nequi y efectivo. No tiene que ser exacto y lo puedes corregir cuando quieras.',
          ),
        ),
      ],
    );
  }
}
