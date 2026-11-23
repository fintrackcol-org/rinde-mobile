import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/presentation/tour_anchors.dart';
import '../../onboarding/presentation/demo_panel.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';

/// Las 4 zonas de la app (MobileTabBar.jsx): Inicio es hoy, Movimientos lo que ya pasó, Planear lo
/// que viene y Yo tu cuenta.
enum RindeTab { home, movements, plan, account }

/// Marco de las pantallas con barra de pestañas: el contenido debajo de la barra de estado y la
/// barra flotando abajo, con «Anotar» en el centro. El contenido se desplaza por debajo de la barra:
/// debe dejar [bottomInset] libre al final.
class RindeTabScaffold extends ConsumerWidget {
  const RindeTabScaffold({super.key, required this.current, required this.child, this.overlay, this.anchors});

  final RindeTab current;
  final Widget child;

  /// Algo encima de todo, barra incluida (el tutorial). Mientras exista, «atrás» es suyo.
  final Widget? overlay;

  /// Solo el Inicio las pasa: el tutorial resalta Anotar, Planear y Yo.
  final TourAnchors? anchors;

  static const _barHeight = 64.0; // h-16
  static const _margin = 12.0; // inset-x-3 y bottom-[max(safe,12px)]
  static const _raise = 12.0; // lo que el círculo de Anotar sobresale de la barra (-mt-6)

  static double _barBottom(BuildContext context) =>
      math.max(MediaQuery.viewPaddingOf(context).bottom, _margin);

  /// Espacio que el contenido deja libre abajo: barra, botón que sobresale, márgenes y zona segura
  /// (104 sin zona segura, como el `6.5rem` de AppShell).
  static double bottomInset(BuildContext context) =>
      _barBottom(context) + _barHeight + _raise + RindeSpace.s4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final safe = MediaQuery.viewPaddingOf(context);
    final demo = ref.watch(sessionControllerProvider.select((s) => s.value?.session?.demo ?? false));
    // Las pestañas se cambian con `go` (no se apilan): atrás vuelve al Inicio y solo ahí cierra la app.
    final backToHome = current != RindeTab.home && overlay == null;
    return PopScope(
      canPop: !backToHome,
      onPopInvokedWithResult: (didPop, _) {
        // Sin `backToHome`, quien frenó el atrás fue otro (el tutorial): es suyo.
        if (!didPop && backToHome) context.go(Routes.app);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // El login deja los íconos de la barra de estado en claro; aquí siguen al tema.
        value: (p.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: p.canvas,
          body: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    if (demo) DemoStrip(onTap: () => showDemoPanel(context)),
                    Expanded(
                      child: demo
                          // La franja ya ocupó la barra de estado; los lados siguen siendo del sistema.
                          ? MediaQuery.removePadding(
                              context: context,
                              removeTop: true,
                              child: SafeArea(top: false, bottom: false, child: child),
                            )
                          : SafeArea(bottom: false, child: child),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: math.max(safe.left, _margin),
                right: math.max(safe.right, _margin),
                bottom: _barBottom(context),
                child: _TabBar(current: current, anchors: anchors),
              ),
              if (overlay != null) Positioned.fill(child: overlay!),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.current, required this.anchors});

  final RindeTab current;
  final TourAnchors? anchors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    // Clave aparte porque «Movimientos» también titula la pantalla. Sin traducción (español) devuelve
    // la clave misma: entonces se ve el nombre completo.
    final short = t('Movimientos (pestaña)');

    Widget tab(
      RindeTab tab,
      String route,
      String label,
      RindeIcons icon, {
      TourTarget? target,
      String? shortLabel,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: RindeTabScaffold._raise + 6),
        child: _TabCell(
          key: target == null ? null : anchors?.key(target),
          label: label,
          shortLabel: shortLabel,
          icon: icon,
          selected: tab == current,
          onTap: () {
            if (tab != current) context.go(route);
          },
        ),
      ),
    );

    // Tope de 1,3 al tamaño de letra: la barra conserva su alto y cada pestaña tiene su nombre para
    // el lector de pantalla.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        role: SemanticsRole.navigation,
        label: t('Secciones'),
        child: SizedBox(
          height: RindeTabScaffold._barHeight + RindeTabScaffold._raise,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: RindeTabScaffold._barHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: p.line),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A141414), offset: Offset(0, 6), blurRadius: 20),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: RindeSpace.s1,
                    children: [
                      tab(RindeTab.home, Routes.app, t('Inicio'), RindeIcons.house),
                      tab(
                        RindeTab.movements,
                        Routes.movements,
                        t('Movimientos'),
                        RindeIcons.list,
                        shortLabel: short == 'Movimientos (pestaña)' ? null : short,
                      ),
                      Expanded(
                        child: _RecordButton(
                          key: anchors?.key(TourTarget.anotar),
                          label: t('Anotar'),
                          onTap: () => context.push(Routes.record),
                        ),
                      ),
                      tab(
                        RindeTab.plan,
                        Routes.plan,
                        t('Planear'),
                        RindeIcons.calendarRange,
                        target: TourTarget.planear,
                      ),
                      tab(
                        RindeTab.account,
                        Routes.account,
                        t('Yo'),
                        RindeIcons.userRound,
                        target: TourTarget.cuenta,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nombre de pestaña: se achica para caber en su celda (320 de ancho, letra grande), nunca se corta.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Flexible(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, style: RindeType.tab.copyWith(color: color)),
    ),
  );
}

class _TabCell extends StatelessWidget {
  const _TabCell({
    super.key,
    required this.label,
    this.shortLabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Solo para la vista: el lector siempre oye [label].
  final String? shortLabel;
  final RindeIcons icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.brand : p.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.brandSoft : Colors.transparent,
        borderRadius: RindeRadius.brX2,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RindeIcon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              _TabLabel(shortLabel ?? label, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Anotar»: círculo violeta de 48 que sobresale de la barra, siempre al alcance del pulgar.
class _RecordButton extends StatefulWidget {
  const _RecordButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        borderRadius: RindeRadius.brX2,
        child: Column(
          children: [
            AnimatedScale(
              scale: _pressed && !MediaQuery.disableAnimationsOf(context) ? 0.94 : 1,
              duration: RindeMotion.fast,
              curve: RindeMotion.standard,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.brandSolid,
                  shape: BoxShape.circle,
                  // ring-4 ring-surface: separa el círculo del contenido que pasa por detrás.
                  border: Border.all(color: p.surface, width: 4, strokeAlign: BorderSide.strokeAlignOutside),
                  boxShadow: const [
                    BoxShadow(color: Color(0x38141414), offset: Offset(0, 6), blurRadius: 16),
                  ],
                ),
                child: const RindeIcon(RindeIcons.plus, size: 24, color: RindeBrand.white),
              ),
            ),
            const SizedBox(height: 2),
            _TabLabel(widget.label, color: p.ink),
          ],
        ),
      ),
    );
  }
}
