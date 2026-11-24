import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show homeUnreadProvider;
import '../data/notifications_repository.dart';

/// GET /notifications de una cuenta. Se pide al abrir la bandeja y se suelta al salir.
final notificationsListProvider = FutureProvider.autoDispose.family<List<AppNotification>, Session?>((
  ref,
  account,
) {
  if (ref.watch(accountProvider) != account) return Completer<List<AppNotification>>().future;
  return ref.watch(notificationsRepositoryProvider).list();
});

/// «Marcar todos como leídos» al abrir la bandeja, con el patrón de los demás writers: un solo envío a
/// la vez por cuenta y la misma cuenta antes de enviar. No espera la bienvenida: no toca la plata.
/// Al terminar, la campana del Inicio vuelve a pedir cuántos quedan sin leer.
class NotificationsWriter {
  NotificationsWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<void>>{};

  /// [account]: la cuenta cuyos avisos se vieron; si ya entró otra, no se marcan los de esa.
  Future<void> markAllRead(Session? account) {
    final key = '${account?.user.id}';
    // Sin devolver el Future quitado: whenComplete lo esperaría y nunca terminaría.
    return _running[key] ??=
        () async {
          if (_ref.read(accountProvider)?.user.id != account?.user.id) {
            throw StateError('Cambió la cuenta antes de enviar');
          }
          await _ref.read(notificationsRepositoryProvider).markAllRead();
          _ref.container.invalidate(homeUnreadProvider);
        }().whenComplete(() {
          _running.remove(key);
        });
  }
}

final notificationsWriterProvider = Provider<NotificationsWriter>(NotificationsWriter.new);
