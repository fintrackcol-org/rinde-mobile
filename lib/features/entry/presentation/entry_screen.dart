import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_repository.dart';

/// Entrada a la app con sesión. Primero trae el perfil (GET /users/me), porque el login no dice
/// si faltan aceptar términos. Términos pendientes → aceptarlos; si no → inicio.
/// Si el perfil no llega (sin red, servidor dormido), no se bloquea: como en la web, se entra con los
/// datos de la sesión y los términos se vuelven a revisar en la próxima apertura.
class EntryScreen extends ConsumerWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final user = ref.watch(sessionControllerProvider).value?.session?.user;
    return Scaffold(
      body: SafeArea(
        child: switch (profile) {
          AsyncData(:final value) when !value.termsAccepted => const _TermsGate(),
          AsyncData(:final value) => _HomePlaceholder(name: value.name, email: value.email),
          AsyncError() when user != null => _HomePlaceholder(name: user.name, email: user.email),
          _ => Center(
            child: Semantics(label: 'Cargando', child: const RindeSpinner(size: 28)),
          ),
        },
      ),
    );
  }
}

/// TermsGate.jsx: bloquea hasta aceptar la versión vigente de los términos.
class _TermsGate extends ConsumerStatefulWidget {
  const _TermsGate();

  @override
  ConsumerState<_TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends ConsumerState<_TermsGate> {
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).acceptTerms();
      ref.invalidate(profileProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.messageFor(fallback: ApiMessages.generic));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.read(appConfigProvider);
    return RindeStateView(
      icon: RindeIcons.shieldAlert,
      title: 'Publicamos nuestros términos y la política de privacidad',
      message:
          'Explican qué hace Rinde con tus datos, con qué servicios los procesamos y cómo pedir que los '
          'veamos, corrijamos o borremos. Para seguir usando la app necesitamos que los aceptes.',
      actions: [
        RindeTextLink(
          label: 'Leer los términos de uso',
          onPressed: () => launchUrl(config.webPage('/terminos'), mode: LaunchMode.externalApplication),
        ),
        RindeTextLink(
          label: 'Leer la política de privacidad',
          onPressed: () => launchUrl(config.webPage('/privacidad'), mode: LaunchMode.externalApplication),
        ),
        if (_error != null) RindeBanner(message: _error!),
        RindeButton(label: 'Acepto los términos y la política', loading: _saving, onPressed: _accept),
        RindeButton(
          label: 'Cerrar sesión',
          variant: RindeButtonVariant.ghost,
          onPressed: _saving ? null : () => ref.read(sessionControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

/// PROVISIONAL: marca el final del primer flujo (ya dentro, con sesión real) mientras se construye
/// el Inicio. No es una pantalla del producto: el siguiente módulo la reemplaza.
class _HomePlaceholder extends ConsumerWidget {
  const _HomePlaceholder({required this.name, required this.email});
  final String? name;
  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RindeStateView(
      leading: const RindeIconTile(RindeIcons.check, tone: RindeBrand.success),
      title: name == null ? 'Hola' : 'Hola, $name',
      message: 'Entraste a Rinde como $email. El Inicio de la app móvil es el próximo módulo.',
      actions: [
        RindeButton(
          label: 'Cerrar sesión',
          variant: RindeButtonVariant.outline,
          leading: const RindeIcon(RindeIcons.logOut, size: 16),
          onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}
