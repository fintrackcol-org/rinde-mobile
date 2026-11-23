import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import 'home_tap.dart';

/// Aviso flotante cuando algo del Inicio no se pudo traer (common/LoadErrorToast.jsx). A diferencia
/// de la web no promete reintentos automáticos: aquí solo se reintenta al tocar o al recargar.
class LoadErrorNotice extends ConsumerWidget {
  const LoadErrorNotice({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final retry = HomeLink(label: t('Reintentar'), onTap: onRetry);
    final message = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: p.negative, shape: BoxShape.circle),
        ),
        const SizedBox(width: RindeSpace.s3),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Text(
              t('No pudimos traer todos tus datos.'),
              style: RindeType.small.w(FontWeight.w600).copyWith(color: p.negative),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: RindeRadius.brX2,
          border: Border.all(color: p.negative.withValues(alpha: 0.6)),
          boxShadow: const [BoxShadow(color: Color(0x26141414), blurRadius: 60, offset: Offset(0, 20))],
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(RindeSpace.s4, 3, RindeSpace.s1, 3),
          // «Reintentar» baja a su propia línea si no cabe al lado: con portugués ×1,3 ya no cabe.
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RindeSpace.s2,
              children: [
                message,
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: RindeSpace.s2),
                  child: retry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
