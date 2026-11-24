import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_flow.dart';
import '../widgets/onboarding_shell.dart';

/// Posición 1: país, idioma y moneda (components/onboarding/CountryStep.jsx). El país propone la
/// moneda y el idioma; una vez la persona toca el idioma, cambiar de país ya no lo mueve (eso lo
/// decide el controlador). La ficha violeta muestra cómo se va a escribir su plata.
///
/// Diferencia con la web: el país no es un `<select>` nativo sino un campo que abre una hoja con
/// buscador, para que el teclado no corte la lista.
class CountryStep extends ConsumerStatefulWidget {
  const CountryStep({super.key, required this.mode});
  final OnboardingMode mode;

  @override
  ConsumerState<CountryStep> createState() => _CountryStepState();
}

class _CountryStepState extends ConsumerState<CountryStep> {
  Future<void> _openCountries(String selected, String language) async {
    final code = await showCountrySheet(context, selected: selected, language: language);
    if (code == null || !mounted) return;
    ref.read(onboardingControllerProvider(widget.mode).notifier).pickCountry(code);
  }

  @override
  Widget build(BuildContext context) {
    final provider = onboardingControllerProvider(widget.mode);
    final draft = ref.watch(provider.select((s) => s.draft));
    final busy = ref.watch(provider.select((s) => s.busy != null));
    final controller = ref.read(provider.notifier);
    final t = ref.watch(trProvider);
    final p = context.palette;

    final country = findCountry(draft.country) ?? findCountry(kDefaultRegion.country)!;
    final language = draft.language;
    final chip = '${country.currencyName(language)} · ${country.currency}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          t('Hagamos que Rinde hable tu idioma.'),
          subtitle: t('Elige tu país y ajustamos la moneda por ti.'),
        ),
        const SizedBox(height: RindeSpace.s6),
        ExcludeSemantics(
          child: Text(t('País'), style: RindeType.label.copyWith(color: p.inkLabel)),
        ),
        const SizedBox(height: RindeSpace.s2),
        CountryField(
          label: t('País'),
          value: country.name(language),
          onTap: busy ? null : () => _openCountries(country.code, language),
        ),
        const SizedBox(height: RindeSpace.s6),
        _SampleCard(
          legend: t('Así se verá tu plata'),
          sample: country.sample,
          sampleKey: country.code,
          chip: chip,
        ),
        const SizedBox(height: RindeSpace.s6),
        ExcludeSemantics(
          child: Text(t('Idioma'), style: RindeType.label.copyWith(color: p.ink)),
        ),
        const SizedBox(height: RindeSpace.s2),
        RindeSegmented<String>(
          semanticLabel: t('Idioma'),
          options: {for (final l in kLanguages) l.code: l.name},
          value: language,
          onChanged: busy ? null : controller.pickLanguage,
        ),
        const SizedBox(height: RindeSpace.s2),
        Text(
          t('Los dos se cambian cuando quieras en Cuenta.'),
          style: RindeType.small.copyWith(color: p.inkMuted),
        ),
      ],
    );
  }
}

