/// Movimientos (transacciones) con el contrato de `/api/v1/transactions` y `/api/v1/categories`
/// de Rinde Web. Solo leen y escriben: los importes y la categoría final los decide el servidor.
library;

import 'dart:convert';

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readMap, readMoney;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

enum MovementType {
  income('ingreso'),
  expense('gasto');

  const MovementType(this.wire);

  /// Como viaja en la API.
  final String wire;

  static MovementType? fromWire(Object? value) => switch (value) {
    'ingreso' => income,
    'gasto' => expense,
    _ => null,
  };
}

/// Tarjeta con la que se pagó un gasto (`card` de la API). `deleted`: la tarjeta se borró después.
class MovementCard {
  const MovementCard({required this.id, required this.name, required this.last4, required this.deleted});

  final String id;
  final String name;
  final String last4;
  final bool deleted;

  static MovementCard? tryParse(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return MovementCard(
      id: raw['id'] as String,
      name: raw['name'] is String ? raw['name'] as String : '',
      last4: raw['last4'] is String ? raw['last4'] as String : '',
      deleted: raw['deleted'] == true,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'last4': last4, 'deleted': deleted};
}

/// Anotado en otra moneda: lo pagado allá y la tasa. El monto del movimiento lo calcula el servidor.
class OriginalAmount {
  const OriginalAmount({required this.currency, required this.amount, required this.rate});

  final String currency;
  final num amount;
  final num rate;

  static OriginalAmount? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final amount = readMoney(raw['amount']);
    final rate = raw['rate'];
    if (raw['currency'] is! String || amount == null || rate is! num || !rate.isFinite) return null;
    return OriginalAmount(currency: raw['currency'] as String, amount: amount, rate: rate);
  }

  Map<String, dynamic> toJson() => {'currency': currency, 'amount': amount, 'rate': rate};

  @override
  bool operator ==(Object other) =>
      other is OriginalAmount && other.currency == currency && other.amount == amount && other.rate == rate;

  @override
  int get hashCode => Object.hash(currency, amount, rate);
}

class Movement {
  const Movement({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.source,
    required this.date,
    this.localId,
    this.category,
    this.createdAt,
    this.updatedAt,
    this.pending = false,
    this.deleted = false,
    this.card,
    this.installments,
    this.emotion,
    this.kakeibo,
    this.original,
  });

  /// Lee un movimiento de la API. Lo que no cuadra con el contrato es [ContractException].
  factory Movement.fromJson(Object? data) {
    final json = readMap(data);
    final id = json['id'];
    final type = MovementType.fromWire(json['type']);
    final amount = readMoney(json['amount']);
    final description = json['description'];
    final category = json['category'];
    final source = json['source'];
    final date = json['date'];
    if (id is! String || id.isEmpty) throw const ContractException('Falta "id"');
    if (type == null) throw const ContractException('"type" no es ingreso ni gasto');
    if (amount == null) throw const ContractException('Falta "amount" o no es un número');
    if (description is! String) throw const ContractException('Falta "description"');
    if (category != null && category is! String) throw const ContractException('"category" no es texto');
    if (source is! String) throw const ContractException('Falta "source"');
    if (date is! String || !_isoDate.hasMatch(date)) throw const ContractException('Falta "date"');
    final installments = json['installments'];
    return Movement(
      id: id,
      localId: json['localId'] is String ? json['localId'] as String : null,
      type: type,
      amount: amount,
      description: description,
      category: category as String?,
      source: source,
      date: date,
      createdAt: _time(json['createdAt']),
      updatedAt: _time(json['updatedAt']),
      // Un reintento con el localId de uno ya borrado lo devuelve con `deletedAt`, sin revivirlo.
      deleted: json['deletedAt'] != null,
      card: MovementCard.tryParse(json['card']),
      installments: installments is int ? installments : null,
      emotion: json['emotion'] is String ? json['emotion'] as String : null,
      kakeibo: json['kakeibo'] is String ? json['kakeibo'] as String : null,
      original: OriginalAmount.tryParse(json['original']),
    );
  }

  final String id;

  /// El que mandó este teléfono al crearlo (solo se conoce en los pendientes y en la demo).
  final String? localId;
  final MovementType type;

  /// Siempre positivo; el signo lo da [type].
  final num amount;
  final String description;

  /// Clave de la categoría, o null si quedó sin clasificar.
  final String? category;

