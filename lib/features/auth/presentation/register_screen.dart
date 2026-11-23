import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_checkbox.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_text_field.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/auth_switch.dart';
import 'widgets/check_inbox.dart';
import 'widgets/google_section.dart';
import 'widgets/password_rules.dart';

/// Registro (pages/auth/Register.jsx): nombre, correo, contraseña con sus requisitos en vivo y
/// aceptación de términos. Al crear la cuenta NO abre sesión: muestra "Confirma tu correo".
///
/// Diferencias con la web, a propósito:
/// - Debajo de la contraseña van las reglas (las mismas del restablecimiento) y no la barra de
///   fuerza, que dice "Media" para contraseñas que el formulario rechaza.
/// - El nombre sí se envía al backend (la web lo pide y lo descarta).
/// - El enlace del correo abre la web (/verificar). Confirmar dentro de la app necesita App Links /
///   Universal Links, que siguen bloqueados; por eso aquí se vuelve a iniciar sesión.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late final _termsLink = TapGestureRecognizer()..onTap = () => _openWeb('/terminos');
  late final _privacyLink = TapGestureRecognizer()..onTap = () => _openWeb('/privacidad');

  bool _accepted = false;
  bool _sending = false;

  /// Tras el primer envío, los errores se revisan al escribir (como en el login).
  bool _submitted = false;

  /// Clave en español o mensaje del servidor; se traduce al mostrarlo.
  String? _error;

  /// Problemas por campo que manda el servidor (422): `name`, `email`, `password`.
  Map<String, String> _fieldErrors = const {};

  /// Correo al que se envió el enlace; con valor se muestra "Confirma tu correo".
  String? _sentTo;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _termsLink.dispose();
    _privacyLink.dispose();
    super.dispose();
  }

  Future<void> _openWeb(String path) async {
    try {
      await launchUrl(ref.read(appConfigProvider).webPage(path), mode: LaunchMode.externalApplication);
    } catch (_) {
      // shortcut: si no hay navegador no se avisa (no existe texto en el producto); agregar aviso si pasa.
    }
  }

  /// Al editar un campo se borra el error que el servidor le había puesto.
  void _clearFieldError(String field) {
    if (_fieldErrors.containsKey(field)) setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() {
      _error = null;
      _submitted = true;
    });
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final email = AuthValidators.normalizeEmail(_email.text);
    try {
      final sentTo = await ref
          .read(authRepositoryProvider)
          .register(name: AuthValidators.normalizeName(_name.text), email: email, password: _password.text);
      if (!mounted) return;
      // Le dice al gestor de contraseñas que guarde el correo y la contraseña nuevos.
      TextInput.finishAutofillContext();
      setState(() {
        _sending = false;
        _fieldErrors = const {};
        _sentTo = sentTo;
      });
    } catch (e) {
      if (!mounted) return;
      const fallback = 'No pudimos crear tu cuenta. Inténtalo de nuevo.';
      setState(() {
        _sending = false;
        if (e is ApiException) {
          _error = e.messageFor(
            byCode: {ApiCodes.emailTaken: 'Ya existe una cuenta con ese correo.'},
            fallback: fallback,
          );
          _fieldErrors = e.fields;
        } else {
          _error = fallback;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final sentTo = _sentTo;
    return sentTo == null ? _form(context, t) : _checkInbox(context, t, sentTo);
  }

  Widget _checkInbox(BuildContext context, Tr t, String sentTo) {
    final p = context.palette;
    final muted = RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.55));
    return AuthScaffold(
      key: const ValueKey('confirm'),
      icon: RindeIcons.mailCheck,
      title: t('Confirma tu correo'),
      // Sin selector: la cuenta ya está creada.
      footer: Center(
        child: RindeTextLink(
          label: t('Ya lo confirmé, iniciar sesión'),
          color: RindeBrand.violetLight,
          onPressed: () => context.pushReplacement(
            Uri(path: Routes.login, queryParameters: {'correo': sentTo}).toString(),
          ),
        ),
      ),
      // Se anuncia al lector al aparecer: el formulario acaba de cambiar por esta pantalla.
      subtitleWidget: Semantics(
        liveRegion: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${t('Te enviamos un enlace a')} '),
              TextSpan(
                text: sentTo,
                style: RindeType.small.w(FontWeight.w500).copyWith(color: RindeBrand.white),
              ),
              TextSpan(text: t('. Ábrelo para activar tu cuenta y entrar.')),
            ],
          ),
          textAlign: TextAlign.center,
          style: muted,
        ),
      ),
      children: [
        CheckInbox(
          tips: [
            t('El enlace vence en 24 horas y sirve una sola vez.'),
            t('¿No lo ves? Revisa las carpetas de spam o promociones.'),
          ],
          onResend: () => ref.read(authRepositoryProvider).resendVerification(sentTo),
          // Vuelve al formulario con lo que ya había escrito.
          onUseOtherEmail: () => setState(() => _sentTo = null),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, Tr t) {
    final p = context.palette;
    // Las mismas piezas de la web (el orden de la frase cambia poco entre idiomas); el lector las oye juntas.
    final terms = [
      t('Soy mayor de edad y acepto los'),
      t('términos de uso'),
      t('y la'),
      t('política de privacidad'),
      t('de Rinde.'),
    ];
    const link = TextStyle(
      color: RindeBrand.violetLight,
      decoration: TextDecoration.underline,
      decorationColor: RindeBrand.violetLight,
    );
    return AuthScaffold(
      key: const ValueKey('form'),
      mode: AuthMode.register,
      title: t('Que tu plata alcance'),
      subtitle: t('Crea tu cuenta en un minuto. Los campos con * son obligatorios.'),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            t('¿Ya tienes cuenta?'),
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.55)),
          ),
          RindeTextLink(
            label: t('Inicia sesión'),
            color: RindeBrand.violetLight,
            onPressed: () => context.pushReplacement(Routes.login),
          ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RindeTextField(
                  label: t('¿Cómo te llamas? *'),
                  controller: _name,
                  hint: t('Tu nombre'),
                  helper: t('Así te saludamos en la app.'),
                  maxLength: AuthValidators.nameMax,
                  autofillHints: const [AutofillHints.givenName],
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) => t.maybe(AuthValidators.name(v)),
                  serverError: _fieldErrors['name'],
                  onChanged: (_) => _clearFieldError('name'),
                  onSubmitted: (_) => _emailFocus.requestFocus(),
                ),
                const SizedBox(height: RindeSpace.s4),
                RindeTextField(
                  label: t('Correo *'),
                  controller: _email,
                  focusNode: _emailFocus,
                  hint: t('tu@correo.com'),
                  helper: t('Te enviamos un enlace para confirmarlo.'),
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (v) => t.maybe(AuthValidators.registerEmail(v)),
                  serverError: _fieldErrors['email'],
                  onChanged: (_) => _clearFieldError('email'),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: RindeSpace.s4),
                RindePasswordField(
                  label: t('Contraseña *'),
                  showLabel: t('Mostrar contraseña'),
                  hideLabel: t('Ocultar contraseña'),
                  controller: _password,
                  focusNode: _passwordFocus,
                  hint: t('Crea una contraseña'),
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  validator: (v) => t.maybe(AuthValidators.newPassword(v)),
                  serverError: _fieldErrors['password'],
                  onChanged: (_) => _clearFieldError('password'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: RindeSpace.s2),
                ValueListenableBuilder(
                  valueListenable: _password,
                  builder: (_, value, _) => PasswordRules(password: value.text),
                ),
                const SizedBox(height: RindeSpace.s6),
                RindeCheckboxField(
                  initialValue: _accepted,
                  onChanged: (v) => _accepted = v,
                  validator: (v) => t.maybe(AuthValidators.acceptTerms(v)),
                  semanticLabel: terms.join(' '),
                  label: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${terms[0]} '),
                        TextSpan(text: terms[1], style: link, recognizer: _termsLink),
                        TextSpan(text: ' ${terms[2]} '),
                        TextSpan(text: terms[3], style: link, recognizer: _privacyLink),
                        TextSpan(text: ' ${terms[4]}'),
                      ],
                    ),
                    // Líneas más altas: los enlaces quedan más fáciles de tocar con el dedo.
                    style: const TextStyle(height: 1.6),
                  ),
                ),
                const SizedBox(height: RindeSpace.s6),
                if (_error != null) ...[
                  RindeBanner(message: t(_error!)),
                  const SizedBox(height: RindeSpace.s4),
                ],
                RindeButton(
                  label: t('Crear cuenta'),
                  loadingLabel: t('Creando cuenta…'),
                  loading: _sending,
                  onPressed: _sending ? null : _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s8),
        const GoogleSection(mode: AuthMode.register),
      ],
    );
  }
}
