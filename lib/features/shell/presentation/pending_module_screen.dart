import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/pending_modules.dart';
import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart';
import '../../onboarding/presentation/demo_panel.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import 'rinde_tab_scaffold.dart';

/// Pantalla de un destino que todavía no está en la app: lo dice sin rodeos, sin datos de mentira
/// ni acciones que no hacen nada. Las pestañas llevan la barra; las demás, «Volver».
class PendingModuleScreen extends ConsumerWidget {
  const PendingModuleScreen(this.module, {super.key, this.query = const {}});

  final PendingModule module;
  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final tab = module.tab;

    Widget body(double bottom) => Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, bottom),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: RindeSpace.authColumn),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RindeIconTile(RindeIcons.construction, tone: p.brand),
              const SizedBox(height: RindeSpace.s4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.brandSoft,
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s1),
                  child: Text(
                    t('En desarrollo'),
                    textAlign: TextAlign.center,
                    style: RindeType.label.copyWith(color: p.brand),
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s3),
              Semantics(
                header: true,
                child: Text(
                  module.title(t, query),
                  textAlign: TextAlign.center,
                  style: RindeType.headline.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s2),
              Text(
                t(
                  'Esta parte todavía no está en la app. Ya funciona en la web de Rinde, con tu misma cuenta.',
                ),
                textAlign: TextAlign.center,
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              // Sin la pantalla de cuenta no habría cómo salir ni repetir el tutorial.
              if (tab == RindeTab.account) ...[
                const SizedBox(height: RindeSpace.s8),
                const _AccountActions(),
              ],
            ],
          ),
        ),
      ),
    );

    if (tab != null) {
      return RindeTabScaffold(current: tab, child: body(RindeTabScaffold.bottomInset(context)));
    }
    final demo = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.demo ?? false));
    void back() => context.canPop() ? context.pop() : context.go(Routes.app);
    return PopScope(
      // Abierta sin pantalla anterior (un enlace directo): atrás lleva al Inicio, no cierra la app.
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.app);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: p.canvas,
          body: Column(
            children: [
              // También aquí se dice que es una demostración.
              if (demo) DemoStrip(onTap: () => showDemoPanel(context)),
              Expanded(
                child: SafeArea(
                  top: !demo,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RindeSpace.s1, RindeSpace.s2, RindeSpace.s1, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: IconButton(
                            onPressed: back,
                            tooltip: t('Volver'),
                            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                            icon: RindeIcon(RindeIcons.chevronLeft, size: 24, color: p.ink),
                          ),
                        ),
                      ),
                      Expanded(child: body(RindeSpace.s6)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo único de «Yo» que no puede esperar a la pantalla de cuenta.
class _AccountActions extends ConsumerStatefulWidget {
  const _AccountActions();

  @override
  ConsumerState<_AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends ConsumerState<_AccountActions> {
  bool _leaving = false;

  Future<void> _signOut() async {
    // Avisar al servidor puede tardar unos segundos si está dormido.
    setState(() => _leaving = true);
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RindeButton(
          label: t('Ver el tutorial otra vez'),
          variant: RindeButtonVariant.outline,
          onPressed: _leaving
              ? null
              : () {
                  ref.read(tourRequestedProvider.notifier).request();
                  context.go(Routes.app);
                },
        ),
        const SizedBox(height: RindeSpace.s3),
        RindeButton(
          label: t('Cerrar sesión'),
          variant: RindeButtonVariant.ghost,
          loading: _leaving,
          onPressed: _signOut,
        ),
      ],
    );
  }
}
