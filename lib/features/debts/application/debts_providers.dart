import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../data/debt_models.dart';
import '../data/debts_repository.dart';

/// GET /debts de quien está dentro (una copia por cuenta, solo en memoria). Vigila el día: «Vence
/// mañana» y la cuota vencida se cuentan desde hoy.
final debtsProvider = perAccount<DebtsList>((ref) {
  ref.watch(todayProvider);
  return ref.watch(debtsRepositoryProvider).list();
});
