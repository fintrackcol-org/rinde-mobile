import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/routes.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/region/money_text.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_money_field.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../cards/application/cards_providers.dart' show cardsProvider;
import '../../../cards/data/card_models.dart' show CreditCard;
import '../../../cards/domain/card_rules.dart' show cardListLabel;
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../home/domain/home_dates.dart';
import '../../application/movements_controller.dart';
import '../../domain/movement.dart';

/// BigAmountWarning de la web: desde este monto el primer toque en Guardar pregunta.
const kBigAmount = 5000000;

/// Las que se ven sin tocar «Ver todas» (Anotar.jsx).
const _visibleCategories = 5;

/// Campos del formulario que el servidor puede marcar en un 422.
const _formFields = {'type', 'amount', 'description', 'date', 'category', 'kakeibo', 'card', 'installments'};

const _kakeibo = [
  ('necesidad', 'Necesidad', 'Lo que no puedes dejar: comida, arriendo, transporte.'),
  ('deseo', 'Deseo', 'Gustos que podrías recortar: domicilios, ropa, salidas.'),
  ('cultura', 'Cultura', 'Lo que te hace crecer: libros, cursos, museos.'),
  ('imprevisto', 'Imprevisto', 'Lo que no estaba en los planes: un arreglo, una multa.'),
];

/// Lo que falta o no cuadra, por campo, con los textos de la web (Anotar o TransactionForm al editar).
/// La fecha futura solo cuenta si cambió: el servidor deja corregir uno viejo con fecha futura.
Map<String, String> movementProblems(
  Tr t, {
  required MovementType type,
  required num? amount,
  required String description,
  required String date,
  required String today,
  required bool editing,
  String? savedDate,
  String? card,
  String installments = '1',
}) {
  final expense = type == MovementType.expense;
  final cuotas = int.tryParse(installments.trim());
  return {
    if (amount == null || amount <= 0)
      'amount': editing
          ? t(amount == null ? 'Ingresa un monto válido' : 'El monto debe ser mayor que 0')
          : t(expense ? 'Escribe cuánto gastaste.' : 'Escribe cuánto te entró.')
    else if (amount > maxAmount)
      'amount': t('El monto es demasiado grande'),
    if (description.trim().isEmpty)
      'description': editing
          ? t('Escribe una descripción')
          : t('Escribe {v1}.', {
              'v1': t(expense ? 'en qué fue, p. ej. «almuerzo»' : 'de qué fue, p. ej. «salario»'),
            }),
    if (date.compareTo(today) > 0 && date != savedDate)
      'date': t('No puedes anotar un movimiento en el futuro'),
    // Cuotas solo con una tarjeta elegida (lib/validation/transaction.js:29-41).
    if (expense && card != null)
      if (installments.trim().isEmpty)
        'installments': t('Ingresa las cuotas')
      else if (cuotas == null || cuotas < 1 || cuotas > 48)
        'installments': t('De 1 a 48 cuotas'),
  };
}

/// isBigAmount de la web: al editar, solo si el monto cambió.
bool needsBigConfirm(num amount, {num? before}) => amount >= kBigAmount && amount != before;

/// El PUT del repositorio manda el estado completo: lo que el formulario no muestra (emoción,
/// Kakeibo, otra moneda) va como estaba. Null si nada cambió, TARJETA Y CUOTAS incluidas: si no,
/// un cambio de solo la tarjeta no se guardaría. Una tarjeta borrada cuenta como «sin tarjeta»
/// (TransactionEdit.jsx:44-46): sin tocarla, no se envía nada de tarjeta.
MovementInput? editedInput(
  Movement saved, {
  required MovementType type,
  required num amount,
  required String description,
  required String date,
  required String? category,
  required String? card,
  required int? installments,
}) {
  final text = description.trim();
  final income = type == MovementType.income;
  final effectiveCard = income ? null : card;
  final effectiveInstallments = effectiveCard == null ? null : installments;
  final savedCard = saved.card == null || saved.card!.deleted ? null : saved.card!.id;
  if (type == saved.type &&
      amount == saved.amount &&
      text == saved.description &&
      date == saved.date &&
      category == saved.category &&
      effectiveCard == savedCard &&
      effectiveInstallments == (savedCard == null ? null : saved.installments)) {
    return null;
  }
  return MovementInput(
    type: type,
    amount: amount,
    description: text,
    date: date,
    category: category,
    card: effectiveCard,
    installments: effectiveInstallments,
    emotion: income ? null : saved.emotion,
    kakeibo: income ? null : saved.kakeibo,
    // Como en la web: si cambia el monto, queda en la moneda principal sin la conversión.
    original: amount == saved.amount ? saved.original : null,
  );
}

