import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
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
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart';
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../shell/presentation/pushed_frame.dart';
import '../application/money_providers.dart';
import '../data/money_models.dart';
import '../domain/commitment_rules.dart';
import 'widgets/commitment_sheet.dart';
import 'widgets/income_overview_card.dart' show moneyOf;
import 'widgets/paid_button.dart';
import 'widgets/salary_section.dart';

/// `/app/mi-plata/pagos` (MoneyPayments.jsx): «Tu sueldo» y los pagos fijos del mes, por pagar y
/// pagados, con «Ya lo pagué», el lápiz para editar y «Agregar pago». Se abre encima; sin pantalla
/// anterior, atrás va a Planear (backPath de la web). Qué está pagado lo dice el servidor; aquí solo
/// se suman «Falta por pagar» y «Ya pagaste» (ver [paymentTotals]).
class MoneyPaymentsScreen extends ConsumerStatefulWidget {
  const MoneyPaymentsScreen({super.key});

  @override
  ConsumerState<MoneyPaymentsScreen> createState() => _MoneyPaymentsScreenState();
}

class _MoneyPaymentsScreenState extends ConsumerState<MoneyPaymentsScreen> {
  /// El error de «Ya lo pagué» o el aviso de un pago que cambió en otro lado.
  String? _error;

  void _setError(String? error) {
    if (mounted) setState(() => _error = error);
  }

  Future<void> _open([Commitment? commitment]) async {
    _setError(null);
    final notice = await showCommitmentSheet(context, commitment: commitment);
    if (notice != null) _setError(notice);
  }

