import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../../auth/application/session_controller.dart';
import '../../cards/domain/card_rules.dart' show shortCardDate;
import '../../debts/data/debt_models.dart' show DebtKind;
import '../../debts/presentation/widgets/debt_sheet.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/commitment_sheet.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/plan_providers.dart';
import '../data/plan_models.dart';
import '../domain/plan_rules.dart';
import 'widgets/plan_widgets.dart';

/// Qué eligió la persona en la hoja de un día.
enum _AddChoice { payment, debt }

/// `/app/calendario` (Calendar.jsx): pagos fijos, aportes a vacas, tarjetas (pago, corte y fecha
/// límite), cuentas y días de pago del mes, con lo que queda después de cada pago según el servidor.
/// Cada día se toca para ver lo que tiene y agregarle un pago de cada mes o una cuenta. El hueco del
/// motor de liquidez marca su día en rojo. Sin pantalla anterior, atrás va a Planear.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late String _month = isoMonth(ref.read(todayProvider));
  var _filter = CalendarFilter.all;

  void _reload() {
    final account = ref.read(accountProvider);
    ref.invalidate(calendarMonthProvider((account, _month)));
    ref.invalidate(liquidityProvider(account));
  }

  Future<void> _openDay(PaymentCalendar data, String day, Shortfall? shortfall) async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.surface,
      builder: (_) => _DaySheet(data: data, day: day, shortfall: shortfall),
    );
    if (!mounted || choice == null) return;
    // Lo que se agrega sale del mismo formulario de Mi plata o de Cuentas; después se vuelve a pedir el mes.
    if (choice == _AddChoice.payment) {
      await showCommitmentSheet(
        context,
        day: int.parse(day.substring(8)),
        month: int.parse(day.substring(5, 7)),
      );
    } else {
      await showDebtSheet(context, kind: DebtKind.payable, dueDate: day);
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(calendarMonthProvider((account, _month)));
    final data = async.value;
    final money = moneyOf(ref);
    // Si falla, el calendario se ve igual, sin la marca del hueco.
    final liquidity = ref.watch(liquidityProvider(account)).value;
    final shortfall = liquidity != null && liquidity.ready ? liquidity.firstShortfall : null;
    final shortfallHere = shortfall != null && data != null && shortfall.date.startsWith(data.month)
        ? shortfall
        : null;

    final children = <Widget>[
      Text(
        t('Tus pagos del mes y cuánto te queda después de cada uno.'),
        style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: RindeSpace.s3),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
            tooltip: t('Mes anterior'),
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: RindeIcon(RindeIcons.chevronLeft, color: p.ink),
          ),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                calendarMonthLabel(_month, region),
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.copyWith(color: p.ink),
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _month = shiftMonth(_month, 1)),
            tooltip: t('Mes siguiente'),
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: RindeIcon(RindeIcons.chevronRight, color: p.ink),
          ),
        ],
      ),
      const SizedBox(height: RindeSpace.s3),
    ];

    if (data == null && async.hasError && !async.isLoading) {
      children.add(
        RindeBanner(
          message: moneyErrorText(async.error!, t),
          action: RindeTextLink(label: t('Reintentar'), onPressed: _reload),
        ),
      );
    } else if (data == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s6),
          child: Semantics(
            label: t('Cargando el calendario'),
            child: const Center(child: ExcludeSemantics(child: RindeSpinner())),
          ),
        ),
      );
    } else {
      // El corte y la fecha límite de las tarjetas solo se mezclan aquí: los demás no los leen como pagos.
      final all = [...data.events, ...data.cardDates]..sort((a, b) => a.date.compareTo(b.date));
      final events = filterEvents(all, _filter);
      final projectedUntil = data.projectedUntil;
      final unknownAfter =
          projectedUntil != null &&
          events.any((e) => e.kind != 'ingreso' && !e.isCardDate && e.date.compareTo(projectedUntil) >= 0);
      String dayName(String date) => date == data.today ? t('Hoy') : shortCardDate(date, region);

      children.addAll([
        Opacity(
          opacity: async.isLoading ? 0.6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: t('Por pagar este mes'),
                        child: MoneyText(
                          money(data.pending),
                          money: money,
                          fit: true,
                          style: RindeType.figure.copyWith(color: p.ink),
                        ),
                      ),
                    ),
                    const SizedBox(width: RindeSpace.s3),
                    Expanded(
                      child: _Figure(
                        label: t('Tienes hoy'),
                        child: data.money == null
                            ? HomeLink(
                                label: t('Dinos cuánto tienes'),
                                onTap: () => context.push(Routes.myMoney),
                              )
                            : MoneyText(
                                money(data.money!),
                                money: money,
                                fit: true,
                                style: RindeType.figure.copyWith(color: p.ink),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeSegmented<CalendarFilter>(
                semanticLabel: t('Qué pagos mostrar'),
                options: {
                  CalendarFilter.all: t('Todo'),
                  CalendarFilter.mine: t('Míos'),
                  CalendarFilter.vacas: t('Vacas'),
                },
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              if (shortfallHere != null) ...[
                const SizedBox(height: RindeSpace.s4),
                PlanAlert(
                  negative: true,
                  icon: RindeIcons.circleAlert,
                  message: money.spoken(
                    '${t('El')} ${shortCardDate(shortfallHere.date, region)} ${t('te faltan')} '
                    '${money(shortfallHere.missing)}${t('. Ver qué pasa')}',
                  ),
                  onTap: () => context.push(Routes.liquidity),
                ),
              ],
              const SizedBox(height: RindeSpace.s4),
              _MonthGrid(
                month: data.month,
                today: data.today,
                events: events,
                shortfallDate: shortfallHere?.date,
                region: region,
                onSelect: (date) => _openDay(data, date, shortfallHere),
              ),
              const SizedBox(height: RindeSpace.s2),
              Text(
                t('Toca un día para ver lo que tiene o agregarle algo.'),
                textAlign: TextAlign.center,
                style: RindeType.caption.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s4),
              if (events.isEmpty)
                HomeSurface(
                  padding: const EdgeInsets.all(RindeSpace.s5),
                  child: Column(
                    children: [
                      Text(
                        t('No hay pagos este mes.'),
                        textAlign: TextAlign.center,
                        style: RindeType.bodyMedium.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: RindeSpace.s1),
                      Text(
                        t('Toca un día para agregar un pago o una cuenta, o agrega tus pagos de cada mes en'),
                        textAlign: TextAlign.center,
                        style: RindeType.small.copyWith(color: p.inkMuted),
                      ),
                      HomeLink(label: '${t('Mi plata')}.', onTap: () => context.push(Routes.myMoney)),
                    ],
                  ),
                )
              else
                for (final (date, group) in groupByDate(events)) ...[
                  Semantics(
                    header: true,
                    child: Text(
                      dayName(date),
                      style: RindeType.small.w(FontWeight.w600).copyWith(color: p.ink.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: RindeSpace.s2),
                  for (final e in group) ...[
                    _EventRow(event: e, money: money),
                    const SizedBox(height: RindeSpace.s2),
                  ],
                  const SizedBox(height: RindeSpace.s2),
                ],
              if (unknownAfter)
                Text(
                  '${t('Después del')} ${shortCardDate(projectedUntil, region)} '
                  '${t('no calculamos cuánto te queda: todavía no sabemos cuánto te van a pagar.')}',
                  textAlign: TextAlign.center,
                  style: RindeType.caption.copyWith(color: p.inkMuted),
                ),
            ],
          ),
        ),
      ]);
    }

    return PushedFrame(
      title: t('Calendario'),
      fallback: Routes.plan,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () {
          _reload();
          return ref
              .read(calendarMonthProvider((account, _month)).future)
              .then<void>((_) {}, onError: (_) {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: children,
        ),
      ),
    );
  }
}

/// Una cifra en su panel (Por pagar este mes, Tienes hoy).
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => HomeSurface(
    padding: const EdgeInsets.all(RindeSpace.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RindeType.caption.copyWith(color: context.palette.inkMuted)),
        const SizedBox(height: RindeSpace.s1),
        child,
      ],
    ),
  );
}