  /// `manual`, `ia` o `sin_clasificar`. Vacío en un pendiente: lo decide el servidor al recibirlo.
  final String source;

  /// AAAA-MM-DD.
  final String date;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Guardado solo en el teléfono: el servidor todavía no lo confirmó.
  final bool pending;

  /// El servidor ya lo había borrado (respuesta a un reintento).
  final bool deleted;
  final MovementCard? card;
  final int? installments;
  final String? emotion;
  final String? kakeibo;
  final OriginalAmount? original;

  bool get isIncome => type == MovementType.income;

  /// La misma forma del servidor (la usa la demostración para guardar).
  Map<String, dynamic> toJson() => {
    'id': id,
    'localId': localId,
    'type': type.wire,
    'amount': amount,
    'description': description,
    'category': category,
    'source': source,
    'date': date,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'deletedAt': null,
    'card': card?.toJson(),
    'installments': installments,
    'emotion': emotion,
    'kakeibo': kakeibo,
    'original': original?.toJson(),
  };
}

DateTime? _time(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

/// Lo que manda el formulario (Anotar o editar).
class MovementInput {
  const MovementInput({
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
    this.category,
    this.card,
    this.installments,
    this.emotion,
    this.kakeibo,
    this.original,
  });

  factory MovementInput.fromJson(Object? data) {
    final json = readMap(data);
    final type = MovementType.fromWire(json['type']);
    final amount = readMoney(json['amount']);
    final date = json['date'];
    if (type == null || amount == null || json['description'] is! String || date is! String) {
      throw const ContractException('Movimiento guardado ilegible');
    }
    final installments = json['installments'];
    return MovementInput(
      type: type,
      amount: amount,
      description: json['description'] as String,
      date: date,
      category: json['category'] is String ? json['category'] as String : null,
      card: json['card'] is String ? json['card'] as String : null,
      installments: installments is int ? installments : null,
      emotion: json['emotion'] is String ? json['emotion'] as String : null,
      kakeibo: json['kakeibo'] is String ? json['kakeibo'] as String : null,
      original: OriginalAmount.tryParse(json['original']),
    );
  }

  final MovementType type;

  /// En la moneda principal. Con [original], el servidor lo reemplaza por monto × tasa.
  final num amount;
  final String description;

  /// AAAA-MM-DD. El servidor rechaza fechas futuras.
  final String date;

  /// null: la categoriza el servidor (IA o sin clasificar).
  final String? category;

  /// Id de la tarjeta (solo gastos).
  final String? card;

  /// 1 a 48, solo con tarjeta.
  final int? installments;
  final String? emotion;
  final String? kakeibo;
  final OriginalAmount? original;

  /// Cuerpo de PUT con solo lo que cambió respecto a [saved] (changedFields de la web).
  Map<String, dynamic> changesFrom(Movement saved) {
    final before = MovementInput(
      type: saved.type,
      amount: saved.amount,
      description: saved.description,
      date: saved.date,
      category: saved.category,
      card: saved.card == null || saved.card!.deleted ? null : saved.card!.id,
      installments: saved.installments,
      emotion: saved.emotion,
      kakeibo: saved.kakeibo,
      original: saved.original,
    ).toJson(update: true);
    final now = toJson(update: true);
    return {
      for (final MapEntry(:key, :value) in now.entries)
        if (jsonEncode(value) != jsonEncode(before[key])) key: value,
    };
  }

  /// Cuerpo de POST (sin nulos opcionales) o de PUT (`update: true`: el estado completo, con null
  /// para quitar tarjeta, emoción, Kakeibo u otra moneda).
  Map<String, dynamic> toJson({bool update = false}) => {
    'type': type.wire,
    'amount': amount,
    'description': description,
    'date': date,
    'category': category,
    if (update || card != null) 'card': card,
    'installments': ?installments,
    if (update || emotion != null) 'emotion': emotion,
    if (update || kakeibo != null) 'kakeibo': kakeibo,
    if (update || original != null) 'original': original?.toJson(),
  };
}

/// Filtros del listado (GET /transactions). Igualdad por valor.
class MovementQuery {
  const MovementQuery({
    this.type,
    this.category,
    this.from,
    this.to,
    this.search,
    this.page = 1,
    this.pageSize = 20,
  });

  final MovementType? type;
  final String? category;

  /// AAAA-MM-DD, inclusive.
  final String? from;
  final String? to;

  /// Busca en la descripción (`q`, 1 a 100 caracteres).
  final String? search;
  final int page;

  /// 1 a 100 (el servidor usa 20 por defecto).
  final int pageSize;

  /// Parámetros de la URL; los vacíos no viajan, como `listTransactions` de la web.
  Map<String, dynamic> toParams({int? page}) {
    final q = search?.trim();
    return {
      'type': ?type?.wire,
      if (category case final c? when c.isNotEmpty) 'category': c,
      if (from case final f? when f.isNotEmpty) 'from': f,
      if (to case final t? when t.isNotEmpty) 'to': t,
      if (q != null && q.isNotEmpty) 'q': q,
      'page': page ?? this.page,
      'pageSize': pageSize,
    };
  }

  /// Si un pendiente (aún sin servidor) cabe en estos filtros, para mostrarlo en la lista.
  bool matches(MovementInput input) {
    final q = search?.trim().toLowerCase();
    return (type == null || input.type == type) &&
        (category == null || category!.isEmpty || input.category == category) &&
        (from == null || from!.isEmpty || input.date.compareTo(from!) >= 0) &&
        (to == null || to!.isEmpty || input.date.compareTo(to!) <= 0) &&
        (q == null || q.isEmpty || input.description.toLowerCase().contains(q));
  }

  @override
  bool operator ==(Object other) =>
      other is MovementQuery &&
      other.type == type &&
      other.category == category &&
      other.from == from &&
      other.to == to &&
      other.search == search &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(type, category, from, to, search, page, pageSize);
}

/// Una página del listado: `{ data, page, pageSize, total }`.
class MovementPage {
  const MovementPage({required this.items, required this.page, required this.pageSize, required this.total});

  factory MovementPage.fromJson(Object? data) {
    final json = readMap(data);
    final list = json['data'];
    final page = json['page'];
    final pageSize = json['pageSize'];
    final total = json['total'];
    if (list is! List) throw const ContractException('Falta "data"');
    if (page is! int || pageSize is! int || total is! int) {
      throw const ContractException('Falta "page", "pageSize" o "total"');
    }
    // Estricto: una fila ilegible falla toda la página en vez de esconder un movimiento.
    return MovementPage(
      items: [for (final item in list) Movement.fromJson(item)],
      page: page,
      pageSize: pageSize,
      total: total,
    );
  }

  final List<Movement> items;
  final int page;
  final int pageSize;

  /// Todos los movimientos que cumplen los filtros, no solo esta página.
  final int total;

  bool get hasMore => page * pageSize < total;
}

class CategoryOption {
  const CategoryOption({required this.key, required this.name, this.icon, this.color, this.custom = false});

  static CategoryOption? tryParse(Object? raw) {
    if (raw is! Map || raw['key'] is! String || raw['name'] is! String) return null;
    return CategoryOption(
      key: raw['key'] as String,
      name: raw['name'] as String,
      icon: raw['icon'] is String ? raw['icon'] as String : null,
      color: raw['color'] is String ? raw['color'] as String : null,
      custom: raw['custom'] == true,
    );
  }

  final String key;

  /// Ya traducido por el servidor (las propias, como las escribió la persona).
  final String name;

  /// Solo las propias.
  final String? icon;
  final String? color;
  final bool custom;
}

/// GET /categories. El tipo lo da la lista en que viene.
class CategoryLists {
  const CategoryLists({required this.expense, required this.income});

  factory CategoryLists.fromJson(Object? data) {
    final json = readMap(data);
    List<CategoryOption> read(String key) {
      final list = json[key];
      if (list is! List) throw ContractException('Falta "$key"');
      return _sorted([for (final c in list) ?CategoryOption.tryParse(c)]);
    }

    return CategoryLists(expense: read('expense'), income: read('income'));
  }

  final List<CategoryOption> expense;
  final List<CategoryOption> income;

  List<CategoryOption> of(MovementType type) => type == MovementType.income ? income : expense;

  /// Clave → nombre, de los dos tipos.
  Map<String, String> get names => {
    for (final c in [...expense, ...income]) c.key: c.name,
  };
}

const _catchAll = {'otros', 'otros_ingresos'};

/// sortCategories de la web: «Otros» y «Otros ingresos» al final, el resto como vino.
List<CategoryOption> _sorted(List<CategoryOption> list) => [
  ...list.where((c) => !_catchAll.contains(c.key)),
  ...list.where((c) => _catchAll.contains(c.key)),
];
