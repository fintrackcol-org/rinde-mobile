import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/presentation/widgets/home_tap.dart';
import '../../../onboarding/domain/income_sources.dart' show maxPayDays;
import '../../../onboarding/presentation/income/pay_days_field.dart';
import '../../application/money_providers.dart';
import '../../application/money_writer.dart';
import '../../data/money_models.dart';
import '../../domain/income_rules.dart';
import 'paid_button.dart' show moneyErrorText;

/// «Tu sueldo» de Pagos del mes (IncomeSection de MiPlata.jsx con IncomeFields.jsx): cómo le entra la
/// plata en una línea y, con «Cambiar» o «Configurar», con fecha fija (y hasta 4 días) o sin ella.
/// PUT /money-profile reemplaza también el saldo y gana el último: solo se escribe si
/// [canWriteBalance] (demo o perfil con `version`). Si no, queda en solo lectura y dice dónde cambiarlo.
class SalarySection extends ConsumerStatefulWidget {
  const SalarySection({super.key, required this.profile});

  final MoneyProfile profile;

  @override
  ConsumerState<SalarySection> createState() => _SalarySectionState();
}

class _SalarySectionState extends ConsumerState<SalarySection> {
  /// null: no se está editando. `''`: aún sin elegir (la web manda null).
  String? _type;
  List<int> _days = const [];
  bool _saving = false;
  String? _error;

  void _edit() => setState(() {
    _type = widget.profile.incomeType ?? '';
    _days = widget.profile.payDays;
    _error = null;
  });

  Future<void> _save() async {
    final t = ref.read(trProvider);
    final type = _type;
    if (type == null || _saving) return;
    if (type == 'fecha_fija' && _days.isEmpty) {
      setState(() => _error = t('Elige al menos un día de pago.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(moneyWriterProvider).saveIncomeType(widget.profile, type.isEmpty ? null : type, _days);
      if (mounted) setState(() => _type = null);
    } on Object catch (e) {
      // El conflicto y la duda traen su propio texto (ver MoneyWriter).
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final profile = widget.profile;
    final account = ref.watch(accountProvider);
    final writable = canWriteBalance(account, profile);
    // Mientras se vuelve a pedir, [profile] es el de antes: cambiarlo desde ahí chocaría con lo propio.
    final reloading = ref.watch(moneyProfileProvider(account)).isLoading;
    final type = _type;

    final children = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: RindeSpace.s2,
        children: [
          HomeSectionTitle(t('Tu sueldo')),
          if (writable && type == null && !reloading)
            HomeLink(label: profile.incomeType != null ? t('Cambiar') : t('Configurar'), onTap: _edit),
        ],
      ),
    ];

    if (type == null) {
      children.add(Text(incomeSummary(profile, t), style: RindeType.body.copyWith(color: p.inkMuted)));
      if (!writable) {
        children.addAll([
          const SizedBox(height: RindeSpace.s3),
          RindeBanner(
            tone: RindeBannerTone.info,
            // TEXTO NUEVO
            message: t('Por ahora cámbialo en la web de Rinde, con tu misma cuenta.'),
          ),
        ]);
      }
    } else {
      children.addAll([
        const SizedBox(height: RindeSpace.s3),
        Semantics(
          container: true,
          label: t('Cómo te entra la plata'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (value, title, text) in [
                ('fecha_fija', t('Con fecha fija'), t('Sueldo, quincena o mesada que llega segura')),
                ('sin_fecha', t('Sin fecha fija'), t('Trabajos, ventas, ayudas o mesada que varía')),
              ]) ...[
                _TypeOption(
                  title: title,
                  text: text,
                  selected: type == value,
                  onTap: _saving
                      ? null
                      : () => setState(() {
                          _type = value;
                          _error = null;
                        }),
                ),
                const SizedBox(height: RindeSpace.s3),
              ],
            ],
          ),
        ),
        if (type == 'fecha_fija') ...[
          const SizedBox(height: RindeSpace.s1),
          // Mientras guarda no se cambian: al guardarse, lo tocado se perdería sin aviso.
          AbsorbPointer(
            absorbing: _saving,
            child: PayDaysField(
              legend: t('¿Qué días te llega? Hasta {MAX_PAY_DAYS}.', {'MAX_PAY_DAYS': maxPayDays}),
              payDays: _days,
              onChanged: (days) => setState(() {
                _days = days;
                _error = null;
              }),
            ),
          ),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: RindeSpace.s3),
          Semantics(
            liveRegion: true,
            child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
          ),
        ],
        const SizedBox(height: RindeSpace.s4),
        RindeButton(label: t('Guardar'), loading: _saving, loadingLabel: t('Guardando…'), onPressed: _save),
        const SizedBox(height: RindeSpace.s2),
        RindeButton(
          label: t('Cancelar'),
          variant: RindeButtonVariant.ghost,
          onPressed: _saving ? null : () => setState(() => _type = null),
        ),
      ]);
    }

    return RindeCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Una opción de «Cómo te entra la plata» (radio de IncomeFields.jsx): título y ejemplo.
class _TypeOption extends StatelessWidget {
  const _TypeOption({required this.title, required this.text, required this.selected, required this.onTap});

  final String title;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: selected ? p.brandSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: RindeRadius.brX2,
          side: BorderSide(color: selected ? p.brand : p.ink.withValues(alpha: 0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RindeType.bodyMedium.copyWith(color: selected ? p.brand : p.ink)),
                Text(text, style: RindeType.small.copyWith(color: p.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
