import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../data/insights_repository.dart';

// Consejos pide lo suyo al abrirse, como la web al montar: al salir se suelta (autoDispose). La copia
// de quien salió no pide nada (como perAccount).

/// GET /insights de una cuenta.
final insightsProvider = FutureProvider.autoDispose.family<InsightsResult, Session?>((ref, account) {
  if (ref.watch(accountProvider) != account) return Completer<InsightsResult>().future;
  return ref.watch(insightsRepositoryProvider).insights();
});

/// GET /transactions/reflection de una cuenta.
final reflectionProvider = FutureProvider.autoDispose.family<WeekReflection, Session?>((ref, account) {
  if (ref.watch(accountProvider) != account) return Completer<WeekReflection>().future;
  return ref.watch(insightsRepositoryProvider).reflection();
});