  Future<void> _refresh() {
    ref.read(todayProvider.notifier).sync();
    // Que el día nuevo llegue antes de refrescar: así se suelta lo del mes pasado.
    ref.read(todayProvider);
    final account = ref.read(accountProvider);
    Future<void> again<T>(FutureProviderFamily<T, Session?> provider) =>
        ref.refresh(provider(account).future).then<void>((_) {}, onError: (_) {});
    return Future.wait([again(moneyProfileProvider), again(paymentCalendarProvider)]);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final profileAsync = ref.watch(moneyProfileProvider(account));
    // Lo anterior se sigue viendo al recargar (es por cuenta y aquí no sale la plata): así «Tu sueldo»
    // no pierde lo que se estaba editando ni el aviso de un conflicto.
    final profile = profileAsync.value;

    final children = <Widget>[
      Text(
        t('Lo que pagas cada mes y cuándo te llega la plata'),
        style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: RindeSpace.s4),
    ];
    if (profile == null && profileAsync.hasError && !profileAsync.isLoading) {
      children.add(
        RindeBanner(
          message: moneyErrorText(profileAsync.error!, t),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(moneyProfileProvider(account)),
          ),
        ),
      );
    } else if (profile == null) {
      children.add(const _Loading(lines: 3));
    } else {
      children.addAll([
        SalarySection(profile: profile),
        const SizedBox(height: RindeSpace.s4),
        // Mientras se vuelve a pedir, el perfil es el de antes: editar desde ahí chocaría con lo propio.
        _MonthPayments(profile: profile, onEdit: profileAsync.isLoading ? null : _open, onError: _setError),
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s4), RindeBanner(message: error)],
        const SizedBox(height: RindeSpace.s4),
        RindeButton(
          label: t('Agregar pago'),
          variant: RindeButtonVariant.soft,
          leading: RindeIcon(RindeIcons.plus, size: 18, color: p.brand),
          onPressed: () => _open(),
        ),
      ]);
    }

    return PushedFrame(
      title: t('Pagos del mes'),
      fallback: Routes.plan,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto que se anuncia como «Cargando…».
class _Loading extends ConsumerWidget {
  const _Loading({this.lines = 2});
  final int lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    container: true,
    label: ref.watch(trProvider)('Cargando…'),
    child: ExcludeSemantics(
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: RindeSpace.s3),
              RindeSkeleton(width: i.isEven ? double.infinity : 180, height: 14),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Lo que sale del calendario del mes: totales, suscripciones, «Por pagar», «Pagados» y «En otros
/// meses». Si el calendario falla, el resto de la página se ve y aquí sale «Reintentar».
class _MonthPayments extends ConsumerWidget {
  const _MonthPayments({required this.profile, required this.onEdit, required this.onError});

  final MoneyProfile profile;

  /// null: el lápiz se ve pero no responde.
  final ValueChanged<Commitment>? onEdit;
  final ValueChanged<String?> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final today = ref.watch(todayProvider);
    final account = ref.watch(accountProvider);
    final async = ref.watch(paymentCalendarProvider(account));
    final payments = async.isReloading ? null : async.value;
    final money = moneyOf(ref);

    if (payments == null && async.hasError && !async.isLoading) {
      return RindeBanner(
        message: moneyErrorText(async.error!, t),
        action: RindeTextLink(
          label: t('Reintentar'),
          onPressed: () => ref.invalidate(paymentCalendarProvider(account)),
        ),
      );
    }
    if (payments == null) return const _Loading();

    final byId = {for (final c in profile.commitments) c.id: c};
    // Los anuales que no se cobran este mes no salen en el calendario: se listan aparte para editarlos.
    final inCalendar = {for (final e in payments) e.id};
    final otherMonths = [
      for (final c in profile.commitments)
        if (c.frequency == 'yearly' && !inCalendar.contains(c.id)) c,
    ];
    final totals = paymentTotals(payments);
    final subscriptions = profile.subscriptionCount ?? 0;
    final stacked = largeText(context);
    final open = onEdit;
    VoidCallback? edit(Commitment c) => open == null ? null : () => open(c);

    Widget total(String label, num value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RindeType.meta.copyWith(color: p.ink.withValues(alpha: 0.7))),
        MoneyText(
          money(value),
          money: money,
          fit: true,
          style: RindeType.title.w(FontWeight.w600).copyWith(color: color),
        ),
      ],
    );
    final pending = total(t('Falta por pagar'), totals.pending, p.ink);
    final paid = total(t('Ya pagaste'), totals.paid, p.positive);

    Widget row(CalendarPayment e) => _Row(
      key: ValueKey('${e.id}-${e.date}'),
      name: e.name,
      detail: [
        '${money(e.amount)} · ${dayAndMonth(e.date, region)}',
        if (e.subscription) t(' · suscripción'),
      ].join(),
      overdue: e.status == 'atrasado' ? ' ${t('· atrasado')}' : null,
      money: money,
      trailing: e.paid
          ? _PaidPill(t('Pagado'))
          // Solo lo de este mes (el calendario es del mes en curso; ver payableNow).
          : payableNow(e.date, today)
          ? PaidButton(id: e.id, name: e.name, amount: e.amount, date: e.date, onError: onError)
          : null,
      onEdit: byId[e.id] == null ? null : edit(byId[e.id]!),
      editLabel: byId[e.id] == null ? null : t('Editar {name}', {'name': e.name}),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSurface(
          padding: const EdgeInsets.all(14),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pending,
                    const SizedBox(height: RindeSpace.s3),
                    paid,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pending),
                    const SizedBox(width: RindeSpace.s3),
                    Expanded(child: paid),
                  ],
                ),
        ),
        if (subscriptions > 0 && profile.subscriptionsMonthly != null) ...[
          const SizedBox(height: RindeSpace.s3),
          MoneyText(
            [
              '${t('Suscripciones:')} ${money(profile.subscriptionsMonthly!)} ${t('al mes')}',
              if (subscriptions > 1) ' ($subscriptions)',
            ].join(),
            money: money,
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.8)),
          ),
        ],
        if (payments.isEmpty) ...[
          const SizedBox(height: RindeSpace.s3),
          Text(
            t('Agrega lo que pagas cada mes (arriendo, internet) y tus suscripciones (Netflix, Spotify).'),
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ],
        _Group(
          title: t('Por pagar'),
          rows: [
            for (final e in payments)
              if (!e.paid) row(e),
          ],
        ),
        _Group(
          title: t('Pagados'),
          rows: [
            for (final e in payments)
              if (e.paid) row(e),
          ],
        ),
        _Group(
          title: t('En otros meses'),
          rows: [
            for (final c in otherMonths)
              _Row(
                key: ValueKey(c.id),
                name: c.name,
                detail: [
                  '${money(c.amount)} · ${commitmentWhen(c, t, region)}',
                  if (c.kind == 'subscription') t(' · suscripción'),
                ].join(),
                money: money,
                onEdit: edit(c),
                editLabel: t('Editar {name}', {'name': c.name}),
              ),
          ],
        ),
        // La recarga falló: lo de arriba es lo último que llegó.
        if (async.hasError) ...[
          const SizedBox(height: RindeSpace.s3),
          Semantics(
            liveRegion: true,
            child: Text(
              t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// Un grupo con su título; sin filas no sale.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSectionTitle(title),
          const SizedBox(height: 6),
          HomeSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: i > 0 ? Border(top: BorderSide(color: context.palette.line)) : null,
                    ),
                    child: row,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila: el nombre, «{monto} · {cuándo}» (con « · atrasado» en rojo y escrito, no solo el color),
/// y a la derecha «Pagado», «Ya lo pagué» y el lápiz. Con la letra agrandada, las acciones bajan.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.name,
    required this.detail,
    required this.money,
    this.editLabel,
    this.overdue,
    this.trailing,
    this.onEdit,
  });

  final String name;
  final String detail;
  final HomeMoney money;

  /// Con él sale el lápiz; sin [onEdit], desactivado.
  final String? editLabel;
  final String? overdue;
  final Widget? trailing;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = RindeType.small.tabular.copyWith(color: p.ink.withValues(alpha: 0.7));
    final info = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RindeType.bodyMedium.copyWith(color: p.ink),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: detail),
                if (overdue != null)
                  TextSpan(
                    text: overdue,
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.negative),
                  ),
              ],
            ),
            semanticsLabel: money.spoken('$detail${overdue ?? ''}'),
            style: style,
          ),
        ],
      ),
    );
    final edit = editLabel == null
        ? null
        : IconButton(
            onPressed: onEdit,
            tooltip: editLabel,
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: RindeIcon(RindeIcons.pencil, size: 18, color: p.inkMuted),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s2),
      child: largeText(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                if (trailing != null || edit != null)
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: RindeSpace.s2,
                    children: [?trailing, ?edit],
                  ),
              ],
            )
          : LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  Expanded(child: info),
                  if (trailing != null || edit != null) ...[
                    const SizedBox(width: RindeSpace.s2),
                    // Las acciones ocupan como mucho media fila; si no caben, su texto baja de línea.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trailing case final action?) Flexible(child: action),
                          ?edit,
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// La pastilla verde «Pagado».
class _PaidPill extends StatelessWidget {
  const _PaidPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.positive.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(RindeRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: RindeSpace.s1),
        child: Text(label, style: RindeType.meta.w(FontWeight.w600).copyWith(color: p.positive)),
      ),
    );
  }
}
