import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../onboarding/presentation/demo_panel.dart';
import '../../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../../application/movement_saver.dart';
import '../../application/movements_controller.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/movement.dart';
import '../list/movement_dates.dart';
import '../list/movement_row.dart';

/// Un movimiento (TransactionDetail.jsx): tipo y categoría, descripción, monto, cuándo y con qué se
/// pagó, y las acciones de editar y eliminar. Siempre pide la versión del servidor; si falla y la
/// lista ya lo traía, muestra esa copia marcada como posiblemente desactualizada.
class MovementDetailScreen extends ConsumerStatefulWidget {
  const MovementDetailScreen({super.key, required this.movementId});

  final String movementId;

  @override
  ConsumerState<MovementDetailScreen> createState() => _MovementDetailScreenState();
}

class _MovementDetailScreenState extends ConsumerState<MovementDetailScreen> {
  void _back() => context.canPop() ? context.pop() : context.go(Routes.movements);

  /// La copia que trajo la lista, sin crear la lista si no existe.
  Movement? _fromList() {
    if (!ref.read(movementsControllerProvider.exists)) return null;
    for (final m in ref.read(movementsControllerProvider).server) {
      if (m.id == widget.movementId) return m;
    }
    return null;
  }

  Future<void> _confirmDelete(Movement m, HomeMoney money) async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Sin arrastre: mientras borra, la hoja no se puede cerrar (Atrás y tocar fuera los frena PopScope).
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => DeleteMovementSheet(movement: m, money: money),
    );
    if (deleted == true && mounted) _back();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final demo = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.demo ?? false));
    final key = (ref.watch(accountProvider), widget.movementId);
    final async = ref.watch(movementDetailProvider(key));
    final money = HomeMoney(
      format: formatFor(ref.watch(appRegionProvider)),
      hidden: ref.watch(hiddenAmountsProvider),
      hiddenLabel: t('Monto oculto'),
    );
    // Con un 404 no se muestra ninguna copia (ni la anterior ni la de la lista): ya no existe.
    final gone = async.error is ApiException && (async.error! as ApiException).status == 404;
    // Si no, lo último del servidor se queda a la vista mientras se vuelve a pedir.
    final fresh = gone ? null : async.value;
    final fallback = fresh == null && async.hasError && !gone ? _fromList() : null;
    final shown = fresh ?? fallback;

    final Widget body;
    if (shown != null) {
      body = _Body(
        movement: shown,
        money: money,
        stale: fallback != null,
        onEdit: () => context.push(Routes.editMovement(shown.id)),
        onDelete: () => _confirmDelete(shown, money),
      );
    } else if (async.hasError) {
      body = Padding(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: RindeSpace.s2,
            children: [
              Text(movementErrorText(async.error, t), style: RindeType.small.copyWith(color: p.negative)),
              RindeTextLink(
                label: t('Reintentar'),
                onPressed: () => ref.invalidate(movementDetailProvider(key)),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Row(
          children: [
            RindeSpinner(color: p.inkMuted),
            const SizedBox(width: RindeSpace.s2),
            Flexible(
              child: Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted)),
            ),
          ],
        ),
      );
    }

    return PopScope(
      // Abierta sin pantalla anterior (un enlace directo): atrás lleva a Movimientos, no cierra la app.
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.movements);
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RindeSpace.s1, RindeSpace.s2, RindeSpace.s1, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: IconButton(
                            onPressed: _back,
                            tooltip: t('Volver'),
                            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                            icon: RindeIcon(RindeIcons.chevronLeft, size: 24, color: p.ink),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            RindeSpace.s4,
                            RindeSpace.s2,
                            RindeSpace.s4,
                            RindeSpace.s6,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                              child: body,
                            ),
                          ),
                        ),
                      ),
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

class _Body extends ConsumerWidget {
  const _Body({
    required this.movement,
    required this.money,
    required this.stale,
    required this.onEdit,
    required this.onDelete,
  });

  final Movement movement;
  final HomeMoney money;
  final bool stale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final now = ref.watch(clockProvider)();
    final names = ref.watch(movementCategoriesProvider(ref.watch(accountProvider))).value?.names ?? const {};
    final m = movement;
    final income = m.isIncome;
    final category = movementCategoryName(m, names, t);
    final kind = income ? t('Ingreso') : (m.category == 'ahorro_inversion' ? t('Ahorro') : t('Gasto'));

