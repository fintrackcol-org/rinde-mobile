import '../../home/data/home_models.dart' show readMap;

/// GET y PUT /users/me/reminder-settings (pushService.js de la web).
class ReminderSettings {
  const ReminderSettings({required this.times, required this.timezone, required this.cardReminders});

  factory ReminderSettings.fromJson(Object? data) {
    final json = readMap(data);
    final times = json['times'];
    return ReminderSettings(
      times: [if (times is List) ...times.whereType<String>()],
      timezone: json['timezone'] is String ? json['timezone'] as String : '',
      cardReminders: json['cardReminders'] == true,
    );
  }

  /// Horas del recordatorio diario. La app no las ofrece (solo llegan por notificación push, que la app
  /// no tiene), pero se reenvían tal cual al cambiar el aviso de tarjetas, como la web.
  final List<String> times;
  final String timezone;

  /// «Pago de tarjetas»: aviso 3 días antes del día de pago de cada tarjeta.
  final bool cardReminders;

  Map<String, dynamic> toJson() => {'times': times, 'timezone': timezone, 'cardReminders': cardReminders};

  ReminderSettings withCardReminders(bool value) =>
      ReminderSettings(times: times, timezone: timezone, cardReminders: value);
}

/// Acceso al bot que da el equipo (FT-0029).
enum WhatsappAccess {
  approved,
  pending,
  rejected,
  none;

  static WhatsappAccess parse(Object? raw) => values.where((a) => a.name == raw).firstOrNull ?? approved;
}

/// GET /whatsapp/link.
class WhatsappLink {
  const WhatsappLink({
    required this.available,
    required this.access,
    required this.linked,
    this.phone,
    this.botNumber,
  });

  factory WhatsappLink.fromJson(Object? data) {
    final json = readMap(data);
    return WhatsappLink(
      available: json['available'] == true,
      // Sin el campo, la web lo da por aprobado (`data.access ?? 'approved'`).
      access: WhatsappAccess.parse(json['access']),
      linked: json['linked'] == true,
      phone: json['phone'] is String ? json['phone'] as String : null,
      botNumber: json['botNumber'] is String ? json['botNumber'] as String : null,
    );
  }

  /// false: el bot no está configurado o la cuenta no lo ve; la fila no se muestra.
  final bool available;
  final WhatsappAccess access;
  final bool linked;

  /// Solo los últimos cuatro dígitos.
  final String? phone;
  final String? botNumber;
}

/// POST /whatsapp/link: código de un solo uso que vence en 10 minutos.
class WhatsappCode {
  const WhatsappCode({required this.code, this.botNumber});

  factory WhatsappCode.fromJson(Object? data) {
    final json = readMap(data);
    final code = json['code'];
    return WhatsappCode(
      code: code is String ? code : '$code',
      botNumber: json['botNumber'] is String ? json['botNumber'] as String : null,
    );
  }

  final String code;
  final String? botNumber;

  /// chatUrl de WhatsappLink.jsx: abre el chat del bot con el código ya escrito.
  Uri? get chatUrl =>
      botNumber == null ? null : Uri.parse('https://wa.me/$botNumber?text=${Uri.encodeComponent(code)}');
}
