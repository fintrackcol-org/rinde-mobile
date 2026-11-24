import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/region/region_provider.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../home/application/home_providers.dart' show clockProvider;
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../movements/presentation/list/movement_dates.dart' show relativeDay;
import '../../application/vacas_providers.dart';
import '../../application/vacas_writer.dart';
import '../../data/vaca_models.dart';

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Abre «Invitar a la vaca» (InvitePanel.jsx): el enlace y el código para compartir, invitar por
/// correo y, para quien administra, las invitaciones pendientes y cambiar el código. El enlace abre la
/// web (`/app/vacas/unirse/:code`); en la app se entra con «Tengo un código». Lee el detalle vivo para
/// mostrar el código nuevo y las invitaciones apenas cambian.
Future<void> showInviteSheet(BuildContext context, {required String vacaId}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.palette.surface,
  builder: (_) => _InviteSheet(vacaId: vacaId),
);

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.vacaId});

  final String vacaId;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _emailField = TextEditingController();
  bool _busy = false;
  bool _copied = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailField.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, ref.read(trProvider)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invite() {
    final t = ref.read(trProvider);
    final clean = _emailField.text.trim().toLowerCase();
    if (!_email.hasMatch(clean)) {
      setState(() => _error = t('Escribe un correo válido.'));
      return;
    }
    _run(() async {
      final sent = await ref.read(vacasWriterProvider).invite(widget.vacaId, clean);
      _emailField.clear();
      return sent
          ? t('Invitación enviada a {clean}.', {'clean': clean})
          : t('Ya le enviamos la invitación a {clean} hace un momento.', {'clean': clean});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final vaca = ref.watch(vacaDetailProvider((ref.watch(accountProvider), widget.vacaId))).value;
    final code = vaca?.code;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t('Invitar a la vaca'), style: RindeType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: RindeSpace.s4),
            if (vaca != null && code != null) ..._share(t, p, vaca, code),
            const SizedBox(height: RindeSpace.s5),
            RindeTextField(
              label: t('Invitar por correo'),
              controller: _emailField,
              hint: 'correo@ejemplo.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              enabled: !_busy,
              onSubmitted: (_) => _invite(),
            ),
            const SizedBox(height: RindeSpace.s2),
            RindeButton(
              label: t('Enviar invitación'),
              variant: RindeButtonVariant.outline,
              leading: RindeIcon(RindeIcons.mail, size: 16, color: p.ink),
              loading: _busy,
              onPressed: _invite,
            ),
            if (_message case final message?)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: RindeSpace.s2),
                  child: Text(message, style: RindeType.small.copyWith(color: p.positive)),
                ),
              ),
            if (_error case final error?)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: RindeSpace.s2),
                  child: Text(error, style: RindeType.small.copyWith(color: p.negative)),
                ),
              ),
            if (vaca != null && vaca.admin && vaca.invitations.isNotEmpty) ...[
              const SizedBox(height: RindeSpace.s5),
              Text(t('Invitaciones pendientes'), style: RindeType.label.copyWith(color: p.inkLabel)),
              for (final inv in vaca.invitations)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv.email,
                            style: RindeType.small.copyWith(color: p.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (inv.sentAt.isNotEmpty)
                            Text(
                              '${t('Enviada:')} ${relativeDay(inv.sentAt, ref.watch(clockProvider)(), ref.watch(appRegionProvider), t)}',
                              style: RindeType.caption.copyWith(color: p.inkMuted),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await ref.read(vacasWriterProvider).cancelInvitation(vaca.id, inv.email);
                              return null;
                            }),
                      tooltip: t('Cancelar invitación a {email}', {'email': inv.email}),
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: RindeIcon(RindeIcons.x, size: 18, color: p.inkMuted),
                    ),
                  ],
                ),
            ],
            if (vaca != null && vaca.admin) ...[
              const SizedBox(height: RindeSpace.s4),
              ConfirmInline(
                compact: true,
                label: t('Cambiar código'),
                question: t('El enlace actual dejará de servir. ¿Cambiar el código?'),
                confirmLabel: t('Sí, cambiar'),
                cancelLabel: t('No'),
                errorText: (e) => moneyErrorText(e, t),
                onConfirm: () => ref.read(vacasWriterProvider).regenerateCode(vaca.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _share(Tr t, RindePalette p, Vaca vaca, String code) {
    final link = ref.read(appConfigProvider).webPage('/app/vacas/unirse/$code').toString();
    return [
      Text(t('Enlace para unirse'), style: RindeType.label.copyWith(color: p.inkLabel)),
      const SizedBox(height: RindeSpace.s2),
      Row(
        children: [
          Expanded(
            child: Semantics(
              label: t('Enlace de invitación'),
              child: SelectableText(link, style: RindeType.small.copyWith(color: p.ink)),
            ),
          ),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (mounted) setState(() => _copied = true);
            },
            tooltip: t('Copiar enlace'),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: RindeIcon(_copied ? RindeIcons.check : RindeIcons.copy, size: 20, color: p.brand),
          ),
        ],
      ),
      const SizedBox(height: RindeSpace.s2),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${t('O comparte el código')} '),
            TextSpan(
              text: code,
              style: RindeType.bodyMedium.w(FontWeight.w700).copyWith(color: p.ink, letterSpacing: 3),
            ),
            TextSpan(text: ' ${t('(en Vacas → Tengo un código).')}'),
          ],
        ),
        style: RindeType.small.copyWith(color: p.inkMuted),
      ),
      const SizedBox(height: RindeSpace.s3),
      RindeButton(
        label: t('Compartir'),
        variant: RindeButtonVariant.outline,
        onPressed: () => SharePlus.instance.share(
          ShareParams(
            title: t('Vaca "{name}"', {'name': vaca.name}),
            text:
                '${t('Únete a la vaca "{name}" en Rinde (código {code}):', {'name': vaca.name, 'code': code})} $link',
          ),
        ),
      ),
    ];
  }
}
