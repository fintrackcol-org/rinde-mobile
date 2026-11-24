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
  // De Planear y del Calendario.
  PendingModule(path: Routes.goals, title: (t, _) => t('Metas'), web: 'Metas.jsx'),
  PendingModule(path: Routes.vacas, title: (t, _) => t('Vacas'), web: 'Vacas.jsx'),
];
