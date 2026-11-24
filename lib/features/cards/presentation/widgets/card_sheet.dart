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
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/cards_writer.dart';
import '../../data/card_models.dart';
import '../../domain/card_rules.dart';
import 'credit_card_art.dart';

/// Abre «Agregar tarjeta» o, con [initial], «Editar tarjeta». Devuelve true si se guardó.
Future<bool?> showCardSheet(BuildContext context, {CreditCard? initial}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastre: cerraría la hoja mientras guarda, saltándose PopScope.
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => CardSheet(initial: initial),
);

/// El formulario de tarjeta (CardForm.jsx): galería por franquicia con vista previa, últimos 4,
/// vencimiento MM/AA, cupos y día de pago; «Nombre» y «Día de corte» van en «Más detalles».
/// - NUNCA se piden el número completo, el CVV ni la clave; los campos van sin autollenado del
///   sistema (ni siquiera el vencimiento: la app se aparta del `cc-exp` de la web por seguridad).
/// - Editar no muestra «Cupo disponible hoy» (eso se corrige con «Actualizar con el banco») y manda
///   SOLO lo que cambió: así el servidor rehace el nombre por defecto (la web manda todo y deja
///   nombres viejos). Un nombre borrado no se envía: el servidor conserva el que había, como la web.
class CardSheet extends ConsumerStatefulWidget {
  const CardSheet({super.key, this.initial});

  final CreditCard? initial;

