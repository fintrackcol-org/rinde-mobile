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
import '../../../../design/widgets/rinde_icon.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/presentation/widgets/home_money.dart';
import '../../../onboarding/domain/income_sources.dart';
import '../../../onboarding/presentation/income/income_source_tile.dart';
import '../../application/money_providers.dart';
import '../../application/money_writer.dart';
import '../../data/money_models.dart';
import '../../domain/income_rules.dart';
import 'income_overview_card.dart' show moneyOf;

/// Abre «Cómo te entra la plata». [edit]: directo a cambiar las fuentes (aún no hay nada que ver).
Future<void> showIncomeSheet(BuildContext context, {bool edit = false}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastre ni asa (que también se arrastra): cerrarían la hoja mientras guarda, saltándose
  // PopScope, y el resultado no se vería.
  enableDrag: false,
  backgroundColor: context.palette.surface,
  builder: (_) => IncomeSheet(edit: edit),
);

/// El detalle de «Cómo te entra la plata» (la hoja de IncomeOverview.jsx). En modo vista: las fuentes,
/// el sueldo propio, el colchón (solo lectura: crearlo y aportarle son del módulo de metas) y salud y
/// pensión. En modo edición: las cinco casillas de la bienvenida. Al cerrarla se descarta lo editado.
class IncomeSheet extends ConsumerStatefulWidget {
  const IncomeSheet({super.key, this.edit = false});

  final bool edit;

