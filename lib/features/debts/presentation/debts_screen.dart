import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/debts_providers.dart';
import '../data/debt_models.dart';
import '../domain/debt_rules.dart';
import 'widgets/debt_card.dart';
import 'widgets/debt_payment_sheet.dart';
import 'widgets/debt_sheet.dart';
import 'widgets/settle_sheet.dart';
import 'widgets/side_switch.dart';

/// `/app/cuentas` (Debts.jsx): lo que te deben y lo que debes, con abonos y cuotas. Una sola pantalla
/// con hojas, sin detalle, como la web. Se abre empujada, sin barra de pestañas (como Mi plata y
/// Tarjetas); sin pantalla anterior, atrás va a Planear (backPath de la web).
///
/// Como la web, no hay avisos de éxito: la hoja se cierra y la lista se recarga. Solo se avisa lo que
/// hay que revisar (un abono o una cuenta sin confirmar, una cuenta ya saldada o que ya no existe), y
/// ese aviso se borra con la siguiente acción.
class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  var _tab = DebtKind.receivable;
  String? _notice;

  /// La copia en memoria de una visita anterior: no se muestra hasta volver a pedirla.
  late bool _stale = ref.read(debtsProvider(ref.read(accountProvider)).exists);

  @override
  void initState() {
    super.initState();
    // Al entrar se vuelve a pedir, con la carga, como la web al montar (Debts.jsx:312-320): la copia
    // puede ser de antes de un abono hecho en otro lado y «Registrar abono» lo repetiría. Tras el
    // primer cuadro: Riverpod no deja invalidar mientras se construye.
    if (_stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(debtsProvider(ref.read(accountProvider)), asReload: true);
        setState(() => _stale = false);
      });
    }
  }

  Future<void> _refresh() =>
      ref.refresh(debtsProvider(ref.read(accountProvider)).future).then<void>((_) {}, onError: (_) {});

  /// Abre una hoja y, al cerrarse, deja su aviso (o ninguno).
  Future<void> _open(Future<String?> Function() sheet) async {
    setState(() => _notice = null);
    final notice = await sheet();
    if (mounted) setState(() => _notice = notice);
  }

  void _add() => _open(
    () => showDebtSheet(
      context,
      kind: _tab,
      // Como la web: tras crear, la pestaña salta al lado de la cuenta nueva (Debts.jsx:326-330).
      onCreated: (kind) {
        if (mounted) setState(() => _tab = kind);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = _stale ? const AsyncLoading<DebtsList>() : ref.watch(debtsProvider(account));
    // Tras abonar o saldar se recarga con la carga, no con la cifra vieja: «Registrar abono» volvería
    // a sugerir lo ya abonado.
    final data = async.isReloading ? null : async.value;
    final money = moneyOf(ref);
    final today = isoDay(ref.watch(todayProvider));

    Widget retry() => RindeBanner(
      message: moneyErrorText(async.error!, t),
      action: RindeTextLink(label: t('Reintentar'), onPressed: () => ref.invalidate(debtsProvider(account))),
    );
    Widget add() => RindeButton(
      label: t('Agregar'),
      leading: const RindeIcon(RindeIcons.plus, size: 16, color: RindeBrand.white),
      size: RindeButtonSize.md,
      expand: false,
      onPressed: _add,
    );

    final children = <Widget>[
      Text(
        t('Quién te debe y a quién le debes.'),
        style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: RindeSpace.s3),
      Align(alignment: AlignmentDirectional.centerStart, child: add()),
      const SizedBox(height: RindeSpace.s5),
      if (_notice case final notice?) ...[
        Semantics(
          container: true,
          liveRegion: true,
          label: money.spoken(notice),
          excludeSemantics: true,
          child: RindeBanner(message: notice),
        ),
        const SizedBox(height: RindeSpace.s4),
      ],
    ];
    if (data == null && async.hasError && !async.isLoading) {
      children.add(retry());
    } else if (data == null) {
      children.add(const _Loading());
    } else {
      // La recarga falló: lo de abajo es lo último que llegó (la web pone el error con Reintentar).
      if (async.hasError) {
        children.addAll([
          retry(),
          const SizedBox(height: RindeSpace.s2),
          Semantics(
            liveRegion: true,
            child: Text(
              t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
          const SizedBox(height: RindeSpace.s4),
        ]);
      }
      children.addAll([
        DebtSideSwitch(
          value: _tab,
          data: data,
          money: money,
          onChanged: (kind) => setState(() => _tab = kind),
        ),
        const SizedBox(height: RindeSpace.s5),
        Semantics(
          container: true,
          label: debtWords(t, _tab).tab,
          explicitChildNodes: true,
          child: _DebtList(
            items: data.items.where((d) => d.kind == _tab).toList(),
            kind: _tab,
            money: money,
            today: today,
            add: add(),
            // Con la lista vieja (falló la recarga) sus montos no son verdad: «Registrar abono»
            // propondría lo ya abonado. Se desactivan hasta recargar, como la web sin conexión.
            stale: async.hasError,
            onPay: (debt) => _open(() => showDebtPaymentSheet(context, debt: debt)),
            onSettle: (debt) => _open(() => showSettleSheet(context, debt: debt)),
            onEdit: (debt) => _open(() => showDebtSheet(context, initial: debt)),
            onOpenMovement: (id) {
              // El aviso de la acción anterior no debe seguir ahí al volver.
              setState(() => _notice = null);
              context.push(Routes.movement(id));
            },
          ),
        ),
      ]);
    }

    return PushedFrame(
      title: t('Cuentas'),
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
                constraints: const BoxConstraints(maxWidth: 672),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un lado (DebtList de Debts.jsx): las pendientes y, debajo, las saldadas; vacío con «Agregar».
class _DebtList extends ConsumerWidget {
  const _DebtList({
    required this.items,
    required this.kind,
    required this.money,
    required this.today,
    required this.add,
    required this.stale,
    required this.onPay,
    required this.onSettle,
    required this.onEdit,
    required this.onOpenMovement,
  });

  final List<Debt> items;
  final DebtKind kind;
  final HomeMoney money;
  final String today;
  final Widget add;
  final bool stale;
  final ValueChanged<Debt> onPay;
  final ValueChanged<Debt> onSettle;
  final ValueChanged<Debt> onEdit;
  final ValueChanged<String> onOpenMovement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final words = debtWords(t, kind);
    if (items.isEmpty) {
      return HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s5),
        child: Column(
          children: [
            Text(
              words.empty,
              textAlign: TextAlign.center,
              style: RindeType.body.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: RindeSpace.s4),
            add,
          ],
        ),
      );
    }
    final pending = items.where((d) => !d.settled).toList();
    final settled = items.where((d) => d.settled).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty)
          Semantics(
            container: true,
            explicitChildNodes: true,
            // En la web va sin t() (Debts.jsx:198).
            label: t('{tab}: pendientes', {'tab': words.tab}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, debt) in pending.indexed) ...[
                  if (i > 0) const SizedBox(height: RindeSpace.s3),
                  DebtCard(
                    key: ValueKey('cuenta-${debt.id}'),
                    debt: debt,
                    money: money,
                    today: today,
                    onPay: stale ? null : () => onPay(debt),
                    onSettle: stale ? null : () => onSettle(debt),
                    onEdit: stale ? null : () => onEdit(debt),
                  ),
                ],
              ],
            ),
          )
        else
          Text(t('Todo está saldado.'), style: RindeType.body.copyWith(color: p.inkMuted)),
        if (settled.isNotEmpty) ...[
          const SizedBox(height: RindeSpace.s6),
          Semantics(
            header: true,
            child: Text(t('Saldadas'), style: RindeType.small.w(FontWeight.w500).copyWith(color: p.inkMuted)),
          ),
          const SizedBox(height: RindeSpace.s2),
          Semantics(
            container: true,
            explicitChildNodes: true,
            // En la web va sin t() (Debts.jsx:218).
            label: t('{tab}: saldadas', {'tab': words.tab}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, debt) in settled.indexed) ...[
                  if (i > 0) const SizedBox(height: RindeSpace.s2),
                  SettledDebtRow(
                    key: ValueKey('saldada-${debt.id}'),
                    debt: debt,
                    money: money,
                    onOpenMovement: onOpenMovement,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Loading extends ConsumerWidget {
  const _Loading();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    container: true,
    label: ref.watch(trProvider)('Cargando…'),
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RindeSkeleton(width: double.infinity, height: 64),
          const SizedBox(height: RindeSpace.s5),
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(height: RindeSpace.s3),
            const RindeSkeleton(width: double.infinity, height: 160),
          ],
        ],
      ),
    ),
  );
}
