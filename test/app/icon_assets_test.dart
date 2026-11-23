import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/design/widgets/rinde_icon.dart';

void main() {
  // Un ícono sin archivo no falla al compilar: se vería un hueco en la pantalla.
  test('cada ícono de RindeIcons tiene su SVG de lucide en assets/icons', () {
    for (final icon in RindeIcons.values) {
      final file = File(icon.asset);
      expect(file.existsSync(), isTrue, reason: icon.asset);
      final svg = file.readAsStringSync();
      expect(
        svg,
        startsWith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '),
        reason: icon.asset,
      );
      expect(svg, contains('stroke="currentColor"'), reason: icon.asset);
    }
  });

  test('no sobran SVG sin entrada en RindeIcons', () {
    final files = Directory('assets/icons')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.svg'))
        .toSet();
    expect(files, {for (final icon in RindeIcons.values) '${icon.file}.svg'});
  });
}
