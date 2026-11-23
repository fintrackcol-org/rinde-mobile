import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/commitments.dart';
import '../../domain/onboarding_flow.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../payments/payment_widgets.dart';
import '../widgets/onboarding_shell.dart';

/// Posición 9: pagos de cada mes (Welcome.jsx, PAYMENTS). Las pastillas agregan o quitan sugerencias,
/// «Otro» agrega uno con nombre editable. Todo vive en el borrador del controlador; el botón
/// «Ver mi plata» y el error los pone la pantalla anfitriona.
class PaymentsStep extends ConsumerStatefulWidget {
  const PaymentsStep({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  ConsumerState<PaymentsStep> createState() => _PaymentsStepState();
}

class _PaymentsStepState extends ConsumerState<PaymentsStep> {
  final _cards = <String, GlobalKey<PaymentCardState>>{};

  OnboardingController get _controller => ref.read(onboardingControllerProvider(widget.mode).notifier);

  void _toggle(String name, {required bool selected}) {
    _controller.toggleSuggestion(name);
  }

  void _addCustom() {
    final key = _controller.addCustom();
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _cards[key]?.currentState?.focusName());
  }

  /// Marcada si hay un pago sugerido con ese nombre (los de «Otro» no cuentan, como en el controlador).
  Widget _suggestion(String name, List<CommitmentItem> items, {required bool atLimit}) {
    final selected = items.any((i) => !i.custom && i.name == name);
    return PaymentPill(
      label: name,
      selected: selected,
      onTap: atLimit && !selected ? null : () => _toggle(name, selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = onboardingControllerProvider(widget.mode);
    final state = ref.watch(provider);
    final t = ref.watch(trProvider);
    final p = context.palette;
    // Los montos van con los separadores de la moneda de la cuenta (como getRegion() en la web).
    final format = formatFor(ref.watch(appRegionProvider));
    final items = state.draft.items;
    final atLimit = items.length >= maxCommitments;

    // Cada intento fallido de «Ver mi plata» trae un error nuevo: el pago con el problema se lleva a la vista.
    ref.listen(provider.select((s) => s.error), (_, error) {
      final key = ref.read(provider).errorItemKey;
      if (error == null || key == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _cards[key]?.currentState?.reveal());
    });
    _cards.removeWhere((key, _) => !items.any((i) => i.key == key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(t('¿Qué pagas cada mes?')),
        const SizedBox(height: RindeSpace.s3),
        RinNote(text: t('Apartamos esa plata antes de decirte cuánto puedes gastar. Toca los que tengas.')),
        if (state.paymentsLocked) ...[
          const SizedBox(height: RindeSpace.s3),
          // TEXTO NUEVO: la etapa 1 ya salió; el servidor no pisa ni borra pagos con el mismo nombre.
          Semantics(
            liveRegion: true,
            child: Text(
              state.paymentsSaved
                  ? t('Tus pagos ya quedaron guardados. Si quieres cambiarlos, hazlo luego en Mi plata.')
                  : t(
                      'No sabemos si tus pagos alcanzaron a guardarse. «Ver mi plata» los envía otra vez. Si ya los cambiaste en la web, toca «Omitir» para no repetirlos.',
                    ),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
        ],
        const SizedBox(height: RindeSpace.s5),
        ExcludeFocus(
          excluding: state.paymentsLocked,
          child: IgnorePointer(
            ignoring: state.paymentsLocked,
            // Atenuado: se ve qué quedó guardado, pero no parece editable.
            child: Opacity(
              opacity: state.paymentsLocked ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _editable(state, t, p, format, items, atLimit),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _editable(
    OnboardingState state,
    Tr t,
    RindePalette p,
    MoneyFormat format,
    List<CommitmentItem> items,
    bool atLimit,
  ) {
    return [
      Semantics(
        container: true,
        label: t('Pagos frecuentes'),
        child: Wrap(
          spacing: RindeSpace.s2,
          runSpacing: RindeSpace.s1,
          children: [
            // El nombre que se guarda es el traducido (como la web).
            for (final name in suggestedCommitments.map(t.call)) _suggestion(name, items, atLimit: atLimit),
            PaymentPill(
              label: t('Otro'),
              dashed: true,
              leading: RindeIcon(RindeIcons.plus, size: 16, color: p.ink.withValues(alpha: 0.7)),
              onTap: atLimit ? null : _addCustom,
            ),
          ],
        ),
      ),
      if (atLimit) ...[
        const SizedBox(height: RindeSpace.s2),
        // TEXTO NUEVO: la web no pone tope y el servidor responde 422 con más de 30.
        Text(
          t('Llegaste al tope de {max} pagos. Quita uno para agregar otro.', {'max': maxCommitments}),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
      ],
      if (items.isNotEmpty) const SizedBox(height: RindeSpace.s5),
      for (final (i, item) in items.indexed) ...[
        if (i > 0) const SizedBox(height: RindeSpace.s3),
        PaymentCard(
          key: _cards.putIfAbsent(item.key, GlobalKey<PaymentCardState>.new),
          item: item,
          format: format,
          highlighted: state.errorItemKey == item.key,
          onChanged: ({name, amount, dayOfMonth}) =>
              _controller.updateItem(item.key, name: name, amount: amount, dayOfMonth: dayOfMonth),
          onRemove: () => _controller.removeItem(item.key),
        ),
      ],
    ];
  }
}
