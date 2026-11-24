import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/money_text.dart' show maxAmount, moneyValue;
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/cards_writer.dart';
import '../../data/card_models.dart';

/// Abre «Ya pagué». true: el pago quedó registrado. false: quedó en duda y no se pudo confirmar; la
/// hoja se cierra para dejar a la vista el historial, donde se borra un pago doble (plan §3.A), en
/// vez de dejar «Registrar pago» a mano para repetirlo sin revisar.
Future<bool?> showPayCardSheet(BuildContext context, {required CreditCard card}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => PayCardSheet(card: card),
    );

/// «Ya pagué» (PayCardForm.jsx): el monto viene sugerido (el extracto o lo usado) y la fecha es hoy,
/// como máximo hoy. La etiqueta dice la moneda PRINCIPAL del usuario: la web la deja fija en COP.
/// El monto precargado se ve aunque los montos estén ocultos, igual que en la web (pregunta 12 de
/// la etapa 4): es un campo que la persona va a editar.
class PayCardSheet extends ConsumerStatefulWidget {
  const PayCardSheet({super.key, required this.card});

  final CreditCard card;

  @override
  ConsumerState<PayCardSheet> createState() => _PayCardSheetState();
}

class _PayCardSheetState extends ConsumerState<PayCardSheet> {
  late String _amount = _raw(widget.card.statementTotal ?? widget.card.used);
  late String _date = isoDay(ref.read(clockProvider)());
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;
  final _amountFocus = FocusNode();

  @override
  void dispose() {
    _amountFocus.dispose();
    super.dispose();
  }

  static String _raw(num amount) {
    final fixed = amount.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  Future<void> _pickDate() async {
    final today = DateTime.parse(isoDay(ref.read(clockProvider)()));
    final current = DateTime.parse(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(2000),
      // Como el max=hoy de la web; el servidor igual rechaza una fecha futura.
      lastDate: today,
      helpText: ref.read(trProvider)('Fecha del pago'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = isoDay(picked);
      _errors = {..._errors}..remove('date');
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final amount = moneyValue(_amount);
    // payCardSchema de la web.
    final problem = amount == null
        ? t('Ingresa un monto')
        : amount <= 0
        ? t('El pago debe ser mayor que 0')
        : amount > maxAmount
        ? t('El monto es demasiado grande')
        : null;
    if (problem != null) {
      setState(() => _errors = {'amount': problem});
      _amountFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    try {
      await ref.read(cardsWriterProvider).pay(widget.card.id, amount: amount!, date: _date);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == ApiCodes.unconfirmed) {
        Navigator.of(context).pop(false);
        return;
      }
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (key == 'amount' || key == 'date') key: t(value),
      };
      setState(() {
        _errors = fields;
        _error = fields.length == e.fields.length && fields.isNotEmpty ? null : moneyErrorText(e, t);
      });
      if (fields.containsKey('amount')) _amountFocus.requestFocus();
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(t('Ya pagué'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _amount,
                format: formatFor(region),
                // TEXTO ajustado: la web dice «Monto pagado (COP)» fijo aunque la moneda sea otra.
                label: t('Monto pagado ({currency})', {'currency': region.currency}),
                semanticLabel: t('Monto pagado ({currency})', {'currency': region.currency}),
                enabled: !_saving,
                focusNode: _amountFocus,
                errorText: _errors['amount'],
                onChanged: (raw) => setState(() {
                  _amount = raw;
                  _errors = {..._errors}..remove('amount');
                }),
              ),
              const SizedBox(height: RindeSpace.s4),
              ExcludeSemantics(
                child: Text(t('Fecha del pago'), style: RindeType.label.copyWith(color: p.inkLabel)),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  label: t('Fecha del pago'),
                  child: TextButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    icon: RindeIcon(RindeIcons.calendarRange, size: 18, color: p.brand),
                    label: Text(
                      dayAndMonth(_date, region),
                      style: RindeType.bodyMedium.copyWith(color: p.brand),
                    ),
                  ),
                ),
              ),
              if (_errors['date'] case final dateError?)
                Semantics(
                  liveRegion: true,
                  child: Text(dateError, style: RindeType.small.copyWith(color: p.negative)),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: t('Registrar pago'),
                loading: _saving,
                loadingLabel: t('Guardando…'),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
