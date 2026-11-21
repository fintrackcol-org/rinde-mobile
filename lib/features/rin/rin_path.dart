import 'dart:ui';

final _token = RegExp(r'[MLHVCQAZmlhvcqaz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
final _command = RegExp(r'^[A-Za-z]$');

/// Convierte el atributo `d` de un `<path>` SVG en un [Path] de Flutter.
///
/// Parser mínimo con los comandos que usa el dibujo de Rin y algunos más: M, L, H, V, C, Q, A y Z,
/// absolutos y relativos. Así los trazos se copian literales de `Rin.jsx` sin rehacerlos a mano.
/// shortcut: sin S ni T (curvas encadenadas) ni banderas de arco pegadas ("a5 5 0 015 5"); si un
/// dibujo nuevo los trae, agregarlos aquí.
Path parseSvgPath(String d) {
  final tokens = [for (final m in _token.allMatches(d)) m[0]!];
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;

  double n() {
    if (i >= tokens.length || _command.hasMatch(tokens[i])) {
      throw FormatException('Faltan números para "$cmd" en el trazo', d);
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    if (_command.hasMatch(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd.isEmpty) {
      throw FormatException('El trazo debe empezar con un comando', d);
    }
    final relative = cmd == cmd.toLowerCase();
    final ox = relative ? x : 0.0, oy = relative ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Los pares que siguen a un M son líneas (regla de SVG).
        cmd = relative ? 'l' : 'L';
      case 'L':
        x = ox + n();
        y = oy + n();
        path.lineTo(x, y);
      case 'H':
        x = ox + n();
        path.lineTo(x, y);
      case 'V':
        y = oy + n();
        path.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'A':
        final rx = n(), ry = n(), rotation = n(), largeArc = n() != 0, sweep = n() != 0;
        x = ox + n();
        y = oy + n();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        // Z no lleva números: si aparecen, el trazo está dañado.
        cmd = '';
      default:
        throw FormatException('Comando "$cmd" no soportado', d);
    }
  }
  return path;
}
