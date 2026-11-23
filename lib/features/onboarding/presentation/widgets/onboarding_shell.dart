import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_line.dart';

/// Marco de los pasos 1-9 (OnboardingShell.jsx): Atrás a la izquierda, la línea de avance en el
/// centro, Omitir a la derecha, el contenido que entra deslizándose y un único botón abajo.
/// El botón y el error suben con el teclado; el contenido se desplaza.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.total,
    required this.direction,
    required this.onBack,
    required this.onSkip,
    required this.action,
    required this.child,
    required this.labels,
    this.busy = false,
    this.error,
    this.overlay,
  });

  final int step;
  final int total;

  /// 1 avanza (entra desde la derecha), -1 vuelve.
  final int direction;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  /// Botón principal (uno solo, 48 de alto).
  final Widget action;

  /// Contenido del paso. Se vuelve a montar en cada paso.
  final Widget child;
  final OnboardingShellLabels labels;
  final bool busy;
  final String? error;

  /// Algo encima de todo (la etiqueta DEMO).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: RindeSpace.readableColumn),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(RindeSpace.s1, RindeSpace.s2, RindeSpace.s1, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: busy ? null : onBack,
                            tooltip: labels.back,
                            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                            icon: RindeIcon(
                              RindeIcons.chevronLeft,
                              color: p.ink.withValues(alpha: busy ? 0.35 : 0.7),
                            ),
                          ),
                          Expanded(
                            child: Semantics(
                              label: labels.progress,
                              value: labels.stepOf(step, total),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s2),
                                child: RindeLine(value: step / total),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: busy ? null : onSkip,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3),
                              foregroundColor: p.ink.withValues(alpha: 0.6),
                              disabledForegroundColor: p.ink.withValues(alpha: 0.3),
                              textStyle: RindeType.control,
                              shape: const RoundedRectangleBorder(borderRadius: RindeRadius.brXl),
                            ),
                            child: Text(labels.skip),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(step),
                        tween: Tween(begin: reduce ? 1 : 0, end: 1),
                        duration: RindeMotion.page,
                        curve: RindeMotion.screen,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset((1 - t) * 16 * direction, 0),
                            child: child,
                          ),
                        ),
                        child: SingleChildScrollView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(
                            RindeSpace.s4,
                            RindeSpace.s6,
                            RindeSpace.s4,
                            RindeSpace.s4,
                          ),
                          // Mientras guarda no se edita: lo escrito en ese momento no viajaría.
                          // Sigue desplazándose; el campo con foco lo suelta (y se cierra el teclado).
                          child: ExcludeFocus(
                            excluding: busy,
                            child: IgnorePointer(
                              ignoring: busy,
                              child: _StepScope(label: labels.stepOf(step, total), child: child),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Barra inferior: el error justo encima del botón.
                    DecoratedBox(
                      decoration: BoxDecoration(color: p.canvas),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          RindeSpace.s4,
                          RindeSpace.s3,
                          RindeSpace.s4,
                          RindeSpace.s3 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (error != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(error!, style: RindeType.small.copyWith(color: p.negative)),
                              ),
                              const SizedBox(height: RindeSpace.s2),
                            ],
                            action,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

/// Textos del marco ya traducidos.
class OnboardingShellLabels {
  const OnboardingShellLabels({
    required this.back,
    required this.skip,
    required this.progress,
    required this.stepOf,
  });

  final String back;
  final String skip;
  final String progress;
  final String Function(int step, int total) stepOf;
}

/// «Paso n de m» del marco, para que el título del paso lo anuncie junto con su texto.
class _StepScope extends InheritedWidget {
  const _StepScope({required this.label, required super.child});
  final String label;

  @override
  bool updateShouldNotify(_StepScope old) => false;
}

/// Título de paso (StepTitle): 28, semibold, tracking -0.025em. Es un encabezado y, al entrar al
/// paso, se anuncia al lector de pantalla con «Paso n de m».
class StepTitle extends StatefulWidget {
  const StepTitle(this.text, {super.key, this.subtitle});
  final String text;
  final String? subtitle;

  @override
  State<StepTitle> createState() => _StepTitleState();
}

class _StepTitleState extends State<StepTitle> {
  @override
  void initState() {
    super.initState();
    // Cada paso monta un título nuevo. Se anuncia a mano: un liveRegion no siempre se lee en el
    // primer montaje, y sin esto cambiar de paso no dice nada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final step = context.getInheritedWidgetOfExactType<_StepScope>()?.label;
      SemanticsService.sendAnnouncement(
        View.of(context),
        [widget.text, ?step].join('\n'),
        Directionality.of(context),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.text,
            style: RindeType.headline.copyWith(fontSize: 28, height: 1.25, color: p.ink),
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: RindeSpace.s2),
          Text(widget.subtitle!, style: RindeType.body.copyWith(color: p.inkMuted)),
        ],
      ],
    );
  }
}

/// Caja de Rin que explica por qué se pregunta algo (Why de Welcome.jsx): fondo brand-soft al 60 %,
/// Rin pequeño a la izquierda y el texto. `rin` se pasa ya construido (para elegir emoción/gesto).
class RinNote extends StatelessWidget {
  const RinNote({super.key, this.rin, required this.text});

  /// Rin solo donde lo aprobó la marca (opción B: saludo, ingresos y final). Sin él, la nota queda.
  final Widget? rin;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(RindeSpace.s3),
      decoration: BoxDecoration(
        color: p.brandSoft.withValues(alpha: p.brandSoft.a * 0.6),
        borderRadius: RindeRadius.brX2,
      ),
      child: Row(
        children: [
          if (rin case final rin?) ...[
            SizedBox(width: 40, height: 44, child: rin),
            const SizedBox(width: RindeSpace.s3),
          ],
          Expanded(
            child: Text(text, style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }
}

/// Franja «DEMO · SIN BACKEND» arriba de toda la bienvenida (solo en sesiones de demostración).
/// Ocupa su propio espacio (con la barra de estado) para no tapar el logo ni los controles.
class DemoStrip extends StatelessWidget {
  const DemoStrip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Material(
        color: RindeBrand.destructive,
        child: SafeArea(
          bottom: false,
          child: Semantics(
            button: true,
            label: 'Modo demostración, sin servidor. Abrir panel de demostración',
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              // Con texto grande crece en alto y parte la línea: el aviso nunca se corta.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 2),
                    child: Text(
                      'DEMO · SIN BACKEND · toca para simular',
                      textAlign: TextAlign.center,
                      style: RindeType.caption
                          .w(FontWeight.w700)
                          .copyWith(color: RindeBrand.white, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
