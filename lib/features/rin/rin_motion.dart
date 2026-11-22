import 'package:flutter/animation.dart';

/// Emociones de Rin, en el mismo orden que `EMOTIONS` de `lib/rin.js` (el índice es la entrada
/// `emocion` de la máquina de Rive). `tranquilo` es la neutral.
enum RinEmotion {
  tranquilo,
  feliz,
  sorprendido,
  pensativo,
  preocupado,
  emocionado,
  conmovido,
  dormido,
  curioso,
  empatico,
}

/// Gestos: animaciones cortas, una a la vez (`GESTURES` de `lib/rin.js`).
///
/// Portados: [saludar], [celebrar], [asentir] y [toque]. Los demás quedan pendientes y por ahora
/// no hacen nada:
/// - [acomodarse] `rin-settle` 0.9 s, [saltar] `rin-jump` 0.8 s: deforman el cuerpo (`.rin-act`).
/// - [senalar] brazo derecho a -96° + `rin-poke`; [acomodar] manos a la pila + `rin-tidy`.
/// - [tambalear] `rin-wobble` 1.1 s; [crecer] `rin-hop` + `rin-pile` + `rin-shadow` 1.3 s.
/// - [guinar] cierra el ojo derecho; [mirarmano] brazo izquierdo a 118° y mira la mano.
/// - Las chispas de la moneda (`rin-twinkle`) de crecer y guiñar (las de celebrar ya están).
enum RinGesture {
  asentir,
  acomodarse,
  saltar,
  celebrar,
  saludar,
  senalar,
  acomodar,
  tambalear,
  toque,
  crecer,
  guinar,
  mirarmano;

  /// Lo que dura el gesto hasta que termina su última animación; `null` si no está portado.
  Duration? get duration => switch (this) {
    // rin-shake 0.42s ease-in-out 0.3s 3.
    saludar => const Duration(milliseconds: 1560),
    // La última chispa: rin-twinkle 0.9s, retardo 0.25s + 2 × 0.13s, dos veces. La web la corta
    // antes si el paso dura menos (`meta_cumplida` lo deja 1.7 s).
    celebrar => const Duration(milliseconds: 2310),
    asentir => const Duration(milliseconds: 800), // rin-nod 0.8s
    toque => const Duration(milliseconds: 600), // rin-tap 0.6s
    _ => null,
  };
}

/// Bocas del dibujo, en el orden de `Rin.jsx`.
enum RinMouth { smile, grin, o, flat, soft, wobble }

/// Curvas del manual visual (`--out` y `--spring` de `rin.css`).
const rinOut = Cubic(0.22, 1, 0.36, 1);
const rinSpring = Cubic(0.34, 1.56, 0.64, 1);

/// Medidas en unidades del dibujo: alto de un billete y suelo.
const rinBillHeight = 13.0;
const rinGround = 266.0;

/// Ningún billete cae derecho: cuánto llega torcido, hasta que Rin los acomoda.
const rinCrooked = <double>[0, 5, -6, 4, -5, 6];

/// Cada valor que se mueve con una transición CSS: su reposo, duración, curva y retardo.
enum RinChannel {
  tilt(0, 500, rinOut),
  armL(16, 500, rinSpring),
  armR(-16, 500, rinSpring, 40),
  ant(0, 700, rinSpring, 60),
  eye(1, 280, rinOut),
  lookX(0, 350, rinOut),
  lookY(0, 350, rinOut),
  blush(0.9, 300, Curves.ease),
  // Ojo abierto, ojo feliz (arco) y ojo cerrado: opacidad y escala vertical.
  openO(1, 180, Curves.ease),
  openS(1, 260, rinOut),
  joyO(0, 180, Curves.ease),
  joyS(0.3, 260, rinOut),
  shutO(0, 180, Curves.ease),
  shutS(0.3, 260, rinOut),
  wetO(0, 180, Curves.ease),
  // Cejas: opacidad, desplazamiento vertical y giro.
  browLO(0, 180, Curves.ease),
  browLY(0, 260, rinOut),
  browLR(0, 260, rinOut),
  browRO(0, 180, Curves.ease),
  browRY(0, 260, rinOut),
  browRR(0, 260, rinOut),
  // Bocas: opacidad, escala y desplazamiento X, en el orden de RinMouth (ver RinPose.mouth).
  smileO(0, 180, Curves.ease),
  smileS(0.5, 260, rinOut),
  smileX(0, 260, rinOut),
  grinO(0, 180, Curves.ease),
  grinS(0.5, 260, rinOut),
  grinX(0, 260, rinOut),
  oO(0, 180, Curves.ease),
  oS(0.5, 260, rinOut),
  oX(0, 260, rinOut),
  flatO(0, 180, Curves.ease),
  flatS(0.5, 260, rinOut),
  flatX(0, 260, rinOut),
  softO(0, 180, Curves.ease),
  softS(0.5, 260, rinOut),
  softX(0, 260, rinOut),
  wobbleO(0, 180, Curves.ease),
  wobbleS(0.5, 260, rinOut),
  wobbleX(0, 260, rinOut),
  zzzO(0, 180, Curves.ease),
  // Altura de Rin sobre su pila (`.rin-rise`).
  rise(rinGround, 550, Cubic(0.34, 1.4, 0.64, 1)),
  // Billetes de abajo arriba: opacidad y desplazamiento X (ver RinPose.bill).
  bill0O(0, 250, Curves.ease),
  bill1O(0, 250, Curves.ease),
  bill2O(0, 250, Curves.ease),
  bill3O(0, 250, Curves.ease),
  bill4O(0, 250, Curves.ease),
  bill5O(0, 250, Curves.ease),
  bill0X(46, 450, rinOut),
  bill1X(46, 450, rinOut),
  bill2X(46, 450, rinOut),
  bill3X(46, 450, rinOut),
  bill4X(46, 450, rinOut),
  bill5X(46, 450, rinOut);

