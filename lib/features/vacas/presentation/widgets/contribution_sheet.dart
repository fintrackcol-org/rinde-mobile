import 'dart:math' as math;

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
import '../../../../design/widgets/rinde_line.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../debts/presentation/widgets/debt_date_field.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../../home/domain/runway.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../movements/application/movements_controller.dart' show movementCategoriesProvider;
import '../../../movements/domain/movement.dart' show MovementType;
import '../../../movements/presentation/record/movement_form.dart' show ChoiceChipButton;
import '../../application/vacas_writer.dart';
import '../../data/vaca_models.dart';
import '../../domain/vaca_rules.dart';

/// Categoría del gasto que deja el aporte si no se elige otra (la misma que usa el servidor).
const kVacaCategory = 'ahorro_inversion';

/// Abre «Aportar» (ContributionForm.jsx del detalle) o, con [quick], «Apartar plata» (SaveSheet de
/// Metas.jsx: propone el plan de la semana, cómo queda la meta y hasta cuándo alcanzaría Mi plata con
/// [balance] y [monthExpense]). El aporte crea un GASTO en Movimientos. Devuelve el monto que quedó
/// registrado, o null si se cerró. Necesita conexión (la cola sin conexión de la web no se porta).
Future<num?> showContributionSheet(
  BuildContext context, {
  required Vaca vaca,
  bool quick = false,
  num? balance,
  num? monthExpense,
}) => showModalBottomSheet<num>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => _ContributionSheet(vaca: vaca, quick: quick, balance: balance, monthExpense: monthExpense),
);

class _ContributionSheet extends ConsumerStatefulWidget {
  const _ContributionSheet({required this.vaca, required this.quick, this.balance, this.monthExpense});

  final Vaca vaca;
  final bool quick;
  final num? balance;
  final num? monthExpense;

