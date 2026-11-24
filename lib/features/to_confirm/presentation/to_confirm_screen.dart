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
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_text_field.dart';
import '../../auth/application/session_controller.dart';
import '../../cards/application/cards_providers.dart' show cardsProvider;
import '../../cards/data/card_models.dart' show CreditCard;
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/data/home_models.dart' show readMoney;
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../movements/domain/movement.dart' show MovementType;
import '../../movements/presentation/list/movement_dates.dart';
import '../../movements/presentation/record/movement_form.dart' show MovementCategoryPicker, PaidWithPicker;
import '../../shell/presentation/pushed_frame.dart';
import '../application/to_confirm_writer.dart';
import '../data/to_confirm_repository.dart';

/// `/app/por-confirmar` (PendingPayments.jsx): pagos con Apple Pay que esperan aprobación (FT-0047).
/// Confirmar anota el gasto (hoja «Confirmar pago»); descartar no anota nada. Sin pantalla anterior,
/// atrás va a Movimientos (backPath de la web).
class ToConfirmScreen extends ConsumerStatefulWidget {
  const ToConfirmScreen({super.key});

  @override
  ConsumerState<ToConfirmScreen> createState() => _ToConfirmScreenState();
}

class _ToConfirmScreenState extends ConsumerState<ToConfirmScreen> {
  String? _notice;
  String? _error;
  String? _discarding;

  /// Los que ya se confirmaron o descartaron: salen de la lista sin esperar a que llegue la recarga.
  final _resolved = <String>{};