/// Formulario de Anotar (nuevo) y de editar ([initial]). [onSave] guarda y devuelve el aviso corto
/// que se muestra al cerrar; lanza [ApiException] si falla.
class MovementForm extends ConsumerStatefulWidget {
  const MovementForm({
    super.key,
    required this.onSave,
    this.initial,
    this.initialType = MovementType.expense,
    this.initialCard,
    this.onTypeChanged,
  });

  final Movement? initial;
  final MovementType initialType;

  /// Tarjeta con que llega `/app/anotar?tarjeta=<id>` (el «Anotar» del detalle de una tarjeta).
  /// Se manda aunque la lista de tarjetas no cargue: el servidor la valida. LA WEB, en ese caso,
  /// guarda el gasto como efectivo sin avisar, y eso baja Mi plata por error (riesgo 2 de RT §8).
  final String? initialCard;
  final ValueChanged<MovementType>? onTypeChanged;

  /// [opened]: el movimiento con que se abrió el formulario (null al anotar). Editar manda solo lo que
  /// cambió respecto a él, aunque la pantalla de abajo se haya refrescado mientras tanto.
  final Future<String?> Function(MovementInput input, Movement? opened) onSave;

  @override
  ConsumerState<MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends ConsumerState<MovementForm> {
  final _amountFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  /// Lo guardado al abrir: se compara contra esto aunque la pantalla de abajo se refresque.
  late final Movement? _saved = widget.initial;
  late final _description = TextEditingController(text: _saved?.description ?? '');
  late MovementType _type = _saved?.type ?? widget.initialType;
  late String _amount = _saved == null ? '' : _raw(_saved.amount);
  late String _date = _saved?.date ?? _today();
  late String? _category = _saved?.category; // null: la elige la IA del servidor

  /// null = «Efectivo o débito». Al editar, una tarjeta borrada arranca como efectivo
  /// (TransactionForm.jsx:40-41).
  late String? _card = _saved == null
      ? (_type == MovementType.expense ? widget.initialCard : null)
      : (_saved.card == null || _saved.card!.deleted ? null : _saved.card!.id);
  late final _installments = TextEditingController(text: '${_saved?.installments ?? 1}');
  final _installmentsFocus = FocusNode();
  String? _kakeibo;
  bool _allCategories = false;
  bool _details = false;
  bool _tried = false;
  bool _saving = false;
  num? _askBig;
  String? _error;
  Map<String, String> _serverFields = const {};

  bool get _editing => _saved != null;
  bool get _expense => _type == MovementType.expense;

  static String _raw(num amount) {
    final fixed = amount.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  String _today() => isoDay(ref.read(clockProvider)());

  /// La tarjeta que se manda (null = «Efectivo o débito»). Al anotar, una que no está en la lista
  /// cargada (un enlace viejo) va en efectivo, como `cardOk` de Anotar.jsx; si la lista no cargó, va
  /// igual y el servidor la valida (la web la manda en efectivo y baja Mi plata por error). Al editar
  /// se respeta lo guardado.
  String? _sentCard(List<CreditCard>? cards) {
    if (!_expense || _card == null) return null;
    if (_editing || cards == null) return _card;
    return cards.any((c) => c.id == _card) ? _card : null;
  }

  List<CreditCard>? _readCards() => _known(ref.read(cardsProvider(ref.read(accountProvider))));

  /// Mientras recarga, o si la recarga falló, la lista puede ser vieja (sin la tarjeta del enlace): se
  /// trata como desconocida.
  static List<CreditCard>? _known(AsyncValue<List<CreditCard>> cards) =>
      cards.isLoading || cards.hasError ? null : cards.value;

  @override
  void dispose() {
    _amountFocus.dispose();
    _descriptionFocus.dispose();
    _installmentsFocus.dispose();
    _description.dispose();
    _installments.dispose();
    super.dispose();
  }

  void _edit(String field, VoidCallback change) => setState(() {
    change();
    if (_serverFields.containsKey(field)) _serverFields = {..._serverFields}..remove(field);
  });

  void _close([String? message]) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    context.canPop() ? context.pop() : context.go(Routes.app);
    if (message != null) messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final amount = moneyValue(_amount);
    final card = _sentCard(_readCards());
    final problems = movementProblems(
      t,
      type: _type,
      amount: amount,
      description: _description.text,
      date: _date,
      today: _today(),
      editing: _editing,
      savedDate: _saved?.date,
      card: card,
      installments: _installments.text,
    );
    // El botón nunca se apaga: si falta algo, lleva a esa casilla.
    if (problems.isNotEmpty) {
      setState(() {
        _tried = true;
        if (problems.containsKey('date') || problems.containsKey('installments')) _details = true;
      });
      if (problems.containsKey('amount')) {
        _amountFocus.requestFocus();
      } else if (problems.containsKey('description')) {
        _descriptionFocus.requestFocus();
      } else if (problems.containsKey('installments')) {
        _installmentsFocus.requestFocus();
      }
      return;
    }
    final installments = card == null ? null : int.parse(_installments.text.trim());
    final MovementInput input;
    if (_editing) {
      final edited = editedInput(
        _saved!,
        type: _type,
        amount: amount!,
        description: _description.text,
        date: _date,
        category: _category,
        card: card,
        installments: installments,
      );
      if (edited == null) return _close();
      input = edited;
    } else {
      input = MovementInput(
        type: _type,
        amount: amount!,
        description: _description.text.trim(),
        date: _date,
        category: _category,
        card: card,
        installments: installments,
        kakeibo: _expense ? _kakeibo : null,
      );
    }
    if (needsBigConfirm(input.amount, before: _saved?.amount) && _askBig != input.amount) {
      setState(() => _askBig = input.amount);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _serverFields = const {};
    });
    try {
      final message = await widget.onSave(input, _saved);
      if (mounted) _close(message);
    } on ApiException catch (e) {
      if (!mounted) return;
      // «Pagado con» y «Cuotas» solo se dibujan con la lista de tarjetas cargada: si no están a la
      // vista, su error va al aviso de abajo para que no quede invisible.
      final cardsShown = _expense && (_readCards()?.isNotEmpty ?? false);
      final known = {
        for (final f in e.fields.entries)
          if (_formFields.contains(f.key) && (cardsShown || (f.key != 'card' && f.key != 'installments')))
            f.key: f.value,
      };
      setState(() {
        _serverFields = known;
        // Sin campos que se puedan marcar en el formulario, el mensaje va arriba del botón.
        _error = known.isNotEmpty && known.length == e.fields.length
            ? null
            : e.messageFor(
                byCode: const {
                  ApiCodes.unauthorized: ApiMessages.sessionExpired,
                  ApiCodes.tokenExpired: ApiMessages.sessionExpired,
                },
                fallback: ApiMessages.generic,
              );
        if (known.containsKey('date') || known.containsKey('card') || known.containsKey('installments')) {
          _details = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = ApiMessages.generic);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickType(MovementType type) {
    if (type == _type) return; // tocar el mismo tipo no borra la categoría
    setState(() {
      // La categoría era del otro tipo; el Kakeibo solo va en gastos.
      _type = type;
      _category = null;
      _kakeibo = null;
      _askBig = null;
      // Al volver a gasto vuelve la tarjeta de `?tarjeta=` (o efectivo), no la última tocada
      // (Anotar.jsx:423). Al editar, la web conserva lo elegido.
      if (!_editing) _card = type == MovementType.expense ? widget.initialCard : null;
    });
    widget.onTypeChanged?.call(type);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final format = formatFor(region);
    final amount = moneyValue(_amount);
    // Como la web: sin tarjetas (o si no cargan) «Pagado con» no aparece.
    final cards = _expense ? _known(ref.watch(cardsProvider(ref.watch(accountProvider)))) : null;
    final card = _sentCard(cards);
    final shown = _tried
        ? movementProblems(
            t,
            type: _type,
            amount: amount,
            description: _description.text,
            date: _date,
            today: _today(),
            editing: _editing,
            savedDate: _saved?.date,
            card: card,
            installments: _installments.text,
          )
        : const <String, String>{};
    String? problem(String field) => shown[field] ?? _serverFields[field];
    final hint = describeAmount(_amount, format: format, inPesos: region.currency == 'COP', t: t);
    final confirming = _askBig != null && _askBig == amount;

    final String saveLabel;
    if (confirming) {
      saveLabel = _editing
          ? t('Sí, guardar')
          : t('Sí, guardar {converted}', {'converted': format.money(amount!)});
    } else if (_editing) {
      saveLabel = t('Guardar cambios');
    } else {
      final base = _expense ? t('Guardar gasto') : t('Guardar ingreso');
      saveLabel = amount != null && amount > 0 ? '$base · ${format.money(amount)}' : base;
    }

    // «Pagado con» y «Cuotas» (Anotar.jsx:684-714, TransactionForm.jsx:216-231). Cuotas solo con una
    // tarjeta elegida de la lista.
    final paidWith = <Widget>[
      if (cards != null && cards.isNotEmpty) ...[
        const SizedBox(height: RindeSpace.s5),
        _PaidWithPicker(
          cards: cards,
          value: card,
          error: problem('card'),
          onChanged: (id) => _edit('card', () => _card = id),
        ),
        if (card != null && cards.any((c) => c.id == card)) ...[
          const SizedBox(height: RindeSpace.s5),
          RindeTextField(
            controller: _installments,
            focusNode: _installmentsFocus,
            enabled: !_saving,
            label: t('Cuotas'),
            // La ayuda solo está en Anotar (en la edición de la web va sin ella).
            helper: _editing ? null : t('De 1 a 48. A más de una cuota el banco suele cobrar intereses.'),
            keyboardType: TextInputType.number,
            maxLength: 2,
            serverError: problem('installments'),
            onChanged: (_) => _edit('installments', () {}),
          ),
        ],
      ],
    ];

    final date = _DateQuickPick(
      value: _date,
      today: _today(),
      region: region,
      error: problem('date'),
      onChanged: (d) => _edit('date', () => _date = d),
    );

    final form = <Widget>[
      RindeSegmented<MovementType>(
        semanticLabel: t('Tipo de movimiento'),
        options: {MovementType.expense: t('Gasto'), MovementType.income: t('Ingreso')},
        value: _type,
        onChanged: _saving ? null : _pickType,
      ),
      const SizedBox(height: RindeSpace.s5),
      RindeMoneyField(
        value: _amount,
        format: format,
        label: _editing ? '${t('Monto')} (${region.currency})' : '${t('Monto')} *',
        semanticLabel: t('Monto'),
        focusNode: _amountFocus,
        autofocus: !_editing,
        enabled: !_saving,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _descriptionFocus.requestFocus(),
        errorText: problem('amount'),
        message: hint?.message,
        messageTone: hint?.tone ?? RindeMoneyMessageTone.info,
        onChanged: (raw) => _edit('amount', () => _amount = raw),
      ),
      const SizedBox(height: RindeSpace.s5),
      RindeTextField(
        controller: _description,
        focusNode: _descriptionFocus,
        enabled: !_saving,
        label: _editing ? t('Descripción') : '${t(_expense ? '¿En qué fue?' : '¿De qué fue?')} *',
        hint: _editing
            ? t('Almuerzo en el restaurante')
            : t(_expense ? 'almuerzo, taxi, arriendo…' : 'salario, venta, freelance…'),
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        serverError: problem('description'),
        onChanged: (_) => _edit('description', () {}),
      ),
      const SizedBox(height: RindeSpace.s5),
      if (_editing) ...[date, const SizedBox(height: RindeSpace.s5)],
      _CategoryPicker(
        type: _type,
        value: _category,
        showAll: _allCategories,
        editing: _editing,
        error: problem('category'),
        onShowAll: () => setState(() => _allCategories = true),
        onChanged: (c) => _edit('category', () => _category = c),
      ),
      if (_editing) ...paidWith,
      if (_saved?.original case final original?) ...[
        const SizedBox(height: RindeSpace.s5),
        RindeBanner(
          tone: RindeBannerTone.info,
          message:
              '${t('Lo pagaste en')} ${original.currency}${t('. Si cambias el monto, queda en')} '
              '${region.currency} ${t('sin la conversión.')}',
        ),
      ],
      if (!_editing) ...[
        const SizedBox(height: RindeSpace.s5),
        _Details(
          open: _details,
          summary: [
            if (_date == _today())
              t('Hoy')
            else if (_date == isoDay(ref.read(clockProvider)().subtract(const Duration(days: 1))))
              t('Ayer')
            else
              dayAndMonth(_date, region),
            if (_expense) card == null ? t('Efectivo o débito') : t('Tarjeta'),
            if (_expense && _kakeibo != null) t(_kakeiboLabel(_kakeibo!)),
          ].join(' · '),
          onToggle: () => setState(() => _details = !_details),
          children: [
            date,
            ...paidWith,
            if (_expense) ...[
              const SizedBox(height: RindeSpace.s5),
              _KakeiboPicker(
                value: _kakeibo,
                error: problem('kakeibo'),
                onChanged: (k) => _edit('kakeibo', () => _kakeibo = k),
              ),
            ],
          ],
        ),
      ],
    ];

    final footer = <Widget>[
      if (_error case final error?) ...[
        RindeBanner(message: t(error)),
        const SizedBox(height: RindeSpace.s3),
      ],
      if (confirming) ...[
        RindeBanner(
          tone: RindeBannerTone.neutral,
          message:
              '${t('¿Seguro que son')} ${format.money(amount!)}? '
              '${t('Es un monto muy alto: revisa que no sobre un cero. Si está bien, toca de nuevo para guardar.')}',
        ),
        const SizedBox(height: RindeSpace.s3),
      ],
      RindeButton(label: saveLabel, loading: _saving, loadingLabel: t('Guardando…'), onPressed: _save),
      if (_editing) ...[
        const SizedBox(height: RindeSpace.s2),
        RindeButton(
          label: t('Cancelar'),
          variant: RindeButtonVariant.outline,
          onPressed: _saving ? null : _close,
        ),
      ],
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form),
              ),
            ),
          ),
        ),
        // Fijo abajo, siempre a la vista; con letra grande se desplaza en vez de tapar el formulario.
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.canvas,
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s3, RindeSpace.s4, RindeSpace.s4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: footer),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _kakeiboLabel(String key) => _kakeibo.firstWhere((k) => k.$1 == key, orElse: () => (key, key, '')).$2;

/// Píldora elegible de 48 de alto (ChipGroup y los botones de categoría de la web).
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? RindeBrand.white : p.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.brandSolid : p.brandSoft,
        borderRadius: BorderRadius.circular(RindeRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RindeRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RindeSize.tapTarget, minWidth: RindeSize.tapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label, style: RindeType.meta.w(FontWeight.w600).copyWith(color: fg)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: RindeSpace.s2),
      child: Semantics(
        header: true,
        child: Text.rich(
          TextSpan(
            text: text,
            children: [
              if (trailing != null)
                TextSpan(
                  text: ' $trailing',
                  style: RindeType.caption.copyWith(color: p.inkMuted),
                ),
            ],
          ),
          style: RindeType.eyebrow.copyWith(color: p.inkMuted),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RindeSpace.s2),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: RindeType.small.copyWith(color: context.palette.negative)),
    ),
  );
}