/// Campo que parece un select de la web (48 de alto, radio 12, borde field-line) y abre la hoja.
class CountryField extends StatelessWidget {
  const CountryField({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      value: value,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: p.field,
        shape: RoundedRectangleBorder(
          borderRadius: RindeRadius.brXl,
          side: BorderSide(color: p.fieldLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RindeSize.field),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(value, style: RindeType.body.copyWith(color: p.ink)),
                  ),
                  const SizedBox(width: RindeSpace.s2),
                  RindeIcon(RindeIcons.chevronDown, size: 18, color: p.inkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ficha violeta «Así se verá tu plata»: #6142FF en los dos temas, texto blanco, radio 24, p20.
/// Se anuncia entera cuando cambia (aria-live="polite").
class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.legend,
    required this.sample,
    required this.sampleKey,
    required this.chip,
  });
  final String legend;
  final String sample;
  final String sampleKey;
  final String chip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$legend: $sample. $chip',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(RindeSpace.s5),
        decoration: const BoxDecoration(color: RindeBrand.violet, borderRadius: RindeRadius.brX3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(legend, style: RindeType.small.copyWith(color: RindeBrand.onVioletMuted)),
            const SizedBox(height: RindeSpace.s1),
            // Una sola línea: con texto grande la cifra se encoge en vez de partirse.
            _SwapIn(
              key: ValueKey(sampleKey),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  sample,
                  maxLines: 1,
                  style: RindeType.display.copyWith(letterSpacing: 0, color: RindeBrand.white).tabular,
                ),
              ),
            ),
            const SizedBox(height: RindeSpace.s3),
            _SwapIn(
              key: ValueKey(chip),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 10 % y no 15 %: el texto blanco queda sobre 4,5:1 contra la ficha violeta.
                  color: RindeBrand.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s1),
                  child: Text(chip, style: RindeType.small.copyWith(color: RindeBrand.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `swap-in` de la web (index.css): 220 ms desde opacidad 0, desenfoque de 3 px y 4 px abajo.
/// Se repite cada vez que cambia la `key`. Con movimiento reducido, directo.
class _SwapIn extends StatelessWidget {
  const _SwapIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: RindeMotion.out,
      child: child,
      builder: (context, t, child) {
        final moved = Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 4), child: child),
        );
        if (t >= 1) return moved;
        final blur = 3 * (1 - t);
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: moved,
        );
      },
    );
  }
}

/// Hoja de países a casi pantalla completa, con buscador que ignora tildes («peru» → Perú).
/// Devuelve el código elegido o null si se cerró sin elegir.
Future<String?> showCountrySheet(BuildContext context, {required String selected, required String language}) {
  final p = context.palette;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(RindeRadius.x3)),
    ),
    builder: (_) => _CountrySheet(selected: selected, language: language),
  );
}

class _CountrySheet extends ConsumerStatefulWidget {
  const _CountrySheet({required this.selected, required this.language});
  final String selected;
  final String language;

  @override
  ConsumerState<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends ConsumerState<_CountrySheet> {
  final _search = TextEditingController();
  late final List<Country> _all = countriesSorted(widget.language);
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final query = foldForSearch(_query.trim());
    final shown = query.isEmpty
        ? _all
        : _all.where((c) => foldForSearch(c.name(widget.language)).contains(query)).toList();

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Padding(
        // La lista se acorta sobre el teclado en vez de quedar debajo.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: RindeSpace.s2),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(RindeSpace.s5, RindeSpace.s2, RindeSpace.s2, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(t('País'), style: RindeType.title.copyWith(color: p.ink)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: t('Cerrar'),
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    icon: RindeIcon(RindeIcons.chevronDown, color: p.ink.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s2),
              child: Semantics(
                // TEXTO NUEVO
                label: t('Buscar país'),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  style: RindeType.body.copyWith(color: p.ink),
                  cursorColor: RindeBrand.violet,
                  decoration: InputDecoration(
                    // TEXTO NUEVO
                    hintText: t('Buscar país'),
                    constraints: const BoxConstraints(minHeight: RindeSize.field),
                    contentPadding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(RindeSpace.s6),
                      child: Text(
                        // TEXTO NUEVO
                        t('No encontramos ese país.'),
                        textAlign: TextAlign.center,
                        style: RindeType.body.copyWith(color: p.inkMuted),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.only(bottom: RindeSpace.s4 + MediaQuery.paddingOf(context).bottom),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final c = shown[i];
                        final picked = c.code == widget.selected;
                        return Semantics(
                          selected: picked,
                          button: true,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(c.code),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: RindeSpace.s5,
                                  vertical: RindeSpace.s3,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.name(widget.language),
                                        style: (picked ? RindeType.bodyMedium : RindeType.body).copyWith(
                                          color: picked ? p.brand : p.ink,
                                        ),
                                      ),
                                    ),
                                    if (picked) RindeIcon(RindeIcons.check, size: 18, color: p.brand),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
