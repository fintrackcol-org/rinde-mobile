import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/features/movements/data/demo_movements_repository.dart';
import 'package:rinde_mobile/features/movements/data/json_list_store.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';

// Integración de la etapa 3: editar manda solo lo que cambió, y lo anotado en la demo suma en el mes.

Movement _saved({String? category = 'transporte', String source = 'ia'}) => Movement(
  id: 't1',
  type: MovementType.expense,
  amount: 12000,
  description: 'Taxi',
  source: source,
  date: '2026-11-20',
  category: category,
);

void main() {
  test('editar solo la descripción no reenvía la categoría (se conserva «sugerida por la IA»)', () {
    const input = MovementInput(
      type: MovementType.expense,
      amount: 12000,
      description: 'Taxi al aeropuerto',
      date: '2026-11-20',
      category: 'transporte',
    );
    expect(input.changesFrom(_saved()), {'description': 'Taxi al aeropuerto'});
  });

  test('cambiar la categoría sí la envía, y nada más', () {
    const input = MovementInput(
      type: MovementType.expense,
      amount: 12000,
      description: 'Taxi',
      date: '2026-11-20',
      category: 'otros',
    );
    expect(input.changesFrom(_saved()), {'category': 'otros'});
  });

  test('la demo suma lo anotado del mes; lo apartado no es gasto y otro mes no cuenta', () async {
    final store = MemoryJsonListStore();
    Map<String, Object?> row(String id, String type, num amount, String date, String? category) => {
      'id': id,
      'type': type,
      'amount': amount,
      'description': 'x',
      'category': category,
      'source': 'manual',
      'date': date,
    };
    await store.write('demo-nuevo', [
      row('a', 'gasto', 12000.5, '2026-11-20', 'transporte'),
      row('b', 'ingreso', 50000, '2026-11-02', 'salario'),
      row('c', 'gasto', 100000, '2026-11-03', 'ahorro_inversion'),
      row('d', 'gasto', 9000, '2026-10-30', 'transporte'),
    ]);
    final totals = await demoMovementTotals(store, 'demo-nuevo', '2026-11-22');
    expect((totals.month, totals.income, totals.expense), ('2026-11', 50000, 12000.5));
    expect(await demoHasMovements(store, 'demo-nuevo'), isTrue);
    expect(await demoHasMovements(store, 'otro'), isFalse);
  });
}
