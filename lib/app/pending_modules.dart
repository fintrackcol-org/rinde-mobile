import '../core/i18n/tr.dart';
import '../features/shell/presentation/rinde_tab_scaffold.dart';
import 'routes.dart';

/// Un destino que ya existe en Rinde Web y todavía no en la app: mientras tanto abre «En desarrollo»
/// (shell/presentation/pending_module_screen.dart). Al construirlo se quita de [pendingModules] y su
/// ruta pasa a router.dart.
class PendingModule {
  const PendingModule({required this.path, required this.title, required this.web, this.tab});

  /// Ruta de go_router, con los mismos nombres de la web.
  final String path;

  /// Título ya traducido. Recibe los parámetros `?…` con que se abrió.
  final String Function(Tr t, Map<String, String> query) title;

  /// Página de Rinde Web (frontend/src/pages/app) que hay que portar.
  final String web;

  /// Pestaña que ocupa; null si se abre encima de otra pantalla, con «Volver».
  final RindeTab? tab;
}

final pendingModules = <PendingModule>[
  PendingModule(path: Routes.notifications, title: (t, _) => t('Notificaciones'), web: 'Notifications.jsx'),
  PendingModule(path: Routes.income, title: (t, _) => t('Ingresos'), web: 'PeriodDetail.jsx (ingreso)'),
  PendingModule(path: Routes.expenses, title: (t, _) => t('Gastos'), web: 'PeriodDetail.jsx (gasto)'),
  PendingModule(path: Routes.toConfirm, title: (t, _) => t('Por confirmar'), web: 'PendingPayments.jsx'),
  // De Planear y del Calendario.
  PendingModule(path: Routes.goals, title: (t, _) => t('Metas'), web: 'Metas.jsx'),
  PendingModule(path: Routes.vacas, title: (t, _) => t('Vacas'), web: 'Vacas.jsx'),
  // Accesos de «Más de tu plata».
  PendingModule(path: Routes.insights, title: (t, _) => t('Consejos'), web: 'Insights.jsx'),
  PendingModule(path: Routes.export, title: (t, _) => t('Exportar movimientos'), web: 'Export.jsx'),
  PendingModule(path: Routes.renta, title: (t, _) => t('Renta y DIAN'), web: 'Renta.jsx'),
];