  const RinChannel(this.rest, this.ms, this.curve, [this.delayMs = 0]);

  final double rest;
  final int ms;
  final Curve curve;
  final int delayMs;
}

typedef _C = RinChannel;

/// Postura completa de Rin: un valor por canal. Equivale a las variables y reglas de
/// `.rin[data-emotion]` y `.rin[data-gesture]` de `rin.css`.
class RinPose {
  const RinPose._(this._v);

  final List<double> _v;

  /// Lo que tarda la transición más larga (antena: 60 ms + 700 ms).
  static final transition = Duration(
    milliseconds: RinChannel.values.map((c) => c.delayMs + c.ms).reduce((a, b) => a > b ? a : b),
  );

  double operator [](RinChannel c) => _v[c.index];

  /// Boca [m]: `k` = 0 opacidad, 1 escala, 2 desplazamiento X.
  double mouth(RinMouth m, int k) => _v[_C.smileO.index + m.index * 3 + k];

  /// Billete [i] (0 abajo): opacidad y desplazamiento X.
  double billOpacity(int i) => _v[_C.bill0O.index + i];
  double billX(int i) => _v[_C.bill0X.index + i];

  /// Postura final para una emoción, el gesto en curso y la pila.
  factory RinPose.target({
    RinEmotion emotion = RinEmotion.tranquilo,
    RinGesture? gesture,
    int level = 0,
    int tidy = 0,
  }) {
    final v = [for (final c in RinChannel.values) c.rest];
    void set(Map<RinChannel, double> values) => values.forEach((c, x) => v[c.index] = x);
    void mouth(RinMouth m, {double scale = 1, double x = 0}) {
      final i = _C.smileO.index + m.index * 3;
      v[i] = 1;
      v[i + 1] = scale;
      v[i + 2] = x;
    }

    // Ojo abierto que se esconde y uno de los otros dos que aparece.
    void swapEyes(RinChannel opacity, RinChannel scale) =>
        set({_C.openO: 0, _C.openS: 0.2, opacity: 1, scale: 1});
    // Cejas inclinadas de conmovido y empático.
    const softBrows = {
      _C.browLO: 0.85, _C.browLY: -2.0, _C.browLR: -9.0, //
      _C.browRO: 0.85, _C.browRY: -2.0, _C.browRR: 9.0,
    };

    switch (emotion) {
      case RinEmotion.tranquilo:
        mouth(RinMouth.smile);
      case RinEmotion.feliz:
        set({_C.armL: 148, _C.armR: -148, _C.ant: -6, _C.blush: 1});
        mouth(RinMouth.grin);
      case RinEmotion.emocionado:
        set({_C.armL: 164, _C.armR: -164, _C.ant: -10, _C.blush: 1});
        swapEyes(_C.joyO, _C.joyS);
        mouth(RinMouth.grin, scale: 1.18);
      case RinEmotion.sorprendido:
        set({_C.armL: 82, _C.armR: -82, _C.ant: -12, _C.eye: 1.16});
        set({_C.browLO: 1, _C.browLY: -5, _C.browRO: 1, _C.browRY: -5});
        mouth(RinMouth.o);
      case RinEmotion.pensativo:
        set({_C.tilt: -5, _C.armL: 8, _C.armR: 128, _C.ant: 12, _C.eye: 0.96, _C.lookX: 2.6, _C.lookY: -3});
        set({_C.browLO: 1, _C.browLY: 1, _C.browLR: 6, _C.browRO: 1, _C.browRY: -5, _C.browRR: -10});
        mouth(RinMouth.flat);
      case RinEmotion.preocupado:
        set({_C.armL: -48, _C.armR: 48, _C.ant: 8, _C.eye: 1.04, _C.lookY: 1.5, _C.blush: 0.6});
        set({_C.browLO: 1, _C.browLY: -1, _C.browLR: -14, _C.browRO: 1, _C.browRY: -1, _C.browRR: 14});
        mouth(RinMouth.soft);
      case RinEmotion.conmovido:
        set({_C.tilt: 3, _C.armL: -142, _C.armR: 142, _C.ant: 5, _C.eye: 1.1, _C.blush: 0.9, _C.wetO: 0.9});
        set(softBrows);
        mouth(RinMouth.wobble);
      case RinEmotion.dormido:
        set({_C.tilt: 4, _C.armL: 6, _C.armR: -6, _C.ant: 36, _C.zzzO: 1});
        swapEyes(_C.shutO, _C.shutS);
        mouth(RinMouth.o, scale: 0.55);
      case RinEmotion.curioso:
        set({_C.tilt: 5, _C.armR: -62, _C.ant: -16, _C.eye: 1.08, _C.lookX: 2.8, _C.lookY: -1});
        set({_C.browRO: 1, _C.browRY: -5, _C.browRR: -6});
        mouth(RinMouth.smile, scale: 0.7, x: 2);
      case RinEmotion.empatico:
        set({_C.tilt: -3, _C.armL: 62, _C.armR: -62, _C.ant: 3, _C.eye: 1.05, _C.blush: 0.9});
        set(softBrows);
        mouth(RinMouth.smile);
    }

    if (gesture == RinGesture.saludar) set({_C.armR: -150});

    // La pila: Rin nunca se estira, sube porque gana billetes.
    final bills = level.clamp(0, rinCrooked.length);
    v[_C.rise.index] = rinGround - bills * rinBillHeight;
    for (var i = 0; i < bills; i++) {
      v[_C.bill0O.index + i] = 1;
      v[_C.bill0X.index + i] = i < tidy ? 0 : rinCrooked[i];
    }
    return RinPose._(v);
  }

