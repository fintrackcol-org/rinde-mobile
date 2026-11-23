import 'package:rinde_mobile/core/network/api_exception.dart';
import 'package:rinde_mobile/features/home/data/home_models.dart';
import 'package:rinde_mobile/features/onboarding/data/onboarding_repository.dart';

/// Datos de ejemplo del Inicio para las pruebas: los mismos de MobileHome.test.jsx y
/// homeNotice.test.js de Rinde Web, para que los casos portados se lean igual.

const offlineError = ApiException(code: ApiCodes.network);
const serverError = ApiException(code: 'INTERNAL_ERROR', status: 500);

const pendingPayments = [
  PendingPayment(id: 'pila', name: 'PILA', amount: 228000, date: '2026-11-13'),
  PendingPayment(id: 'cel', name: 'Plan celular', amount: 45000, date: '2026-11-15'),
  PendingPayment(id: 'visa', name: 'Visa', amount: 180000, date: '2026-11-25'),
];

MoneyPlan planOf({
  num money = 412300,
  num pendingTotal = 273000,
  num free = 139300,
  num shortfall = 0,
  List<PendingPayment> pending = pendingPayments,
}) => MoneyPlan(
  money: money,
  pendingTotal: pendingTotal,
  free: free,
  shortfall: shortfall,
  mode: 'daily',
  perDay: 13900,
  nextPay: '2026-11-30',
  pending: pending,
);

WelcomeStatus statusOf({
  bool welcomeDone = true,
  bool tutorialDone = true,
  bool hasTransactions = true,
  num? money = 412300,
  bool balanceSet = true,
}) => WelcomeStatus(
  welcomeDone: welcomeDone,
  tutorialDone: tutorialDone,
  hasTransactions: hasTransactions,
  money: money,
  balanceSet: balanceSet,
);

MonthTotals totalsOf({String month = '2026-11', num income = 700000, num expense = 287700}) =>
    MonthTotals(month: month, income: income, expense: expense);

CardSummary cardOf(int daysToPayment, {String id = '7', num used = 320000, bool paid = false}) => CardSummary(
  id: id,
  name: 'Mi Visa',
  network: 'visa',
  last4: '4242',
  used: used,
  daysToPayment: daysToPayment,
  paidThisCycle: paid,
);

BudgetStatus budgetOf(
  BudgetLevel level, {
  num? percentage,
  String category = 'vivienda',
  num amount = 450000,
  num consumed = 400000,
}) => BudgetStatus(
  category: category,
  amount: amount,
  consumed: consumed,
  percentage: percentage ?? (level == BudgetLevel.exceeded ? 120 : 89),
  level: level,
);