  @override
  ConsumerState<IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends ConsumerState<IncomeSheet> {
  static final _sourceField = RegExp(r'^sources\[(\d+)\]\.(\w+)');

  /// Los que la casilla sabe marcar; los demás van en el aviso general.
  static const _tileFields = {'amount', 'low', 'high', 'lastMonths'};

  /// Las fuentes mientras se cambian, en el orden en que se eligieron. null = modo vista.
  Map<IncomeKind, IncomeSourceForm>? _forms;
  bool _saving = false;
  String? _error;

  /// 422 del servidor por fuente y campo (`sources[i].amount`).
  Map<IncomeKind, Map<String, String>> _fieldErrors = const {};

  bool _pilaSaving = false;
  bool _pilaDone = false;
  String? _pilaError;

  IncomeOverview? get _income => ref.read(incomeOverviewProvider(ref.read(accountProvider))).value;

  @override
  void initState() {
    super.initState();
    if (widget.edit) _forms = _formsOf(_income);
  }

  Map<IncomeKind, IncomeSourceForm> _formsOf(IncomeOverview? income) => {
    for (final s in income?.sources ?? const <IncomeSource>[]) s.kind: IncomeSourceForm.fromServer(s),
  };

  String _message(ApiException e) => ref
      .read(trProvider)
      .call(
        e.messageFor(
          byCode: const {
            ApiCodes.unauthorized: ApiMessages.sessionExpired,
            ApiCodes.tokenExpired: ApiMessages.sessionExpired,
          },
          fallback: ApiMessages.generic,
        ),
      );

  void _change(IncomeKind kind, Map<IncomeKind, IncomeSourceForm> next) => setState(() {
    _forms = next;
    if (_fieldErrors.containsKey(kind)) _fieldErrors = {..._fieldErrors}..remove(kind);
  });

  void _view() => setState(() {
    _forms = null;
    _error = null;
    _fieldErrors = const {};
  });

  Future<void> _save() async {
    final forms = _forms;
    if (forms == null || _saving) return;
    final kinds = forms.keys.toList();
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref.read(moneyWriterProvider).saveSources([for (final f in forms.values) f.toApi()]);
      if (!mounted) return;
      // La vista espera lo releído: con lo de antes, «Cambiar» volvería a enviar lo que se quitó.
      await ref
          .read(incomeOverviewProvider(ref.read(accountProvider)).future)
          .then<void>((_) {}, onError: (Object _) {});
      if (mounted) _view();
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = <IncomeKind, Map<String, String>>{};
      var unplaced = false;
      for (final MapEntry(:key, :value) in e.fields.entries) {
        final match = _sourceField.firstMatch(key);
        final index = match == null ? kinds.length : int.parse(match[1]!);
        if (index < kinds.length && _tileFields.contains(match![2])) {
          (fields[kinds[index]] ??= {})[match[2]!] = value;
        } else {
          unplaced = true;
        }
      }
      setState(() {
        _fieldErrors = fields;
        // Sin campos que se puedan marcar en su casilla, el mensaje va arriba del botón.
        _error = fields.isNotEmpty && !unplaced ? null : _message(e);
      });
    } catch (_) {
      if (mounted) setState(() => _error = ref.read(trProvider)(ApiMessages.generic));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// «Recordármelo cada mes»: la PILA como pago del mes, con el mismo cuerpo de la web.
  Future<void> _remindPila(SocialSecurity social) async {
    if (_pilaSaving) return;
    final t = ref.read(trProvider);
    setState(() {
      _pilaSaving = true;
      _pilaError = null;
    });
    try {
      await ref.read(moneyWriterProvider).createCommitment({
        'name': t('Seguridad social (PILA)'),
        'amount': social.total,
        'dayOfMonth': 10,
      });
      if (mounted) setState(() => _pilaDone = true);
    } on ApiException catch (e) {
      // 409 COMMITMENT_EXISTS: el mensaje del servidor, nunca el de éxito.
      if (mounted) setState(() => _pilaError = _message(e));
    } catch (_) {
      if (mounted) setState(() => _pilaError = t(ApiMessages.generic));
    } finally {
      if (mounted) setState(() => _pilaSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final async = ref.watch(incomeOverviewProvider(ref.watch(accountProvider)));
    final income = async.value;
    final money = moneyOf(ref);
    final forms = _forms;

    final Widget body;
    if (income == null) {
      body = Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted));
    } else if (forms != null) {
      body = _editor(t, p, forms);
    } else {
      body = _details(t, p, income, money);
    }
    return PopScope(
      // Mientras guarda no se cierra: el resultado tiene que verse.
      canPop: !_saving && !_pilaSaving,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(t('Cómo te entra la plata'), style: RindeType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: RindeSpace.s4),
              // La recarga falló (también la de después de guardar): lo de abajo es lo último que llegó.
              if (income != null && async.hasError) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    t('Lo que ves puede estar desactualizado: es lo último que llegó.'),
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                ),
                const SizedBox(height: RindeSpace.s3),
              ],
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(Tr t, RindePalette p, IncomeOverview income, HomeMoney money) {
    final headline = incomeHeadline(income, t, money.call);
    final cushion = income.cushion;
    final region = ref.watch(appRegionProvider);
    // El servidor la calcula en pesos con el salario mínimo de Colombia, sin mirar la moneda: en otra,
    // la cifra y el pago que crearía «Recordármelo» serían falsos (la web la muestra igual).
    final social = region.country == 'CO' && region.currency == 'COP' ? income.socialSecurity : null;
    final textStyle = RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.8));
    final List<Widget> cushionText = switch (cushion) {
      Cushion(metaId: _?, saved: final saved?, goal: final goal?) => [
        _Rich(
          [('${t('Llevas')} ', false), (money(saved), true), (' ${t('de')} ${money(goal)}.', false)],
          money: money,
          style: textStyle,
        ),
      ],
      Cushion(metaId: null, suggestedGoal: final goal?) when goal > 0 => [
        _Rich(
          [
            ('${t('Para que un mes flaco no te coja la tarde, te sugerimos guardar')} ', false),
            (money(goal), true),
            (t('. Si un mes viene flaco, usas de ahí: para eso es.'), false),
          ],
          money: money,
          style: textStyle,
        ),
      ],
      // Sugerir guardar 0 no dice nada: el bloque no sale.
      _ => const [],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline != null) ...[
          MoneyText(
            headline,
            money: money,
            style: RindeType.body.copyWith(color: p.ink.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: RindeSpace.s3),
        ],
        Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: RindeRadius.brX2,
            side: BorderSide(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final source in income.sources) ...[
                Padding(
                  padding: const EdgeInsets.all(RindeSpace.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t(source.kind.title), style: RindeType.bodyMedium.copyWith(color: p.ink)),
                      MoneyText(
                        sourceSummary(source, t, money.call),
                        money: money,
                        style: RindeType.small.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: p.line),
              ],
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => setState(() => _forms = _formsOf(income)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t('Cambiar cómo te entra la plata'),
                              style: RindeType.bodyMedium.copyWith(color: p.brand),
                            ),
                          ),
                          RindeIcon(RindeIcons.chevronRight, size: 16, color: p.brand),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // El servidor redondea a 50 000: un mes flaco chico (o en otra moneda) da 0, y la web no lo muestra.
        if (income.ownSalary case final salary? when salary > 0)
          _Block(
            title: t('Págate un sueldo'),
            children: [
              _Rich(
                [
                  ('${t('Te sugerimos vivir con')} ', false),
                  ('${money(salary)} ${t('al mes')}', true),
                  (t(', aunque un mes te entre más. Lo que sobre va al colchón.'), false),
                ],
                money: money,
                style: textStyle,
              ),
            ],
          ),
        if (cushionText.isNotEmpty) _Block(title: t('Colchón para meses flacos'), children: cushionText),
        if (social != null)
          _Block(
            title: t('Salud y pensión'),
            children: [
              _Rich(
                [
                  ('${t('Como trabajas por tu cuenta, aparta unos')} ', false),
                  (money(social.total), true),
                  (
                    ' ${t('al mes: salud')} ${money(social.health)} ${t('y pensión')} ${money(social.pension)}'
                        '${t(', sobre el 40 % de lo que te entra (mínimo un salario mínimo).')}',
                    false,
                  ),
                ],
                money: money,
                style: textStyle,
              ),
              Text(
                t('Valor aproximado, no es asesoría tributaria. La ARL es aparte y opcional.'),
                style: RindeType.caption.copyWith(color: p.inkMuted),
              ),
              if (_pilaDone)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    t('Listo: quedó en tus pagos del mes (día 10). Cambia el día si tu planilla vence otro.'),
                    style: RindeType.small.copyWith(color: p.positive),
                  ),
                )
              else
                RindeButton(
                  label: t('Recordármelo cada mes'),
                  variant: RindeButtonVariant.soft,
                  size: RindeButtonSize.md,
                  loading: _pilaSaving,
                  onPressed: () => _remindPila(social),
                ),
              if (_pilaError case final error?)
                Semantics(
                  liveRegion: true,
                  child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                ),
            ],
          ),
      ],
    );
  }

  Widget _editor(Tr t, RindePalette p, Map<IncomeKind, IncomeSourceForm> forms) {
    final format = formatFor(ref.watch(appRegionProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: t('Cómo te entra la plata (puedes elegir varias)'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Elige todas las que apliquen. Los montos son aproximados: más o menos está bien.'),
                style: RindeType.body.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: RindeSpace.s3),
              Material(
                color: p.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: RindeRadius.brX3,
                  side: BorderSide(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final kind in IncomeKind.values) ...[
                      if (kind.index > 0)
                        Divider(height: 1, thickness: 1, color: p.ink.withValues(alpha: 0.08)),
                      IncomeSourceTile(
                        kind: kind,
                        form: forms[kind],
                        format: format,
                        t: t,
                        errors: _fieldErrors[kind] ?? const {},
                        onToggle: () => _change(kind, toggleKind(forms, kind)),
                        onChanged: (form) => _change(kind, {...forms, kind: form}),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s4), RindeBanner(message: error)],
        const SizedBox(height: RindeSpace.s5),
        RindeButton(label: t('Guardar'), loading: _saving, loadingLabel: t('Guardando…'), onPressed: _save),
        // Sin fuentes el servidor borra el tipo de ingreso y el plan deja de estar listo (la web lo
        // permite sin avisar).
        if (forms.isEmpty) ...[
          const SizedBox(height: RindeSpace.s2),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RindeIcon(RindeIcons.circleAlert, size: 16, color: p.caution),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // TEXTO NUEVO
                    t('Si guardas sin ninguna, dejamos de calcular cuánto tienes libre.'),
                    style: RindeType.small.w(FontWeight.w500).copyWith(color: p.caution),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: RindeSpace.s2),
        RindeButton(
          label: t('Cancelar'),
          variant: RindeButtonVariant.ghost,
          onPressed: _saving ? null : _view,
        ),
      ],
    );
  }
}

/// Un bloque del detalle (Block de IncomeOverview.jsx): borde, título y texto.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: RindeRadius.brX2,
          border: Border.all(color: p.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RindeSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink)),
              ),
              for (final child in children) ...[const SizedBox(height: RindeSpace.s2), child],
            ],
          ),
        ),
      ),
    );
  }
}

/// Texto con montos en negrita (los `<strong>` de la web). Oculto, el lector oye «Monto oculto».
class _Rich extends StatelessWidget {
  const _Rich(this.parts, {required this.money, required this.style});

  /// (texto, ¿negrita?), en orden.
  final List<(String, bool)> parts;
  final HomeMoney money;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (final (text, bold) in parts)
          TextSpan(text: text, style: bold ? style.w(FontWeight.w600).tabular : null),
      ],
    ),
    semanticsLabel: money.spoken(parts.map((part) => part.$1).join()),
    style: style,
  );
}