  Future<void> _confirm(IncomingPayment payment) async {
    setState(() => (_notice = null, _error = null));
    final description = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Sin arrastre: cerraría la hoja mientras guarda, saltándose PopScope.
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => _ConfirmSheet(payment: payment),
    );
    if (description == null || !mounted) return;
    final t = ref.read(trProvider);
    _resolved.add(payment.id);
    setState(
      () => _notice = t('Anotado: {description}, {amount}.', {
        'description': description,
        'amount': moneyOf(ref)(payment.amount),
      }),
    );
  }

  Future<void> _discard(IncomingPayment payment) async {
    final t = ref.read(trProvider);
    setState(() => (_discarding = payment.id, _notice = null, _error = null));
    try {
      await ref.read(toConfirmWriterProvider).discard(payment);
      _resolved.add(payment.id);
      if (mounted) {
        setState(
          () => _notice = t('Descartado: {merchant}. No se anotó nada.', {'merchant': payment.merchant}),
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _discarding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(toConfirmListProvider(account));
    final money = moneyOf(ref);
    final items = async.value?.where((p) => !_resolved.contains(p.id)).toList();

    final children = <Widget>[
      Text(
        t('Pagos con Apple Pay que llegaron desde tu iPhone.'),
        style: RindeType.body.copyWith(color: p.inkMuted),
      ),
      const SizedBox(height: RindeSpace.s4),
      if (_error case final error?) ...[
        RindeBanner(
          message: error,
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () {
              setState(() => _error = null);
              ref.invalidate(toConfirmListProvider(account));
            },
          ),
        ),
        const SizedBox(height: RindeSpace.s3),
      ],
      if (async.hasError && !async.isLoading && items == null)
        RindeBanner(
          message: moneyErrorText(async.error!, t),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(toConfirmListProvider(account)),
          ),
        )
      else if (items == null)
        Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted))
      else ...[
        if (_notice case final notice?) ...[
          RindeBanner(
            tone: RindeBannerTone.info,
            message: notice,
            semanticsLabel: money.spoken(notice),
            action: RindeTextLink(label: t('Ver movimientos'), onPressed: () => context.push(Routes.myMoney)),
          ),
          const SizedBox(height: RindeSpace.s4),
        ],
        if (items.isEmpty)
          HomeSurface(
            padding: const EdgeInsets.all(RindeSpace.s5),
            child: Text(
              t(
                'No hay pagos por revisar. Cuando pagues con Apple Pay, el pago llega aquí y tú decides si se anota.',
              ),
              textAlign: TextAlign.center,
              style: RindeType.body.copyWith(color: p.inkMuted),
            ),
          )
        else ...[
          HomeSurface(
            padding: const EdgeInsets.all(RindeSpace.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items.length == 1
                      ? t('1 pago sin revisar')
                      : t('{length} pagos sin revisar', {'length': items.length}),
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
                const SizedBox(height: RindeSpace.s1),
                MoneyText(
                  money(readMoney(items.fold(0, (sum, i) => sum + (i.amount * 100).round()) / 100)!),
                  money: money,
                  style: RindeType.figure.w(FontWeight.w600).copyWith(color: p.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: RindeSpace.s4),
          Semantics(
            container: true,
            label: t('Pagos por confirmar'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: RindeSpace.s2,
              children: [
                for (final payment in items)
                  _PaymentRow(
                    payment: payment,
                    money: money,
                    busy: _discarding == payment.id,
                    onConfirm: () => _confirm(payment),
                    onDiscard: () => _discard(payment),
                  ),
              ],
            ),
          ),
        ],
      ],
    ];

    return PushedFrame(
      title: t('Por confirmar'),
      fallback: Routes.movements,
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () async {
          ref.invalidate(toConfirmListProvider(account));
          await ref.read(toConfirmListProvider(account).future).then((_) {}, onError: (_) {});
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

/// Un pago de la lista (PaymentRow de la web).
class _PaymentRow extends ConsumerWidget {
  const _PaymentRow({
    required this.payment,
    required this.money,
    required this.busy,
    required this.onConfirm,
    required this.onDiscard,
  });

  final IncomingPayment payment;
  final HomeMoney money;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final day = relativeDay(payment.date, ref.watch(todayProvider), region, t);
    return HomeSurface(
      padding: const EdgeInsets.all(RindeSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(payment.merchant, style: RindeType.bodyMedium.copyWith(color: p.ink)),
              ),
              const SizedBox(width: RindeSpace.s3),
              MoneyText(
                money(payment.amount),
                money: money,
                style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            payment.card == null ? day : '$day · ${payment.card}',
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          if (payment.possibleDuplicate) ...[
            const SizedBox(height: RindeSpace.s1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RindeIcon(RindeIcons.triangleAlert, size: 16, color: p.caution),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t('Puede que ya lo hayas anotado: hay un gasto igual por esos días.'),
                    style: RindeType.small.w(FontWeight.w500).copyWith(color: p.caution),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: RindeSpace.s3),
          Row(
            spacing: RindeSpace.s2,
            children: [
              Expanded(
                child: RindeButton(
                  label: t('Confirmar'),
                  size: RindeButtonSize.sm,
                  leading: const RindeIcon(RindeIcons.check, size: 16, color: Colors.white),
                  onPressed: busy ? null : onConfirm,
                ),
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: t('Descartar el pago en {merchant}', {'merchant': payment.merchant}),
                  excludeSemantics: true,
                  onTap: busy ? null : onDiscard,
                  child: RindeButton(
                    label: t('Descartar'),
                    size: RindeButtonSize.sm,
                    variant: RindeButtonVariant.outline,
                    loading: busy,
                    leading: RindeIcon(RindeIcons.x, size: 16, color: p.ink),
                    onPressed: busy ? null : onDiscard,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hoja «Confirmar pago» (ConfirmForm de la web): la descripción (el comercio, editable), la
/// categoría (o que la elija la IA) y «Pagado con», como en Anotar: con tarjeta el gasto no resta de
/// Mi plata hasta pagarla. Arranca con la tarjeta de Wallet si coincide sin duda ([walletCardMatch]);
/// si no, «Efectivo o débito». Devuelve la descripción anotada al confirmar.
class _ConfirmSheet extends ConsumerStatefulWidget {
  const _ConfirmSheet({required this.payment});
  final IncomingPayment payment;

  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  late final _description = TextEditingController(text: widget.payment.merchant);
  String? _category;

  /// La tarjeta que eligió la persona (null = «Efectivo o débito»); antes de tocar nada manda la de
  /// Wallet ([walletCardMatch]).
  String? _card;
  bool _cardTouched = false;
  String? _cardError;
  bool _showAll = false;
  bool _busy = false;
  String? _error;
  String? _fieldError;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// Las tarjetas cargadas, o null mientras cargan o si fallaron: entonces «Pagado con» no aparece y
  /// el gasto va en efectivo, como en Anotar.
  static List<CreditCard>? _known(AsyncValue<List<CreditCard>> cards) =>
      cards.isLoading || cards.hasError ? null : cards.value;

  /// La tarjeta que se manda: solo una de la lista cargada.
  String? _selected(List<CreditCard>? cards) {
    if (cards == null || cards.isEmpty) return null;
    if (!_cardTouched) return walletCardMatch(widget.payment.card, cards);
    return cards.any((c) => c.id == _card) ? _card : null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final t = ref.read(trProvider);
    final text = _description.text.trim();
    if (text.isEmpty) {
      setState(() => _fieldError = t('Escribe una descripción'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => (_busy = true, _error = null, _fieldError = null));
    try {
      final card = _selected(_known(ref.read(cardsProvider(ref.read(accountProvider)))));
      await ref
          .read(toConfirmWriterProvider)
          .confirm(widget.payment, description: text, category: _category, card: card);
      if (mounted) Navigator.of(context).pop(text);
    } on ApiException catch (e) {
      final field = e.fields['description'];
      // Tarjeta ajena o borrada en otro dispositivo: la lista se pone al día y el campo lo dice.
      final cardField = e.fields['card'];
      if (cardField != null) ref.invalidate(cardsProvider);
      if (mounted) {
        setState(
          () => (
            _error = moneyErrorText(e, t),
            _fieldError = field == null ? null : t(field),
            _cardError = cardField == null ? null : t(cardField),
            _busy = false,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => (_error = moneyErrorText(e, t), _busy = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final money = moneyOf(ref);
    final payment = widget.payment;
    final cards = _known(ref.watch(cardsProvider(ref.watch(accountProvider))));
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(t('Confirmar pago'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s4),
              MoneyText(
                '${t('Se anota un gasto de')} ${money(payment.amount)} ${t('con fecha')} '
                '${shortDate(parseIsoDay(payment.date), region)}.',
                money: money,
                style: RindeType.body.copyWith(color: p.ink),
              ),
              const SizedBox(height: RindeSpace.s5),
              RindeTextField(
                label: t('Descripción'),
                controller: _description,
                maxLength: 200,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                serverError: _fieldError,
                onChanged: (_) {
                  if (_fieldError != null) setState(() => _fieldError = null);
                },
              ),
              const SizedBox(height: RindeSpace.s5),
              MovementCategoryPicker(
                type: MovementType.expense,
                value: _category,
                showAll: _showAll,
                // «La clasificamos por ti al guardar.» con «Que la elija la IA», como la web.
                editing: true,
                onShowAll: () => setState(() => _showAll = true),
                onChanged: (c) => setState(() => _category = c),
              ),
              if (cards != null && cards.isNotEmpty) ...[
                const SizedBox(height: RindeSpace.s5),
                PaidWithPicker(
                  cards: cards,
                  value: _selected(cards),
                  error: _cardError,
                  onChanged: (id) => setState(() => (_card = id, _cardTouched = true, _cardError = null)),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(label: t('Anotar el gasto'), loading: _busy, onPressed: _submit),
              const SizedBox(height: RindeSpace.s2),
              RindeButton(
                label: t('Cancelar'),
                variant: RindeButtonVariant.outline,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