/// Categoría: «Que la elija la IA» (null, la decide el servidor al guardar) o una del catálogo.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.type,
    required this.value,
    required this.showAll,
    required this.editing,
    required this.onShowAll,
    required this.onChanged,
    this.error,
  });

  final MovementType type;
  final String? value;
  final bool showAll;
  final bool editing;
  final String? error;
  final VoidCallback onShowAll;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final categories = ref.watch(movementCategoriesProvider(ref.watch(accountProvider)));
    final list = categories.value?.of(type) ?? const <CategoryOption>[];
    final index = list.indexWhere((c) => c.key == value);
    // Una elegida que ya no está en el catálogo (se borró) sigue a la vista.
    final missing = value != null && index < 0 && categories.hasValue;
    final all = showAll || index >= _visibleCategories;
    final visible = all ? list : list.take(_visibleCategories).toList();
    String name(CategoryOption c) => c.custom ? c.name : t(c.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(t('Categoría')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(label: t('Que la elija la IA'), selected: value == null, onTap: () => onChanged(null)),
            if (missing) _Chip(label: value!, selected: true, onTap: () {}),
            for (final c in visible)
              _Chip(label: name(c), selected: c.key == value, onTap: () => onChanged(c.key)),
            if (!all && list.length > _visibleCategories)
              TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  t('Ver todas'),
                  style: RindeType.meta.w(FontWeight.w600).copyWith(color: p.brand),
                ),
              ),
          ],
        ),
        if (categories.isLoading)
          Padding(
            padding: const EdgeInsets.only(top: RindeSpace.s2),
            child: Text(t('Cargando…'), style: RindeType.small.copyWith(color: p.inkMuted)),
          )
        else if (categories.hasError && !categories.hasValue)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RindeTextLink(
              label: t('Reintentar'),
              onPressed: () => ref.invalidate(movementCategoriesProvider),
            ),
          ),
        if (editing && value == null)
          Padding(
            padding: const EdgeInsets.only(top: RindeSpace.s2),
            child: Text(
              t('La clasificamos por ti al guardar.'),
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ),
        if (error != null) _ErrorText(error!),
      ],
    );
  }
}