/// Color de cada tono de la cuadrícula y del saldo (TONE_CLASS de Calendar.jsx).
Color _toneColor(RindePalette p, CalendarTone? tone) => switch (tone) {
  CalendarTone.negative => p.negative,
  CalendarTone.risk => p.caution,
  CalendarTone.ok => p.positive,
  CalendarTone.income => p.brand,
  _ => p.inkMuted,
};

/// Lo que dice el lector de cada tono: el color no puede ser lo único (TONE_SPOKEN).
/// TEXTO NUEVO: «te queda poco», «te alcanza», «por pagar» y «te entra plata» van sin t() en la web
/// (Calendar.jsx:40-43).
String _toneSpoken(Tr t, CalendarTone tone) => switch (tone) {
  CalendarTone.negative => t('no alcanza o está atrasado'),
  CalendarTone.risk => t('te queda poco'),
  CalendarTone.ok => t('te alcanza'),
  CalendarTone.payment => t('por pagar'),
  CalendarTone.income => t('te entra plata'),
  CalendarTone.card => t('corte o pago de tarjeta'),
};

/// PaymentGrid + MonthGrid: el mes de lunes a domingo, con hoy resaltado, el total por pagar de cada
/// día del color del semáforo y la leyenda.
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.events,
    required this.shortfallDate,
    required this.region,
    required this.onSelect,
  });

  final String month;
  final String today;
  final List<CalendarEvent> events;
  final String? shortfallDate;
  final Region region;
  final ValueChanged<String> onSelect;

  // Como la web (MonthGrid.jsx): las iniciales en español.
  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final cells = calendarCells(month, events, today);
    final hidden = moneyOf(ref).hidden;

    Widget cell(CalendarCell? c) {
      if (c == null) return const SizedBox(height: 48);
      // El día en que el motor de liquidez dice que falta plata va en rojo (FT-0059).
      final tone = c.date == shortfallDate ? CalendarTone.negative : c.tone;
      // Con los montos ocultos solo el punto: la cifra corta también es un monto.
      final text = c.total > 0 && !hidden ? shortMoney(c.total, t) : '•';
      final what = c.count == 0
          // TEXTO NUEVO: «sin pagos», «elemento» y «elementos» van sin t() en la web (Calendar.jsx:59).
          ? t('sin pagos')
          : '${c.count} ${c.count == 1 ? t('elemento') : t('elementos')}';
      return Semantics(
        button: true,
        label: '${shortCardDate(c.date, region)}, $what${tone == null ? '' : ', ${_toneSpoken(t, tone)}'}',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onSelect(c.date),
          borderRadius: RindeRadius.brXl,
          child: SizedBox(
            height: 48,
            // Con la letra agrandada el día y su cifra se achican para caber en la celda (h-12 de la web).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: c.isToday ? BoxDecoration(color: p.brandSolid, shape: BoxShape.circle) : null,
                    child: Text(
                      '${c.day}',
                      style: RindeType.small.tabular.copyWith(
                        fontWeight: c.isToday ? FontWeight.w700 : null,
                        color: c.isToday
                            ? RindeBrand.white
                            : (c.isPast ? p.ink.withValues(alpha: 0.6) : p.ink),
                      ),
                    ),
                  ),
                  if (tone != null)
                    Text(
                      // El rojo lleva además un signo: no depende solo del color.
                      tone == CalendarTone.negative ? (c.total > 0 && !hidden ? '! $text' : '!') : text,
                      maxLines: 1,
                      style: RindeType.caption.copyWith(
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: _toneColor(p, tone),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = i; j < i + 7; j++) Expanded(child: cell(j < cells.length ? cells[j] : null)),
          ],
        ),
      );
    }

    final legend = [
      (p.positive, t('Te alcanza con holgura')),
      (p.caution, t('Te queda poco')),
      (p.negative, t('No alcanza o está atrasado')),
    ];

    return Semantics(
      container: true,
      label: t('Pagos de {month}', {'month': calendarMonthLabel(month, region)}),
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (final d in _weekdays)
                    Expanded(
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: RindeType.caption
                            .w(FontWeight.w600)
                            .copyWith(color: p.ink.withValues(alpha: 0.5)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RindeSpace.s2),
            ...rows,
            const SizedBox(height: RindeSpace.s3),
            Divider(height: 1, color: p.ink.withValues(alpha: 0.1)),
            const SizedBox(height: RindeSpace.s3),
            Semantics(
              container: true,
              label: t('Qué significa cada color'),
              child: Wrap(
                spacing: RindeSpace.s4,
                runSpacing: 6,
                children: [
                  for (final (color, label) in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.7)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un pago, un cobro o un día de pago, con cuánto queda después (EventRow). Lleva a su detalle.
class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event, required this.money});

  final CalendarEvent event;
  final HomeMoney money;

  String _route() => switch (event.kind) {
    // Como eventLink de la web: también las metas personales abren /app/vacas/:id.
    'vaca' when event.id != null => Routes.vaca(event.id!),
    'vaca' => Routes.vacas,
    'card' || 'corte' || 'limite' when event.id != null => Routes.card(event.id!),
    'card' || 'corte' || 'limite' => Routes.cards,
    'cuenta' || 'cobro' => Routes.debts,
    'ingreso' => Routes.myMoney,
    _ => Routes.payments,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final e = event;
    final income = e.kind == 'ingreso';
    final receivable = e.kind == 'cobro';
    final paid = e.status == 'pagado';
    var detail = income
        ? t('Te entra plata')
        : switch (e.status) {
            'pagado' => t('Pagado'),
            'pendiente' => t('Por pagar'),
            'atrasado' => t('Atrasado'),
            'sin_registro' => t('Sin registro'),
            _ => '',
          };
    if (e.kind == 'vaca' && !paid) detail = t('{detail} · tu aporte a la vaca', {'detail': detail});
    if (e.kind == 'cuenta') detail = t('{detail} · le debes', {'detail': detail});
    if (e.subscription) detail = t('{detail} · suscripción', {'detail': detail});
    if (receivable) {
      detail = e.status == 'atrasado' ? t('Atrasado · te debe') : t('Te debe · no se suma a tu plata');
    }
    if (e.kind == 'corte') {
      detail = t('Corte de la tarjeta · lo que compres después va al siguiente extracto');
    }
    if (e.kind == 'limite') detail = t('Último día para pagar la tarjeta · hoy no le debes nada');
    final riskText = switch (e.risk) {
      'negativo' => t('No te alcanza'),
      'riesgo' => t('Te queda poco'),
      _ => null,
    };
    final riskColor = switch (e.risk) {
      'negativo' => p.negative,
      'riesgo' => p.caution,
      'ok' => p.positive,
      _ => p.inkMuted,
    };

    final amount = e.amount == null
        ? null
        : MoneyText(
            '${receivable ? '+' : '−'}${money(e.amount!)}',
            money: money,
            style: RindeType.bodyMedium
                .w(FontWeight.w600)
                .copyWith(color: paid || receivable ? p.inkMuted : p.ink),
          );
    // Con la letra agrandada el monto baja debajo del nombre: al lado no cabría.
    final stacked = largeText(context);

    return HomeTap(
      onTap: () => context.push(_route()),
      radius: RindeRadius.brX2,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.all(RindeSpace.s3),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: RindeRadius.brX2,
          border: Border.all(color: p.ink.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.05), shape: BoxShape.circle),
                child: Text(
                  income ? r'$' : (e.name.isEmpty ? '·' : e.name[0].toUpperCase()),
                  style: RindeType.bodyMedium
                      .w(FontWeight.w700)
                      .copyWith(
                        color: income || receivable ? p.positive : (e.kind == 'vaca' ? p.caution : p.brand),
                      ),
                ),
              ),
            ),
            const SizedBox(width: RindeSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RindeType.bodyMedium.copyWith(
                      color: paid ? p.inkMuted : p.ink,
                      decoration: paid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: RindeType.caption.copyWith(
                        color: e.status == 'atrasado' ? p.negative : p.inkMuted,
                      ),
                    ),
                  if (e.balanceAfter case final left?)
                    MoneyText(
                      '${riskText == null ? t('Te quedan ') : '$riskText: '}${money(left)}',
                      money: money,
                      style: RindeType.caption.copyWith(color: riskColor),
                    ),
                  if (stacked && amount != null) amount,
                ],
              ),
            ),
            if (!stacked && amount != null) ...[const SizedBox(width: RindeSpace.s2), amount],
            const SizedBox(width: RindeSpace.s2),
            RindeIcon(RindeIcons.chevronRight, size: 16, color: p.ink.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

/// La ventana de un día: todo lo que tiene (sin el filtro), el hueco si cae ahí y «Agregar a este
/// día» con las dos opciones de la web. Devuelve lo que se eligió agregar.
class _DaySheet extends ConsumerStatefulWidget {
  const _DaySheet({required this.data, required this.day, required this.shortfall});

  final PaymentCalendar data;
  final String day;
  final Shortfall? shortfall;

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  bool _choosing = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final money = moneyOf(ref);
    final day = widget.day;
    final label = shortCardDate(day, region);
    final events = [...widget.data.events, ...widget.data.cardDates].where((e) => e.date == day).toList();

    Widget option(RindeIcons icon, String title, String text, _AddChoice choice) => HomeTap(
      onTap: () => Navigator.of(context).pop(choice),
      radius: RindeRadius.brX2,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(RindeSpace.s3),
        decoration: BoxDecoration(
          borderRadius: RindeRadius.brX2,
          border: Border.all(color: p.ink.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
              child: RindeIcon(icon, color: p.brand),
            ),
            const SizedBox(width: RindeSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RindeType.bodyMedium.copyWith(color: p.ink)),
                  Text(text, style: RindeType.small.copyWith(color: p.inkMuted)),
                ],
              ),
            ),
            RindeIcon(RindeIcons.chevronRight, size: 16, color: p.ink.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );

    final List<Widget> content;
    if (_choosing) {
      content = [
        option(
          RindeIcons.calendarClock,
          t('Pago de cada mes'),
          t('Arriendo, servicios, cuotas. Se repite el día {Number} de cada mes.', {
            'Number': int.parse(day.substring(8)),
          }),
          _AddChoice.payment,
        ),
        const SizedBox(height: RindeSpace.s2),
        option(
          RindeIcons.handCoins,
          t('Cuenta'),
          t('Plata que debes o que te deben, con el aviso que elijas.'),
          _AddChoice.debt,
        ),
      ];
    } else {
      content = [
        if (events.isEmpty)
          Text(t('No tienes pagos ni cuentas este día.'), style: RindeType.body.copyWith(color: p.inkMuted))
        else
          for (final e in events) ...[
            _EventRow(event: e, money: money),
            const SizedBox(height: RindeSpace.s2),
          ],
        if (widget.shortfall case final s? when s.date == day) ...[
          const SizedBox(height: RindeSpace.s2),
          HomeLink(
            label: money.spoken('${t('Este día te faltarían')} ${money(s.missing)}${t('. Ver qué pasa')}'),
            underline: true,
            style: RindeType.small.w(FontWeight.w500).copyWith(color: p.negative),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(Routes.liquidity);
            },
          ),
        ],
        const SizedBox(height: RindeSpace.s4),
        RindeButton(
          label: t('Agregar a este día'),
          leading: const RindeIcon(RindeIcons.plus, size: 18, color: RindeBrand.white),
          onPressed: () => setState(() => _choosing = true),
        ),
      ];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _choosing ? t('Agregar al {v1}', {'v1': label}) : (day == widget.data.today ? t('Hoy') : label),
              style: RindeType.title.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: RindeSpace.s4),
          ...content,
        ],
      ),
    );
  }
}
