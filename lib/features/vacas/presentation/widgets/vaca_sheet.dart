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
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../debts/presentation/widgets/debt_date_field.dart';
import '../../../home/application/home_providers.dart' show todayProvider;
import '../../../home/domain/home_dates.dart';
import '../../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/vacas_writer.dart';
import '../../data/vaca_models.dart';
import '../../domain/vaca_rules.dart';

/// Abre el formulario (VacaForm.jsx) para crear o, con [initial], editar. [personal]: una meta (sin
/// reparto). [askWho]: antes pregunta «¿Es solo para ti o con más personas?» (FT-0066, Vacas.jsx).
/// [prefillName]/[prefillGoal]: el colchón con la cifra puesta. [weeklyIncome]: avisa si el plan se
/// come más del 30 %. Devuelve la vaca creada o editada, o null si se cerró.
Future<Vaca?> showVacaSheet(
  BuildContext context, {
  Vaca? initial,
  bool personal = false,
  bool askWho = false,
  String? prefillName,
  num? prefillGoal,
  num? weeklyIncome,
}) => showModalBottomSheet<Vaca>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => _VacaSheet(
    initial: initial,
    personal: personal,
    askWho: askWho,
    prefillName: prefillName,
    prefillGoal: prefillGoal,
    weeklyIncome: weeklyIncome,
  ),
);

class _VacaSheet extends ConsumerStatefulWidget {
  const _VacaSheet({
    this.initial,
    required this.personal,
    required this.askWho,
    this.prefillName,
    this.prefillGoal,
    this.weeklyIncome,
  });

  final Vaca? initial;
  final bool personal;
  final bool askWho;
  final String? prefillName;
  final num? prefillGoal;
  final num? weeklyIncome;

  @override
  ConsumerState<_VacaSheet> createState() => _VacaSheetState();
}

