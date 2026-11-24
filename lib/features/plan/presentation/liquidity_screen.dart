import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../../auth/application/session_controller.dart';
import '../../cards/domain/card_rules.dart' show shortCardDate;
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/plan_providers.dart';
import '../data/plan_models.dart';
import '../domain/plan_rules.dart';

/// `/app/liquidez` (Liquidity.jsx): la plata día por día que proyecta el SERVIDOR (lo que debo baja
/// el saldo; lo que me deben no suma), por qué faltaría y cómo evitarlo. La app no recalcula nada:
/// pinta los días, el hueco, el tope diario y los supuestos tal como llegan. Sin pantalla anterior,
/// atrás va a Mi plata.
class LiquidityScreen extends ConsumerWidget {
  const LiquidityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(liquidityProvider(account));
    final data = async.value;

    final children = <Widget>[
      Text(
        t('Lo que tienes, lo que gastas y lo que debes pagar, día por día.'),
        style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: RindeSpace.s5),
    ];
    if (data == null && async.hasError && !async.isLoading) {
      children.add(
        RindeBanner(
          message: moneyErrorText(async.error!, t),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(liquidityProvider(account)),
          ),
        ),
      );
    } else if (data == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
          child: Semantics(
            label: t('Calculando tu plata'),
            child: const Center(child: ExcludeSemantics(child: RindeSpinner())),
          ),
        ),
      );
    } else if (!data.ready || !data.hasData) {
      children.add(
        HomeSurface(
          padding: const EdgeInsets.all(RindeSpace.s5),
          child: Column(
            children: [
              Text(
                t('Agrega tus pagos del mes para ver si te alcanza.'),
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.copyWith(color: p.ink),
              ),
              const SizedBox(height: RindeSpace.s1),
              Text(
                t(
                  'Con lo que tienes y tus pagos (arriendo, servicios, tarjetas) te decimos si te va a faltar plata y cuándo.',
                ),
                textAlign: TextAlign.center,
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s3),
              HomeLink(label: t('Ir a Mi plata'), onTap: () => context.push(Routes.myMoney)),
            ],
          ),
        ),
      );
    } else {
      children.add(_Detail(data: data));
    }

    return PushedFrame(
      title: t('Tu plata en los próximos días'),
      fallback: Routes.myMoney,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () => ref.refresh(liquidityProvider(account).future).then<void>((_) {}, onError: (_) {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: children,
        ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.data});

  final Liquidity data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final home = moneyOf(ref);
    // Como la web: los montos de la proyección se muestran redondeados.
    String money(num amount) => home(amount.round());
    final (icon, color) = switch (data.risk) {
      'falta' => (RindeIcons.circleAlert, p.negative),
      'riesgo' => (RindeIcons.triangleAlert, p.caution),
      _ => (RindeIcons.circleCheck, p.positive),
    };
    final message = liquidityMessage(data, t, region, money);
    final shortfall = data.firstShortfall;
    final tips = avoidTips(data, t, money);
    final until = shortCardDate(data.until!, region);
    final today = data.today ?? data.days.first.date;

    Widget panel(List<Widget> children) => HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
    Widget heading(String text) => Semantics(
      header: true,
      child: Text(text, style: RindeType.small.w(FontWeight.w600).copyWith(color: p.ink)),
    );
    Widget figure(String label, Widget value) => Expanded(
      child: panel([
        Text(label, style: RindeType.caption.copyWith(color: p.inkMuted)),
        const SizedBox(height: RindeSpace.s1),
        value,
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: t('Resumen'),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: RindeRadius.brX2),
            child: Padding(
              padding: const EdgeInsets.all(RindeSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: RindeIcon(icon, color: color),
                      ),
                      const SizedBox(width: RindeSpace.s2),
                      Expanded(
                        child: MoneyText(
                          message.title,
                          money: home,
                          style: RindeType.title.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                  if (message.detail case final detail?) ...[
                    const SizedBox(height: RindeSpace.s1),
                    MoneyText(
                      detail,
                      money: home,
                      style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s4),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              figure(
                t('Tienes hoy'),
                MoneyText(
                  money(data.money),
                  money: home,
                  fit: true,
                  style: RindeType.figure.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(width: RindeSpace.s3),
              figure(
                t('Gastas al día'),
                MoneyText(
                  data.pace == null ? '—' : money(data.pace!),
                  money: home,
                  fit: true,
                  style: RindeType.figure.copyWith(color: p.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: RindeSpace.s4),
        panel([
          heading('${t('Día por día, hasta el')} $until'),
          const SizedBox(height: RindeSpace.s3),
          Semantics(
            label: shortfall != null
                ? t('El {date} la plata queda en negativo.', {'date': shortCardDate(shortfall.date, region)})
                : t('La plata no baja de cero hasta el {until}.', {'until': until}),
            child: SizedBox(
              height: 200,
              child: CustomPaint(
                painter: _LiquidityChart(
                  days: data.days,
                  shortfallDate: shortfall?.date,
                  line: p.brand,
                  zero: p.negative,
                  surface: p.surface,
                ),
              ),
            ),
          ),
        ]),
        if (shortfall != null) ...[
          const SizedBox(height: RindeSpace.s4),
          panel([
            heading(t('Por qué pasa')),
            const SizedBox(height: RindeSpace.s3),
            for (final c in shortfall.causes) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RindeType.bodyMedium.copyWith(color: p.ink),
                        ),
                        Text(
                          '${_kindText(t, c.kind)} · '
                          '${shortCardDate(c.date == null || c.date!.compareTo(today) < 0 ? today : c.date!, region)}',
                          style: RindeType.caption.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  MoneyText(
                    '-${money(c.amount)}',
                    money: home,
                    style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
                  ),
                ],
              ),
              const SizedBox(height: RindeSpace.s2),
            ],
            if (data.pace case final pace?)
              MoneyText(
                '${t('Y tu gasto normal de unos')} ${money(pace)} ${t('al día.')}',
                money: home,
                style: RindeType.caption.copyWith(color: p.inkMuted),
              ),
          ]),
        ],
        if (tips.isNotEmpty) ...[
          const SizedBox(height: RindeSpace.s4),
          panel([
            Row(
              children: [
                RindeIcon(RindeIcons.lightbulb, size: 16, color: p.caution),
                const SizedBox(width: RindeSpace.s2),
                Expanded(child: heading(t('Cómo evitarlo'))),
              ],
            ),
            const SizedBox(height: RindeSpace.s3),
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: RindeSpace.s2),
                child: MoneyText(
                  '•  $tip',
                  money: home,
                  style: RindeType.small.copyWith(color: p.ink),
                ),
              ),
            Text(
              t('Son sugerencias: Rinde no mueve ni cambia tus pagos.'),
              style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.5)),
            ),
          ]),
        ],
        const SizedBox(height: RindeSpace.s4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: RindeSpace.s2,
          runSpacing: RindeSpace.s2,
          children: [
            RindeTextLink(
              label: t('Ver el calendario de pagos'),
              onPressed: () => context.push(Routes.calendar),
            ),
            RindeTextLink(label: t('Editar mis pagos'), onPressed: () => context.push(Routes.myMoney)),
          ],
        ),
        if (data.assumptions.isNotEmpty) ...[
          const SizedBox(height: RindeSpace.s3),
          for (final a in data.assumptions)
            Padding(
              padding: const EdgeInsets.only(bottom: RindeSpace.s1),
              child: Text(a, style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.5))),
            ),
        ],
      ],
    );
  }
}

