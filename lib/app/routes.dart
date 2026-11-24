/// Rutas de Rinde Mobile. Las de acceso usan los mismos nombres que Rinde Web.
abstract final class Routes {
  /// Mientras se lee la sesión guardada.
  static const boot = '/arranque';

  /// Primera pantalla sin sesión (en la web, el cierre de la landing).
  static const welcome = '/bienvenida';
  static const login = '/login';
  static const register = '/registro';
  static const forgot = '/recuperar';

  /// Dentro de la app (con sesión).
  static const app = '/app';

  /// Bienvenida completa (cuenta nueva) y solo las preguntas de plata (cuenta con movimientos).
  /// Las dos exigen sesión: están bajo /app.
  static const onboarding = '/app/bienvenida';
  static const onboardingQuestions = '/app/bienvenida/preguntas';

  // Destinos del Inicio y de la barra de pestañas. Mismos nombres que Rinde Web. Los que aún no
  // tienen pantalla propia muestran «En desarrollo» (ver app/pending_modules.dart).
  static const movements = '/app/movimientos';
  static const plan = '/app/planear';
  static const account = '/app/cuenta';
  static const record = '/app/anotar';
  static const recordExpense = '/app/anotar?tipo=gasto';
  static const recordIncome = '/app/anotar?tipo=ingreso';
  static const notifications = '/app/notificaciones';
  static const myMoney = '/app/mi-plata';
  static const payments = '/app/mi-plata/pagos';
  static const fixBalance = '/app/mi-plata/corregir';
  static const income = '/app/ingresos';
  static const expenses = '/app/gastos';
  static const toConfirm = '/app/por-confirmar';
  static const budgets = '/app/presupuestos';

  /// Detalle de un presupuesto: `/app/presupuestos/{categoría}?mes=AAAA-MM` (BudgetDetail.jsx).
  static String budget(String category, String month) =>
      '$budgets/${Uri.encodeComponent(category)}?mes=$month';
  static const goals = '/app/metas';
  static const vacas = '/app/vacas';
  static const cards = '/app/tarjetas';
  static String card(String id) => '/app/tarjetas/$id';

  // Accesos de «Más de tu plata» (MiPlata.jsx).
  static const calendar = '/app/calendario';
  static const debts = '/app/cuentas';
  static const insights = '/app/insights';
  static const export = '/app/transacciones/exportar';
  static const renta = '/app/renta';
  static const liquidity = '/app/liquidez';

  /// Detalle y edición de un movimiento (como la web).
  static String movement(String id) => '/app/transacciones/${Uri.encodeComponent(id)}';
  static String editMovement(String id) => '${movement(id)}/editar';
}
