import 'package:flutter/widgets.dart';

/// Elementos reales del Inicio que el tutorial de primera vez resalta (`data-tour` en Rinde Web).
enum TourTarget {
  /// La tarjeta grande (saldo o libre para gastar).
  saldo,

  /// El botón «Anotar» de la barra de pestañas.
  anotar,

  /// «Este mes»: ingresos y gastos.
  totales,

  /// Pestaña «Planear».
  planear,

  /// Pestaña «Yo».
  cuenta,
}

/// Llaves de esos elementos. Las crea el Inicio y solo él las reparte (a sus tarjetas y a su barra
/// de pestañas): así nunca hay dos widgets vivos con la misma llave.
class TourAnchors {
  final _keys = {
    for (final target in TourTarget.values) target: GlobalKey(debugLabel: 'tour-${target.name}'),
  };

  GlobalKey key(TourTarget target) => _keys[target]!;

  /// Dónde está en pantalla, o null si no se dibujó (el paso se explica igual, en el centro).
  Rect? rectOf(TourTarget target) {
    final box = key(target).currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
