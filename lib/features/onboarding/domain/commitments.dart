/// Pagos de cada mes de la bienvenida (lib/moneyProfile.js y Welcome.jsx de Rinde Web).
///
/// Son para PLANEAR: se apartan antes de decir cuánto se puede gastar. No crean movimientos.
library;

import 'dart:math';

import '../../../core/region/money_text.dart';

/// Sugerencias, en este orden. Son claves de traducción: el nombre se guarda en el idioma de la
/// interfaz (en inglés, «Rent»), igual que en la web.
const suggestedCommitments = ['Arriendo', 'Internet', 'Celular', 'Transporte', 'Universidad', 'Cuota'];

const commitmentNameMax = 60;

/// Corta al tope sin partir un emoji por la mitad (dejaría un carácter inválido).
String clipCommitmentName(String name) {
  if (name.length <= commitmentNameMax) return name;
  final cut = name.substring(0, commitmentNameMax);
  final last = cut.codeUnitAt(cut.length - 1);
  return last >= 0xD800 && last <= 0xDBFF ? cut.substring(0, cut.length - 1) : cut;
}

/// Tope del servidor por bienvenida (MAX_COMMITMENTS). La web no lo avisa y responde 422.
const maxCommitments = 30;

class CommitmentItem {
  const CommitmentItem({
    required this.key,
    required this.name,
    this.amount = '',
    this.dayOfMonth = '',
    this.custom = false,
  });

  factory CommitmentItem.create(String name, {bool custom = false}) =>
      CommitmentItem(key: _newKey(), name: name, custom: custom);

  static CommitmentItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    if (key is! String || key.isEmpty) return null;
    String text(Object? v) => v is String ? v : '';
    final name = text(json['name']);
    return CommitmentItem(
      key: key,
      name: clipCommitmentName(name),
      amount: text(json['amount']),
      dayOfMonth: text(json['dayOfMonth']).replaceAll(RegExp(r'\D'), ''),
      custom: json['custom'] == true,
    );
  }

  final String key;
  final String name;

  /// Monto crudo ("250000" o "12.5").
  final String amount;

  /// Día del mes como texto (solo dígitos).
  final String dayOfMonth;

  /// Lo agregó con «Otro»: el nombre se puede editar.
  final bool custom;

  CommitmentItem copyWith({String? name, String? amount, String? dayOfMonth}) => CommitmentItem(
    key: key,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    custom: custom,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'amount': amount,
    'dayOfMonth': dayOfMonth,
    'custom': custom,
  };
}

/// Mensaje de error de un pago, como clave en español + variables (se traduce al mostrarlo).
class CommitmentProblem {
  const CommitmentProblem(this.key, this.message, [this.vars = const {}]);
  final String key;
  final String message;
  final Map<String, Object> vars;
}

/// Revisa un pago antes de enviar (readCommitmentForm de la web, mismos textos y orden).
/// Devuelve el cuerpo para el servidor o el problema.
({Map<String, dynamic>? data, CommitmentProblem? problem}) readCommitment(CommitmentItem item) {
  final name = item.name.trim();
  if (name.isEmpty) return (data: null, problem: CommitmentProblem(item.key, 'Escribe el nombre del pago.'));
  final amount = moneyValue(item.amount) ?? 0;
  if (!(amount > 0)) {
    return (
      data: null,
      problem: CommitmentProblem(item.key, 'Escribe cuánto pagas por {cleanName}.', {'cleanName': name}),
    );
  }
  final day = int.tryParse(item.dayOfMonth);
  if (day == null || day < 1 || day > 31) {
    return (
      data: null,
      problem: CommitmentProblem(item.key, 'Escribe un día entre 1 y 31 para {cleanName}.', {
        'cleanName': name,
      }),
    );
  }
  return (
    data: {
      'name': name,
      'amount': amount,
      'dayOfMonth': day,
      'kind': 'fixed',
      'frequency': 'monthly',
      'month': null,
    },
    problem: null,
  );
}

/// Revisa todos. Además del orden de la web, avisa los nombres repetidos: el servidor guarda solo el
/// primero sin decir nada (ON CONFLICT por nombre, sin importar mayúsculas).
({List<Map<String, dynamic>> commitments, CommitmentProblem? problem}) readCommitments(
  List<CommitmentItem> items,
) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final item in items) {
    final read = readCommitment(item);
    if (read.problem != null) return (commitments: const [], problem: read.problem);
    final lower = (read.data!['name'] as String).toLowerCase();
    if (!seen.add(lower)) {
      // TEXTO NUEVO: la web no lo avisa (el servidor descarta el repetido en silencio).
      return (
        commitments: const [],
        problem: CommitmentProblem(item.key, 'Ya agregaste {name}. Cambia el nombre o quítalo.', {
          'name': read.data!['name'] as Object,
        }),
      );
    }
    out.add(read.data!);
  }
  return (commitments: out, problem: null);
}

String _newKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