/// Qué es cada pago, en palabras (KIND_TEXT de Liquidity.jsx).
String _kindText(Tr t, String kind) => switch (kind) {
  'compromiso' => t('Pago del mes'),
  'card' => t('Tarjeta'),
  'vaca' => t('Tu aporte a la vaca'),
  'deuda' => t('Cuenta por pagar'),
  _ => t('Pago'),
};

/// La gráfica de LiquidityChart.jsx, sin cifras (las dice el resumen): la línea de la plata al final
/// de cada día con su área, la línea del 0 punteada en rojo, un punto en cada día con pagos y el del
/// hueco en rojo y más grande.
class _LiquidityChart extends CustomPainter {
  _LiquidityChart({
    required this.days,
    required this.shortfallDate,
    required this.line,
    required this.zero,
    required this.surface,
  });

  final List<LiquidityDay> days;
  final String? shortfallDate;
  final Color line;
  final Color zero;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final values = [for (final d in days) d.end.toDouble()];
    final top = math.max(0.0, values.reduce(math.max));
    final bottom = math.min(0.0, values.reduce(math.min));
    final range = top - bottom == 0 ? 1.0 : top - bottom;
    const pad = 8.0;
    double x(int i) =>
        days.length == 1 ? size.width / 2 : pad + i * (size.width - 2 * pad) / (days.length - 1);
    double y(double v) => pad + (top - v) / range * (size.height - 2 * pad);

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(values.length - 1), y(bottom))
      ..lineTo(x(0), y(bottom))
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.1));

    // El 0, punteado.
    final zeroY = y(0);
    final dash = Paint()
      ..color = zero
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 8) {
      canvas.drawLine(Offset(dx, zeroY), Offset(math.min(dx + 4, size.width), zeroY), dash);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final hole = d.date == shortfallDate;
      if (!hole && !d.events.any((e) => e.kind != 'esperado')) continue;
      final center = Offset(x(i), y(values[i]));
      canvas.drawCircle(center, hole ? 8 : 6, Paint()..color = surface);
      canvas.drawCircle(center, hole ? 6 : 4, Paint()..color = hole ? zero : line);
    }
  }

  @override
  bool shouldRepaint(_LiquidityChart old) =>
      old.days != days || old.shortfallDate != shortfallDate || old.line != line || old.surface != surface;
}
