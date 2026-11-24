import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../onboarding/presentation/steps/country_step.dart' show CountryField, showCountrySheet;
import '../../application/account_writer.dart';
import 'account_sheet.dart';

/// CountrySettings.jsx: el país donde está la persona. Quien viaja lo cambia y sus cuentas siguen en
/// su moneda principal. Al guardar, la hoja se cierra (onSaved de la web).
class CountrySheet extends ConsumerStatefulWidget {
  const CountrySheet({super.key});

  @override
  ConsumerState<CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends ConsumerState<CountrySheet> {
  late String _country = ref.read(appRegionProvider).country;
  bool _saving = false;
  String? _error;

  Future<void> _pick() async {
    final language = ref.read(displayLanguageProvider);
    final code = await showCountrySheet(context, selected: _country, language: language);
    if (code != null && mounted) setState(() => _country = code);
  }

  Future<void> _save() async {
    final t = ref.read(trProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountWriterProvider).saveCountry(_country);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final language = ref.watch(displayLanguageProvider);
    final current = ref.watch(appRegionProvider);
    String name(String code) => findCountry(code)?.name(language) ?? code;
    final currencyName = findCountry(current.country)?.currencyName(language) ?? current.currency;

    return PopScope(
      canPop: !_saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CountryField(label: t('¿En qué país estás?'), value: name(_country), onTap: _saving ? null : _pick),
          const SizedBox(height: RindeSpace.s4),
          SheetNote(
            '${t('Tus cuentas siguen en')} $currencyName (${current.currency}'
            '${t('). Si viajas, cambia el país: lo que anotes allá se convierte solo a tu moneda.')}',
          ),
          if (_error case final error?) ...[
            const SizedBox(height: RindeSpace.s4),
            RindeBanner(message: error),
          ],
          // El botón apagado sin explicación parecía un error: se dice por qué.
          if (_country == current.country) ...[
            const SizedBox(height: RindeSpace.s4),
            SheetNote(
              t('Ya estás en {country}. Elige otro país para cambiarlo.', {'country': name(_country)}),
            ),
          ],
          const SizedBox(height: RindeSpace.s4),
          RindeButton(
            label: t('Guardar país'),
            loading: _saving,
            onPressed: _country == current.country ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// LanguageSettings.jsx: el idioma de la app, aparte del país (viajar no lo cambia). Cada idioma con su
/// nombre en ese mismo idioma.
class LanguageSheet extends ConsumerStatefulWidget {
  const LanguageSheet({super.key});

  @override
  ConsumerState<LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends ConsumerState<LanguageSheet> {
  String? _saving;
  String? _error;

  Future<void> _pick(String code) async {
    final t = ref.read(trProvider);
    if (code == ref.read(appRegionProvider).language || _saving != null) return;
    setState(() {
      _saving = code;
      _error = null;
    });
    try {
      await ref.read(accountWriterProvider).saveLanguage(code);
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final language = ref.watch(appRegionProvider.select((r) => r.language));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RindeSegmented<String>(
          semanticLabel: t('Idioma'),
          options: {for (final l in kLanguages) l.code: l.name},
          value: _saving ?? language,
          onChanged: _pick,
        ),
        const SizedBox(height: RindeSpace.s3),
        Semantics(
          liveRegion: true,
          child: SheetNote(
            _saving != null
                ? t('Cambiando el idioma…')
                // TEXTO NUEVO: la web dice que se recarga; la app cambia los textos sin recargar.
                : t('Los textos cambian al instante. Tus datos no cambian.'),
          ),
        ),
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s3), RindeBanner(message: error)],
      ],
    );
  }
}