/// «Pagado con»: «Efectivo o débito» (null) o una tarjeta, con la etiqueta de la lista de Tarjetas.
class _PaidWithPicker extends ConsumerWidget {
  const _PaidWithPicker({required this.cards, required this.value, required this.onChanged, this.error});

  final List<CreditCard> cards;
  final String? value;
  final String? error;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(t('Pagado con')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(label: t('Efectivo o débito'), selected: value == null, onTap: () => onChanged(null)),
            for (final c in cards)
              _Chip(
                label: cardListLabel(t, network: c.network, name: c.name, last4: c.last4),
                selected: value == c.id,
                onTap: () => onChanged(c.id),
              ),
          ],
        ),
        if (error != null) _ErrorText(error!),
      ],
    );
  }
}

/// DateQuickPick: «Hoy», «Ayer» u «Otra fecha» (hasta hoy).
class _DateQuickPick extends ConsumerStatefulWidget {
  const _DateQuickPick({
    required this.value,
    required this.today,
    required this.region,
    required this.onChanged,
    this.error,
  });

  final String value;
  final String today;
  final Region region;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<_DateQuickPick> createState() => _DateQuickPickState();
}

class _DateQuickPickState extends ConsumerState<_DateQuickPick> {
  bool _other = false;

  String get _yesterday => isoDay(DateTime.parse(widget.today).subtract(const Duration(days: 1)));

