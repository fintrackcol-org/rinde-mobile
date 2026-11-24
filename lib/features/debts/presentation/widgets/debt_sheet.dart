import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/debts_writer.dart';
import '../../data/debt_models.dart';
import '../../domain/debt_rules.dart';
import 'debt_date_field.dart';

/// Abre «Nueva cuenta» (del lado [kind], el de la pestaña activa) o, con [initial], «Editar cuenta».
/// Devuelve el aviso que la pantalla debe mostrar al cerrarse (sin confirmar, ya saldada, ya no
/// existe), o null. Al crear, [onCreated] recibe el lado de la cuenta nueva. [dueDate] precarga la
/// fecha de pago de una nueva (el «Agregar a este día» del Calendario).
Future<String?> showDebtSheet(
  BuildContext context, {
  Debt? initial,
  DebtKind kind = DebtKind.receivable,
  ValueChanged<DebtKind>? onCreated,
  String? dueDate,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastre: cerraría la hoja mientras guarda, saltándose PopScope.
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => DebtSheet(initial: initial, kind: kind, onCreated: onCreated, dueDate: dueDate),
);

/// El formulario de una cuenta (DebtForm.jsx) en DOS pasos: «Quién y cuánto» y «Cómo se paga». El
/// paso 3, «Cuándo avisar», no se porta (plan §6.1: sin `reminder` el servidor avisa 1 día antes y,
/// al editar, conserva el aviso que había).
/// - Al crear se elige el lado; al editar no. El préstamo es de hoy por defecto.
/// - Con cuotas, la primera cuota se precarga con `firstDueDate`: el `dueDate` leído es la PRÓXIMA.
/// - Un 422 vuelve al paso de su primer campo con error y le pone el foco.
/// - Editar agrega «Abonos» (cada uno con «Borrar abono» en línea) y «Borrar cuenta».
class DebtSheet extends ConsumerStatefulWidget {
  const DebtSheet({super.key, this.initial, this.kind = DebtKind.receivable, this.onCreated, this.dueDate});

  final Debt? initial;
  final DebtKind kind;
  final ValueChanged<DebtKind>? onCreated;

  /// AAAA-MM-DD con que arranca la fecha de pago de una cuenta nueva.
  final String? dueDate;

  @override
  ConsumerState<DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends ConsumerState<DebtSheet> {
  static const _focusOrder = ['person', 'amount', 'loanDate', 'note', 'installments', 'dueDate'];

  /// La cuenta que se edita; cambia al borrar un abono (la respuesta del servidor).
  late Debt? _debt = widget.initial;
  late DebtKind _kind = widget.initial?.kind ?? widget.kind;
  int _step = 0;
  late final _person = TextEditingController(text: widget.initial?.person ?? '');
  late String _amount = widget.initial == null ? '' : _raw(widget.initial!.amount);
  late String? _loanDate = widget.initial == null
      ? isoDay(ref.read(clockProvider)())
      : widget.initial!.loanDate;
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late bool _inInstallments = widget.initial?.installments != null;
  late final _installments = TextEditingController(text: '${widget.initial?.installments ?? 4}');
  late DebtFrequency _frequency = widget.initial?.frequency ?? DebtFrequency.monthly;

  /// Con cuotas es la PRIMERA cuota (DebtForm.jsx:47-48): nunca el `dueDate` leído, que ya es la
  /// próxima y correría todo el calendario al guardar.
  late String? _dueDate = widget.initial == null
      ? widget.dueDate
      : (widget.initial!.installments != null ? widget.initial!.firstDueDate : widget.initial!.dueDate);
  final _focus = {for (final field in _focusOrder) field: FocusNode()};
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  bool get _editing => widget.initial != null;

  static String _raw(num amount) {
    final fixed = amount.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  DebtFormValues get _values => DebtFormValues(
    person: _person.text,
    amount: _amount,
    loanDate: _loanDate,
    inInstallments: _inInstallments,
    installments: _installments.text,
    frequency: _frequency,
    dueDate: _dueDate,
    note: _note.text,
  );

  @override
  void dispose() {
    _person.dispose();
    _note.dispose();
    _installments.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _clear(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Map<String, String> _problems(Tr t, HomeMoney money) =>
      // Oculto dice «Monto oculto» (también al lector), no la máscara: va dentro del error del campo.
      debtFormProblems(t, _values, paid: _debt?.paid ?? 0, paidText: money.spoken(money(_debt?.paid ?? 0)));

  /// Marca los errores, vuelve al paso del primero y le pone el foco (DebtForm.jsx:104-113).
  void _show(Map<String, String> errors, String? error) {
    final step = debtStepFields.indexWhere((fields) => fields.any(errors.containsKey));
    setState(() {
      _errors = errors;
      _error = error;
      if (step >= 0) _step = step;
    });
    final first = _focusOrder.where(errors.containsKey).firstOrNull;
    if (first != null) {
      // El campo puede ser del otro paso: existe en el cuadro siguiente.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[first]!.requestFocus();
      });
    }
  }

  Future<void> _next() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final problems = _problems(t, moneyOf(ref));
    // Cada paso revisa solo sus campos antes de seguir (DebtForm.jsx:116-118).
    final mine = {
      for (final MapEntry(:key, :value) in problems.entries)
        if (debtStepFields[_step].contains(key)) key: value,
    };
    if (mine.isNotEmpty) return _show(mine, null);
    if (_step == 0) {
      setState(() {
        _step = 1;
        _errors = const {};
        _error = null;
      });
      return;
    }
    if (problems.isNotEmpty) return _show(problems, null);
    await _save(t);
  }

  Future<void> _save(Tr t) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final writer = ref.read(debtsWriterProvider);
    try {
      if (widget.initial case final initial?) {
        await writer.update(initial.id, debtBody(_values));
      } else {
        await writer.create(debtBody(_values, kind: _kind));
        widget.onCreated?.call(_kind);
      }
      _close();
    } on ApiException catch (e) {
      if (!mounted) return;
      // En duda sin confirmar, ya saldada o ya no existe: la hoja se cierra y la pantalla (ya
      // recargada) muestra el mensaje. Sin confirmar, la pestaña también salta a su lado.
      if (e.code == ApiCodes.unconfirmed || (_editing && (e.status == 404 || e.status == 409))) {
        if (!_editing) widget.onCreated?.call(_kind);
        _close(moneyErrorText(e, t));
        return;
      }
      // `kind` no tiene dónde mostrarse en la hoja: va al aviso general (como serverError de la web).
      const placeable = {..._focusOrder, 'frequency'};
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (placeable.contains(key)) key: t(value),
      };
      final unplaced = fields.isEmpty || e.fields.keys.any((k) => !placeable.contains(k));
      _show(fields, unplaced ? moneyErrorText(e, t) : null);
    } on Object catch (e) {
      if (mounted) _show(const {}, moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Borrar un abono: la lista de la hoja pasa a la cuenta como quedó. Con un 404 que no es «ya
  /// estaba borrado» (la cuenta quedó saldada o ya no existe), la hoja se cierra con el mensaje.
  Future<void> _deletePayment(DebtPayment payment) async {
    final t = ref.read(trProvider);
    try {
      final updated = await ref.read(debtsWriterProvider).deletePayment(_debt!, payment);
      if (mounted) setState(() => _debt = updated);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      _close(moneyErrorText(e, t));
    }
  }

  Future<void> _deleteDebt() async {
    await ref.read(debtsWriterProvider).delete(_debt!.id);
    _close();
  }

  /// Cierra la hoja UNA vez: guardar y borrar pueden terminar los dos (o la hoja ya se cerró con
  /// atrás), y un segundo pop durante la salida, que no mira PopScope, sacaría de Cuentas.
  void _close([String? notice]) {
    if (mounted && (ModalRoute.of(context)?.isActive ?? false)) Navigator.of(context).pop(notice);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final money = moneyOf(ref);
    final today = isoDay(ref.watch(clockProvider)());
    final receivable = _kind == DebtKind.receivable;
    final stepTitle = _step == 0 ? t('Quién y cuánto') : t('Cómo se paga');
    final stepText = '${t('Paso')} ${_step + 1} ${t('de')} 2 · $stepTitle';
    final preview = debtPlanPreview(t, _values, today: today, region: region, money: money.call);

    final form = <Widget>[
      if (_step == 0) ...[
        if (!_editing) ...[
          ExcludeSemantics(
            child: Text(t('¿Quién debe?'), style: RindeType.label.copyWith(color: p.inkLabel)),
          ),
          const SizedBox(height: RindeSpace.s2),
          RindeSegmented<DebtKind>(
            options: {DebtKind.receivable: t('Me deben'), DebtKind.payable: t('Debo')},
            value: _kind,
            semanticLabel: t('¿Quién debe?'),
            onChanged: _saving ? null : (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: RindeSpace.s4),
        ],
        RindeTextField(
          label: receivable ? t('¿Quién te debe?') : t('¿A quién le debes?'),
          controller: _person,
          hint: t('Nombre'),
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          enabled: !_saving,
          focusNode: _focus['person'],
          serverError: _errors['person'],
          onChanged: (_) => _clear('person'),
        ),
        const SizedBox(height: RindeSpace.s4),
        RindeMoneyField(
          value: _amount,
          format: formatFor(region),
          // TEXTO ajustado: la web dice «¿Cuánto? (COP)» fijo aunque la moneda sea otra.
          label: t('¿Cuánto? ({currency})', {'currency': region.currency}),
          semanticLabel: t('¿Cuánto? ({currency})', {'currency': region.currency}),
          enabled: !_saving,
          focusNode: _focus['amount'],
          errorText: _errors['amount'],
          onChanged: (raw) => setState(() {
            _amount = raw;
            _errors = {..._errors}..remove('amount');
          }),
        ),
        const SizedBox(height: RindeSpace.s4),
        DebtDateField(
          label: receivable ? t('¿Cuándo le prestaste?') : t('¿Cuándo te prestaron?'),
          value: _loanDate,
          optional: true,
          lastIsToday: true,
          enabled: !_saving,
          focusNode: _focus['loanDate'],
          error: _errors['loanDate'],
          onChanged: (date) => setState(() {
            _loanDate = date;
            _errors = {..._errors}..remove('loanDate');
          }),
        ),
        const SizedBox(height: RindeSpace.s4),
        RindeTextField(
          label: t('Nota (opcional)'),
          controller: _note,
          hint: receivable ? t('Ej.: le presté para el bus') : t('Ej.: el almuerzo del viernes'),
          maxLength: 200,
          enabled: !_saving,
          focusNode: _focus['note'],
          serverError: _errors['note'],
          onChanged: (_) => _clear('note'),
        ),
      ] else ...[
        ExcludeSemantics(
          child: Text(t('¿Cómo se paga?'), style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeSegmented<bool>(
          options: {false: t('De una vez'), true: t('En cuotas')},
          value: _inInstallments,
          semanticLabel: t('¿Cómo se paga?'),
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _inInstallments = value;
                  _errors = const {};
                }),
        ),
        const SizedBox(height: RindeSpace.s4),
        if (_inInstallments) ...[
          RindeTextField(
            label: t('¿Cuántas cuotas?'),
            controller: _installments,
            keyboardType: TextInputType.number,
            maxLength: 2,
            enabled: !_saving,
            focusNode: _focus['installments'],
            serverError: _errors['installments'],
            onChanged: (_) => setState(() => _clear('installments')),
          ),
          const SizedBox(height: RindeSpace.s4),
          ExcludeSemantics(
            child: Text(t('¿Cada cuánto?'), style: RindeType.label.copyWith(color: p.inkLabel)),
          ),
          const SizedBox(height: RindeSpace.s2),
          RindeSegmented<DebtFrequency>(
            options: {for (final f in DebtFrequency.values) f: frequencyLabel(t, f)},
            value: _frequency,
            semanticLabel: t('¿Cada cuánto?'),
            onChanged: _saving ? null : (f) => setState(() => _frequency = f),
          ),
          if (_errors['frequency'] case final error?)
            Text(error, style: RindeType.small.copyWith(color: p.negative)),
          const SizedBox(height: RindeSpace.s4),
          DebtDateField(
            label: t('¿Cuándo es la primera cuota?'),
            value: _dueDate,
            enabled: !_saving,
            focusNode: _focus['dueDate'],
            error: _errors['dueDate'],
            onChanged: (date) => setState(() {
              _dueDate = date;
              _errors = {..._errors}..remove('dueDate');
            }),
          ),
          if (preview != null) ...[
            const SizedBox(height: RindeSpace.s3),
            DecoratedBox(
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
              child: Padding(
                padding: const EdgeInsets.all(RindeSpace.s3),
                child: MoneyText(
                  preview,
                  money: money,
                  style: RindeType.small.w(FontWeight.w500).copyWith(color: p.brand),
                ),
              ),
            ),
          ],
        ] else
          DebtDateField(
            label: t('¿Para cuándo? (opcional)'),
            value: _dueDate,
            optional: true,
            enabled: !_saving,
            focusNode: _focus['dueDate'],
            error: _errors['dueDate'],
            onChanged: (date) => setState(() {
              _dueDate = date;
              _errors = {..._errors}..remove('dueDate');
            }),
          ),
        const SizedBox(height: RindeSpace.s4),
        Text(
          t('Esto no cambia lo que tienes en Mi plata hasta que registres un abono.'),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
      ],
    ];

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
                child: Text(
                  _editing ? t('Editar cuenta') : t('Nueva cuenta'),
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              Semantics(
                liveRegion: true,
                label: stepText,
                excludeSemantics: true,
                child: Text(stepText.toUpperCase(), style: RindeType.eyebrow.copyWith(color: p.inkMuted)),
              ),
              const SizedBox(height: RindeSpace.s2),
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          key: ValueKey('paso-$i'),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step ? p.brand : p.line,
                            borderRadius: BorderRadius.circular(RindeRadius.pill),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: RindeSpace.s5),
              ...form,
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: _step == 0
                    ? t('Siguiente')
                    : _editing
                    ? t('Guardar cambios')
                    : t('Guardar cuenta'),
                loading: _saving,
                loadingLabel: t('Guardando…'),
                onPressed: _next,
              ),
              if (_step > 0) ...[
                const SizedBox(height: RindeSpace.s2),
                RindeButton(
                  label: t('Atrás'),
                  variant: RindeButtonVariant.outline,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _step = 0;
                          _error = null;
                        }),
                ),
              ],
              if (_debt case final debt?) ...[
                if (debt.payments.isNotEmpty) ...[
                  const SizedBox(height: RindeSpace.s5),
                  Divider(height: 1, color: p.line),
                  const SizedBox(height: RindeSpace.s4),
                  _Payments(debt: debt, money: money, today: today, region: region, onDelete: _deletePayment),
                ],
                const SizedBox(height: RindeSpace.s4),
                ConfirmInline(
                  label: t('Borrar cuenta'),
                  question: t('¿Borrar la cuenta de {person}? No se puede deshacer.', {
                    'person': debt.person,
                  }),
                  confirmLabel: t('Sí, borrar'),
                  cancelLabel: t('Cancelar'),
                  onConfirm: _deleteDebt,
                  errorText: (e) => moneyErrorText(e, t),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «Abonos» de la hoja de editar (PaymentHistory de Debts.jsx): fecha, monto y «Borrar abono» en línea.
class _Payments extends ConsumerWidget {
  const _Payments({
    required this.debt,
    required this.money,
    required this.today,
    required this.region,
    required this.onDelete,
  });

  final Debt debt;
  final HomeMoney money;
  final String today;
  final Region region;
  final Future<void> Function(DebtPayment payment) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(t('Abonos'), style: RindeType.small.w(FontWeight.w500).copyWith(color: p.inkLabel)),
        ),
        for (final (payment, question) in [
          for (final payment in debt.payments)
            (
              payment,
              t('¿Borrar el abono de {amount}?{v2}', {
                'amount': money(payment.amount),
                'v2': payment.transactionId == null
                    ? ''
                    : t(' También se borra el movimiento que se anotó con él.'),
              }),
            ),
        ])
          Padding(
            // Si la lista cambia con una confirmación abierta, esta sigue con SU abono.
            key: ValueKey('abono-${payment.id}'),
            padding: const EdgeInsets.only(top: RindeSpace.s2),
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.wash, borderRadius: RindeRadius.brXl),
              child: Padding(
                padding: const EdgeInsets.all(RindeSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: RindeSpace.s3,
                      children: [
                        Text(
                          debtShortDate(payment.date, today, region),
                          style: RindeType.small.copyWith(color: p.ink),
                        ),
                        MoneyText(
                          money(payment.amount),
                          money: money,
                          style: RindeType.small.w(FontWeight.w600).copyWith(color: p.ink),
                        ),
                      ],
                    ),
                    ConfirmInline(
                      compact: true,
                      label: t('Borrar abono'),
                      question: question,
                      questionSemantics: money.spoken(question),
                      confirmLabel: t('Sí, borrar'),
                      cancelLabel: t('Cancelar'),
                      onConfirm: () => onDelete(payment),
                      errorText: (e) => moneyErrorText(e, t),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