  /// Valor de cada canal a [ms] milisegundos de una transición de [from] a [to].
  static RinPose lerp(RinPose from, RinPose to, double ms) => RinPose._([
    for (final c in RinChannel.values)
      from[c] + (to[c] - from[c]) * c.curve.transform(((ms - c.delayMs) / c.ms).clamp(0.0, 1.0)),
  ]);
}

/// Valor de una animación CSS por fotogramas clave en el avance [p] (0 a 1). [frames] son pares
/// (porcentaje, valor) ordenados que incluyen 0 y 1; [curve] se aplica en cada tramo, como
/// `animation-timing-function`.
double rinKeyframes(double p, List<(double, double)> frames, Curve curve) {
  for (var i = 1; i < frames.length; i++) {
    final (t1, v1) = frames[i];
    if (p <= t1) {
      final (t0, v0) = frames[i - 1];
      final local = t1 == t0 ? 1.0 : ((p - t0) / (t1 - t0)).clamp(0.0, 1.0);
      return v0 + (v1 - v0) * curve.transform(local);
    }
  }
  return frames.last.$2;
}

// Fotogramas clave de los gestos en `rin.css`: (porcentaje, valor) con el 0 % y el 100 % implícitos
// (el reposo). Un `transform` se separa en traslación Y y escalas X/Y: sin giros, interpolar cada
// componente da lo mismo que la interpolación de matrices del navegador.
typedef _Frames = List<(double, double)>;

