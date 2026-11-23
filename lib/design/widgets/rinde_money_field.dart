import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/i18n/tr.dart';
import '../../core/region/money_text.dart';
import '../../core/region/region.dart';
import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';

/// Campo de monto (common/MoneyInput.jsx): se escribe con los separadores del país, se guarda
/// "crudo" ("1234567.5"), sin signo, máximo 10 enteros y 2 decimales. Teclado numérico con coma/punto.
class RindeMoneyField extends StatefulWidget {
  const RindeMoneyField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.format,
    required this.semanticLabel,
    this.label,
    this.hint = '0',
    this.helper,
    this.message,
    this.messageTone = RindeMoneyMessageTone.info,
    this.autofocus = false,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
    this.enabled = true,
  });

  /// Valor crudo.
  final String value;
  final ValueChanged<String> onChanged;

  /// Separadores del país (formatFor(region)).
  final MoneyFormat format;

  /// Nombre para el lector de pantalla (el label visible puede estar fuera).
  final String semanticLabel;
  final String? label;
  final String hint;
  final String? helper;

  /// Aviso bajo el campo (describeAmount de la web: «≈ 1,5 millones de pesos»…).
  final String? message;
  final RindeMoneyMessageTone messageTone;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final bool enabled;

  @override
  State<RindeMoneyField> createState() => _RindeMoneyFieldState();
}

enum RindeMoneyMessageTone { info, warning, error }

class _RindeMoneyFieldState extends State<RindeMoneyField> {
  late final _controller = TextEditingController(text: _display(widget.value));

  String _display(String raw) =>
      formatMoneyInput(raw, group: widget.format.inputGroup, decimal: widget.format.inputDecimal);

  @override
  void didUpdateWidget(RindeMoneyField old) {
    super.didUpdateWidget(old);
    // Cambió desde afuera (propuesta de saldo, otro país): se muestra sin perder lo que coincide.
    final current = parseMoneyInput(_controller.text, decimal: widget.format.inputDecimal);
    if (current != widget.value || old.format != widget.format) {
      final text = _display(widget.value);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final messageColor = switch (widget.messageTone) {
      RindeMoneyMessageTone.info => p.inkMuted,
      RindeMoneyMessageTone.warning => p.caution,
      RindeMoneyMessageTone.error => p.negative,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          ExcludeSemantics(
            child: Text(widget.label!, style: RindeType.label.copyWith(color: p.inkLabel)),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          label: widget.semanticLabel,
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            inputFormatters: [_MoneyFormatter(widget.format)],
            style: RindeType.body.copyWith(color: p.ink).tabular,
            cursorColor: RindeBrand.violet,
            onChanged: (text) => widget.onChanged(parseMoneyInput(text, decimal: widget.format.inputDecimal)),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            // Al abrir el teclado sube también el aviso y la ayuda que van debajo del campo, que crecen
            // con el tamaño de texto.
            scrollPadding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.textScalerOf(context).scale(120)),
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: widget.errorText,
              errorStyle: RindeType.small.copyWith(color: p.negative),
              constraints: const BoxConstraints(minHeight: RindeSize.field),
              contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 14, RindeSpace.s4, 14),
              prefixIcon: const SizedBox(width: RindeSpace.s4),
              prefixIconConstraints: const BoxConstraints.tightFor(width: RindeSpace.s4),
            ),
          ),
        ),
        if (widget.message != null && widget.message!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(widget.message!, style: RindeType.small.copyWith(color: messageColor)),
          ),
        ],
        if (widget.helper != null) ...[
          const SizedBox(height: 6),
          Text(widget.helper!, style: RindeType.small.copyWith(color: p.inkMuted)),
        ],
      ],
    );
  }
}

/// Mantiene el texto agrupado mientras se escribe y deja el cursor donde estaba (contando dígitos).
class _MoneyFormatter extends TextInputFormatter {
  _MoneyFormatter(this.format);
  final MoneyFormat format;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final decimal = format.inputDecimal;
    // Lo insertado descuenta lo seleccionado que se reemplazó (pegar sobre «1.000» también es pegar).
    final selection = oldValue.selection;
    final replaced = selection.isValid ? selection.end - selection.start : 0;
    final pasted = newValue.text.length - (oldValue.text.length - replaced) > 1;
    final raw = pasted
        ? parsePastedMoney(newValue.text, decimal: decimal)
        : parseMoneyInput(newValue.text, decimal: decimal);
    final text = formatMoneyInput(raw, group: format.inputGroup, decimal: decimal);
    // Cuántos dígitos/decimal había antes del cursor → misma cantidad en el texto nuevo.
    final cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    var significant = 0;
    for (final ch in newValue.text.substring(0, cursor).split('')) {
      if (RegExp(r'\d').hasMatch(ch) || ch == decimal) significant++;
    }
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < significant) {
      final ch = text[offset];
      if (RegExp(r'\d').hasMatch(ch) || ch == decimal) seen++;
      offset++;
    }
    if (pasted) offset = text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Aviso bajo el campo de saldo (describeAmount de la web), ya en el idioma de [t], o null.
/// `inPesos`: la palabra «de pesos» y el «¿faltan ceros?» solo tienen sentido en COP.
({String message, RindeMoneyMessageTone tone})? describeAmount(
  String raw, {
  required MoneyFormat format,
  required bool inPesos,
  required Tr t,
}) {
  final value = moneyValue(raw);
  if (value == null || value <= 0) return null;
  if (value > maxAmount) {
    return (
      message: t('Supera el máximo permitido ({MAX_AMOUNT}).', {'MAX_AMOUNT': format.money(maxAmount)}),
      tone: RindeMoneyMessageTone.error,
    );
  }
  final words = bigAmountWords(value, t.language, format.inputDecimal);
  final unit = inPesos ? t(' de pesos') : '';
  if (value >= largeAmount) {
    return (
      message: t('Monto muy grande ({value}{unit}). Revisa que no sobren ceros.', {
        'value': words,
        'unit': unit,
      }),
      tone: RindeMoneyMessageTone.warning,
    );
  }
  if (value >= 1000000) return (message: '≈ $words$unit', tone: RindeMoneyMessageTone.info);
  if (value < 1000 && inPesos) {
    return (
      message: t('Son menos de {amount}. ¿Faltan ceros?', {'amount': format.money(1000)}),
      tone: RindeMoneyMessageTone.info,
    );
  }
  return null;
}

/// «1,5 millones», «1.5 million», «1,5 milhão»: un decimal como mucho, con el separador con que se
/// escribe el monto. No pasa por t(): el plural cambia con el número y cada idioma tiene su regla.
String bigAmountWords(num value, String language, String decimal) {
  num tenth(num x) => (x * 10).round() / 10;
  var n = tenth(value / 1000000);
  // 999,95 millones redondea a 1000: se dice en miles de millones.
  final billions = n >= 1000;
  if (billions) n = tenth(value / 1000000000);
  final word = switch (language) {
    'en' => billions ? 'billion' : 'million',
    // En portugués el singular llega hasta 2: «1,5 milhão».
    'pt' => billions ? (n < 2 ? 'bilhão' : 'bilhões') : (n < 2 ? 'milhão' : 'milhões'),
    _ => billions ? 'mil millones' : (n == 1 ? 'millón' : 'millones'),
  };
  final number = n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);
  return '${number.replaceAll('.', decimal)} $word';
}