    final rows = <(String, String)>[
      (t('Cuándo'), longDay(m.date, now, region, t)),
      if (!income)
        (
          t('Pagado con'),
          switch (m.card) {
            null => t('Efectivo o débito'),
            final c when c.deleted => t('Tarjeta eliminada'),
            // cardMark de la web: el nombre ya puede traer «••1234».
            final c => c.name.contains('••${c.last4}') ? c.name : '${c.name} ••${c.last4}',
          },
        ),
      if (m.card != null && (m.installments ?? 0) > 1) (t('Cuotas'), '${m.installments}'),
      if (m.original case final o?)
        (
          income ? t('Recibido allá') : t('Pagado allá'),
          '${money.hidden ? money(o.amount) : _inCurrency(o.amount, o.currency, region)}'
              ' · 1 ${o.currency} = ${money.format.money(o.rate)}',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale) ...[
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
          const SizedBox(height: RindeSpace.s3),
        ],
        Text('$kind · $category', style: RindeType.meta.copyWith(color: p.inkMuted)),
        const SizedBox(height: RindeSpace.s2),
        Semantics(
          header: true,
          child: Text(m.description, style: RindeType.headline.copyWith(color: p.ink)),
        ),
        const SizedBox(height: RindeSpace.s2),
        MoneyText(
          signedAmount(m, money, gap: ' '),
          money: money,
          fit: true,
          style: RindeType.amount.copyWith(color: income ? p.positive : p.ink),
        ),
        if (m.category != null) ...[
          const SizedBox(height: RindeSpace.s2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.brandSolid,
                borderRadius: BorderRadius.circular(RindeRadius.sm),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
                  child: Text.rich(
                    TextSpan(
                      text: category,
                      children: [
                        if (m.source == 'ia')
                          TextSpan(
                            text: ' ${t('· sugerida por la IA')}',
                            style: const TextStyle(fontWeight: FontWeight.w400),
                          ),
                      ],
                    ),
                    style: RindeType.meta.w(FontWeight.w600).copyWith(color: RindeBrand.white),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: RindeSpace.s6),
        RindeCard(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s5),
          child: Column(
            children: [
              for (final (i, (label, value)) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: p.line),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: RindeSpace.s4,
                      children: [
                        Text(label, style: RindeType.control.copyWith(color: p.inkMuted)),
                        Text(
                          value,
                          textAlign: TextAlign.end,
                          semanticsLabel: money.spoken(value),
                          style: RindeType.control.tabular.copyWith(color: p.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: RindeSpace.s6),
        RindeButton(label: income ? t('Editar ingreso') : t('Editar gasto'), onPressed: onEdit),
        const SizedBox(height: RindeSpace.s2),
        _DangerButton(label: income ? t('Eliminar ingreso') : t('Eliminar gasto'), onPressed: onDelete),
      ],
    );
  }

  /// formatIn de la web: el monto con el formato del país de esa moneda. Sin un país que la use, el
  /// número con su código (nunca el símbolo de otra moneda).
  static String _inCurrency(num amount, String currency, Region region) {
    if (!kCountries.any((c) => c.currency == currency)) return '$amount $currency';
    return formatFor(Region(country: '', currency: currency, language: region.language)).money(amount);
  }
}

/// Borde y texto en rojo (outline de la web con border-negative/30).
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(RindeSize.buttonLg),
        foregroundColor: p.negative,
        side: BorderSide(color: p.negative.withValues(alpha: 0.3)),
        shape: const RoundedRectangleBorder(borderRadius: RindeRadius.brXl),
        textStyle: RindeType.buttonLg,
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Hoja «¿Eliminar este movimiento?». Devuelve true si el servidor lo borró. Si falla, se queda
/// abierta con el motivo y el movimiento sigue intacto. No hay deshacer, como en la web.
class DeleteMovementSheet extends ConsumerStatefulWidget {
  const DeleteMovementSheet({super.key, required this.movement, required this.money});

  final Movement movement;
  final HomeMoney money;

  @override
  ConsumerState<DeleteMovementSheet> createState() => _DeleteMovementSheetState();
}

class _DeleteMovementSheetState extends ConsumerState<DeleteMovementSheet> {
  bool _removing = false;
  String? _error;

  Future<void> _remove() async {
    final t = ref.read(trProvider);
    setState(() => (_removing = true, _error = null));
    try {
      await ref.read(movementSaverProvider).delete(widget.movement.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => (_removing = false, _error = movementErrorText(e, t)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final m = widget.movement;
    final description = t('{description} · {v2}. Se quita de tus totales.', {
      'description': m.description,
      'v2': widget.money(m.amount),
    });
    return PopScope(
      // Mientras borra no se cierra: el resultado tiene que verse.
      canPop: !_removing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(t('¿Eliminar este movimiento?'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s2),
              Text(
                description,
                semanticsLabel: widget.money.spoken(description),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s4),
              if (_error case final error?) ...[
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                ),
                const SizedBox(height: RindeSpace.s3),
              ],
              FilledButton(
                onPressed: _removing ? null : _remove,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(RindeSize.buttonLg),
                  backgroundColor: p.negative,
                  foregroundColor: RindeBrand.white,
                  disabledBackgroundColor: p.negative.withValues(alpha: 0.6),
                  disabledForegroundColor: RindeBrand.white,
                  shape: const RoundedRectangleBorder(borderRadius: RindeRadius.brXl),
                  textStyle: RindeType.buttonLg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: RindeSpace.s2,
                  children: [
                    if (_removing) const RindeSpinner(color: RindeBrand.white),
                    Flexible(child: Text(t('Sí, eliminar'), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              const SizedBox(height: RindeSpace.s2),
              RindeButton(
                label: t('Cancelar'),
                variant: RindeButtonVariant.ghost,
                onPressed: _removing ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
