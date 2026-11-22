import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_icon.dart';

/// Ilustraciones del recorrido «Cómo funciona» (HowItWorksTour.jsx). Son ejemplos: el escenario
/// que las rodea lleva la etiqueta «Ejemplo» y nada se anota en la cuenta.
///
/// Con movimiento reducido cada escena se dibuja quieta en su estado final (la web deja la 1 en
/// el primer estado y sigue animando las barras y la respuesta de WhatsApp).

/// Montos y frases de los ejemplos a la escala de la moneda (inThousands/demoMoney de la web): en
/// pesos colombianos se habla en miles («40 mil», $ 40.000); en las demás, el número solo (40, $40).
class TourExample {
  TourExample(Region region, this.t) : inThousands = region.currency == 'COP', _format = formatFor(region);

  final Tr t;
  final bool inThousands;
  final MoneyFormat _format;

  String money(num pesos) => _format.money(inThousands ? pesos : pesos / 1000);
}

/// Escena 1: la ficha violeta del inicio con el saldo que baja al anotar un gasto.
class BalanceScene extends StatelessWidget {
  const BalanceScene({super.key, required this.example});
  final TourExample example;

  @override
  Widget build(BuildContext context) {
    final t = example.t;
    final white = RindeType.small.copyWith(color: RindeBrand.white);
    return _Phases(
      at: const [1600],
      builder: (phase) {
        final money = phase == 0 ? 100000 : 80000;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RindeSpace.s5),
          decoration: const BoxDecoration(color: RindeBrand.violet, borderRadius: RindeRadius.brX3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Saldo disponible'), style: white.copyWith(color: RindeBrand.onVioletMuted)),
              const SizedBox(height: RindeSpace.s1),
              // Cada monto entra cayendo unos píxeles (la web lo monta de nuevo con key={money}).
              _Enter(
                key: ValueKey(money),
                duration: RindeMotion.rise,
                curve: RindeMotion.out,
                builder: (v) => Opacity(
                  opacity: 0.4 + 0.6 * v,
                  child: Transform.translate(
                    offset: Offset(0, -6 * (1 - v)),
                    child: _Amount(example.money(money), size: 36, line: 40, color: RindeBrand.white),
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s3),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0x26FFFFFF),
                  borderRadius: BorderRadius.all(Radius.circular(RindeRadius.pill)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s1),
                  child: Text(t('Banco + Nequi + efectivo'), style: white),
                ),
              ),
              // La ficha crece con suavidad en vez de saltar como en la web.
              AnimatedSize(
                duration: RindeMotion.base,
                curve: RindeMotion.out,
                alignment: Alignment.topLeft,
                child: phase == 0
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: RindeSpace.s2),
                        child: _Enter(
                          duration: RindeMotion.base,
                          builder: (v) => Opacity(
                            opacity: v,
                            child: Text(
                              '− ${example.money(20000)} ${t('· almuerzo')}',
                              style: white.copyWith(color: RindeBrand.onVioletMuted),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Escena 2: «Anota hablando», contado sin sonido. Primero la onda (escucha), luego lo que se dijo,
/// cómo lo entendió Rinde (palabra → categoría, número → monto) y al final el movimiento. Todo
/// ocupa su sitio desde el principio: nada empuja a lo demás al aparecer.
class VoiceScene extends StatelessWidget {
  const VoiceScene({super.key, required this.example});
  final TourExample example;

  /// Cuándo aparece cada parte (ms): lo dicho, lo que Rinde entendió, lo anotado.
  static const steps = [1300, 2100, 2900];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = example.t;
    final phrase = example.inThousands ? t('“gasolina 40 mil”') : t('“gasolina 40”');
    // «gasolina 40 mil» → lo que nombra el gasto y lo que dice el monto (como la web, ya traducido).
    final [word, ...amountWords] = phrase.replaceAll(RegExp('[“”]'), '').split(' ');
    final amount = example.money(40000);
    Widget fade(bool shown, Widget child) =>
        _Reveal(shown: shown, rise: 0, duration: RindeMotion.base, curve: RindeMotion.standard, child: child);

    return _Phases(
      at: steps,
      builder: (phase) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s3),
            decoration: const BoxDecoration(
              color: RindeBrand.violet,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(RindeRadius.x3),
                topRight: Radius.circular(RindeRadius.x3),
                bottomLeft: Radius.circular(RindeRadius.x3),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RindeIcon(RindeIcons.mic, size: 16, color: RindeBrand.white),
                const SizedBox(width: RindeSpace.s3),
                // La onda y la frase comparten casilla: el globo no cambia de tamaño entre una y otra.
                Flexible(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      fade(phase == 0, _VoiceWave(listening: phase == 0)),
                      fade(phase >= 1, Text(phrase, style: RindeType.body.copyWith(color: RindeBrand.white))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RindeSpace.s3),
          _Reveal(
            shown: phase >= 2,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: RindeSpace.s2,
              runSpacing: RindeSpace.s2,
              children: [
                _Token(from: word, to: t('Transporte')),
                _Token(from: amountWords.join(' '), to: amount),
              ],
            ),
          ),
          const SizedBox(height: RindeSpace.s3),
          _Reveal(
            shown: phase >= 3,
            child: MergeSemantics(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(RindeSpace.s4),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: RindeRadius.brX2,
                  border: Border.all(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        RindeIcon(RindeIcons.checkBold, size: 16, color: p.positive),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(t('Anotado'), style: RindeType.small.copyWith(color: p.positive)),
                        ),
                      ],
                    ),
                    const SizedBox(height: RindeSpace.s1),
                    // En una línea si caben; con texto muy grande el monto baja en vez de desbordar.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: RindeSpace.s3,
                      children: [
                        Text(t('Transporte · gasolina'), style: RindeType.bodyMedium.copyWith(color: p.ink)),
                        Text('− $amount', style: RindeType.bodyMedium.copyWith(color: p.negative).tabular),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escena 3: lo que Mi plata responde cada día.
class PlanScene extends StatelessWidget {
  const PlanScene({super.key, required this.example});
  final TourExample example;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = example.t;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RindeIcon(RindeIcons.wallet, size: 16, color: p.brand),
              const SizedBox(width: RindeSpace.s2),
              Flexible(
                child: Text(t('Hoy puedes gastar'), style: RindeType.small.copyWith(color: p.inkMuted)),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s1),
          _Amount(example.money(32000), size: 30, line: 36, color: p.ink),
          const SizedBox(height: RindeSpace.s3),
          _Bar(fraction: 0.45, color: p.brandSolid),
          const SizedBox(height: RindeSpace.s3),
          Text(
            t('Faltan 12 días para tu sueldo y ya apartamos el arriendo.'),
            style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// Escena 4: una vaca con su barra de aportes (450 de 600 = 75 %).
class VacaScene extends StatelessWidget {
  const VacaScene({super.key, required this.example});
  final TourExample example;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = example.t;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RindeIcon(RindeIcons.users, size: 16, color: p.brand),
              const SizedBox(width: RindeSpace.s2),
              Flexible(
                child: Text(t('Paseo a Villa de Leyva'), style: RindeType.bodyMedium.copyWith(color: p.ink)),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s1),
          Text(
            '${example.money(450000)} ${t('de')} ${example.money(600000)} ${t('· 4 amigos')}',
            style: RindeType.small.copyWith(color: p.inkMuted).tabular,
          ),
          const SizedBox(height: RindeSpace.s3),
          _Bar(fraction: 0.75, color: p.positive),
        ],
      ),
    );
  }
}

/// Escena 5: un chat de WhatsApp con Rinde. [onReplied] avisa cuando la respuesta terminó de entrar.
class WhatsappScene extends StatelessWidget {
  const WhatsappScene({super.key, required this.example, this.onReplied});
  final TourExample example;
  final VoidCallback? onReplied;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = example.t;
    final money = example.money(38000);
    return _Card(
      padding: RindeSpace.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: RindeSpace.s8),
              child: _Bubble(
                text: example.inThousands ? t('hice 38 mil') : t('hice 38'),
                // Los colores de WhatsApp, fijos en los dos temas (como la web).
                color: const Color(0xFFD9FDD3),
                textColor: const Color(0xFF111B21),
                mine: true,
              ),
            ),
          ),
          const SizedBox(height: RindeSpace.s2),
          _Enter(
            delay: const Duration(milliseconds: 900),
            duration: const Duration(milliseconds: 400),
            onEnd: onReplied,
            builder: (v) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - v)),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: RindeSpace.s8),
                    child: _Bubble(
                      // Las mismas dos claves de la web (la frase está partida allá), para heredar en/pt.
                      text: '${t('Listo, anoté un ingreso de')} $money${t('. Hoy llevas')} $money.',
                      color: p.surfaceMuted,
                      textColor: p.ink,
                      mine: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Piezas ───────────────────────────────────────────────────────────────────────────────────

/// Fases de una secuencia: pasa a la fase i+1 a los `at[i]` ms del montaje. Con movimiento
/// reducido arranca ya en la última y no programa nada.
class _Phases extends StatefulWidget {
  const _Phases({required this.at, required this.builder});
  final List<int> at;
  final Widget Function(int phase) builder;

  @override
  State<_Phases> createState() => _PhasesState();
}

class _PhasesState extends State<_Phases> {
  final _timers = <Timer>[];
  int? _phase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phase != null) return; // Si cambia el movimiento reducido, el paso monta la escena de nuevo.
    final still = MediaQuery.disableAnimationsOf(context);
    _phase = still ? widget.at.length : 0;
    if (still) return;
    for (final (i, ms) in widget.at.indexed) {
      _timers.add(Timer(Duration(milliseconds: ms), () => setState(() => _phase = i + 1)));
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_phase!);
}

/// Algo que entra al montarse, después de [delay]. Con movimiento reducido ya está en su sitio.
class _Enter extends StatelessWidget {
  const _Enter({
    super.key,
    required this.builder,
    required this.duration,
    this.delay = Duration.zero,
    this.curve = RindeMotion.screen,
    this.onEnd,
  });

  final Widget Function(double v) builder;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return builder(1);
    final total = delay + duration;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: curve),
      onEnd: onEnd,
      builder: (context, v, _) => builder(v),
    );
  }
}

/// Aparece (opacidad y [rise] px hacia arriba) cuando [shown] pasa a true. Oculta sigue ocupando su
/// sitio y queda fuera del lector de pantalla (Opacity 0 no publica semántica).
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.shown,
    required this.child,
    this.rise = 8,
    this.duration = const Duration(milliseconds: 300),
    this.curve = RindeMotion.out,
  });

  final bool shown;
  final Widget child;
  final double rise;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final target = shown ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) return Opacity(opacity: target, child: child);
    return TweenAnimationBuilder<double>(
      // Solo cuenta `end`: al cambiar, anima desde donde esté.
      tween: Tween(begin: target, end: target),
      duration: duration,
      curve: curve,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * rise), child: child),
      ),
    );
  }
}

