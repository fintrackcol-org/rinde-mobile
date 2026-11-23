import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/presentation/money_invite.dart';
import '../../shell/presentation/rinde_tab_scaffold.dart';
import '../application/home_providers.dart';
import '../application/tour_controller.dart';
import '../domain/home_view.dart';
import 'tour/coach_tour.dart';
import 'tour_anchors.dart';
import 'widgets/balance_links.dart';
import 'widgets/hero_card.dart';
import 'widgets/home_empty.dart';
import 'widgets/home_header.dart';
import 'widgets/home_money.dart';
import 'widgets/home_notice_card.dart';
import 'widgets/home_tap.dart';
import 'widgets/load_error_notice.dart';
import 'widgets/month_totals.dart';
import 'widgets/next_payments.dart';
import '../../movements/application/movement_saver.dart' show pendingMovementsProvider;

/// Inicio (MobileHome.jsx de Rinde Web): la cifra de lo que puedes gastar, lo próximo que hay que
/// pagar y cómo va el mes. Dibuja lo que decide `homeViewProvider`: no pide datos ni hace cuentas.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  /// Al volver a la app, el Inicio se vuelve a pedir si lleva más de esto sin actualizarse.
  static const _stale = Duration(minutes: 5);

  final _anchors = TourAnchors();
  bool _wasEligible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cada vez que se entra al Inicio, no solo al volver a la app: las otras pestañas lo desmontan.
    WidgetsBinding.instance.addPostFrameCallback((_) => _catchUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _catchUp();
  }

  void _catchUp() {
    if (!mounted) return;
    final account = ref.read(accountProvider);
    if (account == null) return;
    // Al abrir la app, al entrar al Inicio y al volver: lo anotado sin conexión se reenvía con el
    // mismo localId, así el servidor no lo duplica.
    unawaited(ref.read(pendingMovementsProvider.notifier).retryPending());
    // Si ya es otro día, lo que depende de hoy se vuelve a pedir solo.
    ref.read(todayProvider.notifier).sync();
    final at = ref.read(homeFreshnessProvider).of(account);
    if (at != null && ref.read(clockProvider)().difference(at) > _stale) unawaited(_refresh());
  }

  Future<void> _refresh() => refreshHome(ref);

  /// El tutorial de primera vez: se ofrece cuando el Inicio ya cargó, o lo pidieron desde «Yo».
  void _syncTour(HomeView view) {
    final start = view.tourEligible && !_wasEligible;
    _wasEligible = view.tourEligible;
    final requested = ref.watch(tourRequestedProvider) && view.hero is! HeroLoading;
    if (!start && !requested) return;
    // Después del cuadro: un proveedor no se cambia mientras se dibuja.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tour = ref.read(tourControllerProvider.notifier);
      if (requested && ref.read(tourRequestedProvider)) {
        ref.read(tourRequestedProvider.notifier).clear();
        tour.open();
      } else if (start) {
        unawaited(tour.maybeStart());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(homeViewProvider);
    final t = ref.watch(trProvider);
    final p = context.palette;
    // El único camino de un monto a la pantalla y al lector: oculto, no sale ni un dígito.
    final money = HomeMoney(
      format: formatFor(ref.watch(appRegionProvider)),
      hidden: ref.watch(hiddenAmountsProvider),
      hiddenLabel: t('Monto oculto'),
    );
    final tourOpen = ref.watch(tourControllerProvider);
    _syncTour(view);
    final bottom = RindeTabScaffold.bottomInset(context);
    // En una pantalla bajita (acostado, dividida) el aviso fijo se comería la lista: va dentro de ella.
    final pinnedError = view.loadError && MediaQuery.sizeOf(context).height >= 480;

    final heroHasRetry = switch (view.hero) {
      HeroUnknown(reason: UnknownReason.offline || UnknownReason.error) => true,
      _ => false,
    };
    final blocks = <Widget>[
      const HomeHeader(),
      if (view.loadError && !pinnedError) LoadErrorNotice(onRetry: _refresh),
      if (view.offline)
        Semantics(
          container: true,
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RindeSpace.s3,
                children: [
                  // No promete actualizarse solo: aquí nada avisa que volvió internet.
                  Text(
                    t('Sin conexión'),
                    style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                  ),
                  // Sin cifra, el «Reintentar» ya lo trae la tarjeta grande.
                  if (!heroHasRetry) HomeLink(label: t('Reintentar'), onTap: _refresh),
                ],
              ),
            ),
          ),
        ),
      if (view.stale)
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _anchors.key(TourTarget.saldo),
            child: HeroCard(hero: view.hero, money: money, onRetry: _refresh),
          ),
          if (view.negativeNote) ...[const SizedBox(height: 6), const NegativeBalanceNote()],
          if (view.showLinks) BalanceLinks(reviewExpenses: view.reviewExpenses, balanceSet: view.balanceSet),
        ],
      ),
      if (view.nextPayments.isNotEmpty) NextPayments(payments: view.nextPayments, money: money),
      KeyedSubtree(
        key: _anchors.key(TourTarget.totales),
        child: MonthSection(totals: view.totals, toConfirm: view.toConfirm, money: money),
      ),
      // Uno solo: el aviso gana y, sin aviso, la invitación o el acceso a Mi plata.
      if (view.notice case final notice?)
        HomeNoticeCard(notice: notice, money: money)
      else if (view.footer == HomeFooter.invite)
        const MoneyInviteCard()
      else if (view.footer == HomeFooter.setup)
        const MoneySetupLink(),
      if (view.empty) const HomeEmpty(),
    ];

    return RindeTabScaffold(
      current: RindeTab.home,
      anchors: _anchors,
      overlay: tourOpen
          ? CoachTour(anchors: _anchors, onClose: (_) => ref.read(tourControllerProvider.notifier).close())
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La lista ocupa todo lo que quede aunque el contenido sea corto: se hala desde cualquier parte.
          Expanded(
            child: RefreshIndicator(
              color: p.brandSolid,
              backgroundColor: p.surface,
              onRefresh: _refresh,
              child: SingleChildScrollView(
                // Siempre se puede halar para recargar, aunque el contenido quepa en la pantalla.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  RindeSpace.s4,
                  RindeSpace.s4,
                  RindeSpace.s4,
                  // Con el aviso de error fijo la lista termina encima de él, mida lo que mida.
                  pinnedError ? RindeSpace.s4 : bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, block) in blocks.indexed) ...[
                          if (i > 0) const SizedBox(height: RindeSpace.s4),
                          block,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Una sesión vencida no llega aquí: `loadError` ya la descarta y el router lleva al login.
          if (pinnedError)
            Padding(
              padding: EdgeInsets.fromLTRB(RindeSpace.s3, 0, RindeSpace.s3, bottom - RindeSpace.s1),
              child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                  child: LoadErrorNotice(onRetry: _refresh),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
