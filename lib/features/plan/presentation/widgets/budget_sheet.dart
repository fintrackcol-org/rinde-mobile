import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/money_text.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/data/home_models.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../movements/application/movements_controller.dart' show movementCategoriesProvider;
import '../../../movements/presentation/record/movement_form.dart' show ChoiceChipButton;
import '../../application/budgets_writer.dart';
import '../../domain/plan_rules.dart';

/// Lo que devuelve la hoja al cerrarse.
enum BudgetSheetResult { created, updated, deleted }

/// «Nuevo presupuesto» del mes [month] o, con [initial], «Modificar presupuesto» (BudgetForm.jsx en
/// la hoja del celular). [used]: las categorías que ya tienen presupuesto ese mes (RN-03). Con
/// [canDelete], la hoja de editar trae «Eliminar presupuesto» (BudgetDetail.jsx).
Future<BudgetSheetResult?> showBudgetSheet(
  BuildContext context, {
  required String month,
  BudgetStatus? initial,
  List<String> used = const [],
  bool canDelete = false,
}) => showModalBottomSheet<BudgetSheetResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastre: cerraría la hoja mientras guarda, saltándose PopScope.
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => _BudgetSheet(month: month, initial: initial, used: used, canDelete: canDelete),
);

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({
    required this.month,
    required this.initial,
    required this.used,
    required this.canDelete,
  });

  final String month;
  final BudgetStatus? initial;
  final List<String> used;
  final bool canDelete;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  static const _max = 9999999999.99;

  String? _category;
  late String _amount = widget.initial == null ? '' : '${widget.initial!.amount}';
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  bool get _editing => widget.initial != null;

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final amount = moneyValue(_amount);
    // budgetSchema de la web.
    final errors = {
      if (!_editing && _category == null) 'category': t('Elige una categoría'),
      if (amount == null)
        'amount': t('Ingresa un monto válido')
      else if (amount <= 0)
        'amount': t('El límite debe ser mayor que 0')
      else if (amount > _max)
        'amount': t('El monto es demasiado grande'),
    };
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _error = null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final writer = ref.read(budgetsWriterProvider);
    try {
      if (_editing) {
        await writer.update(widget.initial!, widget.month, amount!);
      } else {
        await writer.create(category: _category!, month: widget.month, amount: amount!);
      }
      if (mounted) {
        Navigator.of(context).pop(_editing ? BudgetSheetResult.updated : BudgetSheetResult.created);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (key == 'category' || key == 'amount') key: t(value),
      };
      setState(() {
        _errors = fields;
        _error = moneyErrorText(e, t);
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
    final monthLabel = budgetMonthLabel(widget.month, region);
    final categories = ref.watch(movementCategoriesProvider(ref.watch(accountProvider)));
    final expense = categories.value?.expense ?? const [];
    final available = expense.where((c) => !widget.used.contains(c.key)).toList();
    final initial = widget.initial;

    Widget body;
    if (!_editing && available.isEmpty && expense.isNotEmpty) {
      body = Text(
        '${t('Todas tus categorías de gasto ya tienen presupuesto en')} $monthLabel'
        '${t('. Puedes cambiar sus límites desde la lista.')}',
        style: RindeType.body.copyWith(color: p.inkMuted),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (initial != null) ...[
            Text(t('Categoría'), style: RindeType.label.copyWith(color: p.ink.withValues(alpha: 0.8))),
            const SizedBox(height: RindeSpace.s2),
            Text(
              categories.value?.names[initial.category] ?? initial.category,
              style: RindeType.title.w(FontWeight.w500).copyWith(color: p.ink),
            ),
          ] else ...[
            Semantics(
              header: true,
              child: Text(t('Categoría de gasto'), style: RindeType.eyebrow.copyWith(color: p.inkMuted)),
            ),
            const SizedBox(height: RindeSpace.s2),
            if (categories.isLoading)
              Text(t('Cargando…'), style: RindeType.small.copyWith(color: p.inkMuted))
            else if (categories.hasError && !categories.hasValue)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: RindeTextLink(
                  label: t('Reintentar'),
                  onPressed: () => ref.invalidate(movementCategoriesProvider),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in available)
                    ChoiceChipButton(
                      label: c.custom ? c.name : t(c.name),
                      selected: c.key == _category,
                      onTap: () => setState(() {
                        _category = c.key;
                        _errors = {..._errors}..remove('category');
                      }),
                    ),
                ],
              ),
            if (_errors['category'] case final error?)
              Padding(
                padding: const EdgeInsets.only(top: RindeSpace.s2),
                child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
              ),
          ],
          const SizedBox(height: RindeSpace.s5),
          RindeMoneyField(
            value: _amount,
            format: formatFor(region),
            // TEXTO NUEVO (ajustado): la web dice «Límite del mes (COP)» fijo aunque la moneda sea otra.
            label: t('Límite del mes ({currency})', {'currency': region.currency}),
            semanticLabel: t('Límite del mes ({currency})', {'currency': region.currency}),
            hint: '0',
            enabled: !_saving,
            errorText: _errors['amount'],
            onChanged: (raw) => setState(() {
              _amount = raw;
              _errors = {..._errors}..remove('amount');
            }),
          ),
          const SizedBox(height: RindeSpace.s2),
          Text(
            '${_editing ? t('Aplica a ') : t('Se crea para ')}$monthLabel'
            '${t('. Te avisamos al llegar al 80 % y al pasarte del 100 %.')}',
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: RindeSpace.s4),
            RindeBanner(message: error),
          ],
          const SizedBox(height: RindeSpace.s5),
          RindeButton(
            label: _editing ? t('Guardar límite') : t('Crear presupuesto'),
            loading: _saving,
            loadingLabel: t('Guardando…'),
            onPressed: _save,
          ),
          const SizedBox(height: RindeSpace.s2),
          RindeButton(
            label: t('Cancelar'),
            variant: RindeButtonVariant.outline,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          if (initial != null && widget.canDelete) ...[
            const SizedBox(height: RindeSpace.s3),
            Center(
              child: ConfirmInline(
                label: t('Eliminar presupuesto'),
                question: t('¿Eliminar este presupuesto?'),
                confirmLabel: t('Sí, eliminar'),
                cancelLabel: t('Cancelar'),
                errorText: (e) => moneyErrorText(e, t),
                onConfirm: () async {
                  final navigator = Navigator.of(context);
                  await ref.read(budgetsWriterProvider).delete(initial, widget.month);
                  if (mounted) navigator.pop(BudgetSheetResult.deleted);
                },
              ),
            ),
          ],
        ],
      );
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
                child: Text(
                  _editing ? t('Modificar presupuesto') : t('Nuevo presupuesto'),
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              body,
            ],
          ),
        ),
      ),
    );
  }
}