class _VacaSheetState extends ConsumerState<_VacaSheet> {
  /// null: todavía no eligió para quién es (solo con askWho).
  late bool? _personal = widget.askWho ? null : (widget.initial?.personal ?? widget.personal);
  late final _name = TextEditingController(text: widget.initial?.name ?? widget.prefillName ?? '');
  late String _goal = _raw(widget.initial?.goal ?? widget.prefillGoal);
  late final _description = TextEditingController(text: widget.initial?.description ?? '');
  late String? _deadline = widget.initial?.deadline;
  late String _split = widget.initial?.split ?? 'igual';
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  static String _raw(num? value) => value == null || value <= 0 ? '' : '${value.round()}';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _clear(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Future<void> _save() async {
    if (_saving) return;
    final t = ref.read(trProvider);
    final personal = _personal ?? false;
    final name = _name.text.trim();
    final goal = moneyValue(_goal);
    final description = _description.text.trim();
    // vacaSchema de la web.
    final errors = {
      if (name.isEmpty) 'name': t('Ponle un nombre a la vaca'),
      if (goal == null)
        'goal': t('Ingresa un monto válido')
      else if (goal <= 0)
        'goal': t('La meta debe ser mayor que 0')
      else if (goal > maxAmount)
        'goal': t('El monto es demasiado grande'),
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'goal': goal,
      'description': description.isEmpty ? null : description,
      'deadline': _deadline,
      if (!personal) 'split': _split,
      if (widget.initial == null && personal) 'personal': true,
    };
    try {
      final writer = ref.read(vacasWriterProvider);
      final initial = widget.initial;
      final Vaca saved;
      if (initial == null) {
        saved = await writer.create(body);
      } else {
        await writer.update(initial.id, body..remove('personal'));
        saved = initial;
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      const known = {'name', 'goal', 'description', 'deadline', 'split'};
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
    final personal = _personal;
    final editing = widget.initial != null;
    final title = personal == true
        ? (editing ? t('Editar meta') : t('Nueva meta'))
        : (editing ? t('Editar vaca') : t('Nueva vaca'));
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
                  personal == null ? t('Nueva vaca') : title,
                  style: RindeType.title.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: RindeSpace.s4),
              if (personal == null)
                _WhoChoice(onChoose: (solo) => setState(() => _personal = solo))
              else
                ..._form(t, p, region, personal),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(Tr t, RindePalette p, Region region, bool personal) {
    final today = isoDay(ref.watch(todayProvider));
    final money = moneyOf(ref);
    final plan = personal
        ? weeklyPlan(
            goal: moneyValue(_goal) ?? 0,
            saved: widget.initial?.total ?? 0,
            deadline: _deadline,
            today: today,
          )
        : null;
    return [
      if (widget.askWho && personal) ...[
        DecoratedBox(
          decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${t('Como es solo para ti, la guardamos en')} '),
                  TextSpan(
                    text: t('Metas'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: t(': sin invitaciones ni reparto.')),
                ],
              ),
              style: RindeType.small.copyWith(color: p.ink),
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s4),
      ],
      RindeTextField(
        label: personal ? t('Ponle nombre *') : t('Nombre'),
        controller: _name,
        hint: personal ? t('Ej. Moto, semestre, viaje') : t('Ej. Paseo de fin de año'),
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        enabled: !_saving,
        serverError: _errors['name'],
        onChanged: (_) => _clear('name'),
      ),
      const SizedBox(height: RindeSpace.s4),
      RindeMoneyField(
        value: _goal,
        format: formatFor(region),
        // TEXTO ajustado: la web dice «Meta (COP)» fijo aunque la moneda sea otra.
        label: personal ? t('¿Cuánto necesitas? *') : t('Meta ({currency})', {'currency': region.currency}),
        semanticLabel: personal
            ? t('¿Cuánto necesitas? *')
            : t('Meta ({currency})', {'currency': region.currency}),
        enabled: !_saving,
        errorText: _errors['goal'],
        onChanged: (raw) => setState(() {
          _goal = raw;
          _errors = {..._errors}..remove('goal');
        }),
      ),
      const SizedBox(height: RindeSpace.s4),
      DebtDateField(
        label: personal ? t('¿Para cuándo?') : t('Fecha límite (opcional)'),
        value: _deadline,
        optional: true,
        firstIsToday: true,
        enabled: !_saving,
        error: _errors['deadline'],
        onChanged: (date) => setState(() {
          _deadline = date;
          _errors = {..._errors}..remove('deadline');
        }),
      ),
      if (plan != null) ...[
        const SizedBox(height: RindeSpace.s3),
        Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
            child: Padding(
              padding: const EdgeInsets.all(RindeSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Tu plan').toUpperCase(), style: RindeType.eyebrow.copyWith(color: p.brand)),
                  const SizedBox(height: RindeSpace.s1),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: pesos(money, plan.perWeek), style: RindeType.figure.tabular),
                        TextSpan(text: ' ${t('por semana')}'),
                      ],
                    ),
                    style: RindeType.body.copyWith(color: p.ink),
                  ),
                  Text(
                    '${plan.weeks == 1 ? t('Durante 1 semana') : t('Durante {weeks} semanas', {'weeks': plan.weeks})}'
                    '${t(', y llegas a tiempo.')}',
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isTooMuch(plan.perWeek, widget.weeklyIncome)) ...[
          const SizedBox(height: RindeSpace.s2),
          RindeBanner(
            tone: RindeBannerTone.info,
            message:
                '${t('Es mucho para tus ingresos.')} ${t('Pasa del 30 % de lo que te entra por semana (')}'
                '${pesos(money, widget.weeklyIncome!)}${t('). Prueba con más tiempo.')}',
          ),
        ],
      ],
      const SizedBox(height: RindeSpace.s4),
      RindeTextField(
        label: t('¿Para qué es? (opcional)'),
        controller: _description,
        hint: personal ? t('Ej. La cuota inicial de la moto') : t('Ej. Hotel y transporte'),
        maxLength: 200,
        enabled: !_saving,
        serverError: _errors['description'],
        onChanged: (_) => _clear('description'),
      ),
      if (!personal) ...[
        const SizedBox(height: RindeSpace.s4),
        ExcludeSemantics(
          child: Text(t('Cómo se reparte'), style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeSegmented<String>(
          options: {'igual': t('Partes iguales'), 'personalizado': t('Cuotas a medida')},
          value: _split,
          semanticLabel: t('Cómo se reparte'),
          onChanged: _saving ? null : (value) => setState(() => _split = value),
        ),
        const SizedBox(height: RindeSpace.s2),
        Text(
          t(
            'Con partes iguales, a cada miembro le toca la meta dividida entre todos. Con cuotas a medida, un administrador pone la de cada uno y lo demás se reparte.',
          ),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
      ],
      if (_error case final error?) ...[const SizedBox(height: RindeSpace.s4), RindeBanner(message: error)],
      const SizedBox(height: RindeSpace.s5),
      RindeButton(
        label: widget.initial != null
            ? t('Guardar cambios')
            : personal
            ? t('Crear meta')
            : t('Crear vaca'),
        loading: _saving,
        loadingLabel: t('Guardando…'),
        onPressed: _save,
      ),
      const SizedBox(height: RindeSpace.s2),
      RindeButton(
        label: t('Cancelar'),
        variant: RindeButtonVariant.outline,
        onPressed: _saving
            ? null
            : () => widget.askWho ? setState(() => _personal = null) : Navigator.of(context).pop(),
      ),
    ];
  }
}

/// «¿Es solo para ti o con más personas?» (WhoChoice de Vacas.jsx).
class _WhoChoice extends ConsumerWidget {
  const _WhoChoice({required this.onChoose});

  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    Widget option(bool solo, RindeIcons icon, String title, String hint) => Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s3),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RindeRadius.brX2,
          side: BorderSide(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChoose(solo),
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Row(
              children: [
                RindeIconTile(icon, tone: p.brand),
                const SizedBox(width: RindeSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink)),
                      Text(hint, style: RindeType.small.copyWith(color: p.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('¿Es solo para ti o con más personas?'), style: RindeType.small.copyWith(color: p.inkMuted)),
        option(
          true,
          RindeIcons.userRound,
          t('Solo para mí'),
          t('Una meta propia: la moto, el semestre, un viaje.'),
        ),
        option(
          false,
          RindeIcons.users,
          t('Con más personas'),
          t('Juntan plata entre varios: el paseo, un regalo.'),
        ),
      ],
    );
  }
}
