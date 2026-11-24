import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/account_writer.dart';
import '../account_screen.dart' show ProfileInitial, accountName, displayName;
import 'account_sheet.dart';

/// Largo máximo del nombre (MAX_NAME_LENGTH de userService.js, igual que `usuarios.nombre`).
const maxNameLength = 60;

/// ProfileCard.jsx: inicial, nombre y correo; el nombre se edita aquí (PATCH /users/me).
class ProfileSheet extends ConsumerStatefulWidget {
  const ProfileSheet({super.key});

  @override
  ConsumerState<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<ProfileSheet> {
  final _draft = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _start(String? name) => setState(() {
    _draft.text = name ?? '';
    _error = null;
    _notice = null;
    _editing = true;
  });

  Future<void> _save() async {
    final t = ref.read(trProvider);
    final clean = _draft.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length > maxNameLength) {
      setState(() => _error = t('Máximo {MAX_NAME_LENGTH} caracteres.', {'MAX_NAME_LENGTH': maxNameLength}));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(accountWriterProvider).saveName(clean.isEmpty ? null : clean);
      if (!mounted) return;
      setState(() {
        _notice = saved != null ? t('Nombre guardado.') : t('Nombre borrado.');
        _editing = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fields['name'] ?? moneyErrorText(e, t));
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
    final account = ref.watch(accountProvider);
    final name = accountName(ref);
    final email = account?.user.email ?? '';
    final shown = displayName(name, email);

    return PopScope(
      canPop: !_saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfileInitial(name: shown, email: email),
              const SizedBox(width: RindeSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown.isEmpty ? t('Tu cuenta') : shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RindeType.title.copyWith(color: p.ink),
                    ),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RindeType.body.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_editing) ...[
            const SizedBox(height: RindeSpace.s4),
            if (name == null) ...[
              SheetNote(
                t('Agrega tu nombre para que te saludemos por él. Por ahora usamos el de tu correo.'),
              ),
              const SizedBox(height: RindeSpace.s4),
            ],
            RindeButton(
              label: name != null ? t('Editar nombre') : t('Agregar nombre'),
              variant: RindeButtonVariant.outline,
              onPressed: () => _start(name),
            ),
          ] else ...[
            const SizedBox(height: RindeSpace.s5),
            RindeTextField(
              label: t('Tu nombre'),
              hint: t('Felipe'),
              controller: _draft,
              maxLength: maxNameLength,
              autofocus: true,
              enabled: !_saving,
              autofillHints: const [AutofillHints.givenName],
              textCapitalization: TextCapitalization.words,
              serverError: _error,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: RindeSpace.s3),
            RindeButton(
              label: t('Guardar nombre'),
              loading: _saving,
              loadingLabel: t('Guardando…'),
              onPressed: _save,
            ),
            const SizedBox(height: RindeSpace.s2),
            RindeButton(
              label: t('Cancelar'),
              variant: RindeButtonVariant.outline,
              onPressed: _saving ? null : () => setState(() => _editing = false),
            ),
          ],
          if (_notice case final notice?) ...[
            const SizedBox(height: RindeSpace.s3),
            RindeBanner(message: notice, tone: RindeBannerTone.success),
          ],
        ],
      ),
    );
  }
}
