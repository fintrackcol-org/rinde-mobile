import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_text_field.dart';
import '../application/session_controller.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/auth_switch.dart';
import 'widgets/google_section.dart';

/// Iniciar sesión (pages/auth/Login.jsx).
///
/// Sin "Recordarme 30 días": en la web no se envía ni cambia nada, y en el celular la sesión
/// siempre queda guardada en el almacenamiento seguro hasta cerrar sesión o que venza.
/// Al entrar no navega: el router ve la sesión nueva y lleva a /app.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  /// Correo precargado (`?correo=`, viene del registro).
  final String? initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _resendSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();

  bool _submitted = false;
  bool _loading = false;

  /// Clave en español o mensaje del servidor; se traduce al mostrarlo (igual [_resendNotice]).
  String? _error;

  /// Correo con el que el servidor respondió EMAIL_NOT_VERIFIED; con valor se ofrece reenviar.
  String? _unverifiedEmail;
  bool _resending = false;
  String? _resendNotice;
  bool _resendFailed = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
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
      _unverifiedEmail = null;
      _resendNotice = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signIn(email: email, password: _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.messageFor(
          byCode: const {
            ApiCodes.unauthorized: 'Correo o contraseña incorrectos.',
            ApiCodes.emailNotVerified: 'Confirma tu correo para entrar: abre el enlace que te enviamos.',
          },
          fallback: 'No pudimos iniciar sesión. Inténtalo de nuevo.',
        );
        if (e.code == ApiCodes.emailNotVerified) _unverifiedEmail = email;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos iniciar sesión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Reenvío con spinner y 60 s de espera tras enviar: el límite del servidor (20 cada 15 min)
  /// es compartido, y la web deja tocarlo sin pausa (flujo.md §7.7).
  Future<void> _resend() async {
    final email = _unverifiedEmail;
    if (email == null || _resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _resendNotice = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerification(email);
      if (!mounted) return;
      setState(() {
        _resendFailed = false;
        _resendNotice = 'Te enviamos un enlace nuevo. Revisa tu correo.';
      });
      _startCooldown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resendFailed = true;
        _resendNotice = e.messageFor(fallback: 'No pudimos enviar el enlace. Inténtalo de nuevo.');
      });
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) t.cancel();
      setState(() => _cooldown -= 1);
    });
  }

  void _openForgot() {
    final email = AuthValidators.normalizeEmail(_email.text);
    context.push(
      Uri(path: Routes.forgot, queryParameters: email.isEmpty ? null : {'correo': email}).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final expired = ref.watch(sessionControllerProvider).value?.expired ?? false;
    final muted = RindeBrand.white.withValues(alpha: 0.55);
    final clock = '${_cooldown ~/ 60}:${(_cooldown % 60).toString().padLeft(2, '0')}';

    return AuthScaffold(
      mode: AuthMode.login,
      title: t('Inicia sesión en tu cuenta'),
      subtitle: t('Ingresa tus datos para continuar con tus finanzas.'),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(t('¿Primera vez en Rinde?'), style: RindeType.small.copyWith(color: muted)),
          const SizedBox(width: RindeSpace.s1),
          RindeTextLink(
            label: t('Crea tu cuenta gratis'),
            onPressed: () => context.pushReplacement(Routes.register),
          ),
        ],
      ),
      children: [
        // La web no explica por qué volvió al login; aquí sí, si venció la sesión.
        if (expired && _error == null) ...[
          RindeBanner(message: t(ApiMessages.sessionExpired), tone: RindeBannerTone.neutral),
          const SizedBox(height: RindeSpace.s6),
        ],
        Form(
          key: _formKey,
          autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RindeTextField(
                  label: t('Correo electrónico'),
                  hint: t('tu@correo.com'),
                  controller: _email,
                  validator: (v) => t.maybe(AuthValidators.email(v)),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                ),
                const SizedBox(height: RindeSpace.s4),
                RindePasswordField(
                  label: t('Contraseña'),
                  hint: t('Tu contraseña'),
                  showLabel: t('Mostrar contraseña'),
                  hideLabel: t('Ocultar contraseña'),
                  controller: _password,
                  validator: (v) => t.maybe(AuthValidators.loginPassword(v)),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: RindeTextLink(
                    label: t('¿Olvidaste tu contraseña?'),
                    color: RindeBrand.white.withValues(alpha: 0.6),
                    style: RindeType.small,
                    onPressed: _openForgot,
                  ),
                ),
                const SizedBox(height: RindeSpace.s4),
                if (_error != null) ...[
                  RindeBanner(
                    message: t(_error!),
                    action: _unverifiedEmail == null
                        ? null
                        : RindeButton(
                            label: _cooldown > 0 ? '${t('Reenviar enlace en')} $clock' : t('Reenviar enlace'),
                            variant: RindeButtonVariant.outline,
                            expand: false,
                            loading: _resending,
                            onPressed: _cooldown > 0 ? null : _resend,
                          ),
                  ),
                  const SizedBox(height: RindeSpace.s4),
                ],
                if (_resendNotice != null) ...[
                  RindeBanner(
                    message: t(_resendNotice!),
                    tone: _resendFailed ? RindeBannerTone.error : RindeBannerTone.success,
                  ),
                  const SizedBox(height: RindeSpace.s4),
                ],
                RindeButton(
                  label: t('Iniciar sesión'),
                  loadingLabel: t('Ingresando…'),
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s8),
        const GoogleSection(mode: AuthMode.login),
      ],
    );
  }
}
