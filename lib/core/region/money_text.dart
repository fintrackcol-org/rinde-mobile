/// Montos escritos por la persona (MoneyInput y lib/money.js de Rinde Web).
///
/// El valor "crudo" es texto con solo dígitos y punto decimal opcional ("1234567.5"): así se guarda en
/// el borrador y así se convierte a número. En pantalla se muestra agrupado con los separadores del país.
library;

const maxAmount = 9999999999.99;
const largeAmount = 100000000;
const _maxIntegerDigits = 10;
const _maxDecimals = 2;

/// Texto que escribe la persona → crudo. Sin signo (no hay negativos), máximo 10 enteros y 2 decimales.
String parseMoneyInput(String text, {required String decimal}) {
  final buffer = StringBuffer();
  for (final ch in text.split('')) {
    if (RegExp(r'\d').hasMatch(ch) || ch == decimal) buffer.write(ch);
  }
  final cleaned = buffer.toString();
  final parts = cleaned.split(decimal);
  var integer = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (integer.length > _maxIntegerDigits) integer = integer.substring(0, _maxIntegerDigits);
  if (parts.length == 1) return integer;
  var decimals = parts.skip(1).join();
  if (decimals.length > _maxDecimals) decimals = decimals.substring(0, _maxDecimals);
  return '${integer.isEmpty ? '0' : integer}.$decimals';
}

/// Lo pegado: "1500.50" con un solo separador del otro sistema y 1-2 dígitos se lee como decimal.
String parsePastedMoney(String text, {required String decimal}) {
  final value = text.trim();
  final other = decimal == ',' ? '.' : ',';
  if (RegExp('^\\d+${RegExp.escape(other)}\\d{1,2}\$').hasMatch(value)) {
    return parseMoneyInput(value.replaceFirst(other, decimal), decimal: decimal);
  }
  return parseMoneyInput(value, decimal: decimal);
}

/// Crudo → texto para mostrar en el campo ("1234567.5" → "1.234.567,5" en Colombia).
String formatMoneyInput(String raw, {required String group, required String decimal}) {
  if (raw.isEmpty) return '';
  final parts = raw.split('.');
  final integer = parts.first;
  final grouped = integer.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => group);
  return parts.length == 1 ? grouped : '$grouped$decimal${parts[1]}';
}

/// Crudo → número, o null si está vacío. "12." se lee 12.
num? moneyValue(String raw) {
  if (raw.trim().isEmpty) return null;
  final value = num.tryParse(raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw);
  return value;
}
