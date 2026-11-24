import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show clockProvider;
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface, HomeTap;
import '../../movements/presentation/list/movement_dates.dart' show shortDate;
import '../../shell/presentation/pushed_frame.dart';
import '../application/notifications_writer.dart';
import '../data/notifications_repository.dart';

/// timeAgo de la web: «ahora», «hace 5 min», «hace 3 h», «ayer», «hace 4 días» o «12 oct».
String timeAgo(DateTime when, DateTime now, Region region, Tr t) {
  final minutes = now.difference(when).inMinutes;
  // TEXTO NUEVO: la web deja «ahora» y «ayer» sin traducir.
  if (minutes < 1) return t('ahora');
  if (minutes < 60) return t('hace {minutes} min', {'minutes': minutes});
  final hours = minutes ~/ 60;
  if (hours < 24) return t('hace {hours} h', {'hours': hours});
  final days = hours ~/ 24;
  if (days == 1) return t('ayer');
  if (days < 7) return t('hace {days} días', {'days': days});
  return shortDate(when.toLocal(), region, withYear: false);
}

/// `/app/notificaciones` (Notifications.jsx), a la que lleva la campana del Inicio. Al abrirla, los
/// avisos quedan leídos; siguen en «Nuevas» durante esta visita para ver cuáles eran. La app no tiene
/// push: es la bandeja que guarda el servidor.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Los que llegaron sin leer: siguen en «Nuevas» toda la visita, aunque ya queden leídos.
  final _fresh = <String>{};

  /// Los sin leer que ya se mandaron a marcar (al recargar, solo los nuevos vuelven a enviar).
  final _sent = <String>{};

  void _markRead(List<AppNotification> items) {
    var pending = false;
    for (final n in items) {
      if (n.read) continue;
      _fresh.add(n.id);
      if (_sent.add(n.id)) pending = true;
    }
    if (!pending) return;
    final account = ref.read(accountProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Si falla (sin conexión, demo), la campana sigue con su número: se marcan la próxima vez.
      ref.read(notificationsWriterProvider).markAllRead(account).catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final async = ref.watch(notificationsListProvider(account));
    final items = async.value;
    if (items != null) _markRead(items);

    final List<Widget> children;
    if (items == null && async.hasError && !async.isLoading) {
      children = [
        RindeBanner(
          message: t('No pudimos cargar tus avisos. Revisa tu conexión.'),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(notificationsListProvider(account)),
          ),
        ),
      ];
    } else if (items == null) {
      children = [Text(t('Cargando…'), style: RindeType.body.copyWith(color: p.inkMuted))];
    } else if (items.isEmpty) {
      children = [
        HomeSurface(
          padding: const EdgeInsets.all(RindeSpace.s6),
          child: Column(
            children: [
              RindeIcon(RindeIcons.bell, size: 24, color: p.inkMuted),
              const SizedBox(height: 6),
              Text(
                t('No tienes notificaciones'),
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.copyWith(color: p.ink),
              ),
              const SizedBox(height: 6),
              Text(
                t('Aquí verás tus pagos, tarjetas y presupuestos.'),
                textAlign: TextAlign.center,
                style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ];
    } else {
      children = [
        _Group(title: t('Nuevas'), fresh: true, items: [...items.where((n) => _fresh.contains(n.id))]),
        _Group(title: t('Anteriores'), items: [...items.where((n) => !_fresh.contains(n.id))]),
      ];
    }

    return PushedFrame(
      title: t('Notificaciones'),
      child: RefreshIndicator(
        color: p.brandSolid,
        backgroundColor: p.surface,
        onRefresh: () async {
          ref.invalidate(notificationsListProvider(account));
          await ref.read(notificationsListProvider(account).future).then((_) {}, onError: (_) {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
          children: children,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items, this.fresh = false});

  final String title;
  final List<AppNotification> items;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: RindeSpace.s5),
      child: Semantics(
        container: true,
        label: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: RindeType.label.copyWith(color: p.ink.withValues(alpha: 0.7))),
            ),
            const SizedBox(height: RindeSpace.s2),
            ClipRRect(
              borderRadius: RindeRadius.brX2,
              child: HomeSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                      _Item(item: item, fresh: fresh),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un aviso; si lleva a una pantalla que la app tiene, toda la fila la abre.
class _Item extends ConsumerWidget {
  const _Item({required this.item, required this.fresh});

  final AppNotification item;
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final when = timeAgo(item.createdAt, ref.watch(clockProvider)(), ref.watch(appRegionProvider), t);
    final content = ColoredBox(
      color: fresh ? p.brandSoft : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: RindeSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: RindeType.body.w(fresh ? FontWeight.w600 : FontWeight.w500).copyWith(color: p.ink),
                  ),
                ),
                const SizedBox(width: RindeSpace.s3),
                Text(when, style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.7))),
              ],
            ),
            const SizedBox(height: 2),
            Text(item.body, style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
    final url = item.url;
    final uri = url == null || !url.startsWith('/app/') ? null : Uri.tryParse(url);
    // Solo rutas de la app que existen aquí; una que la app no tiene (p. ej. una vaca) no se abre.
    if (uri == null || GoRouter.of(context).configuration.findMatch(uri).isError) {
      return MergeSemantics(child: content);
    }
    return HomeTap(onTap: () => context.push(url!), radius: BorderRadius.zero, scale: 1, child: content);
  }
}