// rin-shake: 25 % rotate(-14°), 75 % rotate(14°).
const _Frames _shake = [(0, 0), (0.25, -14), (0.75, 14), (1, 0)];
// rin-nod: 25 % scale(1.03, 0.94), 50 % none, 75 % scale(1.02, 0.96).
const _Frames _nodSX = [(0, 1), (0.25, 1.03), (0.5, 1), (0.75, 1.02), (1, 1)];
const _Frames _nodSY = [(0, 1), (0.25, 0.94), (0.5, 1), (0.75, 0.96), (1, 1)];
// rin-tap: 30 % scale(1.1, 0.88), 60 % translateY(-6px) scale(0.95, 1.08).
const _Frames _tapY = [(0, 0), (0.3, 0), (0.6, -6), (1, 0)];
const _Frames _tapSX = [(0, 1), (0.3, 1.1), (0.6, 0.95), (1, 1)];
const _Frames _tapSY = [(0, 1), (0.3, 0.88), (0.6, 1.08), (1, 1)];
// rin-cheer: 8 % scale(1.08, 0.88), 26 % translateY(-30px) scale(0.95, 1.07), 42 % scale(1.1, 0.88),
// 56 % translateY(-14px) scale(0.97, 1.04), 70 % scale(1.06, 0.93), 84 % scale(0.99, 1.02).
const _Frames _cheerY = [(0, 0), (0.08, 0), (0.26, -30), (0.42, 0), (0.56, -14), (0.7, 0), (0.84, 0), (1, 0)];
const _Frames _cheerSX = [
  (0, 1),
  (0.08, 1.08),
  (0.26, 0.95),
  (0.42, 1.1),
  (0.56, 0.97),
  (0.7, 1.06),
  (0.84, 0.99),
  (1, 1),
];
const _Frames _cheerSY = [
  (0, 1),
  (0.08, 0.88),
  (0.26, 1.07),
  (0.42, 0.88),
  (0.56, 1.04),
  (0.7, 0.93),
  (0.84, 1.02),
  (1, 1),
];
// rin-toss: 10 % none, 24 % translateY(-22px) scaleX(-1), 38 % translateY(-36px) scaleX(1),
// 52 % translateY(-30px) scaleX(-1), 66 % translateY(-10px) scaleX(1), 76 % scale(1.18, 0.86),
// 88 % scale(0.96, 1.05). La moneda gira porque scaleX pasa de 1 a -1.
const _Frames _tossY = [
  (0, 0),
  (0.1, 0),
  (0.24, -22),
  (0.38, -36),
  (0.52, -30),
  (0.66, -10),
  (0.76, 0),
  (0.88, 0),
  (1, 0),
];
const _Frames _tossSX = [
  (0, 1),
  (0.1, 1),
  (0.24, -1),
  (0.38, 1),
  (0.52, -1),
  (0.66, 1),
  (0.76, 1.18),
  (0.88, 0.96),
  (1, 1),
];
const _Frames _tossSY = [
  (0, 1),
  (0.1, 1),
  (0.24, 1),
  (0.38, 1),
  (0.52, 1),
  (0.66, 1),
  (0.76, 0.86),
  (0.88, 1.05),
  (1, 1),
];
// rin-twinkle: 0 % y 100 % opacity 0 scale(0.3), 50 % opacity 1 scale(1).
const _Frames _twinkleO = [(0, 0), (0.5, 1), (1, 0)];
const _Frames _twinkleS = [(0, 0.3), (0.5, 1), (1, 0.3)];

/// Todo lo que el pintor necesita para un fotograma: la postura, el gesto en curso y la vida en
/// reposo. Sin gesto, todos los valores del gesto quedan en reposo (identidad).
class RinFrame {
  const RinFrame({
    required this.pose,
    this.breathX = 1,
    this.breathY = 1,
    this.sway = 0,
    this.blink = 1,
    this.glanceX = 0,
    this.glanceY = 0,
    this.zzzOpacity = 1,
    this.zzzX = 0,
    this.zzzY = 0,
    this.zzzScale = 1,
    this.waveL = 0,
    this.waveR = 0,
    this.actY = 0,
    this.actSX = 1,
    this.actSY = 1,
    this.coinY = 0,
    this.coinSX = 1,
    this.coinSY = 1,
    this.sparks = const [],
  });

