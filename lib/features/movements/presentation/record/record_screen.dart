import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../auth/application/session_controller.dart';
import '../../../onboarding/presentation/demo_panel.dart';
import '../../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../../application/movement_saver.dart';
import '../../application/movements_controller.dart';
import '../../domain/movement.dart';
import 'movement_form.dart';

/// Aviso corto al guardar uno nuevo (savedMessage de TransactionEdit.jsx).
String savedMessage(Tr t, Movement saved, Map<String, String> names) {
  if (saved.pending) return t('Guardado sin conexión. Se sincronizará cuando vuelva internet.');
  if (saved.source == 'sin_clasificar') {
    return t(
      'Guardado sin clasificar: no pudimos sugerir una categoría. Puedes elegirla editando el movimiento.',
    );
  }
  final key = saved.category;
  if (key == null) return t(saved.isIncome ? 'Ingreso guardado' : 'Gasto guardado');
  final name = names[key] ?? key;
  return saved.source == 'ia'
      ? t('Guardado en {name} (sugerida por IA).', {'name': name})
      : t('Guardado en {name}.', {'name': name});
}

/// `/app/anotar?tipo=ingreso|gasto` (Anotar.jsx): anotar un movimiento nuevo.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key, this.initialType = MovementType.expense});

  final MovementType initialType;

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  // Uno por borrador: cada reintento del mismo formulario lo repite y el servidor no lo duplica.
  final _localId = MovementSaver.newLocalId();
  late MovementType _type = widget.initialType;

  Future<String?> _save(MovementInput input, Movement? _) async {
    final saved = await ref.read(movementSaverProvider).create(input, localId: _localId);
    final t = ref.read(trProvider);
    final names = ref.read(movementCategoriesProvider(ref.read(accountProvider))).value?.names ?? const {};
    return savedMessage(t, saved, {for (final e in names.entries) e.key: t(e.value)});
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    return _PushedFrame(
      title: t(_type == MovementType.income ? 'Anotar un ingreso' : 'Anotar un gasto'),
      closeLabel: t('Cerrar sin anotar'),
      child: MovementForm(
        initialType: widget.initialType,
        onSave: _save,
        onTypeChanged: (type) => setState(() => _type = type),
      ),
    );
  }
}

/// `/app/transacciones/:id/editar` (TransactionEdit.jsx): el mismo formulario con lo guardado.
class EditMovementScreen extends ConsumerWidget {
  const EditMovementScreen({super.key, required this.movementId});

  final String movementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final key = (ref.watch(accountProvider), movementId);
    final movement = ref.watch(movementDetailProvider(key));
    final p = context.palette;

    final Widget body;
    if (movement.value case final m?) {
      body = MovementForm(
        initial: m,
        onSave: (input, opened) async {
          await ref.read(movementSaverProvider).update(m.id, input, from: opened ?? m);
          return t('Cambios guardados.');
        },
      );
    } else if (movement.hasError) {
      final e = movement.error;
      body = RindeStateView(
        icon: RindeIcons.circleAlert,
        title: e is ApiException ? t(e.messageFor(fallback: ApiMessages.generic)) : t(ApiMessages.generic),
        actions: [
          RindeButton(label: t('Reintentar'), onPressed: () => ref.invalidate(movementDetailProvider(key))),
        ],
      );
    } else {
      body = Center(
        child: Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted)),
      );
    }
    return _PushedFrame(title: t('Editar movimiento'), closeLabel: t('Volver'), back: true, child: body);
  }
}

/// Marco de pantalla empujada (patrón de PendingModuleScreen): franja demo, título y salida.
class _PushedFrame extends ConsumerWidget {
  const _PushedFrame({required this.title, required this.closeLabel, required this.child, this.back = false});

  final String title;
  final String closeLabel;
  final bool back;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final demo = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.demo ?? false));
    void leave() => context.canPop() ? context.pop() : context.go(Routes.app);
    final close = IconButton(
      onPressed: leave,
      tooltip: closeLabel,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: RindeIcon(back ? RindeIcons.chevronLeft : RindeIcons.x, size: 24, color: p.ink),
    );
    final heading = Expanded(
      child: Semantics(
        header: true,
        child: Text(title, style: RindeType.headline.copyWith(color: p.ink)),
      ),
    );
    return PopScope(
      // Abierta sin pantalla anterior (enlace directo): atrás lleva al Inicio, no cierra la app.
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
              if (demo) DemoStrip(onTap: () => showDemoPanel(context)),
              Expanded(
                child: SafeArea(
                  top: !demo,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RindeSpace.s1, RindeSpace.s2, RindeSpace.s1, 0),
                        child: Row(
                          children: back
                              ? [close, const SizedBox(width: RindeSpace.s1), heading]
                              : [const SizedBox(width: RindeSpace.s3), heading, close],
                        ),
                      ),
                      Expanded(child: child),
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
