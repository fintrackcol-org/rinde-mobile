import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../auth/application/session_controller.dart';
import '../data/draft_store.dart';
import '../data/onboarding_repository.dart';
import '../../../design/widgets/rinde_icon.dart';

/// Invitación del inicio para quien ya tiene movimientos (MoneyInvite.jsx): «Responder» abre las tres
/// preguntas y «Ahora no» marca la bienvenida sin respuestas (POST {}). Mejora sobre la web: spinner,
/// un solo envío aunque se toque dos veces y error visible.
class MoneyInviteCard extends ConsumerStatefulWidget {
  const MoneyInviteCard({super.key});

  @override
  ConsumerState<MoneyInviteCard> createState() => _MoneyInviteCardState();
}

class _MoneyInviteCardState extends ConsumerState<MoneyInviteCard> {
  bool _busy = false;

  /// Ya guardado: la tarjeta se quita sin esperar a que el Inicio logre recargar (puede fallar).
  bool _done = false;

  /// Clave en español o mensaje del servidor (ya traducido); se pasa por t() al dibujar.
  String? _error;

  Future<void> _later() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // El contenedor y no `ref`: si la tarjeta ya no está cuando llega la respuesta, el estado viejo
    // (bienvenida pendiente) no puede quedarse guardado.
    final container = ProviderScope.containerOf(context, listen: false);
    final account = ref.read(accountProvider);
    final drafts = ref.read(draftStoreProvider);
    try {
      await ref.read(onboardingRepositoryProvider).finishWelcome(const {});
      // Dijo que no: el borrador sobra, salvo que ya haya salido. Ese se retoma para no perder las fuentes.
      if (account != null) {
        final saved = await drafts.read(account.user.id);
        // Solo lo que se pudo leer: null también es un llavero que no respondió.
        if (saved is Map && saved['sentWelcome'] is! String) await drafts.clear(account.user.id);
      }
      container.invalidate(pendingSourcesProvider);
      // Confirmado: el inicio vuelve a pedir el estado.
      container.invalidate(welcomeStatusProvider, asReload: true);
      if (mounted) setState(() => _done = true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.messageFor(fallback: ApiMessages.generic) : ApiMessages.generic;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    if (_done) return const SizedBox.shrink();
    return RindeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brX2),
                child: RindeIcon(RindeIcons.wallet, color: p.brand),
              ),
              const SizedBox(width: RindeSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        t('¿Ya tenías plata cuando empezaste?'),
                        style: RindeType.bodyMedium
                            .w(FontWeight.w600)
                            .copyWith(color: p.ink, letterSpacing: -0.4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(
                        'Dinos cuánta tienes hoy y cómo te entra: son tres preguntas y las cambias cuando quieras.',
                      ),
                      style: RindeType.small.copyWith(color: p.inkMuted),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: RindeSpace.s1),
                      Semantics(
                        liveRegion: true,
                        child: Text(t(_error!), style: RindeType.small.copyWith(color: p.negative)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s2),
          Wrap(
            spacing: RindeSpace.s2,
            children: [
              _TapArea(
                onTap: _busy ? null : () => context.go(Routes.onboardingQuestions),
                child: RindeButton(
                  label: t('Responder'),
                  size: RindeButtonSize.sm,
                  expand: false,
                  onPressed: _busy ? null : () => context.go(Routes.onboardingQuestions),
                ),
              ),
              _TapArea(
                onTap: _busy ? null : _later,
                child: RindeButton(
                  label: t('Ahora no'),
                  variant: RindeButtonVariant.ghost,
                  size: RindeButtonSize.sm,
                  expand: false,
                  loading: _busy,
                  onPressed: _busy ? null : _later,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El botón sm mide 36 como en la web; esto lleva el área táctil a 48 sin cambiar el dibujo.
/// Los toques sobre el botón los toma el botón; los del margen, esta área.
class _TapArea extends StatelessWidget {
  const _TapArea({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child),
  );
}