  Future<void> _pick() async {
    final last = DateTime.parse(widget.today);
    final current = DateTime.parse(widget.value);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(last) ? last : current,
      firstDate: DateTime(2000),
      lastDate: last,
      helpText: ref.read(trProvider)('Fecha del movimiento'),
    );
    if (picked == null || !mounted) return;
    setState(() => _other = true);
    widget.onChanged(isoDay(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final mode = _other
        ? 'other'
        : widget.value == widget.today
        ? 'today'
        : widget.value == _yesterday
        ? 'yesterday'
        : 'other';
    final year = widget.value.substring(0, 4);
    final label =
        '${dayAndMonth(widget.value, widget.region)}'
        '${year == widget.today.substring(0, 4) ? '' : ' $year'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(t('Fecha')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: t('Hoy'),
              selected: mode == 'today',
              onTap: () {
                setState(() => _other = false);
                widget.onChanged(widget.today);
              },
            ),
            _Chip(
              label: t('Ayer'),
              selected: mode == 'yesterday',
              onTap: () {
                setState(() => _other = false);
                widget.onChanged(_yesterday);
              },
            ),
            _Chip(label: t('Otra fecha'), selected: mode == 'other', onTap: _pick),
          ],
        ),
        if (mode == 'other')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              label: t('Fecha del movimiento'),
              child: TextButton.icon(
                onPressed: _pick,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: RindeIcon(RindeIcons.calendarRange, size: 18, color: p.brand),
                label: Text(label, style: RindeType.bodyMedium.copyWith(color: p.brand)),
              ),
            ),
          ),
        if (widget.error != null) _ErrorText(widget.error!),
      ],
    );
  }
}

