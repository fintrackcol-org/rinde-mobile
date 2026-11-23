import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/presentation/home_screen.dart';
import '../../onboarding/data/onboarding_repository.dart';

/// Entrada a la app con sesión. Primero trae el perfil (GET /users/me), porque el login no dice
/// si faltan aceptar términos. Términos pendientes → aceptarlos; si no → bienvenida o Inicio.
/// Si el perfil no llega (sin red, servidor dormido), no se bloquea: como en la web, se entra con los
/// datos de la sesión y los términos se vuelven a revisar en la próxima apertura.
class EntryScreen extends ConsumerWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(ref.watch(accountProvider)));
    // Lo último que se supo manda: ni una recarga ni su fallo levantan el bloqueo de los términos.
    if (profile.value?.termsAccepted == false) {
      return const Scaffold(body: SafeArea(child: _TermsGate()));
    }
    return switch (profile) {
      // Solo espera la primera vez: un fallo deja pasar, y una recarga (o su reintento) no tapa el Inicio.
      _ when profile.isLoading && !profile.hasValue && !profile.hasError => const _Loading(),
      _ => const _WelcomeGate(),
    };
  }
}

class _Loading extends ConsumerWidget {
  const _Loading();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Semantics(label: ref.watch(trProvider)('Cargando…'), child: const RindeSpinner(size: 28)),
    ),
  );
}

/// TermsGate.jsx: bloquea hasta aceptar la versión vigente de los términos.
class _TermsGate extends ConsumerStatefulWidget {
  const _TermsGate();

  @override
  ConsumerState<_TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends ConsumerState<_TermsGate> {
  bool _saving = false;
  bool _leaving = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).acceptTerms();
      if (!mounted) return;
      ref.invalidate(profileProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.messageFor(fallback: ApiMessages.generic));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final config = ref.read(appConfigProvider);
    return RindeStateView(
      icon: RindeIcons.shieldAlert,
      title: t('Publicamos nuestros términos y la política de privacidad'),
      message: t(
        'Explican qué hace Rinde con tus datos, con qué servicios los procesamos y cómo pedir que los veamos, corrijamos o borremos. Para seguir usando la app necesitamos que los aceptes.',
      ),
      actions: [
        RindeTextLink(
          label: t('Leer los términos de uso'),
          onPressed: () => launchUrl(config.webPage('/terminos'), mode: LaunchMode.externalApplication),
        ),
        RindeTextLink(
          label: t('Leer la política de privacidad'),
          onPressed: () => launchUrl(config.webPage('/privacidad'), mode: LaunchMode.externalApplication),
        ),
        // t() deja igual un mensaje del servidor (ya viene traducido) y traduce los de respaldo.
        if (_error != null) RindeBanner(message: t(_error!)),
        RindeButton(
          label: t('Acepto los términos y la política'),
          loading: _saving,
          onPressed: _leaving ? null : _accept,
        ),
        RindeButton(
          label: t('Cerrar sesión'),
          variant: RindeButtonVariant.ghost,
          loading: _leaving,
          onPressed: _saving || _leaving
              ? null
              : () {
                  setState(() => _leaving = true);
                  unawaited(ref.read(sessionControllerProvider.notifier).signOut());
                },
        ),
      ],
    );
  }
}

/// Decide la bienvenida como el Inicio de la web (Dashboard.jsx): sin movimientos y sin bienvenida →
/// bienvenida completa; si no, el Inicio (que invita a las tres preguntas a quien no las respondió).
/// Si no se puede saber (sin red), no se redirige: se entra al Inicio, que dice qué falló.
class _WelcomeGate extends ConsumerStatefulWidget {
  const _WelcomeGate();

  @override
  ConsumerState<_WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends ConsumerState<_WelcomeGate> {
  /// Destino al que ya se mandó: cada decisión navega una sola vez, no en cada redibujado.
  String? _sent;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(welcomeStatusProvider(ref.watch(accountProvider)));
    final pending = ref.watch(pendingSourcesProvider(ref.watch(accountProvider)));
    final deferred = ref.watch(resumeDeferredProvider);
    // Solo con un dato fresco: mientras se vuelve a pedir (p. ej. justo al terminar la bienvenida),
    // el valor anterior diría «pendiente» y devolvería a la persona a la bienvenida.
    final fresh = status.isLoading || status.hasError ? null : status.value;
    // Sin bienvenida y sin movimientos → completa. Bienvenida guardada pero con las fuentes
    // pendientes en este dispositivo → solo las preguntas de plata, para terminar la etapa 2
    // (salvo que en esta sesión ya haya dicho que después).
    final target = fresh == null
        ? null
        : !fresh.welcomeDone && !fresh.hasTransactions
        ? Routes.onboarding
        : fresh.welcomeDone && pending.value == true && !deferred
        ? Routes.onboardingQuestions
        : null;
    if (target == null) {
      _sent = null;
    } else if (_sent != target) {
      _sent = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(target);
      });
    }
    // Espera solo mientras no hay nada que mostrar; una recarga del Inicio no lo reemplaza. También
    // espera si lo último que se supo era «cuenta nueva sin bienvenida»: justo al terminarla, ese dato
    // viejo dibujaría por un instante un Inicio que ya no es cierto.
    final old = status.value;
    final waiting =
        (status.isLoading && !status.hasValue && !status.hasError) ||
        (status.isLoading && old != null && !old.welcomeDone && !old.hasTransactions) ||
        (pending.isLoading && !pending.hasValue);
    if (waiting || target != null) return const _Loading();
    return const HomeScreen();
  }
}
