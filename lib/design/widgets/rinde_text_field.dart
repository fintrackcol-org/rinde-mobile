import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_icon.dart';

/// Campo de Rinde (ui/input.jsx + FormField.jsx): label arriba, campo de 48 de alto y radio 12,
/// borde violeta al enfocar, borde rojo y mensaje debajo si hay error.
/// El error lo valida [validator] o llega del servidor en [serverError].
class RindeTextField extends StatelessWidget {
  const RindeTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.serverError,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.suffix,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? serverError;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final bool enabled;
  final bool obscureText;
  final bool autocorrect;

  /// false: sin la barra de sugerencias del teclado (los últimos 4 de una tarjeta).
  final bool enableSuggestions;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Se ve arriba; al lector se le da como nombre del campo (Semantics de abajo).
        ExcludeSemantics(
          child: Text(label, style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        const SizedBox(height: RindeSpace.s2),
        Semantics(
          label: label,
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            validator: validator,
            forceErrorText: serverError,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            onFieldSubmitted: onSubmitted,
            onChanged: onChanged,
            autofocus: autofocus,
            enabled: enabled,
            obscureText: obscureText,
            autocorrect: autocorrect && !obscureText,
            enableSuggestions: enableSuggestions && !obscureText,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            style: RindeType.body.copyWith(color: p.ink),
            cursorColor: RindeBrand.violet,
            decoration: InputDecoration(
              semanticCounterText: '',
              counterText: '',
              hintText: hint,
              helperText: helper,
              helperMaxLines: 3,
              helperStyle: RindeType.small.copyWith(color: p.inkMuted),
              errorMaxLines: 3,
              errorStyle: RindeType.small.copyWith(color: p.negative),
              suffixIcon: suffix,
              suffixIconConstraints: const BoxConstraints(
                minWidth: RindeSize.tapTarget,
                minHeight: RindeSize.field,
              ),
              constraints: const BoxConstraints(minHeight: RindeSize.field),
              // La ayuda y el error empiezan donde el padding izquierdo; con 0 quedan alineados con
              // el label, como en la web. Los 16 de adentro los pone el prefijo vacío.
              contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 14, RindeSpace.s4, 14),
              prefixIcon: const SizedBox(width: RindeSpace.s4),
              prefixIconConstraints: const BoxConstraints.tightFor(width: RindeSpace.s4),
            ),
          ),
        ),
      ],
    );
  }
}

/// Contraseña con botón de ojo (PasswordInput.jsx): 48 de ancho, "Mostrar/Ocultar contraseña".
class RindePasswordField extends StatefulWidget {
  const RindePasswordField({
    super.key,
    required this.label,
    required this.showLabel,
    required this.hideLabel,
    this.controller,
    this.hint,
    this.helper,
    this.serverError,
    this.validator,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;

  /// Nombre del botón del ojo, ya traducido: «Mostrar contraseña» y «Ocultar contraseña».
  final String showLabel;
  final String hideLabel;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? serverError;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<RindePasswordField> createState() => _RindePasswordFieldState();
}

class _RindePasswordFieldState extends State<RindePasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tooltip = _visible ? widget.hideLabel : widget.showLabel;
    return RindeTextField(
      label: widget.label,
      controller: widget.controller,
      hint: widget.hint,
      helper: widget.helper,
      serverError: widget.serverError,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      keyboardType: TextInputType.visiblePassword,
      suffix: Semantics(
        button: true,
        toggled: _visible,
        label: tooltip,
        onTap: () => setState(() => _visible = !_visible),
        excludeSemantics: true,
        child: IconButton(
          onPressed: () => setState(() => _visible = !_visible),
          tooltip: tooltip,
          style: IconButton.styleFrom(minimumSize: const Size(RindeSize.tapTarget, RindeSize.field)),
          icon: RindeIcon(
            _visible ? RindeIcons.eyeOff : RindeIcons.eye,
            color: p.ink.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
