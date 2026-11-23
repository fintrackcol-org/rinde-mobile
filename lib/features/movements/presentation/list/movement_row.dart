import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../domain/movement.dart';

/// Mensaje de un fallo como lo muestra la web: el del servidor o el genérico, traducido.
String movementErrorText(Object? error, Tr t) =>
    t(error is ApiException ? error.messageFor(fallback: ApiMessages.generic) : ApiMessages.generic);

/// Nombre de la categoría: el del catálogo, la clave si no está, o «Sin clasificar».
String movementCategoryName(Movement m, Map<String, String> names, Tr t) =>
    m.category == null ? t('Sin clasificar') : (names[m.category] ?? m.category!);

/// Monto con signo (`+$ 12.500` / `−$ 12.500`); oculto, solo la máscara.
String signedAmount(Movement m, HomeMoney money, {String gap = ''}) =>
    money.hidden ? money(m.amount) : '${m.isIncome ? '+' : '−'}$gap${money(m.amount)}';

enum MovementSync { pending, rejected }

/// Un movimiento en la lista (MovementRow.jsx en tarjeta, como la pestaña Movimientos de la web).
class MovementRow extends StatelessWidget {
  const MovementRow({
    super.key,
    required this.movement,
    required this.category,
    required this.money,
    required this.t,
    this.sync,
    this.onTap,
  });

  final Movement movement;
  final String category;
  final HomeMoney money;
  final Tr t;
  final MovementSync? sync;

  /// null: no se abre (un pendiente aún no tiene id del servidor).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = movement;
    final status = switch (sync) {
      MovementSync.pending => t('Pendiente de sincronizar'),
      MovementSync.rejected => t('No se pudo sincronizar'),
      null => null,
    };
    final amount = Text(
      signedAmount(m, money),
      style: RindeType.bodyMedium.w(FontWeight.w600).tabular.copyWith(color: m.isIncome ? p.positive : p.ink),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          m.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RindeType.bodyMedium.copyWith(color: p.ink),
        ),
        Text(
          category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
        if (status != null)
          Text(
            status,
            style: RindeType.caption
                .w(FontWeight.w500)
                .copyWith(color: sync == MovementSync.rejected ? p.negative : p.brand),
          ),
      ],
    );
    // Con letra grande el monto baja a su propia línea: nunca se corta.
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final spoken = [
      m.description,
      category,
      ?status,
      '${m.isIncome ? t('Ingreso de ') : t('Gasto de ')}${money.hidden ? money.hiddenLabel : money(m.amount)}',
    ].join(', ');
    return Semantics(
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RindeRadius.brX2,
          side: BorderSide(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 10),
              child: big
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        texts,
                        Align(alignment: AlignmentDirectional.centerEnd, child: amount),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: texts),
                        const SizedBox(width: RindeSpace.s3),
                        amount,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
