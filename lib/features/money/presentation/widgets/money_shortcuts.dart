import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../home/presentation/widgets/home_tap.dart';

/// «Más de tu plata» (MORE_OF_YOUR_MONEY de MiPlata.jsx + common/ShortcutGrid.jsx): los accesos a lo
/// demás de la plata, en el orden de la web. Los que la app aún no tiene abren «En desarrollo».
class MoneyShortcuts extends ConsumerWidget {
  const MoneyShortcuts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final items = [
      (Routes.budgets, t('Presupuestos'), t('Topes por categoría'), RindeIcons.target),
      (Routes.calendar, t('Calendario'), t('Pagos fijos del mes'), RindeIcons.calendarDays),
      (Routes.debts, t('Cuentas'), t('Lo que te deben y debes'), RindeIcons.handCoins),
      (Routes.cards, t('Tarjetas'), t('Cupo y fechas de pago'), RindeIcons.creditCard),
      (Routes.toConfirm, t('Por confirmar'), t('Gastos que llegaron solos'), RindeIcons.inbox),
      (Routes.insights, t('Consejos'), t('Tu semana y la IA'), RindeIcons.sparkles),
      (Routes.export, t('Exportar'), t('Excel o PDF'), RindeIcons.download),
      (Routes.renta, t('Renta y DIAN'), t('Si te toca declarar'), RindeIcons.landmark),
      (Routes.liquidity, t('Próximos días'), t('Lo que entra y sale'), RindeIcons.trendingUp),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dos columnas como la web; una con la letra agrandada o si la palabra más larga no cabe entera
        // en media fila (se partiría: «Presupuesto/s»). La celda pierde 10 de separación y su relleno.
        final cell = (constraints.maxWidth - 10) / 2 - (RindeSpace.s4 + 28);
        final columns = largeText(context) || _widestWord(context, [for (final i in items) i.$2]) > cell
            ? 1
            : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSectionTitle(t('Más de tu plata')),
            const SizedBox(height: RindeSpace.s3),
            for (var i = 0; i < items.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + columns; j++) ...[
                      if (j > i) const SizedBox(width: 10),
                      Expanded(child: j < items.length ? _Shortcut(item: items[j]) : const SizedBox()),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

final _labelStyle = RindeType.control.w(FontWeight.w600);

/// Ancho de la palabra más larga de [labels], con la letra y el tamaño que eligió la persona.
double _widestWord(BuildContext context, List<String> labels) {
  final style = DefaultTextStyle.of(context).style.merge(_labelStyle);
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final word in labels.expand((label) => label.split(' '))) {
    painter
      ..text = TextSpan(text: word, style: style)
      ..layout();
    widest = math.max(widest, painter.width);
  }
  painter.dispose();
  return widest;
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.item});

  final (String route, String label, String hint, RindeIcons icon) item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (route, label, hint, icon) = item;
    return HomeTap(
      onTap: () => context.push(route),
      child: HomeSurface(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  RindeSpace.s4,
                  RindeSpace.s4,
                  28,
                  RindeSpace.s4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RindeIcon(icon, color: p.brand),
                    const SizedBox(height: RindeSpace.s2),
                    Text(label, style: _labelStyle.copyWith(color: p.ink)),
                    const SizedBox(height: RindeSpace.s1),
                    Text(hint, style: RindeType.meta.copyWith(color: p.inkMuted)),
                  ],
                ),
              ),
              PositionedDirectional(
                top: RindeSpace.s4,
                end: RindeSpace.s3,
                child: RindeIcon(RindeIcons.chevronRight, size: 16, color: p.ink.withValues(alpha: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
