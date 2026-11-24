import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../home/data/home_models.dart' show readMoney;
import '../../../home/domain/home_dates.dart';
import '../../../home/presentation/widgets/home_tap.dart' show largeText;
import '../../../onboarding/domain/commitments.dart';
import '../../application/money_writer.dart';
import '../../data/money_models.dart';
import 'paid_button.dart' show moneyErrorText;

/// Abre «Nuevo pago» o, con [commitment], «Editar pago». Devuelve un aviso para la pantalla (el pago
/// cambió en otro lado y se está recargando) o null. [day] y [month] precargan uno nuevo (el
/// «Agregar a este día» del Calendario).
Future<String?> showCommitmentSheet(BuildContext context, {Commitment? commitment, int? day, int? month}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Sin arrastre ni asa (que también se arrastra): cerrarían la hoja mientras guarda, saltándose
      // PopScope, y el resultado no se vería.
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => CommitmentSheet(commitment: commitment, day: day, month: month),
    );

/// El formulario de un pago fijo o suscripción (CommitmentDialog de MiPlata.jsx), sin el bloque
/// «Avisarme»: la app no tiene notificaciones y, al editar, sin `reminder` el aviso guardado sigue
/// igual. Un pago creado aquí nace sin aviso (en la web, con «1 día antes»).
class CommitmentSheet extends ConsumerStatefulWidget {
  const CommitmentSheet({super.key, this.commitment, this.day, this.month});

  final Commitment? commitment;

  /// Día del mes y mes (1 a 12, solo si se vuelve anual) con que arranca uno nuevo.
  final int? day;
  final int? month;

  @override
  ConsumerState<CommitmentSheet> createState() => _CommitmentSheetState();
}

class _CommitmentSheetState extends ConsumerState<CommitmentSheet> {
  /// Qué campo marca cada mensaje de readCommitment.
  static const _fieldOf = {
    'Escribe el nombre del pago.': 'name',
    'Escribe cuánto pagas por {cleanName}.': 'amount',
    'Escribe un día entre 1 y 31 para {cleanName}.': 'dayOfMonth',
    'Elige en qué mes se cobra {cleanName}.': 'month',
  };

  late final _name = TextEditingController(text: widget.commitment?.name ?? '');
  late final _day = TextEditingController(text: '${widget.commitment?.dayOfMonth ?? widget.day ?? ''}');
  late String _amount = widget.commitment == null ? '' : '${readMoney(widget.commitment!.amount)}';
  late String _kind = widget.commitment?.kind ?? 'fixed';
  late String _frequency = widget.commitment?.frequency ?? 'monthly';
  late int? _month = widget.commitment?.month ?? widget.month;
  final _focus = {for (final field in _fieldOf.values) field: FocusNode()};

