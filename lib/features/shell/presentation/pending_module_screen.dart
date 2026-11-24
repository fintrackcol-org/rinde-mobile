import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/pending_modules.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import 'pushed_frame.dart';
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
            ],
          ),
        ),
      ),
    );

    if (tab != null) {
      return RindeTabScaffold(current: tab, child: body(RindeTabScaffold.bottomInset(context)));
    }
    return PushedFrame(child: body(RindeSpace.s6));
  }
}