/// Onda de 7 barras (voice-wave: 0,9 s, scaleY 0,3 ↔ 1, desfase de 120 ms cada 4). Se detiene
/// cuando deja de escuchar.
class _VoiceWave extends StatefulWidget {
  const _VoiceWave({required this.listening});
  final bool listening;

  @override
  State<_VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<_VoiceWave> with SingleTickerProviderStateMixin {
  static const _cycleMs = 900.0;
  late final _clock = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_VoiceWave old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.listening && !MediaQuery.disableAnimationsOf(context);
    if (!run) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  double _scale(int bar) {
    final cycle = ((_clock.value * _cycleMs - (bar % 4) * 120) / _cycleMs) % 1.0;
    final half = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2;
    return 0.3 + 0.7 * Curves.easeInOut.transform(half);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var bar = 0; bar < 7; bar++)
            Padding(
              padding: EdgeInsets.only(left: bar == 0 ? 0 : RindeSpace.s1),
              child: Transform.scale(
                scaleX: 1,
                scaleY: _scale(bar),
                child: const SizedBox(
                  width: 4,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RindeBrand.white,
                      borderRadius: BorderRadius.all(Radius.circular(RindeRadius.pill)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Ficha «lo dicho → lo entendido».
class _Token extends StatelessWidget {
  const _Token({required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.all(Radius.circular(RindeRadius.pill)),
          border: Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(from, style: RindeType.small.copyWith(color: p.inkMuted)),
            ),
            const SizedBox(width: 6),
            RindeIcon(RindeIcons.arrowRight, size: 14, color: p.ink.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(to, style: RindeType.small.w(FontWeight.w500).copyWith(color: p.ink).tabular),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta blanca de las escenas 3-5 (radio 24, borde ink/10).
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = RindeSpace.s5});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: RindeRadius.brX3,
        border: Border.all(color: p.line),
      ),
      child: child,
    );
  }
}

/// Monto grande en una línea: con texto muy grande se encoge en vez de partirse.
class _Amount extends StatelessWidget {
  const _Amount(this.text, {required this.size, required this.line, required this.color});
  final String text;
  final double size;
  final double line;
  final Color color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      maxLines: 1,
      style: RindeType.display
          .copyWith(fontSize: size, height: line / size, letterSpacing: 0, color: color)
          .tabular,
    ),
  );
}

/// Barra que se llena hasta [fraction] (0,4 s de espera y 1 s, como la web). Decorativa.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.all(Radius.circular(RindeRadius.pill)),
    child: SizedBox(
      height: RindeSpace.s2,
      width: double.infinity,
      child: ColoredBox(
        color: context.palette.line,
        child: _Enter(
          delay: const Duration(milliseconds: 400),
          duration: const Duration(seconds: 1),
          builder: (v) => FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction * v,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(Radius.circular(RindeRadius.pill)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Globo de chat: el propio con la esquina inferior del lado de la persona más cerrada.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.color, required this.textColor, required this.mine});
  final String text;
  final Color color;
  final Color textColor;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(RindeRadius.x2);
    const tail = Radius.circular(6);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadiusDirectional.only(
          topStart: round,
          topEnd: round,
          bottomStart: mine ? round : tail,
          bottomEnd: mine ? tail : round,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
        child: Text(text, style: RindeType.small.copyWith(color: textColor)),
      ),
    );
  }
}
