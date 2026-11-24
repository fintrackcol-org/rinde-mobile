import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/debts_writer.dart';
import '../../data/debt_models.dart';
import '../../domain/debt_rules.dart';
import 'debt_payment_sheet.dart' show DebtMovementBox;

/// Abre «Ya me pagó todo» / «Ya pagué todo». Devuelve el aviso para la pantalla (la cuenta ya no
/// existe) o null.
Future<String?> showSettleSheet(BuildContext context, {required Debt debt}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => SettleSheet(debt: debt),
);

/// SettleForm de Debts.jsx: salda lo que falta y, con la casilla (marcada), registra el movimiento por
/// lo que faltaba. No manda fecha, como la web: el servidor usa el hoy del usuario.
class SettleSheet extends ConsumerStatefulWidget {
  const SettleSheet({super.key, required this.debt});

  final Debt debt;

  @override
  ConsumerState<SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<SettleSheet> {
  bool _record = true;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    final t = ref.read(trProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(debtsWriterProvider).settle(widget.debt.id, createTransaction: _record);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Ya no existe o ya la saldaron en otro lado: se cierra y la lista, ya recargada, lo dice.
      if (e.status == 404 || e.status == 409) {
        Navigator.of(context).pop(moneyErrorText(e, t));
        return;
      }
      setState(() => _error = moneyErrorText(e, t));
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final debt = widget.debt;
    final words = debtWords(t, debt.kind);
    final receivable = debt.kind == DebtKind.receivable;
    final text = [
      receivable
          ? t('{person} te pagó lo que faltaba: ', {'person': debt.person})
          : t('Le pagaste a {person} lo que faltaba: ', {'person': debt.person}),
      money(debt.pending),
      '.',
    ].join();

    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(words.settleAll, style: RindeType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: RindeSpace.s4),
            MoneyText(
              text,
              money: money,
              style: RindeType.body.copyWith(color: p.ink),
            ),
            const SizedBox(height: RindeSpace.s4),
            DebtMovementBox(
              title: words.movement,
              detail:
                  '${t('Así tu saldo de hoy queda bien. Va en')} '
                  '${receivable ? t('Otros ingresos') : t('Otros')}'
                  '${t('; puedes cambiar la categoría después.')}',
              enabled: !_busy,
              onChanged: (value) => _record = value,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: RindeSpace.s4),
              RindeBanner(message: error),
            ],
            const SizedBox(height: RindeSpace.s5),
            RindeButton(label: words.settleAll, loading: _busy, onPressed: _confirm),
          ],
        ),
      ),
    );
  }
}
