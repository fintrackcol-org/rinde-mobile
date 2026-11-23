import 'dart:convert';

import '../../../core/region/money_text.dart';
import '../../../core/region/region.dart';
import 'commitments.dart';
import 'income_sources.dart';
import 'onboarding_flow.dart';

/// BORRADOR LOCAL de la bienvenida: lo respondido que todavía no confirmó el servidor.
/// Va por usuario (nunca se mezcla entre cuentas) y se guarda cifrado, porque tiene plata.
class OnboardingDraft {
  const OnboardingDraft({
    required this.position,
    required this.country,
    required this.language,
    this.languagePicked = false,
    this.sources = const {},
    this.balance = '',
    this.items = const [],
    this.sentWelcome,
    this.welcomeConfirmed = false,
    this.sourcesSent = false,
    this.confirmedBalance,
    this.welcomeKey,
  });

  /// Borrador nuevo: país sugerido y su idioma (el controlador lo cambia por el idioma que ya se ve).
  factory OnboardingDraft.fresh(String suggestedCountry) {
    final region = regionForCountry(suggestedCountry);
    return OnboardingDraft(
      position: OnboardingSteps.hello,
      country: region.country,
      language: region.language,
    );
  }

  /// Lee sin confiar: lo dañado vuelve al valor inicial en vez de romper la pantalla.
  /// Una versión distinta se descarta entera.
  factory OnboardingDraft.fromJson(Object? json, {required String suggestedCountry}) {
    final fresh = OnboardingDraft.fresh(suggestedCountry);
    if (json is! Map || json['v'] != version) return fresh;
    final country = json['country'] is String && findCountry(json['country'] as String) != null
        ? json['country'] as String
        : fresh.country;
    final language = json['language'] is String && isAppLanguage(json['language'] as String)
        ? json['language'] as String
        : regionForCountry(country).language;
    final sources = <IncomeKind, IncomeSourceForm>{};
    if (json['sources'] is List) {
      for (final raw in json['sources'] as List) {
        final form = IncomeSourceForm.fromJson(raw);
        if (form != null) sources.putIfAbsent(form.kind, () => form);
      }
    }
    final items = json['items'] is List
        ? (json['items'] as List)
              .map(CommitmentItem.fromJson)
              .whereType<CommitmentItem>()
              .take(maxCommitments)
              .toList()
        : <CommitmentItem>[];
    final balance = json['balance'] is String ? json['balance'] as String : '';
    return OnboardingDraft(
      position: OnboardingSteps.valid(json['position']),
      country: country,
      language: language,
      languagePicked: json['languagePicked'] == true,
      sources: sources,
      // Solo un monto crudo como lo escribe el campo (sin signo, NaN ni exponentes); si no, se descarta.
      balance: RegExp(r'^\d{1,10}(\.\d{0,2})?$').hasMatch(balance) ? balance : '',
      items: items,
      sentWelcome: json['sentWelcome'] is String ? json['sentWelcome'] as String : null,
      welcomeConfirmed: json['sentWelcome'] is String && json['welcomeConfirmed'] == true,
      sourcesSent: json['sourcesSent'] == true,
      confirmedBalance: json['confirmedBalance'] is num ? json['confirmedBalance'] as num : null,
      welcomeKey: json['welcomeKey'] is String ? json['welcomeKey'] as String : null,
    );
  }

  static const version = 1;

  final int position;
  final String country;
  final String language;

  /// La persona eligió el idioma a mano: cambiar de país ya no lo cambia.
  final bool languagePicked;

  /// En el orden en que se marcaron.
  final Map<IncomeKind, IncomeSourceForm> sources;

  /// Saldo crudo; '' = no lo dijo (se envía null, no 0).
  final String balance;
  final List<CommitmentItem> items;

  /// Cuerpo de POST /money-profile/welcome que se empezó a enviar. Se anota ANTES de enviarlo: si la
  /// respuesta no llega (espera vencida, app cerrada), la etapa 1 pudo quedar en el servidor y al
  /// reabrir se retoma para guardar las fuentes en vez de perderlas.
  final String? sentWelcome;

