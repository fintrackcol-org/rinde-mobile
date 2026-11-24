import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_checkbox.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/account_writer.dart';
import 'account_sheet.dart';

/// DeleteAccount.jsx (FT-0017, exigido por Google Play y App Store): explica qué se borra, pide marcar
/// que se entiende que no se puede deshacer y confirmar con la contraseña. Al terminar sale de la
/// cuenta, no deja nada de ella en el teléfono y el login avisa que se eliminó.
///
/// La web también confirma con Google; en la app el ingreso con Google aún no existe, así que quien
/// está dentro entró con contraseña. La contraseña solo vive en este campo: no se guarda.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({super.key});

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  final _password = TextEditingController();
  bool _understood = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _understood && !_busy && _password.text.isNotEmpty;

  Future<void> _confirm() async {
    if (!_ready) return;
    final t = ref.read(trProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Sin sesión, el router lleva al login, que avisa que la cuenta se eliminó.
      await ref.read(accountWriterProvider).deleteAccount(_password.text);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = moneyErrorText(e, t);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final bullets = [
      t('Tus movimientos, presupuestos, tarjetas, soportes y Mi plata.'),
      t('Tus ajustes, recordatorios y la conexión con WhatsApp.'),
      t('Las vacas y negocios donde estás solo.'),
    ];
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Se borra para siempre:'), style: RindeType.label.copyWith(color: p.ink)),
          const SizedBox(height: RindeSpace.s2),
          for (final line in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: RindeSpace.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SheetNote('•', tone: p.ink.withValues(alpha: 0.7)),
                  const SizedBox(width: RindeSpace.s2),
                  Expanded(child: SheetNote(line, tone: p.ink.withValues(alpha: 0.7))),
                ],
              ),
            ),
          const SizedBox(height: RindeSpace.s1),
          SheetNote(
            t(
              'En las vacas y negocios compartidos, tus aportes quedan sin tu nombre para que las cuentas del grupo sigan cuadrando, y otro miembro pasa a administrarlos.',
            ),
          ),
          const SizedBox(height: RindeSpace.s5),
          DecoratedBox(
            decoration: BoxDecoration(
              color: RindeBrand.destructive.withValues(alpha: 0.1),
              borderRadius: RindeRadius.brXl,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3),
              child: RindeCheckboxField(
                semanticLabel: t('Entiendo que mi cuenta y mis datos se borran y no se pueden recuperar.'),
                label: Text(
                  t('Entiendo que mi cuenta y mis datos se borran y no se pueden recuperar.'),
                  style: RindeType.small.copyWith(color: p.ink),
                ),
                onChanged: _busy ? null : (value) => setState(() => _understood = value),
              ),
            ),
          ),
          const SizedBox(height: RindeSpace.s5),
          RindePasswordField(
            label: t('Escribe tu contraseña para confirmar'),
            showLabel: t('Mostrar contraseña'),
            hideLabel: t('Ocultar contraseña'),
            controller: _password,
            serverError: _error,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: RindeSpace.s3),
          _DangerButton(
            label: t('Eliminar mi cuenta para siempre'),
            busyLabel: t('Eliminando…'),
            busy: _busy,
            onPressed: _ready ? _confirm : null,
          ),
          if (_error case final error?) ...[
            const SizedBox(height: RindeSpace.s3),
            RindeBanner(message: error),
          ],
        ],
      ),
    );
  }
}

/// Botón rojo (bg-destructive): blanco sobre el rojo oscuro en los dos temas, por contraste.
class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: p.negativeSolid,
        foregroundColor: RindeBrand.white,
        disabledBackgroundColor: p.negativeSolid.withValues(alpha: 0.4),
        disabledForegroundColor: RindeBrand.white.withValues(alpha: 0.8),
        minimumSize: const Size.fromHeight(RindeSize.buttonLg),
        shape: const RoundedRectangleBorder(borderRadius: RindeRadius.brXl),
        textStyle: RindeType.bodyMedium,
      ),
      child: Text(busy ? busyLabel : label),
    );
  }
}
