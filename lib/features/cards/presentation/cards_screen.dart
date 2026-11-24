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
import '../../../design/widgets/rinde_circle_actions.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../application/cards_providers.dart';
import '../data/card_models.dart';
import '../domain/card_rules.dart';
import '../../shell/presentation/pushed_frame.dart';
import 'widgets/card_row.dart';
import 'widgets/card_sheet.dart';
import 'widgets/credit_card_art.dart';

/// `/app/tarjetas` (Cards.jsx, variante de celular): «Debes en total», las acciones en círculos y
/// las filas compactas. Se abre empujada, sin barra de pestañas (la web la muestra con «Planear»
/// marcado: la app se aparta igual que con Mi plata); sin pantalla anterior, atrás va a Planear.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key});

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  /// La copia en memoria de una visita anterior: no se muestra hasta volver a pedirla.
  late bool _stale = ref.read(cardsProvider(ref.read(accountProvider)).exists);

  @override
  void initState() {
    super.initState();
    // Al entrar se vuelve a pedir, con la carga, como la web al montar: la copia puede ser de antes
    // de un pago hecho en otro lado. Tras el primer cuadro: Riverpod no deja invalidar mientras se
    // construye.
    if (_stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(cardsProvider(ref.read(accountProvider)), asReload: true);
        setState(() => _stale = false);
      });
    }
  }

  Future<void> _add() async {
    await showCardSheet(context);
  }

  Future<void> _refresh() =>
      ref.refresh(cardsProvider(ref.read(accountProvider)).future).then<void>((_) {}, onError: (_) {});

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = _stale ? const AsyncLoading<List<CreditCard>>() : ref.watch(cardsProvider(account));
    final cards = async.isReloading ? null : async.value;
    final money = moneyOf(ref);

    // Las acciones en círculos van siempre, también en el vacío y con error (Cards.jsx:175-181).
    final actions = RindeCircleActions(
      label: t('Acciones de Tarjetas'),
      actions: [
        RindeCircleAction(
          label: t('Anotar'),
          icon: RindeIcons.plus,
          primary: true,
          onTap: () => context.push(Routes.record),
        ),
        RindeCircleAction(label: t('Agregar tarjeta'), icon: RindeIcons.creditCard, onTap: _add),
      ],
    );
    Widget retry() => RindeBanner(
      message: moneyErrorText(async.error!, t),
      action: RindeTextLink(label: t('Reintentar'), onPressed: () => ref.invalidate(cardsProvider(account))),
    );

    final children = <Widget>[];
    if (cards != null && cards.isNotEmpty) {
      final next = nextDueCard(cards);
      children.addAll([
        Text(t('Debes en total'), style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7))),
        const SizedBox(height: RindeSpace.s1),
        MoneyText(
          money(debtTotal(cards)),
          money: money,
          fit: true,
          style: RindeType.display.copyWith(color: p.ink),
        ),
        if (next != null) ...[
          const SizedBox(height: RindeSpace.s2),
          Text(
            // La web hace dueText().replace('Se paga', 'Próximo pago') sin t() (Cards.jsx:172): solo
            // cambia cuando dice «Se paga…».
            next.daysToPayment < 0 || next.paidThisCycle
                ? paymentText(t, next, ref.watch(appRegionProvider))
                // TEXTO NUEVO
                : t('Próximo pago {when}', {'when': dueWhen(t, next.daysToPayment)}),
            style: RindeType.lead.w(FontWeight.w500).copyWith(color: p.caution),
          ),
        ],
        const SizedBox(height: RindeSpace.s5),
      ]);
    }
    children.addAll([actions, const SizedBox(height: RindeSpace.s5)]);
    if (cards == null && async.hasError && !async.isLoading) {
      children.add(retry());
    } else if (cards == null) {
      children.add(const _Loading());
    } else {
      // La recarga falló: lo de arriba es lo último que llegó (la web pone el error con Reintentar).
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
      if (cards.isEmpty) {
        children.add(_Empty(onAdd: _add));
      } else {
        children.addAll([
          HomeSectionTitle(t('Mis tarjetas')),
          const SizedBox(height: RindeSpace.s2),
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            CardRow(card: card, money: money, onTap: () => context.push(Routes.card(card.id))),
          ],
        ]);
      }
    }

    return PushedFrame(
      title: t('Tarjetas'),
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

/// Estado vacío (Cards.jsx:35-46): una tarjeta de ejemplo y la invitación.
class _Empty extends ConsumerWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s5),
      child: Column(
        children: [
          CreditCardArt(
            network: 'visa',
            tier: 'gold',
            last4: '1234',
            // TEXTO NUEVO (en la web va sin t(), Cards.jsx:37)
            name: t('Ejemplo'),
            small: true,
          ),
          const SizedBox(height: RindeSpace.s4),
          Semantics(
            header: true,
            child: Text(
              t('Aún no tienes tarjetas'),
              textAlign: TextAlign.center,
              style: RindeType.title.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: RindeSpace.s1),
          Text(
            t('Agrega una para ver cuánto cupo te queda y cuándo toca pagar.'),
            textAlign: TextAlign.center,
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: RindeSpace.s4),
          RindeButton(label: t('Agregar mi primera tarjeta'), onPressed: onAdd),
        ],
      ),
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
      child: HomeSurface(
        padding: const EdgeInsets.all(RindeSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RindeSkeleton(width: 180, height: 32),
            const SizedBox(height: RindeSpace.s3),
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(height: RindeSpace.s3),
              const RindeSkeleton(width: double.infinity, height: 72),
            ],
          ],
        ),
      ),
    ),
  );
}
