import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../auth/application/session_controller.dart';
import '../../../shell/presentation/pushed_frame.dart';
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
    return PushedFrame(
      title: t(_type == MovementType.income ? 'Anotar un ingreso' : 'Anotar un gasto'),
      closeLabel: t('Cerrar sin anotar'),
      back: false,
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
    return PushedFrame(title: t('Editar movimiento'), child: body);
  }
}
