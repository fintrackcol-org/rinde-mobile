/// Reglas puras de Tarjetas: SOLO presentación (textos, porcentaje, suma en centavos, vista previa).
/// Los importes autoritativos (`used`, `available`, fechas, extracto, vencimiento) vienen del
/// servidor y aquí no se recalculan (cardFormat.js y cardStyles.js de Rinde Web).
library;

import '../../../core/i18n/tr.dart';
import '../../../core/region/money_text.dart' show maxAmount, moneyValue;
import '../../../core/region/region.dart';
import '../../home/domain/home_dates.dart';
import '../data/card_models.dart';

/// Niveles válidos por franquicia (lib/cardStyles.js, igual que el backend).
const cardTiers = <String, List<String>>{
  'visa': ['clasica', 'gold', 'platinum', 'black'],
  'mastercard': ['clasica', 'gold', 'platinum', 'black'],
  'amex': ['green', 'blue', 'gold', 'platinum'],
  'otra': ['clasica'],
};

/// «Visa», «Mastercard», «Amex», «Otra» (NETWORK_LABELS); una red desconocida cae en [fallback].
String networkLabel(Tr t, String network, {String? fallback}) => switch (network) {
  'visa' => t('Visa'),
  'mastercard' => t('Mastercard'),
  'amex' => t('Amex'),
  'otra' => t('Otra'),
  _ => fallback ?? t('Otra'),
};

String tierLabel(Tr t, String tier) => switch (tier) {
  'clasica' => t('Clásica'),
  'gold' => t('Gold'),
  'platinum' => t('Platinum'),
  'black' => t('Black'),
  'green' => t('Green'),
  'blue' => t('Blue'),
  _ => tier,
};

/// «Visa Gold» (cardLabel de cardStyles.js); «Otra» va sin nivel.
String networkTierLabel(Tr t, String network, String tier) {
  final base = networkLabel(t, network);
  return network == 'otra' ? base : '$base ${tierLabel(t, tier)}'.trim();
}

/// «{Franquicia} ••{last4}» (Cards.jsx:25): la fila, el detalle, Anotar y el aviso del Inicio dicen
/// lo mismo. Con una red desconocida usa el nombre guardado, como la web.
String cardListLabel(Tr t, {required String network, required String name, required String last4}) {
  final brand = networkLabel(t, network, fallback: name.isEmpty ? t('Tarjeta') : name);
  return last4.isEmpty ? brand : '$brand ••$last4';
}

/// «15 nov» a partir de AAAA-MM-DD (shortDate de cardFormat.js, siempre día primero como la web).
String shortCardDate(String iso, Region region) {
  final parts = iso.split('-');
  return '${int.parse(parts[2])} ${shortMonthName(int.parse(parts[1]), region)}';
}

/// paymentText de cardFormat.js: «Pagas en 5 días (15 nov)».
String paymentText(Tr t, CreditCard card, Region region) {
  if (card.paidThisCycle) return t('Pago de este mes al día');
  if (card.daysToPayment < 0) {
    return t('Pago atrasado desde el {nextPaymentDate}', {
      'nextPaymentDate': card.nextPaymentDate == null ? '' : shortCardDate(card.nextPaymentDate!, region),
    });
  }
  final when = card.nextPaymentDate == null ? '' : ' (${shortCardDate(card.nextPaymentDate!, region)})';
  if (card.daysToPayment == 0) return t('Pagas hoy{when}', {'when': when});
  if (card.daysToPayment == 1) return t('Pagas en 1 día{when}', {'when': when});
  return t('Pagas en {daysToPayment} días{when}', {'daysToPayment': card.daysToPayment, 'when': when});
}

/// «hoy», «mañana», «en {days} días»: las mismas claves del aviso del Inicio (la web deja «hoy» y
/// «en N días» sin t(): aquí sí se traducen).
String dueWhen(Tr t, int days) => switch (days) {
  0 => t('hoy'),
  1 => t('mañana'),
  _ => t('en {days} días', {'days': days}),
};

/// dueText de cardFormat.js: «Se paga hoy». Pagada o atrasada cae en [paymentText].
String dueText(Tr t, CreditCard card, Region region) {
  if (card.paidThisCycle || card.daysToPayment < 0) return paymentText(t, card, region);
  return t('Se paga {v1}', {'v1': dueWhen(t, card.daysToPayment)});
}

