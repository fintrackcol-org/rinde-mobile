import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/money_text.dart' show moneyValue;
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_checkbox.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/debts_writer.dart';
import '../../data/debt_models.dart';
import '../../domain/debt_rules.dart';
import 'debt_date_field.dart';

/// Abre «Registrar abono». Devuelve el aviso para la pantalla (en duda sin confirmar, ya saldada, ya
/// no existe) o null.
Future<String?> showDebtPaymentSheet(BuildContext context, {required Debt debt}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => DebtPaymentSheet(debt: debt),
    );

/// «Registrar abono» (PaymentForm.jsx): propone la próxima cuota (o lo pendiente) y ofrece «Todo lo que
/// falta»; no deja pasar de lo pendiente; la fecha es hoy por defecto y como máximo; la casilla de
/// anotar el movimiento viene marcada. El monto precargado se ve aunque los montos estén ocultos,
/// como la web: es un campo que se va a editar.
class DebtPaymentSheet extends ConsumerStatefulWidget {
  const DebtPaymentSheet({super.key, required this.debt});

  final Debt debt;

  @override
  ConsumerState<DebtPaymentSheet> createState() => _DebtPaymentSheetState();
}

class _DebtPaymentSheetState extends ConsumerState<DebtPaymentSheet> {
  late final num _suggested = widget.debt.nextInstallment?.amount ?? widget.debt.pending;
  late String _amount = _raw(_suggested);
  late String _date = isoDay(ref.read(clockProvider)());
  bool _record = true;
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

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final debt = widget.debt;
    final money = moneyOf(ref);
    final problems = debtPaymentProblems(
      t,
      amount: _amount,
      pending: debt.pending,
      // Oculto dice «Monto oculto» (también al lector), no la máscara: va dentro del error del campo.
      pendingText: money.spoken(money(debt.pending)),
    );
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
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
      await ref
          .read(debtsWriterProvider)
          .pay(debt.id, amount: moneyValue(_amount)!, date: _date, createTransaction: _record);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Sin confirmar: se cierra para no repetirlo a ciegas (los abonos quedan en «Editar»). Ya
      // saldada o ya no existe: se cierra y la lista, ya recargada, muestra el mensaje del servidor.
      if (e.code == ApiCodes.unconfirmed || e.status == 404 || e.status == 409) {
        Navigator.of(context).pop(moneyErrorText(e, t));
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
    final money = moneyOf(ref);
    final debt = widget.debt;
    final receivable = debt.kind == DebtKind.receivable;
    final next = debt.nextInstallment;
    final header = [
      receivable
          ? t('{person} te debe ', {'person': debt.person})
          : t('Le debes a {person} ', {'person': debt.person}),
      money(debt.pending),
      if (next != null && debt.installments != null)
        ' ${t('· cuota')} ${next.number} ${t('de')} ${debt.installments}',
      '.',
    ].join();
    final all = '${t('Todo lo que falta (')}${money(debt.pending)})';

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
                child: Text(t('Registrar abono'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s3),
              MoneyText(
                header,
                money: money,
                style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _amount,
                format: formatFor(region),
                label: receivable ? t('¿Cuánto te pagó?') : t('¿Cuánto pagaste?'),
                semanticLabel: receivable ? t('¿Cuánto te pagó?') : t('¿Cuánto pagaste?'),
                enabled: !_saving,
                focusNode: _amountFocus,
                errorText: _errors['amount'],
                onChanged: (raw) => setState(() {
                  _amount = raw;
                  _errors = {..._errors}..remove('amount');
                }),
              ),
              if ((_suggested * 100).round() != (debt.pending * 100).round())
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _amount = _raw(debt.pending);
                            _errors = {..._errors}..remove('amount');
                          }),
                    style: TextButton.styleFrom(
                      foregroundColor: p.brand,
                      minimumSize: const Size(48, RindeSize.button),
                      textStyle: RindeType.small.w(FontWeight.w500),
                    ),
                    // El botón conserva su acción y su estado para el lector; solo cambia lo que oye.
                    child: Text(all, semanticsLabel: money.spoken(all)),
                  ),
                ),
              const SizedBox(height: RindeSpace.s4),
              DebtDateField(
                label: t('¿Cuándo?'),
                value: _date,
                lastIsToday: true,
                enabled: !_saving,
                error: _errors['date'],
                onChanged: (date) => setState(() {
                  if (date != null) _date = date;
                  _errors = {..._errors}..remove('date');
                }),
              ),
              const SizedBox(height: RindeSpace.s4),
              DebtMovementBox(
                title: receivable
                    ? t('Anotar el ingreso en Movimientos')
                    : t('Anotar el gasto en Movimientos'),
                detail: t('Así tu saldo de hoy queda bien.'),
                enabled: !_saving,
                onChanged: (value) => _record = value,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: t('Registrar abono'),
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

/// La casilla marcada de «Anotar el ingreso/gasto en Movimientos» en su caja gris (abonar y saldar).
class DebtMovementBox extends StatelessWidget {
  const DebtMovementBox({
    super.key,
    required this.title,
    required this.detail,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String detail;
  final ValueChanged<bool> onChanged;

  /// Mientras guarda no se cambia (como la web): el envío ya salió con lo que estaba marcado.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3),
        child: IgnorePointer(
          ignoring: !enabled,
          child: RindeCheckboxField(
            initialValue: true,
            semanticLabel: title,
            onChanged: onChanged,
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RindeType.small.w(FontWeight.w500).copyWith(color: p.ink)),
                Text(detail, style: RindeType.small.copyWith(color: p.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
