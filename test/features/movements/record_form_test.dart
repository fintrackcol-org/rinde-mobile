import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/movements/presentation/record/movement_form.dart';

const _t = Tr('es', {});

Map<String, String> _problems({
  MovementType type = MovementType.expense,
  num? amount = 1000,
  String description = 'Almuerzo',
  String date = '2026-11-22',
  bool editing = false,
  String? savedDate,
}) => movementProblems(
  _t,
  type: type,
  amount: amount,
  description: description,
  date: date,
  today: '2026-11-22',
  editing: editing,
  savedDate: savedDate,
);

const _saved = Movement(
  id: 'id-1',
  type: MovementType.expense,
  amount: 50000,
  description: 'Mercado',
  source: 'ia',
  date: '2026-11-20',
  category: 'alimentacion',
  card: MovementCard(id: 'card-1', name: 'Visa', last4: '1234', deleted: true),
  installments: 3,
  emotion: 'normal',
  kakeibo: 'necesidad',
  original: OriginalAmount(currency: 'USD', amount: 12.5, rate: 4000),
);

void main() {
  group('movementProblems: los textos de la web', () {
    test('Anotar: sin monto y sin descripción, por tipo', () {
      expect(_problems(amount: null, description: ' '), {
        'amount': 'Escribe cuánto gastaste.',
        'description': 'Escribe en qué fue, p. ej. «almuerzo».',
      });
      expect(_problems(type: MovementType.income, amount: 0, description: ''), {
        'amount': 'Escribe cuánto te entró.',
        'description': 'Escribe de qué fue, p. ej. «salario».',
      });
    });

    test('editar: los de TransactionForm', () {
      expect(_problems(amount: null, description: '', editing: true), {
        'amount': 'Ingresa un monto válido',
        'description': 'Escribe una descripción',
      });
      expect(_problems(amount: 0, editing: true)['amount'], 'El monto debe ser mayor que 0');
    });

    test('tope del servidor y fecha futura', () {
      expect(_problems(amount: 9999999999.99), isEmpty);
      expect(_problems(amount: 10000000000)['amount'], 'El monto es demasiado grande');
      expect(_problems(date: '2026-11-23')['date'], 'No puedes anotar un movimiento en el futuro');
      // Un movimiento viejo con fecha futura se puede seguir corrigiendo si no se toca la fecha.
      expect(_problems(date: '2026-12-01', editing: true, savedDate: '2026-12-01'), isEmpty);
    });
  });

  test('needsBigConfirm: desde 5 millones y, al editar, solo si cambió', () {
    expect(needsBigConfirm(4999999), isFalse);
    expect(needsBigConfirm(5000000), isTrue);
    expect(needsBigConfirm(6000000, before: 6000000), isFalse);
    expect(needsBigConfirm(6000000, before: 5000000), isTrue);
  });

  group('editedInput', () {
    MovementInput? edit({
      MovementType type = MovementType.expense,
      num amount = 50000,
      String description = 'Mercado',
      String date = '2026-11-20',
      String? category = 'alimentacion',
    }) => editedInput(
      _saved,
      type: type,
      amount: amount,
      description: description,
      date: date,
      category: category,
    );

    test('sin cambios no hay nada que mandar (espacios al final no cuentan)', () {
      expect(edit(), isNull);
      expect(edit(description: 'Mercado  '), isNull);
    });

    test('conserva lo que el formulario no muestra', () {
      final body = edit(description: 'Mercado grande')!.toJson(update: true);
      expect(body['description'], 'Mercado grande');
      expect(body['card'], 'card-1');
      expect(body['installments'], 3);
      expect(body['emotion'], 'normal');
      expect(body['kakeibo'], 'necesidad');
      expect(body['original'], {'currency': 'USD', 'amount': 12.5, 'rate': 4000});
    });

    test('cambiar el monto quita la otra moneda; pasar a ingreso quita tarjeta y reflexión', () {
      expect(edit(amount: 60000)!.toJson(update: true)['original'], isNull);
      final income = edit(type: MovementType.income, category: null)!.toJson(update: true);
      expect(income['card'], isNull);
      expect(income.containsKey('installments'), isFalse);
      expect(income['emotion'], isNull);
      expect(income['kakeibo'], isNull);
      expect(income['category'], isNull);
    });
  });
}