  @override
  ConsumerState<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends ConsumerState<CardSheet> {
  static const _focusOrder = ['last4', 'expiry', 'limit', 'available', 'paymentDay', 'name', 'cutoffDay'];

  late String _network = widget.initial?.network ?? 'visa';
  late String _tier = widget.initial?.tier ?? 'clasica';
  late final _last4 = TextEditingController(text: widget.initial?.last4 ?? '');
  late final _expiry = TextEditingController(text: _initialExpiry(widget.initial));
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _paymentDay = TextEditingController(text: '${widget.initial?.paymentDay ?? ''}');
  late final _cutoffDay = TextEditingController(text: '${widget.initial?.cutoffDay ?? ''}');
  late String _limit = widget.initial == null ? '' : _raw(widget.initial!.limit);
  String _available = '';
  final _focus = {for (final field in _focusOrder) field: FocusNode()};
  bool _details = false;
  bool _saving = false;
  Map<String, String> _errors = const {};
  String? _error;

  bool get _editing => widget.initial != null;

  static String _initialExpiry(CreditCard? card) => card?.expiryMonth == null
      ? ''
      : '${card!.expiryMonth.toString().padLeft(2, '0')}/${(card.expiryYear! % 100).toString().padLeft(2, '0')}';

  static String _raw(num amount) {
    final fixed = amount.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  @override
  void dispose() {
    _last4.dispose();
    _expiry.dispose();
    _name.dispose();
    _paymentDay.dispose();
    _cutoffDay.dispose();
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
      if (errors.containsKey('name') || errors.containsKey('cutoffDay')) _details = true;
    });
    final first = _focusOrder.where(errors.containsKey).firstOrNull;
    if (first != null) _focus[first]!.requestFocus();
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final problems = cardFormProblems(
      t,
      network: _network,
      tier: _tier,
      last4: _last4.text,
      name: _name.text,
      expiry: _expiry.text,
      limit: moneyValue(_limit),
      available: moneyValue(_available),
      paymentDay: _paymentDay.text,
      cutoffDay: _cutoffDay.text,
      editing: _editing,
    );
    if (problems.isNotEmpty) return _show(problems, null);
    final body = cardBody(
      widget.initial,
      network: _network,
      tier: _tier,
      last4: _last4.text,
      limit: _limit,
      available: _available,
      paymentDay: _paymentDay.text,
      name: _name.text,
      cutoffDay: _cutoffDay.text,
      expiry: _expiry.text,
    );
    // Nada cambió: no se envía nada, como un PUT vacío no tendría sentido.
    if (body == null) return Navigator.of(context).pop(false);
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final writer = ref.read(cardsWriterProvider);
    try {
      if (widget.initial case final initial?) {
        await writer.updateCard(initial.id, body);
      } else {
        await writer.createCard(body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // La tarjeta ya no existe: la hoja se cierra y la pantalla recarga (ya se invalidó).
      if (_editing && e.status == 404) {
        Navigator.of(context).pop(false);
        return;
      }
      final fields = {
        for (final MapEntry(:key, :value) in e.fields.entries)
          if (_focus.containsKey(key))
            key: t(value)
          else if (key == 'expiryMonth' || key == 'expiryYear')
            'expiry': t(value),
        // El 409 de últimos 4 repetidos va A SU CAMPO (en la web sale abajo, como texto suelto).
        if (e.code == 'CARD_EXISTS') 'last4': moneyErrorText(e, t),
      };
      final unplaced =
          fields.isEmpty ||
          e.fields.keys.any((k) => !_focus.containsKey(k) && k != 'expiryMonth' && k != 'expiryYear');
      _show(fields, unplaced ? moneyErrorText(e, t) : null);
    } on Object catch (e) {
      if (mounted) _show(const {}, moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final format = formatFor(region);
    final digits = RegExp(r'^\d{4}$').hasMatch(_last4.text) ? _last4.text : '····';
    final previewName = _name.text.trim().isEmpty
        ? '${networkTierLabel(t, _network, _tier)} ••$digits'
        : _name.text.trim();

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
                  // El título de la hoja de la web (Cards.jsx:199); «Nueva tarjeta» es solo el
                  // aria-label de su formulario.
                  _editing ? t('Editar tarjeta') : t('Agregar tarjeta'),
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              Center(
                child: CreditCardArt(
                  network: _network,
                  tier: _tier,
                  last4: digits,
                  name: previewName,
                  expiry: RegExp(r'^\d{2}/\d{2}$').hasMatch(_expiry.text) ? _expiry.text : null,
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              _Gallery(
                network: _network,
                tier: _tier,
                last4: RegExp(r'^\d{4}$').hasMatch(_last4.text) ? _last4.text : '0000',
                enabled: !_saving,
                onPick: (network, tier) => setState(() {
                  _network = network;
                  _tier = tier;
                  _errors = {..._errors}..remove('tier');
                }),
              ),
              if (_errors['tier'] case final tierError?) ...[
                const SizedBox(height: RindeSpace.s2),
                Semantics(
                  liveRegion: true,
                  child: Text(tierError, style: RindeType.small.copyWith(color: p.negative)),
                ),
              ],
              const SizedBox(height: RindeSpace.s4),
              RindeTextField(
                label: t('Últimos 4 dígitos'),
                controller: _last4,
                hint: '1234',
                keyboardType: TextInputType.number,
                maxLength: 4,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                focusNode: _focus['last4'],
                serverError: _errors['last4'],
                onChanged: (_) => setState(() => _clear('last4')),
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeTextField(
                // La web agrega «Te avisamos 2 meses antes…», pero ese aviso es un push que la app
                // no recibe: no se promete (pregunta 15 del plan).
                label: t('Vence (MM/AA, opcional)'),
                controller: _expiry,
                hint: '03/27',
                keyboardType: TextInputType.number,
                maxLength: 5,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                focusNode: _focus['expiry'],
                serverError: _errors['expiry'],
                onChanged: (raw) {
                  final formatted = formatExpiry(raw);
                  if (formatted != raw) {
                    _expiry.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }
                  setState(() => _clear('expiry'));
                },
              ),
              const SizedBox(height: RindeSpace.s4),
              RindeMoneyField(
                value: _limit,
                format: format,
                label: t('Cupo total'),
                semanticLabel: t('Cupo total'),
                enabled: !_saving,
                focusNode: _focus['limit'],
                errorText: _errors['limit'],
                onChanged: (raw) => setState(() {
                  _limit = raw;
                  _clear('limit');
                }),
              ),
              if (!_editing) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeMoneyField(
                  value: _available,
                  format: format,
                  label: t('Cupo disponible hoy'),
                  semanticLabel: t('Cupo disponible hoy'),
                  helper: t('Los ves en la app de tu banco'),
                  enabled: !_saving,
                  focusNode: _focus['available'],
                  errorText: _errors['available'],
                  onChanged: (raw) => setState(() {
                    _available = raw;
                    _clear('available');
                  }),
                ),
              ],
              const SizedBox(height: RindeSpace.s4),
              RindeTextField(
                label: t('Día de pago'),
                controller: _paymentDay,
                hint: '15',
                keyboardType: TextInputType.number,
                maxLength: 2,
                enabled: !_saving,
                focusNode: _focus['paymentDay'],
                serverError: _errors['paymentDay'],
                onChanged: (_) => setState(() => _clear('paymentDay')),
              ),
              const SizedBox(height: RindeSpace.s4),
              _Details(
                open: _details,
                label: t('Más detalles'),
                onToggle: () => setState(() => _details = !_details),
                children: [
                  RindeTextField(
                    label: t('Nombre (opcional)'),
                    controller: _name,
                    hint: '${networkTierLabel(t, _network, _tier)} ••$digits',
                    maxLength: 40,
                    enabled: !_saving,
                    focusNode: _focus['name'],
                    serverError: _errors['name'],
                    onChanged: (_) => setState(() => _clear('name')),
                  ),
                  const SizedBox(height: RindeSpace.s4),
                  RindeTextField(
                    label: t('Día de corte (opcional)'),
                    controller: _cutoffDay,
                    hint: '1',
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    enabled: !_saving,
                    focusNode: _focus['cutoffDay'],
                    serverError: _errors['cutoffDay'],
                    onChanged: (_) => setState(() => _clear('cutoffDay')),
                  ),
                ],
              ),
              if (_error case final error?) ...[
                const SizedBox(height: RindeSpace.s4),
                RindeBanner(message: error),
              ],
              const SizedBox(height: RindeSpace.s5),
              RindeButton(
                label: _editing ? t('Guardar cambios') : t('Agregar tarjeta'),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Galería por franquicia (CardForm.jsx:49-77): tocar una tarjeta dibujada elige el tipo.
class _Gallery extends ConsumerWidget {
  const _Gallery({
    required this.network,
    required this.tier,
    required this.last4,
    required this.enabled,
    required this.onPick,
  });

  final String network;
  final String tier;
  final String last4;
  final bool enabled;
  final void Function(String network, String tier) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(t('Tipo de tarjeta'), style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        for (final MapEntry(key: net, value: tiers) in cardTiers.entries) ...[
          const SizedBox(height: RindeSpace.s2),
          Text(networkLabel(t, net), style: RindeType.caption.w(FontWeight.w500).copyWith(color: p.inkMuted)),
          const SizedBox(height: RindeSpace.s1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in tiers)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: RindeSpace.s2),
                    child: Semantics(
                      button: true,
                      selected: net == network && option == tier,
                      label: networkTierLabel(t, net, option),
                      onTap: enabled ? () => onPick(net, option) : null,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: enabled ? () => onPick(net, option) : null,
                        child: Opacity(
                          opacity: net == network && option == tier ? 1 : 0.7,
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              borderRadius: RindeRadius.brX2,
                              border: net == network && option == tier
                                  ? Border.all(color: p.brand, width: 2)
                                  : null,
                            ),
                            child: CreditCardArt(network: net, tier: option, last4: last4, small: true),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// «Más detalles» plegable, que se abre solo si un error cae adentro.
class _Details extends StatelessWidget {
  const _Details({required this.open, required this.label, required this.onToggle, required this.children});

  final bool open;
  final String label;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: RindeRadius.brX2,
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onToggle,
              borderRadius: RindeRadius.brX2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: RindeType.control.w(FontWeight.w600).copyWith(color: p.ink),
                        ),
                      ),
                      RotatedBox(
                        quarterTurns: open ? 2 : 0,
                        child: RindeIcon(RindeIcons.chevronDown, size: 20, color: p.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.all(RindeSpace.s4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ],
      ),
    );
  }
}