  /// El servidor confirmó [sentWelcome]: si el siguiente intento manda lo mismo no se repite, y los
  /// pagos ya no se editan aquí.
  final bool welcomeConfirmed;

  /// PUT /money-profile/sources salió alguna vez: si después quita todas las fuentes, hay que mandar
  /// la lista vacía para borrarlas en el servidor.
  final bool sourcesSent;

  /// El saldo que el servidor respondió que guardó. No se vuelve a enviar: pisaría el que la persona
  /// corrija después en Mi plata.
  final num? confirmedBalance;

  /// Llave de idempotencia del último envío de la etapa 1 y lo que se envió con ella
  /// (`<llave> <huella>`): un reintento idéntico la repite; uno distinto saca otra.
  final String? welcomeKey;

  /// Los pagos que salieron en la etapa 1, o null si no salió ninguno. Desde entonces no se editan y
  /// un reenvío los repite desde aquí, no desde la pantalla: el servidor no pisa ni borra pagos, así
  /// que otra lista los duplicaría. Si se omitieron, no hay nada que bloquear.
  List<Map<String, dynamic>>? get sentCommitments {
    final sent = sentWelcome;
    if (sent == null) return null;
    try {
      if (jsonDecode(sent) case {'commitments': final List<dynamic> list} when list.isNotEmpty) {
        return [
          for (final c in list)
            if (c is Map<String, dynamic>) c,
        ];
      }
    } on FormatException {
      // Una marca ilegible no bloquea nada.
    }
    return null;
  }

  OnboardingDraft copyWith({
    int? position,
    String? country,
    String? language,
    bool? languagePicked,
    Map<IncomeKind, IncomeSourceForm>? sources,
    String? balance,
    List<CommitmentItem>? items,
    String? Function()? sentWelcome,
    bool? welcomeConfirmed,
    bool? sourcesSent,
    num? Function()? confirmedBalance,
    String? welcomeKey,
  }) => OnboardingDraft(
    position: position ?? this.position,
    country: country ?? this.country,
    language: language ?? this.language,
    languagePicked: languagePicked ?? this.languagePicked,
    sources: sources ?? this.sources,
    balance: balance ?? this.balance,
    items: items ?? this.items,
    sentWelcome: sentWelcome != null ? sentWelcome() : this.sentWelcome,
    welcomeConfirmed: welcomeConfirmed ?? this.welcomeConfirmed,
    sourcesSent: sourcesSent ?? this.sourcesSent,
    confirmedBalance: confirmedBalance != null ? confirmedBalance() : this.confirmedBalance,
    welcomeKey: welcomeKey ?? this.welcomeKey,
  );

  Map<String, dynamic> toJson() => {
    'v': version,
    'position': position,
    'country': country,
    'language': language,
    'languagePicked': languagePicked,
    'sources': [for (final f in sources.values) f.toJson()],
    'balance': balance,
    'items': [for (final i in items) i.toJson()],
    'sentWelcome': ?sentWelcome,
    if (welcomeConfirmed) 'welcomeConfirmed': true,
    if (sourcesSent) 'sourcesSent': true,
    'confirmedBalance': ?confirmedBalance,
    'welcomeKey': ?welcomeKey,
  };
}

/// Cuerpo de POST /money-profile/welcome.
///
/// La bienvenida siempre manda `incomeType: null` y `payDays: []`: los fija PUT /money-profile/sources
/// después (por eso el orden importa: si la bienvenida fuera después, borraría el tipo de ingreso).
/// `{}` = «Ahora no» (se marca la bienvenida sin respuestas).
Map<String, dynamic> welcomeBody({required String balance, List<Map<String, dynamic>>? commitments}) => {
  'incomeType': null,
  'payDays': <int>[],
  'balance': moneyValue(balance),
  'commitments': ?commitments,
};

/// Huella estable del cuerpo, para saber si un intento anterior ya lo guardó.
String fingerprint(Map<String, dynamic> body) => jsonEncode(body);