/// «¿Podías evitarlo?» (opcional, solo gastos). Tocar el elegido lo quita.
class _KakeiboPicker extends ConsumerWidget {
  const _KakeiboPicker({required this.value, required this.onChanged, this.error});

  final String? value;
  final String? error;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final chosen = _kakeibo.where((k) => k.$1 == value).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(t('¿Podías evitarlo?'), trailing: t('(opcional)')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (key, label, _) in _kakeibo)
              _Chip(
                label: t(label),
                selected: value == key,
                onTap: () => onChanged(value == key ? null : key),
              ),
          ],
        ),
        const SizedBox(height: RindeSpace.s2),
        Semantics(
          liveRegion: true,
          child: Text(
            t(chosen?.$3 ?? 'Necesidad, deseo, cultura o imprevisto: te ayuda a ver en qué podrías ahorrar.'),
            style: RindeType.caption.copyWith(color: p.inkMuted),
          ),
        ),
        if (error != null) _ErrorText(error!),
      ],
    );
  }
}

/// «Más detalles»: plegado, con el resumen de lo que lleva.
class _Details extends ConsumerWidget {
  const _Details({required this.open, required this.summary, required this.onToggle, required this.children});

  final bool open;
  final String summary;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
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
                        child: Text.rich(
                          TextSpan(
                            text: t('Más detalles'),
                            style: RindeType.control.w(FontWeight.w600).copyWith(color: p.ink),
                            children: [
                              TextSpan(
                                text: ' · $summary',
                                style: RindeType.control.copyWith(color: p.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: RindeSpace.s2),
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
