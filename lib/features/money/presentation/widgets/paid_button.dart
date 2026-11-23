import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../home/application/home_providers.dart';
import '../../../home/domain/home_dates.dart';
import '../../../movements/application/movement_saver.dart';
import '../../application/money_providers.dart';
import '../../application/money_writer.dart';
import '../../domain/commitment_rules.dart';

/// Texto de un error de Mi plata, con los mensajes propios de la app.
String moneyErrorText(Object e, Tr t) => t(
  e is ApiException
      ? e.messageFor(
          byCode: const {
            ApiCodes.unauthorized: ApiMessages.sessionExpired,
            ApiCodes.tokenExpired: ApiMessages.sessionExpired,
          },
          fallback: ApiMessages.generic,
        )
      : ApiMessages.generic,
);

/// «Ya lo pagué» de un pago (MoneyPayments.jsx y PendingPayments.jsx). Mientras se guarda uno (y hasta
/// que llega lo nuevo), todos esperan (como la web). Si en la cola ya hay un gasto igual de este mes, en
/// vez del botón dice «Pendiente de sincronizar»: sin conexión no se anota dos veces (la web sí lo permite).
class PaidButton extends ConsumerWidget {
  const PaidButton({
    super.key,
    required this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.onError,
  });

  final String id;
  final String name;
  final num amount;

  /// AAAA-MM-DD de la ocurrencia: con el id forma la clave del pago.
  final String date;

  /// El error para mostrar; null al empezar otro intento.
  final ValueChanged<String?> onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final key = dismissKey(id, date);
    final paying = ref.watch(payingPaymentProvider);
    final queue = ref.watch(pendingMovementsProvider).value;
    final today = isoDay(ref.watch(todayProvider));
    if (queue != null && queuedPayment(queue, name: name, amount: amount, date: today)) {
      return Text(t('Pendiente de sincronizar'), style: RindeType.meta.copyWith(color: p.inkMuted));
    }

    Future<void> pay() async {
      // Lo que se usa después de esperar se toma antes: la fila puede desaparecer al guardarse.
      final busy = ref.read(payingPaymentProvider.notifier);
      final writer = ref.read(moneyWriterProvider);
      if (ref.read(payingPaymentProvider) != null) return;
      busy.set(key);
      onError(null);
      try {
        await writer.markPaid(key: key, name: name, amount: amount);
      } on Object catch (e) {
        onError(moneyErrorText(e, t));
      } finally {
        busy.set(null);
      }
    }

    final enabled = paying == null;
    // El lector oye a qué pago corresponde (el nombre va oculto en la web: sr-only).
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: '${t('Ya lo pagué')} $name',
      onTap: enabled ? pay : null,
      excludeSemantics: true,
      child: RindeButton(
        label: t('Ya lo pagué'),
        variant: RindeButtonVariant.soft,
        // 44 de alto, como el h-11 del aviso de la web.
        size: RindeButtonSize.md,
        expand: false,
        loading: paying == key,
        onPressed: enabled ? pay : null,
      ),
    );
  }
}
