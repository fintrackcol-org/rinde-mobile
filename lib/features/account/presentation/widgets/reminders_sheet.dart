import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../auth/application/session_controller.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/account_providers.dart';
import '../../application/account_writer.dart';
import 'account_sheet.dart';

/// NotificationSettings.jsx, solo lo que el servidor guarda y cumple sin la app: «Pago de tarjetas»
/// (el aviso queda en la bandeja de avisos y llega por las notificaciones de la web).
///
/// Se ocultan, porque solo llegan por notificación push y la app no tiene push: «Notificaciones en este
/// dispositivo» (permiso del navegador) y «Recordatorios diarios» (el servidor los omite si la cuenta
/// no tiene un dispositivo suscrito). Las horas guardadas se conservan al cambiar el aviso de tarjetas.
class RemindersSheet extends ConsumerStatefulWidget {
  const RemindersSheet({super.key});

  @override
  ConsumerState<RemindersSheet> createState() => _RemindersSheetState();
}

class _RemindersSheetState extends ConsumerState<RemindersSheet> {
  bool _saving = false;

  /// Lo que devolvió el último guardado, mientras la lista se vuelve a pedir.
  bool? _saved;
  String? _error;

  Future<void> _toggle(bool on) async {
    final t = ref.read(trProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(accountWriterProvider).setCardReminders(on);
      if (mounted) setState(() => _saved = saved.cardReminders);
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final settings = ref.watch(reminderSettingsProvider(ref.watch(accountProvider)));
    final value = settings.isLoading
        ? _saved ?? settings.value?.cardReminders
        : settings.value?.cardReminders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Pago de tarjetas'), style: RindeType.bodyMedium.copyWith(color: p.ink)),
        const SizedBox(height: RindeSpace.s2),
        if (settings.hasError && !settings.isLoading)
          RindeBanner(
            message: moneyErrorText(settings.error!, t),
            action: RindeButton(
              label: t('Reintentar'),
              variant: RindeButtonVariant.outline,
              size: RindeButtonSize.sm,
              expand: false,
              onPressed: () => ref.invalidate(reminderSettingsProvider),
            ),
          )
        else
          MergeSemantics(
            child: Row(
              children: [
                Expanded(child: SheetNote(t('Te avisamos 3 días antes del día de pago de cada tarjeta.'))),
                const SizedBox(width: RindeSpace.s4),
                Switch(
                  value: value ?? false,
                  activeTrackColor: p.brandSolid,
                  onChanged: value == null || _saving ? null : _toggle,
                ),
              ],
            ),
          ),
        if (value == null && !settings.hasError) ...[
          const SizedBox(height: RindeSpace.s2),
          SheetNote(t('Cargando…')),
        ],
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s3), RindeBanner(message: error)],
      ],
    );
  }
}
