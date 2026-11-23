import 'package:flutter_test/flutter_test.dart';
import 'package:rinde_mobile/core/i18n/tr.dart';
import 'package:rinde_mobile/core/region/region.dart';
import 'package:rinde_mobile/features/movements/presentation/list/movement_dates.dart';

const _es = Region(country: 'CO', currency: 'COP', language: 'es');
const _en = Region(country: 'US', currency: 'USD', language: 'en');
const _t = Tr('es', {});

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final now = DateTime(2026, 11, 22, 23, 30); // domingo

  test('rangos de lib/period.js: semana de lunes a domingo, mes y año', () {
    final week = periodRange(MovementPeriod.week, now);
    expect((_iso(week.from), _iso(week.to)), ('2026-11-16', '2026-11-22'));
    final month = periodRange(MovementPeriod.month, DateTime(2028, 2, 10));
    expect((_iso(month.from), _iso(month.to)), ('2028-02-01', '2028-02-29'));
    final year = periodRange(MovementPeriod.year, now);
    expect((_iso(year.from), _iso(year.to)), ('2026-01-01', '2026-12-31'));
  });

  test('las flechas cruzan de mes y de año sin saltarse días', () {
    expect(_iso(shiftPeriod(MovementPeriod.month, DateTime(2026, 1, 31), -1)), '2025-12-01');
    expect(_iso(shiftPeriod(MovementPeriod.week, DateTime(2026, 1, 1), -1)), '2025-12-22');
    expect(isCurrentPeriod(MovementPeriod.month, DateTime(2026, 11, 1), now), isTrue);
    expect(isCurrentPeriod(MovementPeriod.month, DateTime(2026, 10, 31), now), isFalse);
  });

  test('nombres del periodo como la web', () {
    expect(periodLabel(MovementPeriod.month, now, now, _es, _t), 'noviembre');
    expect(periodLabel(MovementPeriod.month, DateTime(2025, 9), now, _es, _t), 'septiembre de 2025');
    expect(periodLabel(MovementPeriod.month, DateTime(2025, 9), now, _en, _t), 'September 2025');
    expect(periodLabel(MovementPeriod.year, now, now, _es, _t), '2026');
    expect(periodLabel(MovementPeriod.week, now, now, _es, _t), 'esta semana');
    expect(periodLabel(MovementPeriod.week, DateTime(2026, 11, 4), now, _es, _t), 'semana del 2 al 8 nov');
    expect(
      periodLabel(MovementPeriod.week, DateTime(2026, 1, 1), now, _es, _t),
      'semana del 29 dic al 4 ene',
    );
  });

  test('día relativo: Hoy, Ayer y la fecha con año solo si no es el actual', () {
    expect(relativeDay('2026-11-22', now, _es, _t), 'Hoy');
    expect(relativeDay('2026-11-21', now, _es, _t), 'Ayer');
    expect(relativeDay('2026-10-12', now, _es, _t), '12 oct');
    expect(relativeDay('2025-10-12', now, _es, _t), '12 oct 2025');
    expect(relativeDay('2026-10-12', now, _en, _t), 'Oct 12');
    expect(longDay('2026-11-22', now, _es, _t), 'Hoy, 22 nov 2026');
    expect(longDay('2026-11-04', now, _en, _t), 'Nov 4, 2026');
  });
}
