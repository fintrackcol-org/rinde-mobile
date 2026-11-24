import '../../../../app/routes.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/application/money_providers.dart';
import '../../../money/data/money_models.dart';
import '../../../shell/presentation/rinde_tab_scaffold.dart';
import '../../application/movement_saver.dart';
import '../../application/movements_controller.dart';
import '../../domain/movement.dart';
import 'adjustment_row.dart';
import 'movement_dates.dart';
import 'movement_row.dart';

/// Pausa tras dejar de escribir antes de buscar (SEARCH_DELAY_MS de la web).
const _searchDelay = Duration(milliseconds: 300);

/// Pestaña Movimientos (Movements.jsx + MovementList standalone): periodo, buscador, filtros y la
/// lista por día. Cada vez que se abre arranca en el mes actual sin filtros, como la web.
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  MovementPeriod _period = MovementPeriod.month;
  late DateTime _date;
  String _q = '';
  MovementType? _type;
  String? _category;
  bool _retrying = false;
  bool _retryLeftItems = false;

  /// La consulta que esta pantalla pidió por última vez.
  MovementQuery? _wanted;

  @override
  void initState() {
    super.initState();
    _date = ref.read(clockProvider)();
    _reapply();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => _q.isNotEmpty || _type != null || _category != null;

  void _apply() {
    final range = periodRange(_period, _date);
    _wanted = MovementQuery(
      type: _type,
      category: _category,
      from: isoDay(range.from),
      to: isoDay(range.to),
      search: _q.isEmpty ? null : _q,
    );
    unawaited(ref.read(movementsControllerProvider.notifier).setQuery(_wanted!));
  }

  /// El controlador arranca (y vuelve a arrancar al cambiar la sesión) sin periodo y pide esa lista en
  /// una microtarea. Leerlo lo construye ya si hace falta; la consulta del periodo va en la microtarea
  /// siguiente: así es la última y la otra se descarta.
  void _reapply() {
    ref.read(movementsControllerProvider);
    Future.microtask(() {
      if (mounted) _apply();
    });
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, () {
      final q = text.trim();
      if (!mounted || q == _q) return;
      _q = q;
      _apply();
    });
  }

  void _setPeriod(MovementPeriod period, DateTime date) {
    setState(() => (_period = period, _date = date));
    _apply();
  }

  /// Cambiar el tipo borra la categoría (pickType de la web).
  void _pickType(MovementType? type) {
    setState(() => (_type = type, _category = null));
    _apply();
  }

  void _pickCategory(String? key) {
    setState(() => _category = key);
    _apply();
  }

  /// Deslizar para recargar también reenvía los pendientes (con su mismo localId, sin duplicar).
  Future<void> _refresh() {
    ref.invalidate(balanceAdjustmentsProvider);
    return Future.wait([
      ref.read(pendingMovementsProvider.notifier).retryPending(),
      ref.read(movementsControllerProvider.notifier).refresh(),
    ]);
  }

  Future<void> _retryPending() async {
    setState(() => (_retrying = true, _retryLeftItems = false));
    await ref.read(pendingMovementsProvider.notifier).retryPending();
    if (!mounted) return;
    final left = ref.read(pendingMovementsProvider).value?.items.isNotEmpty ?? false;
    setState(() => (_retrying = false, _retryLeftItems = left));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final now = ref.watch(clockProvider)();
    final s = ref.watch(movementsControllerProvider);
    // Al cambiar la sesión o el repositorio, el controlador vuelve a arrancar sin periodo.
    ref.listen(accountProvider, (_, _) => _reapply());
    ref.listen(movementsControllerProvider.select((s) => s.query), (_, query) {
      if (_wanted != null && query != _wanted) _reapply();
    });
    final pending = ref.watch(pendingMovementsProvider).value;
    final categories = ref.watch(movementCategoriesProvider(ref.watch(accountProvider)));
    final names = categories.value?.names ?? const <String, String>{};
    // El único camino de un monto a la pantalla y al lector: oculto, no sale ni un dígito.
    final money = HomeMoney(
      format: formatFor(region),
      hidden: ref.watch(hiddenAmountsProvider),
      hiddenLabel: t('Monto oculto'),
    );
    final label = periodLabel(_period, _date, now, region, t);
    final range = periodRange(_period, _date);
    // Un ajuste no tiene tipo, categoría ni descripción: con un filtro puesto no aparece. Si fallan,
    // la lista se ve igual, sin ellos (como la web).
    final adjustments = _filtered
        ? const <BalanceAdjustment>[]
        : ref
                  .watch(
                    balanceAdjustmentsProvider((
                      ref.watch(accountProvider),
                      isoDay(range.from),
                      isoDay(range.to),
                    )),
                  )
                  .value ??
              const <BalanceAdjustment>[];
    final loaded = s.total != null;
    // Sin la primera página no se sabe cuáles van: ni sueltos mientras carga ni junto al error (la web
    // tampoco pinta filas sin respuesta).
    final rows = withAdjustments(s.server, adjustments, complete: loaded && !s.hasMore);

    final waiting = pending?.items ?? const [];
    final rejected = pending?.rejected ?? const [];
    final entries = <Widget Function()>[
      () => _Header(
        t: t,
        period: _period,
        label: label,
        atCurrent: isCurrentPeriod(_period, _date, now),
        onPeriod: (period) => _setPeriod(period, now),
        onShift: (delta) => _setPeriod(_period, shiftPeriod(_period, _date, delta)),
        search: _search,
        onSearch: _onSearch,
        type: _type,
        onType: _pickType,
        categoryName: _category == null ? null : (names[_category] ?? _category),
        onCategory: _openCategories,
      ),
      if (waiting.isNotEmpty || rejected.isNotEmpty)
        () => _PendingPanel(
          t: t,
          money: money,
          names: names,
          waiting: waiting,
          rejected: rejected,
          retrying: _retrying,
          retryLeftItems: _retryLeftItems,
          onRetry: _retryPending,
          onDiscard: () => ref.read(pendingMovementsProvider.notifier).clearRejected(),
        ),
      if (s.error != null)
        () => _ErrorNote(
          message: movementErrorText(s.error, t),
          // Lo que se ve es lo último que llegó: se dice, no se presenta como fresco.
          stale: s.server.isNotEmpty,
          t: t,
          onRetry: _refresh,
        ),
      if (!loaded && s.error == null)
        () => Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s8),
          child: Semantics(
            liveRegion: true,
            child: Row(
              children: [
                RindeSpinner(color: p.inkMuted),
                const SizedBox(width: RindeSpace.s2),
                Flexible(
                  child: Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted)),
                ),
              ],
            ),
          ),
        )
      else if (loaded && rows.isEmpty && !s.loading && s.error == null)
        () => Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s8),
          child: Text(
            _filtered
                ? t('Ningún movimiento coincide con la búsqueda.')
                : t('No hay movimientos en {toLowerCase}.', {'toLowerCase': label.toLowerCase()}),
            textAlign: TextAlign.center,
            style: RindeType.body.copyWith(color: p.inkMuted),
          ),
        ),
      // Solo la cuenta: sumar montos en el teléfono daría cifras que el servidor no respalda.
      if (s.total case final total? when s.server.isNotEmpty)
        () => Padding(
          padding: const EdgeInsets.only(top: RindeSpace.s3),
          child: Text(
            total == 1 ? t('1 movimiento') : t('{length} movimientos', {'length': total}),
            style: RindeType.meta.copyWith(color: p.inkMuted),
          ),
        ),
      ..._groups(rows, now, region, t, names, money),
      if (s.hasMore && s.server.isNotEmpty)
        () => Padding(
          padding: const EdgeInsets.only(top: RindeSpace.s4),
          child: RindeButton(
            label: t('Ver más'),
            variant: RindeButtonVariant.soft,
            loading: s.loading,
            onPressed: () => ref.read(movementsControllerProvider.notifier).loadMore(),
          ),
        ),
    ];

    return RindeTabScaffold(
      current: RindeTab.movements,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: _refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            RindeSpace.s4,
            RindeSpace.s4,
            RindeSpace.s4,
            RindeTabScaffold.bottomInset(context),
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            // Cerca del final pide la página siguiente; si falló, espera a «Reintentar».
            if (i >= entries.length - 5 && s.hasMore && !s.loading && s.error == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(ref.read(movementsControllerProvider.notifier).loadMore());
              });
            }
            return entries[i]();
          },
        ),
      ),
    );
  }

  /// Encabezado de día y filas, en el orden del servidor (fecha y creación, de lo nuevo a lo viejo),
  /// con los ajustes de saldo al inicio de su día.
  List<Widget Function()> _groups(
    List<Object> items,
    DateTime now,
    Region region,
    Tr t,
    Map<String, String> names,
    HomeMoney money,
  ) {
    final out = <Widget Function()>[];
    String? last;
    for (final row in items) {
      final date = switch (row) {
        final Movement m => m.date,
        final BalanceAdjustment a => a.date,
        _ => throw ArgumentError(row),
      };
      if (date != last) {
        last = date;
        final day = relativeDay(date, now, region, t);
        out.add(() => _DayHeader(day));
      }
      out.add(
        () => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: switch (row) {
            final BalanceAdjustment a => AdjustmentRow(adjustment: a, money: money, t: t),
            final m as Movement => MovementRow(
              movement: m,
              category: movementCategoryName(m, names, t),
              money: money,
              t: t,
              onTap: () => context.push(Routes.movement(m.id)),
            ),
          },
        ),
      );
    }
    return out;
  }

  Future<void> _openCategories() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    builder: (sheet) => _CategorySheet(type: _type, selected: _category, onPick: _pickCategory),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);
  final String day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RindeSpace.s4, bottom: RindeSpace.s1),
    child: Semantics(
      header: true,
      child: Text(day.toUpperCase(), style: RindeType.eyebrow.copyWith(color: context.palette.inkMuted)),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.t,
    required this.period,
    required this.label,
    required this.atCurrent,
    required this.onPeriod,
    required this.onShift,
    required this.search,
    required this.onSearch,
    required this.type,
    required this.onType,
    required this.categoryName,
    required this.onCategory,
  });

  final Tr t;
  final MovementPeriod period;
  final String label;
  final bool atCurrent;
  final ValueChanged<MovementPeriod> onPeriod;
  final ValueChanged<int> onShift;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final MovementType? type;
  final ValueChanged<MovementType?> onType;
  final String? categoryName;
  final VoidCallback onCategory;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget arrow(String tooltip, RindeIcons icon, VoidCallback? onTap) => IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: RindeIcon(icon, size: 20, color: onTap == null ? p.ink.withValues(alpha: 0.3) : p.ink),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(t('¿En qué se te fue?'), style: RindeType.headline.copyWith(color: p.ink)),
        ),
        const SizedBox(height: RindeSpace.s4),
        RindeSegmented<MovementPeriod>(
          semanticLabel: t('Periodo del resumen'),
          options: {
            MovementPeriod.week: t('Semana'),
            MovementPeriod.month: t('Mes'),
            MovementPeriod.year: t('Año'),
          },
          value: period,
          onChanged: onPeriod,
        ),
        const SizedBox(height: RindeSpace.s2),
        Row(
          children: [
            arrow(t('Periodo anterior'), RindeIcons.chevronLeft, () => onShift(-1)),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
              ),
            ),
            // No deja ir más allá del periodo actual.
            arrow(t('Periodo siguiente'), RindeIcons.chevronRight, atCurrent ? null : () => onShift(1)),
          ],
        ),
        const SizedBox(height: RindeSpace.s2),
        Semantics(
          textField: true,
          label: t('Buscar movimiento'),
          child: TextField(
            controller: search,
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            style: RindeType.body.copyWith(color: p.ink),
            cursorColor: RindeBrand.violet,
            decoration: InputDecoration(
              hintText: t('Buscar movimiento'),
              hintStyle: RindeType.body.copyWith(color: p.inkMuted),
              filled: true,
              fillColor: p.wash,
              constraints: const BoxConstraints(minHeight: RindeSize.field),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              // Centrado: sin esto el ícono se estira a todo el alto del campo.
              prefixIcon: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: RindeIcon(RindeIcons.search, size: 18, color: p.inkMuted),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RindeRadius.pill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RindeRadius.pill),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RindeRadius.pill),
                borderSide: BorderSide(color: p.brand.withValues(alpha: 0.4), width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s3),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 6,
            children: [
              for (final (value, text) in [
                (null, t('Todos')),
                (MovementType.expense, t('Gastos')),
                (MovementType.income, t('Ingresos')),
              ])
                _Chip(label: text, selected: type == value, onTap: () => onType(value)),
              _Chip(
                label: categoryName ?? t('Categoría'),
                selected: categoryName != null,
                trailing: RindeIcons.chevronDown,
                onTap: onCategory,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.trailing});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RindeIcons? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.brand : p.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? p.brandSoft : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? p.brand : p.lineStrong, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: RindeSpace.s1,
                children: [
                  Text(
                    label,
                    style: RindeType.small
                        .w(selected ? FontWeight.w600 : FontWeight.w500)
                        .copyWith(color: color),
                  ),
                  if (trailing != null) RindeIcon(trailing!, size: 16, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja «Categoría»: todas, o una del tipo elegido (de los dos tipos con «Todos»).
class _CategorySheet extends ConsumerWidget {
  const _CategorySheet({required this.type, required this.selected, required this.onPick});

  final MovementType? type;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(movementCategoriesProvider(account));
    final lists = async.value;
    final options = lists == null
        ? const <CategoryOption>[]
        : (type == null ? [...lists.expense, ...lists.income] : lists.of(type!));

    Widget option(String text, String? key) => Semantics(
      button: true,
      selected: selected == key,
      label: text,
      excludeSemantics: true,
      onTap: () => _pick(context, key),
      child: InkWell(
        onTap: () => _pick(context, key),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                text,
                style: RindeType.bodyMedium.copyWith(color: selected == key ? p.brand : p.ink),
              ),
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 0, RindeSpace.s4, RindeSpace.s2),
              child: Semantics(
                header: true,
                child: Text(t('Categoría'), style: RindeType.title.copyWith(color: p.ink)),
              ),
            ),
            option(t('Todas las categorías'), null),
            if (lists == null && async.hasError)
              Padding(
                padding: const EdgeInsets.all(RindeSpace.s4),
                child: Wrap(
                  spacing: RindeSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      movementErrorText(async.error, t),
                      style: RindeType.small.copyWith(color: p.negative),
                    ),
                    RindeTextLink(
                      label: t('Reintentar'),
                      onPressed: () => ref.invalidate(movementCategoriesProvider(account)),
                    ),
                  ],
                ),
              )
            else if (lists == null)
              const Padding(
                padding: EdgeInsets.all(RindeSpace.s4),
                child: Center(child: RindeSpinner()),
              ),
            for (final c in options) option(c.name, c.key),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context, String? key) {
    Navigator.of(context).pop();
    if (key != selected) onPick(key);
  }
}

