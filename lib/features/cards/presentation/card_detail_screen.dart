import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
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
import '../../auth/data/auth_models.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart';
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/cards_providers.dart';
import '../application/cards_writer.dart';
import '../data/card_models.dart';
import '../domain/card_rules.dart';
import 'widgets/bank_sync_sheet.dart';
import 'widgets/card_history.dart';
import 'widgets/card_row.dart' show CardUsageBar;
import 'widgets/card_sheet.dart';
import '../../../design/widgets/confirm_inline.dart';
import 'widgets/expiry_badge.dart';
import 'widgets/pay_card_sheet.dart';

/// `/app/tarjetas/:id` (CardDetail.jsx, variante de celular): lo que se debe, cuándo se paga, el
/// extracto, la barra, las acciones en círculos, «Compras y pagos» y «Eliminar tarjeta» con
/// confirmación EN LÍNEA que al terminar vuelve a la lista. Sin pantalla anterior, atrás va a
/// Tarjetas (backPath de la web).
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  /// Lo que salió bien, en verde. Se queda hasta la siguiente acción, como la web (CardDetail.jsx:235).
  /// Un pago en duda sin confirmar va en el mismo lugar con [_noticeTone] de error.
  String? _notice;
  var _noticeTone = RindeBannerTone.success;

  (Session?, String) get _key => (ref.read(accountProvider), widget.cardId);

  /// La copia en memoria de una visita anterior: no se muestra hasta volver a pedirla.
  late bool _stale = ref.read(cardDetailProvider(_key).exists);

  @override
  void initState() {
    super.initState();
    // Al entrar se vuelve a pedir, con la carga, como la web al montar: «Abonar» sugeriría la deuda
    // de antes de un pago hecho en otro lado. Tras el primer cuadro: Riverpod no deja invalidar
    // mientras se construye.
    if (_stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(cardDetailProvider(_key), asReload: true);
        setState(() => _stale = false);
      });
    }
  }

  Future<void> _refresh() => ref.refresh(cardDetailProvider(_key).future).then<void>((_) {}, onError: (_) {});

  void _setNotice(String? notice, {RindeBannerTone tone = RindeBannerTone.success}) {
    if (mounted) {
      setState(() {
        _notice = notice;
        _noticeTone = tone;
      });
    }
  }

  Future<void> _pay(CreditCard card) async {
    _setNotice(null);
    final paid = await showPayCardSheet(context, card: card);
    if (paid == null || !mounted) return;
    final t = ref.read(trProvider);
    paid
        ? _setNotice(t('Pago registrado.'))
        : _setNotice(t(CardsWriter.unconfirmedText), tone: RindeBannerTone.error);
  }

  Future<void> _sync(CreditCard card) async {
    _setNotice(null);
    final done = await showBankSyncSheet(context, card: card);
    if (done == null || !mounted) return;
    final t = ref.read(trProvider);
    final money = moneyOf(ref);
    _setNotice(
      done.chargeAmount == null
          ? t('Tarjeta actualizada con el banco.')
          : t('Se registró un gasto de {v1} en Cargos del banco.', {'v1': money(done.chargeAmount!)}),
    );
  }

  Future<void> _edit(CreditCard card) async {
    _setNotice(null);
    final saved = await showCardSheet(context, initial: card);
    if (saved == true && mounted) _setNotice(ref.read(trProvider)('Cambios guardados.'));
  }

  Future<void> _deletePayment(String paymentId) async {
    _setNotice(null);
    await ref.read(cardsWriterProvider).deletePayment(widget.cardId, paymentId);
    if (mounted) _setNotice(ref.read(trProvider)('Pago eliminado.'));
  }

  Future<void> _deleteCard() async {
    _setNotice(null);
    await ref.read(cardsWriterProvider).deleteCard(widget.cardId);
    // Como la web: al terminar vuelve a la lista, sin mensaje (CardDetail.jsx:257-260).
    if (mounted) {
      context.canPop() ? context.pop() : context.go(Routes.cards);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final key = (ref.watch(accountProvider), widget.cardId);
    final async = _stale ? const AsyncLoading<CardDetailData>() : ref.watch(cardDetailProvider(key));
    final detail = async.isReloading ? null : async.value;
    final money = moneyOf(ref);
    final error = async.error;
    final notFound = error is ApiException && error.status == 404;

    final children = <Widget>[];
    if (_notice case final notice? when detail != null) {
      children.addAll([
        // Se ve la máscara, como la web; el lector oye «Monto oculto».
        Semantics(
          container: true,
          liveRegion: true,
          label: money.spoken(notice),
          excludeSemantics: true,
          child: RindeBanner(tone: _noticeTone, message: notice),
        ),
        const SizedBox(height: RindeSpace.s4),
      ]);
    }
    if (detail == null && async.hasError && !async.isLoading) {
      children.add(
        RindeStateView(
          icon: RindeIcons.circleAlert,
          title: error is ApiException
              ? t(error.messageFor(fallback: ApiMessages.generic))
              : t(ApiMessages.generic),
          actions: [
            RindeButton(label: t('Reintentar'), onPressed: () => ref.invalidate(cardDetailProvider(key))),
            if (notFound)
              RindeButton(
                label: t('Volver'),
                variant: RindeButtonVariant.outline,
                onPressed: () => context.canPop() ? context.pop() : context.go(Routes.cards),
              ),
          ],
        ),
      );
    } else if (detail == null) {
      children.add(const _Loading());
    } else {
      final card = detail.card;
      if (async.hasError) {
        children.addAll([
          RindeBanner(
            message: moneyErrorText(async.error!, t),
            // La web muestra el error sin «Reintentar» (CardDetail.jsx:236); aquí se agrega con una
            // clave que ya existe.
            action: RindeTextLink(
              label: t('Reintentar'),
              onPressed: () => ref.invalidate(cardDetailProvider(key)),
            ),
          ),
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
        Semantics(
          header: true,
          child: Text(
            '${cardListLabel(t, network: card.network, name: card.name, last4: card.last4)} '
            '${t('· Lo que debes')}',
            style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: RindeSpace.s1),
        MoneyText(
          money(card.used),
          money: money,
          fit: true,
          style: RindeType.display.copyWith(color: p.ink),
        ),
        // Sin deuda y «atrasada» no se dice nada: mismo criterio del aviso del Inicio (pregunta 4).
        if (showDueLine(card)) ...[
          const SizedBox(height: RindeSpace.s2),
          Text(
            dueText(t, card, region),
            // En el detalle del celular la web lo pinta siempre en amarillo (CardDetail.jsx:86).
            style: RindeType.lead.w(FontWeight.w500).copyWith(color: p.caution),
          ),
        ],
        ExpiryBadge(expiry: card.expiry),
        if (card.statementTotal case final statementTotal?) ...[
          const SizedBox(height: RindeSpace.s2),
          MoneyText(
            [
              '${t('Total del extracto')} ${money(statementTotal)}',
              if (card.statementDueDate case final due?)
                t(' · vence el {statementDueDate}', {'statementDueDate': shortCardDate(due, region)}),
            ].join(),
            money: money,
            style: RindeType.small.tabular.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ],
        const SizedBox(height: RindeSpace.s4),
        CardUsageBar(card: card),
        const SizedBox(height: RindeSpace.s2),
        MoneyText(
          '${t('Disponible')} ${money(card.available)} ${t('de')} ${money(card.limit)}',
          money: money,
          style: RindeType.small.tabular.copyWith(color: p.ink.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: RindeSpace.s5),
        RindeCircleActions(
          label: t('Acciones de la tarjeta'),
          actions: [
            RindeCircleAction(
              label: t('Anotar'),
              icon: RindeIcons.plus,
              primary: true,
              onTap: () {
                // La lista de Anotar puede venir de antes (sin esta tarjeta): con ella, el gasto iría en
                // efectivo y bajaría Mi plata. Se vuelve a pedir; mientras carga, la tarjeta va igual.
                ref.invalidate(cardsProvider);
                // El aviso de la acción anterior («Pago eliminado.») no debe seguir ahí al volver.
                _setNotice(null);
                context.push('${Routes.record}?tarjeta=${Uri.encodeComponent(card.id)}');
              },
            ),
            RindeCircleAction(label: t('Abonar'), icon: RindeIcons.circleDollarSign, onTap: () => _pay(card)),
            RindeCircleAction(
              label: t('Actualizar saldo'),
              icon: RindeIcons.refreshCw,
              onTap: () => _sync(card),
            ),
            RindeCircleAction(label: t('Editar'), icon: RindeIcons.pencil, onTap: () => _edit(card)),
          ],
        ),
        const SizedBox(height: RindeSpace.s5),
        HomeSectionTitle(t('Compras y pagos')),
        const SizedBox(height: RindeSpace.s2),
        CardHistory(
          movements: detail.movements,
          money: money,
          onDeletePayment: _deletePayment,
          errorText: (e) => moneyErrorText(e, t),
        ),
        const SizedBox(height: RindeSpace.s5),
        ConfirmInline(
          label: t('Eliminar tarjeta'),
          question: t('¿Eliminar esta tarjeta? Las compras se quedan en tu historial.'),
          confirmLabel: t('Sí, eliminar'),
          cancelLabel: t('Cancelar'),
          onConfirm: _deleteCard,
          errorText: (e) => moneyErrorText(e, t),
        ),
      ]);
    }

    return PushedFrame(
      fallback: Routes.cards,
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

class _Loading extends ConsumerWidget {
  const _Loading();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    container: true,
    label: ref.watch(trProvider)('Cargando…'),
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RindeSkeleton(width: 180, height: 16),
          const SizedBox(height: RindeSpace.s3),
          const RindeSkeleton(width: 220, height: 36),
          const SizedBox(height: RindeSpace.s4),
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: RindeSpace.s3),
            const RindeSkeleton(width: double.infinity, height: 48),
          ],
        ],
      ),
    ),
  );
}