/// La línea del estado del pago se oculta cuando diría «Pago atrasado» sin deuda (used <= 0):
/// el mismo criterio del aviso del Inicio (home_notice.dart). LA WEB SÍ la muestra; es una
/// diferencia a propósito para no avisar algo falso (pregunta 4 del plan).
bool showDueLine(CreditCard card) => !(card.daysToPayment < 0 && !card.paidThisCycle && card.used <= 0);

/// dueText en amarillo cuando faltan 3 días o menos o está atrasada (Cards.jsx:59).
bool dueSoon(CreditCard card) => !card.paidThisCycle && card.daysToPayment <= 3;

/// El % de la barra: `min(100, round(used/limit*100))` (Cards.jsx:58). Solo presentación.
int usagePercent(CreditCard card) {
  if (card.limit <= 0) return 0;
  final pct = (card.used / card.limit * 100).round();
  return pct > 100 ? 100 : (pct < 0 ? 0 : pct);
}

/// «Debes en total»: la suma de `used` EN CENTAVOS. La web suma los decimales flotantes
/// (Cards.jsx:170) y puede arrastrar residuos; el valor es el mismo sin ellos.
num debtTotal(List<CreditCard> cards) {
  final cents = cards.fold<int>(0, (sum, c) => sum + (c.used * 100).round());
  return cents % 100 == 0 ? cents ~/ 100 : cents / 100;
}

/// La próxima a pagar (Cards.jsx:149): sin pagar este ciclo, la de menos días. Se descarta la que
/// diría «Pago atrasado» sin deber nada, con el criterio del aviso del Inicio (ver [showDueLine]).
CreditCard? nextDueCard(List<CreditCard> cards) {
  CreditCard? next;
  for (final card in cards) {
    if (card.paidThisCycle || !showDueLine(card)) continue;
    if (next == null || card.daysToPayment < next.daysToPayment) next = card;
  }
  return next;
}

/// La diferencia que decidirá el servidor al actualizar con el banco (cardFormat.js:27-34):
/// `cupo − disponible − usado`, redondeada a centavos. null si el disponible no es un número.
/// Mayor que 0 = se registrará el gasto «Cargos del banco».
num? syncDifference(CreditCard card, num? available) {
  if (available == null) return null;
  final cents = (card.limit * 100).round() - (available * 100).round() - (card.used * 100).round();
  return cents % 100 == 0 ? cents ~/ 100 : cents / 100;
}

/// expiryNotice de cardFormat.js: el texto de la pastilla, o null si no vence pronto.
({String text, bool expired})? expiryNotice(Tr t, CardExpiry? expiry) {
  if (expiry == null) return null;
  if (expiry.expired) {
    return (text: t('Vencida ({label}) · actualiza la fecha', {'label': expiry.label}), expired: true);
  }
  if (expiry.soon) {
    return (
      text: t('Vence pronto ({label}) · pide la nueva al banco', {'label': expiry.label}),
      expired: false,
    );
  }
  return null;
}

/// Pone la barra sola mientras se escribe el vencimiento: «032» → «03/2» (formatExpiry de la web).
String formatExpiry(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final cut = digits.length > 4 ? digits.substring(0, 4) : digits;
  return cut.length > 2 ? '${cut.substring(0, 2)}/${cut.substring(2)}' : cut;
}

/// «03/27» → (3, 2027); null si está vacío. El formato ya lo validó [cardFormProblems].
(int, int)? parseExpiry(String value) {
  if (value.isEmpty) return null;
  final parts = value.split('/');
  return (int.parse(parts[0]), 2000 + int.parse(parts[1]));
}

final _expiryPattern = RegExp(r'^((0[1-9]|1[0-2])\/\d{2})?$');
final _fourDigits = RegExp(r'^\d{4}$');

