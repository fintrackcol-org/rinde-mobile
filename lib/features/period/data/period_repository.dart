import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../../home/data/demo_home_repository.dart';
import '../../movements/presentation/list/movement_dates.dart';
import 'period_models.dart';

/// Resumen de un periodo para Ingresos y Gastos (summaryService.js de la web). Las listas salen de
/// `MovementsRepository.list`.
/// - [ApiPeriodRepository]: la real.
/// - [DemoPeriodRepository]: MODO DEMOSTRACIÓN, el resumen sintético del Inicio demo, sin red.
abstract interface class PeriodRepository {
  bool get isDemo;

  /// GET /transactions/summary?period=week|month|year&date=AAAA-MM-DD.
  Future<PeriodSummary> summary(MovementPeriod period, String date);
}

class ApiPeriodRepository implements PeriodRepository {
  ApiPeriodRepository(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<PeriodSummary> summary(MovementPeriod period, String date) async => PeriodSummary.fromJson(
    await _api.get('/transactions/summary', query: {'period': period.name, 'date': date}),
  );
}

class DemoPeriodRepository implements PeriodRepository {
  DemoPeriodRepository(this.home);
  final DemoHomeRepository home;

  @override
  bool get isDemo => true;

  @override
  Future<PeriodSummary> summary(MovementPeriod period, String date) async {
    final range = periodRange(period, parseIsoDay(date));
    return PeriodSummary.fromJson(await home.demoPeriodSummary(period.name, range.from, range.to));
  }
}

/// Una sesión demo nunca usa la API.
final periodRepositoryProvider = Provider<PeriodRepository>((ref) {
  final session = ref.watch(accountProvider);
  if (session != null && session.demo) {
    return DemoPeriodRepository(ref.watch(demoHomeRepositoryProvider(session.user.id)));
  }
  return ApiPeriodRepository(ref.watch(apiClientProvider));
});
