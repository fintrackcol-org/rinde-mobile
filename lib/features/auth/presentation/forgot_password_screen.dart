import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_text_field.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/check_inbox.dart';

/// Recuperar contraseña (pages/auth/ForgotPassword.jsx): formulario del correo y, al enviarlo,
/// "Revisa tu correo". La API responde igual exista o no la cuenta, así que tampoco lo afirma.
///
/// El enlace del correo abre Rinde Web (/restablecer), donde se crea la contraseña nueva.
/// Restablecerla dentro de la app requiere App Links / Universal Links (bloqueado por ahora).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  /// Correo precargado (`?correo=`, viene del login).
  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');

  bool _submitted = false;
  bool _loading = false;
  String? _error;

  /// Correo al que se pidió el enlace; con valor se muestra "Revisa tu correo".
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final email = AuthValidators.normalizeEmail(_email.text);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).forgotPassword(email);
      if (mounted) setState(() => _sentTo = email);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.messageFor(fallback: 'No pudimos enviar el enlace. Inténtalo de nuevo.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _backToLogin() => context.canPop() ? context.pop() : context.go(Routes.login);

  @override
  Widget build(BuildContext context) {
    final footer = Center(
      child: RindeTextLink(label: 'Volver a iniciar sesión', onPressed: _backToLogin),
    );
    final sentTo = _sentTo;
    if (sentTo != null) return _sent(sentTo, footer);

    return AuthScaffold(
      icon: RindeIcons.mail,
      title: 'Recupera tu contraseña',
      subtitle: 'Escribe tu correo y te enviamos un enlace para crear una nueva.',
      footer: footer,
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RindeTextField(
                label: 'Correo electrónico',
                hint: 'tu@correo.com',
                controller: _email,
                validator: AuthValidators.email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: RindeSpace.s6),
              if (_error != null) ...[RindeBanner(message: _error!), const SizedBox(height: RindeSpace.s6)],
              RindeButton(
                label: 'Enviar enlace',
                loadingLabel: 'Enviando…',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sent(String sentTo, Widget footer) {
    final muted = RindeBrand.white.withValues(alpha: 0.55);
    return AuthScaffold(
      icon: RindeIcons.mailCheck,
      title: 'Revisa tu correo',
      footer: footer,
      // Subtítulo con el correo en negrita; al lector se le anuncia la frase de la web (sr-only).
      subtitleWidget: Semantics(
        liveRegion: true,
        label: 'Te enviamos un enlace a $sentTo si tiene una cuenta.',
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Si '),
              TextSpan(
                text: sentTo,
                style: RindeType.small.w(FontWeight.w500).copyWith(color: RindeBrand.white),
              ),
              const TextSpan(
                text: ' tiene una cuenta, te llegará un enlace para crear una contraseña nueva.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: RindeType.small.copyWith(color: muted),
        ),
      ),
      children: [
        CheckInbox(
          tips: const [
            'El enlace vence en 30 minutos y sirve una sola vez.',
            '¿No lo ves? Revisa las carpetas de spam o promociones.',
          ],
          onResend: () => ref.read(authRepositoryProvider).forgotPassword(sentTo),
          onUseOtherEmail: () => setState(() => _sentTo = null),
        ),
      ],
    );
  }
}
