import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/home/data/home_repository.dart';

import 'home_fixtures.dart';

/// Repositorio del Inicio con respuestas a la medida. Guarda cada llamada con sus argumentos.
class FakeHomeRepository implements HomeRepository {
  final calls = <String>[];

  Future<MoneyPlan> Function() onPlan = () async => planOf();
  Future<MonthTotals> Function(String date) onTotals = (date) async => totalsOf(month: date.substring(0, 7));
  Future<List<BudgetStatus>> Function() onBudgets = () async => const [];
  Future<List<CardSummary>> Function() onCards = () async => const [];
  Future<int> Function() onToConfirm = () async => 0;
  Future<int> Function() onUnread = () async => 0;
  Future<Map<String, String>> Function() onCategoryNames = () async => const {'vivienda': 'Vivienda'};
  Future<void> Function() onFinishTutorial = () async {};

  int count(String call) => calls.where((c) => c == call || c.startsWith('$call ')).length;

  @override
  bool get isDemo => false;

  @override
  Future<MoneyPlan> plan() {
    calls.add('plan');
    return onPlan();
  }

  @override
  Future<MonthTotals> monthTotals(String date) {
    calls.add('monthTotals $date');
    return onTotals(date);
  }

  @override
  Future<List<BudgetStatus>> budgets(String month) {
    calls.add('budgets $month');
    return onBudgets();
  }

  @override
  Future<List<CardSummary>> cards() {
    calls.add('cards');
    return onCards();
  }

  @override
  Future<int> toConfirm() {
    calls.add('toConfirm');
    return onToConfirm();
  }

  @override
  Future<int> unread() {
    calls.add('unread');
    return onUnread();
  }

  @override
  Future<Map<String, String>> categoryNames() {
    calls.add('categoryNames');
    return onCategoryNames();
  }

  @override
  Future<void> finishTutorial() {
    calls.add('finishTutorial');
    return onFinishTutorial();
  }
}