  /// Fotograma en el segundo [t] del reloj, con [gesture] en curso desde hace [at] segundos.
  factory RinFrame.alive(RinPose pose, double t, RinEmotion emotion, {RinGesture? gesture, double at = 0}) {
    double phase(double period) => (t / period) % 1;

    // rin-breath: 3.8 s (5.6 s dormido), 50 % scale(0.994, 1.016).
    final breath = phase(emotion == RinEmotion.dormido ? 5.6 : 3.8);
    // rin-sway: 4.6 s, de -3° a 3°.
    final sway = phase(4.6);
    // rin-blink: 6.4 s con la curva por defecto (ease); un parpadeo y luego uno doble.
    final blink = phase(6.4);
    // rin-glance: 12 s, solo tranquilo y feliz.
    final glances = emotion == RinEmotion.tranquilo || emotion == RinEmotion.feliz;
    final glance = phase(12);
    // rin-zzz: 3.2 s, solo dormido.
    final zzz = phase(3.2);
    const io = Curves.easeInOut;

    // Una animación CSS de [length] s con retardo [delay] y [times] vueltas, a los [at] s del gesto.
    // Sin `animation-fill-mode`: fuera de su tiempo vale el reposo (el 0 % implícito).
    double play(double length, _Frames frames, Curve curve, {double delay = 0, int times = 1}) {
      final local = at - delay;
      if (local < 0 || local >= length * times) return frames.first.$2;
      return rinKeyframes((local / length) % 1, frames, curve);
    }

    var waveL = 0.0, waveR = 0.0, actY = 0.0, actSX = 1.0, actSY = 1.0;
    var coinY = 0.0, coinSX = 1.0, coinSY = 1.0;
    var sparks = const <(double, double)>[];
    switch (gesture) {
      case RinGesture.saludar:
        waveR = play(0.42, _shake, io, delay: 0.3, times: 3);
      case RinGesture.asentir:
        actSX = play(0.8, _nodSX, io);
        actSY = play(0.8, _nodSY, io);
      case RinGesture.toque:
        actY = play(0.6, _tapY, rinOut);
        actSX = play(0.6, _tapSX, rinOut);
        actSY = play(0.6, _tapSY, rinOut);
      case RinGesture.celebrar:
        actY = play(1.5, _cheerY, rinOut);
        actSX = play(1.5, _cheerSX, rinOut);
        actSY = play(1.5, _cheerSY, rinOut);
        coinY = play(1.5, _tossY, io);
        coinSX = play(1.5, _tossSX, io);
        coinSY = play(1.5, _tossSY, io);
        waveL = waveR = play(0.5, _shake, io, delay: 0.2, times: 2);
        sparks = [
          for (var n = 0; n < 3; n++)
            (
              play(0.9, _twinkleO, io, delay: 0.25 + n * 0.13, times: 2),
              play(0.9, _twinkleS, io, delay: 0.25 + n * 0.13, times: 2),
            ),
        ];
      default:
        break;
    }

    return RinFrame(
      pose: pose,
      breathX: rinKeyframes(breath, const [(0, 1), (0.5, 0.994), (1, 1)], io),
      breathY: rinKeyframes(breath, const [(0, 1), (0.5, 1.016), (1, 1)], io),
      sway: rinKeyframes(sway, const [(0, -3), (0.5, 3), (1, -3)], io),
      blink: rinKeyframes(blink, const [
        (0, 1), (0.44, 1), (0.46, 0.08), (0.48, 1), (0.86, 1), //
        (0.88, 0.08), (0.90, 1), (0.92, 0.08), (0.94, 1), (1, 1),
      ], Curves.ease),
      glanceX: glances
          ? rinKeyframes(glance, const [
              (0, 0),
              (0.58, 0),
              (0.62, 3),
              (0.69, 3),
              (0.72, 0),
              (0.76, -3),
              (0.84, -3),
              (0.88, 0),
              (1, 0), //
            ], io)
          : 0,
      glanceY: glances
          ? rinKeyframes(glance, const [
              (0, 0), (0.58, 0), (0.62, 0), (0.69, 0), (0.72, 0), (0.76, 1), (0.84, 1), (0.88, 0), (1, 0), //
            ], io)
          : 0,
      zzzOpacity: rinKeyframes(zzz, const [(0, 0), (0.4, 1), (1, 0)], io),
      zzzX: rinKeyframes(zzz, const [(0, -4), (1, 6)], io),
      zzzY: rinKeyframes(zzz, const [(0, 6), (1, -8)], io),
      zzzScale: rinKeyframes(zzz, const [(0, 0.8), (1, 1.05)], io),
      waveL: waveL,
      waveR: waveR,
      actY: actY,
      actSX: actSX,
      actSY: actSY,
      coinY: coinY,
      coinSX: coinSX,
      coinSY: coinSY,
      sparks: sparks,
    );
  }

  final RinPose pose;
  final double breathX, breathY, sway, blink, glanceX, glanceY;
  final double zzzOpacity, zzzX, zzzY, zzzScale;

  /// Sacudida de cada brazo en grados (`.rin-arm-act`): saludar y celebrar.
  final double waveL, waveR;

  /// Cuerpo entero (`.rin-act`) desde los pies: traslación Y y escalas X/Y.
  final double actY, actSX, actSY;

  /// Moneda de la antena (`.rin-coin`) desde su centro: traslación Y y escalas X/Y.
  final double coinY, coinSX, coinSY;

  /// Chispas ámbar (`.rin-spark`), en orden: (opacidad, escala). Vacío si no hay.
  final List<(double, double)> sparks;
}
