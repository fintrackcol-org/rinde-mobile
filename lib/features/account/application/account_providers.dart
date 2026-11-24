import '../../auth/application/session_controller.dart';
import '../data/account_models.dart';
import '../data/account_repository.dart';

/// GET /users/me/reminder-settings de quien está dentro (una copia por cuenta, solo en memoria).
final reminderSettingsProvider = perAccount<ReminderSettings>(
  (ref) => ref.watch(accountRepositoryProvider).reminderSettings(),
);

/// GET /whatsapp/link de quien está dentro.
final whatsappLinkProvider = perAccount<WhatsappLink>(
  (ref) => ref.watch(accountRepositoryProvider).whatsapp(),
);
