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
  });

  /// Borrador nuevo: país sugerido y su idioma.
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

  /// Cuerpo de POST /money-profile/welcome que el servidor YA confirmó en un intento anterior.
  /// Si el siguiente intento manda lo mismo, no se repite: solo falta guardar las fuentes.
  final String? sentWelcome;

  OnboardingDraft copyWith({
    int? position,
    String? country,
    String? language,
    bool? languagePicked,
    Map<IncomeKind, IncomeSourceForm>? sources,
    String? balance,
    List<CommitmentItem>? items,
    String? Function()? sentWelcome,
  }) => OnboardingDraft(
    position: position ?? this.position,
    country: country ?? this.country,
    language: language ?? this.language,
    languagePicked: languagePicked ?? this.languagePicked,
    sources: sources ?? this.sources,
    balance: balance ?? this.balance,
    items: items ?? this.items,
    sentWelcome: sentWelcome != null ? sentWelcome() : this.sentWelcome,
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
