// La hoja de presupuestos mientras se elimina (no se cierra ni guarda) y «Presupuesto creado» cuando
// la relectura del mes falla (el presupuesto ya quedó: sin aviso y sin error suelto).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rinde_mobile/core/config/app_config.dart';
import 'package:rinde_mobile/core/storage/session_storage.dart';
import 'package:rinde_mobile/design/theme/rinde_theme.dart';
import 'package:rinde_mobile/design/widgets/rinde_button.dart';
import 'package:rinde_mobile/features/home/application/home_providers.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/movements/application/movements_controller.dart';
import 'package:rinde_mobile/features/movements/domain/movement.dart';
import 'package:rinde_mobile/features/plan/application/budgets_writer.dart';
import 'package:rinde_mobile/features/plan/application/plan_providers.dart';
import 'package:rinde_mobile/features/plan/presentation/budgets_screen.dart';
import 'package:rinde_mobile/features/plan/presentation/widgets/budget_sheet.dart';

const _food = BudgetStatus(
  id: 'p1',
  category: 'alimentacion',
  amount: 200000,
  consumed: 0,
  percentage: 0,
  level: BudgetLevel.none,
);

class _Writer extends BudgetsWriter {
  _Writer(this.ref) : super(ref);
  final Ref ref;
  final deleting = Completer<void>();
  final sent = <String>[];

  @override
  Future<void> delete(BudgetStatus budget, String month) {
    sent.add('DELETE ${budget.id}');
    return deleting.future;
  }

  @override
  Future<void> update(BudgetStatus budget, String month, num amount) async => sent.add('PUT ${budget.id}');

  @override
  Future<void> create({required String category, required String month, required num amount}) async {
    sent.add('POST $category');
    ref.invalidate(budgetsMonthProvider);
  }
}

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // PushedFrame necesita el router.
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => home)],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: '', environment: 'local')),
        sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 10)),
        movementCategoriesProvider.overrideWith(
          (ref, _) async => const CategoryLists(
            expense: [
              CategoryOption(key: 'alimentacion', name: 'Alimentación'),
              CategoryOption(key: 'ocio', name: 'Ocio'),
            ],
            income: [],
          ),
        ),
        homeCategoryNamesProvider.overrideWith((ref, _) async => const {'ocio': 'Ocio'}),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: RindeTheme.light,
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mientras se elimina, atrás no cierra la hoja y «Guardar límite» no responde', (tester) async {
    late _Writer writer;
    BudgetSheetResult? result;
    var closed = false;
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showBudgetSheet(context, month: '2026-11', initial: _food, canDelete: true);
              closed = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
      [budgetsWriterProvider.overrideWith((ref) => writer = _Writer(ref))],
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar presupuesto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, eliminar'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(closed, isFalse);
    expect(tester.widget<RindeButton>(find.widgetWithText(RindeButton, 'Guardar límite')).onPressed, isNull);

    writer.deleting.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, BudgetSheetResult.deleted);
    expect(writer.sent, ['DELETE p1']);
  });

  testWidgets('creado y la relectura del mes falla: sin aviso y sin error suelto', (tester) async {
    var reads = 0;
    await _pump(tester, const BudgetsScreen(), [
      budgetsWriterProvider.overrideWith(_Writer.new),
      budgetsMonthProvider.overrideWith((ref, _) async {
        if (reads++ > 0) throw StateError('sin red');
        return const [_food];
      }),
    ]);
    await tester.tap(find.text('Nuevo presupuesto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocio'));
    await tester.enterText(find.byType(EditableText), '50000');
    await tester.tap(find.text('Crear presupuesto'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('creado'), findsNothing);
  });
}
