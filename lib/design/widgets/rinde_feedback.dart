import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_icon.dart';

enum RindeBannerTone { error, success, info, neutral }

/// Avisos de Rinde Web: error del servidor (destructive/10), éxito (mint/10), invitación
/// (violet/15) y neutro (white/10). Se anuncian al lector de pantalla al aparecer.
class RindeBanner extends StatelessWidget {
  const RindeBanner({
    super.key,
    required this.message,
    this.tone = RindeBannerTone.error,
    this.action,
    this.semanticsLabel,
  });

  final String message;

  /// Lo que oye el lector si no es [message] (con montos ocultos, `money.spoken(message)`).
  final String? semanticsLabel;
  final RindeBannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isPublic = p == RindePalette.public;
    final color = switch (tone) {
      RindeBannerTone.error => isPublic ? RindeBrand.destructive : p.negative,
      RindeBannerTone.success => isPublic ? RindeBrand.mint : p.positive,
      RindeBannerTone.info => isPublic ? RindeBrand.violetLight : p.brand,
      RindeBannerTone.neutral => p.ink.withValues(alpha: 0.8),
    };
    final background = switch (tone) {
      RindeBannerTone.info => RindeBrand.violet.withValues(alpha: 0.15),
      RindeBannerTone.neutral => p.ink.withValues(alpha: 0.1),
      _ => color.withValues(alpha: 0.1),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: RindeRadius.brXl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                semanticsLabel: semanticsLabel,
                style: RindeType.small.copyWith(color: color),
              ),
              if (action != null) ...[const SizedBox(height: RindeSpace.s2), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel de Rinde (layout/Panel.jsx): radio 16, borde ink/10, fondo surface, padding 20.
class RindeCard extends StatelessWidget {
  const RindeCard({super.key, required this.child, this.padding = const EdgeInsets.all(RindeSpace.s5)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: RindeRadius.brX2,
        border: Border.all(color: p.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Cuadro de ícono sobre un título (AuthLayout): 56, radio 16, violeta suave.
class RindeIconTile extends StatelessWidget {
  const RindeIconTile(this.icon, {super.key, this.tone});
  final RindeIcons icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? RindeBrand.violetLight;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: RindeBrand.violet.withValues(alpha: 0.15),
        borderRadius: RindeRadius.brX2,
        border: Border.all(color: RindeBrand.violet.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: RindeIcon(icon, size: 24, color: c),
    );
  }
}

/// Estado de pantalla completa (cargando, error, enlace vencido...): ícono, título, texto y acciones.
class RindeStateView extends StatelessWidget {
  const RindeStateView({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.message,
    this.actions = const [],
  });

  final String title;
  final RindeIcons? icon;
  final Widget? leading;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RindeSpace.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: RindeSpace.authColumn),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) leading! else if (icon != null) RindeIconTile(icon!),
              const SizedBox(height: RindeSpace.s6),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RindeType.headline.copyWith(color: p.ink),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: RindeSpace.s2),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: RindeSpace.s8),
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(height: RindeSpace.s3),
                  a,
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