/// Validaciones del formulario de tarjeta, con los textos exactos de lib/validation/card.js.
/// [editing]: sin «Cupo disponible hoy». Los montos llegan crudos (RindeMoneyField).
Map<String, String> cardFormProblems(
  Tr t, {
  required String network,
  required String tier,
  required String last4,
  required String name,
  required String expiry,
  required num? limit,
  required num? available,
  required String paymentDay,
  required String cutoffDay,
  required bool editing,
}) {
  String? dayProblem(String raw, {required bool required}) {
    if (raw.trim().isEmpty) return required ? t('Ingresa un día') : null;
    final day = int.tryParse(raw.trim());
    if (day == null) return t('Ingresa un día');
    if (day < 1 || day > 31) return t('Del 1 al 31');
    return null;
  }

  final problems = <String, String>{
    if (!(cardTiers[network]?.contains(tier) ?? false)) 'tier': t('Elige un tipo de tarjeta'),
    if (!_fourDigits.hasMatch(last4)) 'last4': t('Escribe exactamente 4 dígitos'),
    if (name.trim().length > 40) 'name': t('Máximo 40 caracteres'),
    if (!_expiryPattern.hasMatch(expiry)) 'expiry': t('Escribe el mes y el año: MM/AA'),
  };
  final String? limitProblem;
  if (limit == null) {
    limitProblem = t('Ingresa un monto');
  } else if (limit > maxAmount) {
    limitProblem = t('El monto es demasiado grande');
  } else if (limit <= 0) {
    limitProblem = t('El cupo debe ser mayor que 0');
  } else {
    limitProblem = null;
  }
  if (limitProblem != null) problems['limit'] = limitProblem;
  if (!editing) {
    final String? availableProblem;
    if (available == null) {
      availableProblem = t('Ingresa un monto');
    } else if (available > maxAmount) {
      availableProblem = t('El monto es demasiado grande');
    } else if (available < 0) {
      availableProblem = t('No puede ser negativo');
    } else if (limit != null && available > limit) {
      availableProblem = t('No puede ser mayor que el cupo total');
    } else {
      availableProblem = null;
    }
    if (availableProblem != null) problems['available'] = availableProblem;
  }
  if (dayProblem(paymentDay, required: true) case final p?) problems['paymentDay'] = p;
  if (dayProblem(cutoffDay, required: false) case final p?) problems['cutoffDay'] = p;
  return problems;
}

/// Cuerpo de POST /cards (completo) o, con [initial], de PUT con SOLO lo que cambió (CardForm.jsx):
/// - nunca `available` al editar (el servidor lo rechaza: se corrige con «Actualizar con el banco»);
/// - `expiryMonth` y `expiryYear` siempre juntos (con uno solo da 422) y en null si se borró;
/// - un nombre vacío no se envía (con "" da 422; el servidor conserva o pone el por defecto). Al no
///   mandar lo que no cambió, el servidor rehace el nombre por defecto si cambian los últimos 4 o el
///   tipo: la web manda todo y deja el nombre viejo.
/// null = nada cambió. Los textos ya pasaron [cardFormProblems]; los montos llegan crudos.
Map<String, dynamic>? cardBody(
  CreditCard? initial, {
  required String network,
  required String tier,
  required String last4,
  required String limit,
  required String available,
  required String paymentDay,
  required String name,
  required String cutoffDay,
  required String expiry,
}) {
  final cleanName = name.trim();
  final date = parseExpiry(expiry);
  final cutoff = cutoffDay.trim().isEmpty ? null : int.parse(cutoffDay.trim());
  final day = int.parse(paymentDay.trim());
  final cupo = moneyValue(limit)!;
  if (initial == null) {
    return {
      'network': network,
      'tier': tier,
      'last4': last4,
      'limit': cupo,
      'available': moneyValue(available),
      'paymentDay': day,
      if (cleanName.isNotEmpty) 'name': cleanName,
      'cutoffDay': ?cutoff,
      if (date != null) ...{'expiryMonth': date.$1, 'expiryYear': date.$2},
    };
  }
  final body = <String, dynamic>{
    // El nivel se valida contra la franquicia: si cambia uno, van los dos.
    if (network != initial.network || tier != initial.tier) ...{'network': network, 'tier': tier},
    if (last4 != initial.last4) 'last4': last4,
    if ((cupo * 100).round() != (initial.limit * 100).round()) 'limit': cupo,
    if (day != initial.paymentDay) 'paymentDay': day,
    if (cleanName.isNotEmpty && cleanName != initial.name) 'name': cleanName,
    if (cutoff != initial.cutoffDay) 'cutoffDay': cutoff,
    if (date?.$1 != initial.expiryMonth || date?.$2 != initial.expiryYear) ...{
      'expiryMonth': date?.$1,
      'expiryYear': date?.$2,
    },
  };
  return body.isEmpty ? null : body;
}

/// Cuerpo de «Actualizar con el banco» (BankSyncForm.jsx:35-36): los opcionales vacíos SE OMITEN,
/// porque con null el servidor responde 422; sin ellos, el extracto guardado no cambia.
Map<String, dynamic> bankSyncBody({
  required String available,
  required String statementTotal,
  String? statementDueDate,
}) => {
  'available': moneyValue(available),
  'statementTotal': ?moneyValue(statementTotal),
  'statementDueDate': ?statementDueDate,
};