  /// Problema por campo (`name`, `amount`, `dayOfMonth`, `month`): local o del servidor.
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _day.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _clear(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  void _show(Map<String, String> errors, String? error) {
    setState(() {
      _errors = errors;
      _error = error;
    });
    if (errors.isNotEmpty) _focus[_fieldOf.values.firstWhere(errors.containsKey)]!.requestFocus();
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final read = readCommitment(
      CommitmentItem(
        key: 'pago',
        name: clipCommitmentName(_name.text),
        amount: _amount,
        dayOfMonth: _day.text.replaceAll(RegExp(r'\D'), ''),
        kind: _kind,
        frequency: _frequency,
        month: _month,
      ),
    );
    if (read.problem case final problem?) {
      _show({_fieldOf[problem.message]!: t(problem.message, problem.vars)}, null);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final writer = ref.read(moneyWriterProvider);
    final opened = widget.commitment;
    try {
      if (opened == null) {
        await writer.createCommitment(read.data!);
      } else {
        await writer.updateCommitment(opened, read.data!);
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Lo borraron o lo cambiaron en otro lado: la hoja se cierra y la lista ya se está recargando.
      if (opened != null && (e.status == 404 || e.code == ApiCodes.profileChanged)) {
        Navigator.of(context).pop(e.status == 404 ? null : moneyErrorText(e, t));
        return;
      }
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (_focus.containsKey(key)) key: t(value),
        // El nombre identifica el pago: el repetido se marca en su campo.
        if (e.code == 'COMMITMENT_EXISTS') 'name': moneyErrorText(e, t),
      };
      final unplaced = fields.isEmpty || e.fields.keys.any((key) => !_focus.containsKey(key));
      _show(fields, unplaced ? moneyErrorText(e, t) : null);
    } on Object catch (e) {
      if (mounted) _show(const {}, moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Sin arrastre: mientras borra no se cierra (Atrás lo frena PopScope).
      enableDrag: false,
      backgroundColor: context.palette.surface,
      builder: (_) => DeleteCommitmentSheet(commitment: widget.commitment!),
    );
    if (deleted == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final editing = widget.commitment != null;
    final subscription = _kind == 'subscription';

    final amount = RindeMoneyField(
      value: _amount,
      onChanged: (raw) {
        _amount = raw;
        _clear('amount');
      },
      format: formatFor(region),
      label: t('Monto'),
      semanticLabel: t('Monto'),
      focusNode: _focus['amount'],
      errorText: _errors['amount'],
    );
    final day = RindeTextField(
      label: t('Día'),
      controller: _day,
      hint: '30',
      keyboardType: TextInputType.number,
      maxLength: 2,
      focusNode: _focus['dayOfMonth'],
      serverError: _errors['dayOfMonth'],
      onChanged: (_) => _clear('dayOfMonth'),
    );

    return PopScope(
      // Mientras guarda no se cierra: el resultado tiene que verse.
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
                  editing ? t('Editar pago') : t('Nuevo pago'),
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              _Label(t('¿Qué es?')),
              RindeSegmented<String>(
                semanticLabel: t('¿Qué es?'),
                options: {'fixed': t('Pago fijo'), 'subscription': t('Suscripción')},
                value: _kind,
                onChanged: _saving ? null : (kind) => setState(() => _kind = kind),
              ),
              const SizedBox(height: 6),
              Text(
                subscription
                    ? t('Un servicio que se cobra solo y puedes cancelar: Netflix, Spotify, iCloud.')
                    : t('Lo que pagas sí o sí: arriendo, internet, la cuota del carro.'),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeTextField(
                label: t('Nombre'),
                controller: _name,
                hint: subscription ? t('Netflix') : t('Arriendo'),
                maxLength: commitmentNameMax,
                textCapitalization: TextCapitalization.sentences,
                focusNode: _focus['name'],
                serverError: _errors['name'],
                onChanged: (_) => _clear('name'),
              ),
              const SizedBox(height: RindeSpace.s4),
              // Con la letra agrandada el día baja: al lado no cabría.
              if (largeText(context)) ...[
                amount,
                const SizedBox(height: RindeSpace.s4),
                day,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: amount),
                    const SizedBox(width: RindeSpace.s3),
                    SizedBox(width: 96, child: day),
                  ],
                ),
              const SizedBox(height: RindeSpace.s4),
              _Label(t('¿Cada cuánto?')),
              RindeSegmented<String>(
                semanticLabel: t('¿Cada cuánto?'),
                options: {'monthly': t('Cada mes'), 'yearly': t('Una vez al año')},
                value: _frequency,
                onChanged: _saving
                    ? null
                    : (frequency) => setState(() {
                        _frequency = frequency;
                        _clear('month');
                      }),
              ),
              if (_frequency == 'yearly') ...[
                const SizedBox(height: RindeSpace.s4),
                _Label(t('Mes del cobro')),
                Semantics(
                  label: t('Mes del cobro'),
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    focusNode: _focus['month'],
                    isExpanded: true,
                    hint: Text(t('Elige el mes')),
                    forceErrorText: _errors['month'],
                    style: RindeType.body.copyWith(color: p.ink),
                    dropdownColor: p.surface,
                    decoration: InputDecoration(
                      errorMaxLines: 3,
                      errorStyle: RindeType.small.copyWith(color: p.negative),
                      constraints: const BoxConstraints(minHeight: RindeSize.field),
                      contentPadding: const EdgeInsetsDirectional.fromSTEB(
                        RindeSpace.s4,
                        14,
                        RindeSpace.s3,
                        14,
                      ),
                    ),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(monthName(m, region))),
                    ],
                    onChanged: _saving
                        ? null
                        : (m) => setState(() {
                            _month = m;
                            _clear('month');
                          }),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: t('Guardar pago'),
                loading: _saving,
                loadingLabel: t('Guardando…'),
                onPressed: _save,
              ),
              const SizedBox(height: RindeSpace.s2),
              RindeButton(
                label: t('Cancelar'),
                variant: RindeButtonVariant.ghost,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
              if (editing) ...[
                const SizedBox(height: RindeSpace.s2),
                TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: p.negative,
                    minimumSize: const Size.fromHeight(RindeSize.button),
                    textStyle: RindeType.bodyMedium,
                  ),
                  child: Text(t('Eliminar pago')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta de un grupo del formulario (la que el lector ya oye en el control).
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: RindeSpace.s2),
    child: ExcludeSemantics(
      child: Text(text, style: RindeType.label.copyWith(color: context.palette.inkLabel)),
    ),
  );
}

/// «¿Eliminar {name}?»: la web borra sin preguntar; aquí se confirma. Devuelve true si se borró. Si
/// falla, se queda abierta con el motivo y el pago sigue igual.
class DeleteCommitmentSheet extends ConsumerStatefulWidget {
  const DeleteCommitmentSheet({super.key, required this.commitment});

  final Commitment commitment;

  @override
  ConsumerState<DeleteCommitmentSheet> createState() => _DeleteCommitmentSheetState();
}

class _DeleteCommitmentSheetState extends ConsumerState<DeleteCommitmentSheet> {
  bool _removing = false;
  String? _error;

  Future<void> _remove() async {
    final t = ref.read(trProvider);
    setState(() => (_removing = true, _error = null));
    try {
      await ref.read(moneyWriterProvider).deleteCommitment(widget.commitment.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => (_removing = false, _error = moneyErrorText(e, t)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return PopScope(
      canPop: !_removing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  // TEXTO NUEVO
                  t('¿Eliminar {name}?', {'name': widget.commitment.name}),
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s2),
              Text(
                // TEXTO NUEVO
                t('Se borra el pago y su aviso. Los gastos que ya anotaste no cambian.'),
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s4),
              if (_error case final error?) ...[
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                ),
                const SizedBox(height: RindeSpace.s3),
              ],
              FilledButton(
                onPressed: _removing ? null : _remove,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(RindeSize.buttonLg),
                  backgroundColor: p.negativeSolid,
                  foregroundColor: RindeBrand.white,
                  disabledBackgroundColor: p.negativeSolid.withValues(alpha: 0.6),
                  disabledForegroundColor: RindeBrand.white,
                  shape: const RoundedRectangleBorder(borderRadius: RindeRadius.brXl),
                  textStyle: RindeType.buttonLg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: RindeSpace.s2,
                  children: [
                    if (_removing) const RindeSpinner(color: RindeBrand.white),
                    Flexible(child: Text(t('Eliminar pago'), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              const SizedBox(height: RindeSpace.s2),
              RindeButton(
                label: t('Cancelar'),
                variant: RindeButtonVariant.ghost,
                onPressed: _removing ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
