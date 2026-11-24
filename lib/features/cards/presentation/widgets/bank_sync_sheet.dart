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
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/cards_writer.dart';
import '../../data/card_models.dart';
import '../../domain/card_rules.dart';

/// Lo que respondió «Actualizar con el banco»: el monto del gasto «Cargos del banco», o null.
class BankSyncDone {
  const BankSyncDone({this.chargeAmount});
  final num? chargeAmount;
}

/// Abre «Actualizar con el banco». Devuelve el resultado si se guardó.
Future<BankSyncDone?> showBankSyncSheet(BuildContext context, {required CreditCard card}) =>
    showModalBottomSheet<BankSyncDone>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => BankSyncSheet(card: card),
    );

/// «Actualizar con el banco» (BankSyncForm.jsx): es MANUAL (no hay conexión con bancos). Se copia
/// el disponible de la app del banco y, si se quiere, el extracto. La vista previa la calcula el
/// cliente con la misma fórmula del servidor; quien decide es el servidor. Los opcionales vacíos SE
/// OMITEN del cuerpo (con null el servidor responde 422).
class BankSyncSheet extends ConsumerStatefulWidget {
  const BankSyncSheet({super.key, required this.card});

  final CreditCard card;

  @override
  ConsumerState<BankSyncSheet> createState() => _BankSyncSheetState();
}

class _BankSyncSheetState extends ConsumerState<BankSyncSheet> {
  String _available = '';
  String _statementTotal = '';
  String? _statementDueDate;
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;
  final _focus = {'available': FocusNode(), 'statementTotal': FocusNode()};

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _clear(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Future<void> _pickDate() async {
    final current = _statementDueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? ref.read(clockProvider)() : DateTime.parse(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: ref.read(trProvider)('Fecha límite (opcional)'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _statementDueDate = isoDay(picked);
      _errors = {..._errors}..remove('statementDueDate');
    });
  }

  Map<String, String> _problems(Tr t) {
    final available = moneyValue(_available);
    final total = moneyValue(_statementTotal);
    return {
      if (available == null)
        'available': t('Ingresa un monto')
      else if (available < 0)
        'available': t('No puede ser negativo')
      else if (available > maxAmount)
        'available': t('El monto es demasiado grande'),
      if (_statementTotal.trim().isNotEmpty && (total == null || total <= 0))
        'statementTotal': t('El total debe ser mayor que 0')
      else if (total != null && total > maxAmount)
        'statementTotal': t('El monto es demasiado grande'),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final problems = _problems(t);
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
      _focus[problems.keys.first]?.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final body = bankSyncBody(
      available: _available,
      statementTotal: _statementTotal,
      statementDueDate: _statementDueDate,
    );
    try {
      final charge = await ref.read(cardsWriterProvider).syncWithBank(widget.card, body);
      if (mounted) Navigator.of(context).pop(BankSyncDone(chargeAmount: charge));
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (const {'available', 'statementTotal', 'statementDueDate'}.contains(key)) key: t(value),
      };
      setState(() {
        _errors = fields;
        _error = fields.length == e.fields.length && fields.isNotEmpty ? null : moneyErrorText(e, t);
      });
      if (fields.isNotEmpty) _focus[fields.keys.first]?.requestFocus();
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
    final difference = syncDifference(widget.card, moneyValue(_available));
    final preview = difference == null
        ? null
        : difference > 0
        ? t('Se registrará un gasto de {difference} en Cargos del banco.', {'difference': money(difference)})
        : t('Se corregirá el cupo sin registrar gasto.');

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
                child: Text(t('Actualizar con el banco'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s3),
              Text(
                t(
                  'Rinde no calcula intereses. Si el banco cobró de más, la diferencia queda como gasto «Cargos del banco» de la tarjeta (intereses, cuota de manejo u otros cargos).',
                ),
                style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _available,
                format: formatFor(region),
                label: t('Cupo disponible'),
                semanticLabel: t('Cupo disponible'),
                enabled: !_saving,
                focusNode: _focus['available'],
                errorText: _errors['available'],
                onChanged: (raw) => setState(() {
                  _available = raw;
                  _clear('available');
                }),
              ),
              if (preview != null) ...[
                const SizedBox(height: RindeSpace.s2),
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: MoneyText(
                    preview,
                    money: money,
                    style: RindeType.small.w(FontWeight.w500).copyWith(color: p.ink),
                  ),
                ),
              ],
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _statementTotal,
                format: formatFor(region),
                label: t('Total a pagar del extracto (opcional)'),
                semanticLabel: t('Total a pagar del extracto (opcional)'),
                enabled: !_saving,
                focusNode: _focus['statementTotal'],
                errorText: _errors['statementTotal'],
                onChanged: (raw) => setState(() {
                  _statementTotal = raw;
                  _clear('statementTotal');
                }),
              ),
              const SizedBox(height: RindeSpace.s4),
              ExcludeSemantics(
                child: Text(t('Fecha límite (opcional)'), style: RindeType.label.copyWith(color: p.inkLabel)),
              ),
              Row(
                children: [
                  Semantics(
                    label: t('Fecha límite (opcional)'),
                    child: TextButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: RindeIcon(RindeIcons.calendarRange, size: 18, color: p.brand),
                      label: Text(
                        _statementDueDate == null ? '—' : dayAndMonth(_statementDueDate!, region),
                        style: RindeType.bodyMedium.copyWith(color: p.brand),
                      ),
                    ),
                  ),
                  if (_statementDueDate != null)
                    IconButton(
                      onPressed: _saving ? null : () => setState(() => _statementDueDate = null),
                      tooltip: t('Quitar {v1}', {'v1': t('Fecha límite (opcional)')}),
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: RindeIcon(RindeIcons.x, size: 18, color: p.inkMuted),
                    ),
                ],
              ),
              if (_errors['statementDueDate'] case final dateError?)
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
                label: t('Actualizar'),
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
