/// Fuentes de ingreso (lib/incomeSources.js y moneyProfile.js de Rinde Web).
///
/// Son para PLANEAR: saber cuándo entra plata. No se anotan como ingresos ni crean movimientos.
library;

enum IncomeKind {
  sueldo('Sueldo fijo', 'Te pagan lo mismo cada mes o quincena'),
  comisiones('Sueldo + comisiones', 'Una base fija y lo que vendas'),
  proyectos('Por proyectos u honorarios', 'Diseño, programación, asesorías…'),
  diario('Por días o por apps', 'Domicilios, Uber, ventas diarias'),
  mesada('Mesada o ayuda', 'Lo que te dan tus papás u otra persona');

  const IncomeKind(this.title, this.description);

  /// Textos en español; son la clave de traducción.
  final String title;
  final String description;

  static IncomeKind? parse(Object? value) {
    for (final k in values) {
      if (k.name == value) return k;
    }
    return null;
  }
}

/// Cada cuánto llega la mesada (PERIODS de IncomeSourcesFields.jsx). Sueldo siempre va 'mensual'.
const mesadaFrequencies = {'mensual': 'Al mes', 'quincenal': 'Quincena', 'semanal': 'Semana'};

/// Días que se trabaja a la semana (opciones exactas de la web).
const workDayOptions = ['3', '4', '5', '6', '7'];

const maxPayDays = 4;
const maxSources = 8;

/// Respuestas de una fuente. Todo es texto "crudo" ('' = no lo dijo), como en la web.
class IncomeSourceForm {
  const IncomeSourceForm({
    required this.kind,
    this.amount = '',
    this.low = '',
    this.high = '',
    this.payDays = const [],
    this.lastMonths = const ['', '', ''],
    this.workDays = '6',
    this.frequency = 'mensual',
  });

  /// Valores iniciales de cada tipo (emptyForm).
  factory IncomeSourceForm.empty(IncomeKind kind) => IncomeSourceForm(kind: kind);

  /// Lee una fuente del borrador sin confiar en su forma: lo que no sirve vuelve al valor inicial.
  static IncomeSourceForm? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = IncomeKind.parse(json['kind']);
    if (kind == null) return null;
    String text(Object? v) => v is String ? v : '';
    final payDays = json['payDays'] is List
        ? (json['payDays'] as List)
              .whereType<int>()
              .where((d) => d >= 1 && d <= 31)
              .toSet()
              .take(maxPayDays)
              .toList()
        : <int>[];
    payDays.sort();
    final months = json['lastMonths'] is List ? (json['lastMonths'] as List).map(text).toList() : <String>[];
    final workDays = text(json['workDays']);
    final frequency = text(json['frequency']);
    return IncomeSourceForm(
      kind: kind,
      amount: text(json['amount']),
      low: text(json['low']),
      high: text(json['high']),
      payDays: payDays,
      lastMonths: [for (var i = 0; i < 3; i++) i < months.length ? months[i] : ''],
      workDays: workDayOptions.contains(workDays) ? workDays : '6',
      frequency: mesadaFrequencies.containsKey(frequency) ? frequency : 'mensual',
    );
  }

  final IncomeKind kind;
  final String amount;
  final String low;
  final String high;
  final List<int> payDays;

  /// Este mes, hace 1 mes, hace 2 (solo proyectos).
  final List<String> lastMonths;
  final String workDays;
  final String frequency;

  IncomeSourceForm copyWith({
    String? amount,
    String? low,
    String? high,
    List<int>? payDays,
    List<String>? lastMonths,
    String? workDays,
    String? frequency,
  }) => IncomeSourceForm(
    kind: kind,
    amount: amount ?? this.amount,
    low: low ?? this.low,
    high: high ?? this.high,
    payDays: payDays ?? this.payDays,
    lastMonths: lastMonths ?? this.lastMonths,
    workDays: workDays ?? this.workDays,
    frequency: frequency ?? this.frequency,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'amount': amount,
    'low': low,
    'high': high,
    'payDays': payDays,
    'lastMonths': lastMonths,
    'workDays': workDays,
    'frequency': frequency,
  };

  /// Contrato de PUT /money-profile/sources (toApiSources de la web).
  Map<String, dynamic> toApi() {
    num? n(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return num.tryParse(t.endsWith('.') ? t.substring(0, t.length - 1) : t);
    }

    final usesAmount = kind != IncomeKind.proyectos;
    final usesRange = kind == IncomeKind.comisiones;
    final usesPayDays = kind == IncomeKind.sueldo || kind == IncomeKind.comisiones;
    return {
      'kind': kind.name,
      'frequency': switch (kind) {
        IncomeKind.mesada => frequency,
        IncomeKind.diario => 'diario',
        IncomeKind.proyectos => 'irregular',
        _ => 'mensual',
      },
      'payDays': usesPayDays ? payDays : <int>[],
      'amount': usesAmount ? n(amount) : null,
      'low': usesRange ? n(low) : null,
      'high': usesRange ? n(high) : null,
      // Como la web: los meses vacíos o en 0 no se envían.
      'lastMonths': kind == IncomeKind.proyectos
          ? lastMonths.map((m) => n(m) ?? 0).where((m) => m > 0).toList()
          : <num>[],
      'workDays': kind == IncomeKind.diario ? int.tryParse(workDays) : null,
    };
  }
}

/// Marca o desmarca una fuente. Desmarcar descarta lo escrito en ella (como en la web).
/// El orden es el de selección.
Map<IncomeKind, IncomeSourceForm> toggleKind(Map<IncomeKind, IncomeSourceForm> forms, IncomeKind kind) {
  final next = Map<IncomeKind, IncomeSourceForm>.of(forms);
  if (next.containsKey(kind)) {
    next.remove(kind);
  } else {
    next[kind] = IncomeSourceForm.empty(kind);
  }
  return next;
}

/// Agrega o quita un día de pago. Ordenados y máximo 4: el quinto no entra (la pantalla lo avisa).
List<int> togglePayDay(List<int> days, int day) {
  if (days.contains(day)) return [...days]..remove(day);
  if (days.length >= maxPayDays) return days;
  return [...days, day]..sort();
}