/// Error de la lista y, si hay algo cargado, que puede estar desactualizado.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, required this.stale, required this.t, required this.onRetry});

  final String message;
  final bool stale;
  final Tr t;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s3),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RindeSpace.s2,
              children: [
                Text(message, style: RindeType.small.copyWith(color: p.negative)),
                RindeTextLink(label: t('Reintentar'), onPressed: onRetry),
              ],
            ),
            if (stale)
              Text(
                t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lo guardado sin conexión (PendingList de la web): espera al servidor, con «Reintentar». Lo que el
/// servidor rechazó al reintentar se muestra con su motivo y se puede descartar.
class _PendingPanel extends StatelessWidget {
  const _PendingPanel({
    required this.t,
    required this.money,
    required this.names,
    required this.waiting,
    required this.rejected,
    required this.retrying,
    required this.retryLeftItems,
    required this.onRetry,
    required this.onDiscard,
  });

  final Tr t;
  final HomeMoney money;
  final Map<String, String> names;
  final List<PendingMovement> waiting;
  final List<RejectedMovement> rejected;
  final bool retrying;
  final bool retryLeftItems;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.brandSoft.withValues(alpha: 0.6), borderRadius: RindeRadius.brXl),
        child: Padding(
          padding: const EdgeInsets.all(RindeSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RindeSpace.s2,
            children: [
              if (waiting.isNotEmpty) ...[
                Semantics(
                  header: true,
                  child: Text(
                    '${t('Pendientes de sincronizar (')}${waiting.length})',
                    style: RindeType.label.copyWith(color: p.brand),
                  ),
                ),
                // Del más nuevo al más viejo, como la lista.
                for (final item in waiting.reversed)
                  MovementRow(
                    movement: item.toMovement(),
                    category: movementCategoryName(item.toMovement(), names, t),
                    money: money,
                    t: t,
                    sync: MovementSync.pending,
                  ),
                RindeButton(
                  label: t('Reintentar'),
                  variant: RindeButtonVariant.soft,
                  size: RindeButtonSize.md,
                  loading: retrying,
                  onPressed: onRetry,
                ),
                if (retryLeftItems && !retrying)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t('No se pudo sincronizar'),
                      style: RindeType.small.copyWith(color: p.negative),
                    ),
                  ),
              ],
              for (final r in rejected)
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    // cardDropped NO es un rechazo: el gasto quedó guardado, solo que sin tarjeta.
                    r.cardDropped
                        ? '${r.movement.input.description} · ${t(r.message)}'
                        : '${r.movement.input.description} · ${t('No se pudo sincronizar:')} ${t(r.message)}',
                    style: RindeType.small.copyWith(color: r.cardDropped ? p.ink : p.negative),
                  ),
                ),
              if (rejected.isNotEmpty)
                RindeButton(
                  label: t('Descartar'),
                  variant: RindeButtonVariant.outline,
                  size: RindeButtonSize.md,
                  onPressed: onDiscard,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