  @override
  ConsumerState<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<_ContributionSheet> {
  late final num? _suggested = _plan();
  late String _amount = widget.quick && _suggested != null ? '${_suggested.round()}' : '';
  late String _date = isoDay(ref.read(clockProvider)());
  String _category = kVacaCategory;
  final _note = TextEditingController();
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  /// El plan de la semana, sin pasarse de lo que falta (Metas.jsx).
  num? _plan() {
    final week = widget.vaca.projection.neededPerWeek ?? 0;
    return week > 0 ? math.min(upToThousand(week), widget.vaca.projection.remaining) : null;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final amount = moneyValue(_amount);
    final note = _note.text.trim();
    // contributionSchema de la web; «Apartar plata» tiene su propio aviso.
    final problem = amount == null || amount <= 0
        ? (widget.quick
              ? t('Escribe cuánto vas a apartar')
              : amount == null
              ? t('Ingresa un monto válido')
              : t('El aporte debe ser mayor que 0'))
        : amount > maxAmount
        ? t('El monto es demasiado grande')
        : null;
    if (problem != null) {
      setState(() => _errors = {'amount': problem});
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    try {
      final saved = await ref.read(vacasWriterProvider).contribute(widget.vaca.id, {
        'amount': amount,
        'date': _date,
        'note': widget.quick || note.isEmpty ? null : note,
        'category': widget.quick ? kVacaCategory : _category,
      });
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      const known = {'amount', 'date', 'note', 'category'};
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (known.contains(key)) key: t(value),
      };
      setState(() {
        _errors = fields;
        _error = fields.isNotEmpty && fields.length == e.fields.length ? null : moneyErrorText(e, t);
      });
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
    final vaca = widget.vaca;
    final value = moneyValue(_amount) ?? 0;
    final String title;
    final String? description;
    if (widget.quick) {
      title = t('Apartar para {name}', {'name': vaca.name});
      description = null;
    } else {
      title = t('Aportar');
      description = vaca.personal
          ? (vaca.myRemaining > 0
                ? t('Te faltan {myRemaining} para la meta.', {'myRemaining': pesos(money, vaca.myRemaining)})
                : t('Ya completaste la meta.'))
          : (vaca.myRemaining > 0
                ? t('Te faltan {myRemaining} de tu parte.', {'myRemaining': pesos(money, vaca.myRemaining)})
                : t('Ya pusiste tu parte.'));
    }
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
                child: Text(title, style: RindeType.title.copyWith(color: p.ink)),
              ),
              if (description != null) ...[
                const SizedBox(height: RindeSpace.s1),
                MoneyText(
                  description,
                  money: money,
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
              ],
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _amount,
                format: formatFor(region),
                // TEXTO ajustado: la web dice «Monto del aporte (COP)» fijo aunque la moneda sea otra.
                label: widget.quick
                    ? t('¿Cuánto apartas hoy?')
                    : t('Monto del aporte ({currency})', {'currency': region.currency}),
                semanticLabel: widget.quick
                    ? t('¿Cuánto apartas hoy?')
                    : t('Monto del aporte ({currency})', {'currency': region.currency}),
                enabled: !_saving,
                errorText: _errors['amount'],
                onChanged: (raw) => setState(() {
                  _amount = raw;
                  _errors = {..._errors}..remove('amount');
                }),
              ),
              if (widget.quick && _suggested != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ChoiceChipButton(
                    label: '${pesos(money, _suggested)} ${t('· tu plan')}',
                    selected: false,
                    onTap: () => setState(() => _amount = '${_suggested.round()}'),
                  ),
                ),
              if (!widget.quick && vaca.myRemaining > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: RindeTextLink(
                    label: '${t('Poner lo que me falta (')}${pesos(money, vaca.myRemaining)})',
                    onPressed: _saving ? null : () => setState(() => _amount = '${vaca.myRemaining.round()}'),
                  ),
                ),
              if (widget.quick) ..._quickPreview(t, p, region, money, value) else ..._details(t, p),
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: !widget.quick
                    ? t('Aportar')
                    : value > 0
                    ? t('Apartar {value}', {'value': pesos(money, value)})
                    : t('Apartar'),
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

  /// Cómo queda la meta y hasta cuándo alcanzaría Mi plata (SaveSheet).
  List<Widget> _quickPreview(Tr t, RindePalette p, Region region, HomeMoney money, num value) {
    final vaca = widget.vaca;
    final after = vaca.total + value;
    final pct = vaca.goal > 0 ? math.min(100, (after / vaca.goal * 100).round()) : 0;
    final today = ref.read(clockProvider)();
    final now = runway(balance: widget.balance, monthExpense: widget.monthExpense, today: today);
    final then = widget.balance == null
        ? null
        : runway(balance: widget.balance! - value, monthExpense: widget.monthExpense, today: today);
    return [
      const SizedBox(height: RindeSpace.s4),
      DecoratedBox(
        decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.05), borderRadius: RindeRadius.brX2),
        child: Padding(
          padding: const EdgeInsets.all(RindeSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('La meta queda en').toUpperCase(),
                      style: RindeType.eyebrow.copyWith(color: p.inkMuted),
                    ),
                  ),
                  Text('$pct %', style: RindeType.figureMd.tabular.copyWith(color: p.ink)),
                ],
              ),
              const SizedBox(height: RindeSpace.s2),
              RindeLine(value: pct / 100),
              const SizedBox(height: RindeSpace.s2),
              MoneyText(
                '${pesos(money, after)} ${t('de')} ${pesos(money, vaca.goal)}',
                money: money,
                style: RindeType.small.tabular.copyWith(color: p.ink),
              ),
            ],
          ),
        ),
      ),
      if (now != null && then != null && value > 0) ...[
        const SizedBox(height: RindeSpace.s4),
        Text(
          '${t('Mi plata te alcanzaría')} '
          '${then.lasts ? t('hasta después de fin de mes') : untilText(t, then, region)} '
          '${t('(hoy:')} ${now.lasts ? t('pasa el fin de mes') : '${now.until.day} ${shortMonthName(now.until.month, region)}'}). '
          '${then.days < now.days ? t('Apartar también es gastar: revisa que te quede para el mes.') : t('Sigues cubierto.')}',
          style: RindeType.body.copyWith(color: p.ink),
        ),
      ],
    ];
  }

  /// Fecha (como máximo hoy), cómo queda en los gastos y la nota (ContributionForm).
  List<Widget> _details(Tr t, RindePalette p) {
    final categories = ref.watch(movementCategoriesProvider(ref.watch(accountProvider)));
    final list = categories.value?.of(MovementType.expense) ?? const [];
    // Si la lista aún no carga (o no trae la de por defecto), igual se puede aportar.
    final options = [
      if (!list.any((c) => c.key == kVacaCategory)) (key: kVacaCategory, name: t('Ahorro/Inversión')),
      for (final c in list) (key: c.key, name: c.custom ? c.name : t(c.name)),
    ];
    return [
      const SizedBox(height: RindeSpace.s4),
      DebtDateField(
        label: t('Fecha'),
        value: _date,
        lastIsToday: true,
        enabled: !_saving,
        error: _errors['date'],
        onChanged: (date) => setState(() => _date = date ?? _date),
      ),
      const SizedBox(height: RindeSpace.s4),
      ExcludeSemantics(
        child: Text(t('Queda en mis gastos como'), style: RindeType.label.copyWith(color: p.inkLabel)),
      ),
      const SizedBox(height: RindeSpace.s2),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in options)
            ChoiceChipButton(
              label: c.name,
              selected: c.key == _category,
              onTap: () => setState(() => _category = c.key),
            ),
        ],
      ),
      if (_errors['category'] case final error?)
        Text(error, style: RindeType.small.copyWith(color: p.negative)),
      const SizedBox(height: RindeSpace.s4),
      RindeTextField(
        label: t('Nota (opcional)'),
        controller: _note,
        hint: t('Ej. Mi parte de octubre'),
        maxLength: 120,
        enabled: !_saving,
        serverError: _errors['note'],
      ),
    ];
  }
}
