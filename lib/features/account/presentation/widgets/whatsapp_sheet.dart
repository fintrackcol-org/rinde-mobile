import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../auth/application/session_controller.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../application/account_providers.dart';
import '../../application/account_writer.dart';
import '../../data/account_models.dart';
import 'account_sheet.dart';

/// WhatsappLink.jsx (FT-0029): conectar el número con el bot, pedir acceso si el equipo aún no lo dio
/// y desconectarlo. El panel del equipo («Ver uso y accesos del equipo») sigue solo en la web.
class WhatsappSheet extends ConsumerStatefulWidget {
  const WhatsappSheet({super.key});

  @override
  ConsumerState<WhatsappSheet> createState() => _WhatsappSheetState();
}

class _WhatsappSheetState extends ConsumerState<WhatsappSheet> {
  WhatsappCode? _pending;
  bool _creating = false;
  String? _error;

  Future<void> _run(Future<void> Function(AccountWriter writer) action) async {
    final t = ref.read(trProvider);
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await action(ref.read(accountWriterProvider));
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _createCode() => _run((writer) async {
    final code = await writer.createWhatsappCode();
    if (mounted) setState(() => _pending = code);
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final link = ref.watch(whatsappLinkProvider(ref.watch(accountProvider)));
    final data = link.value;

    final Widget body;
    if (data == null) {
      body = link.hasError && !link.isLoading
          ? RindeBanner(
              message: moneyErrorText(link.error!, t),
              action: RindeTextLink(
                label: t('Reintentar'),
                onPressed: () => ref.read(accountWriterProvider).reloadWhatsapp(),
              ),
            )
          : const Align(alignment: AlignmentDirectional.centerStart, child: RindeSpinner());
    } else if (!data.available) {
      // La web no muestra nada: el bot no está para esta cuenta.
      body = const SizedBox.shrink();
    } else if (data.access != WhatsappAccess.approved) {
      body = _AccessStep(
        access: data.access,
        asking: _creating,
        onAsk: () => _run((w) => w.requestWhatsappAccess()),
      );
    } else if (data.linked) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RindeIcon(RindeIcons.circleCheck, color: p.positive),
              const SizedBox(width: RindeSpace.s2),
              Expanded(
                child: Text(
                  data.phone != null
                      ? t('Conectado con {phone}', {'phone': data.phone})
                      : t('Conectado con tu WhatsApp'),
                  style: RindeType.small.copyWith(color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s2),
          ConfirmInline(
            label: t('Desconectar'),
            question: t('¿Desconectar este número? Tus movimientos no se borran.'),
            confirmLabel: t('Sí, desconectar'),
            cancelLabel: t('Cancelar'),
            onConfirm: () async {
              await ref.read(accountWriterProvider).unlinkWhatsapp();
              if (mounted) setState(() => _pending = null);
            },
            errorText: (e) => moneyErrorText(e, t),
          ),
        ],
      );
    } else if (_pending case final pending?) {
      body = _CodeStep(
        pending: pending,
        checking: link.isLoading,
        onCheck: () => ref.read(accountWriterProvider).reloadWhatsapp(),
      );
    } else {
      body = RindeButton(
        label: t('Conectar WhatsApp'),
        loading: _creating,
        leading: const RindeIcon(RindeIcons.messageCircle, size: 18, color: RindeBrand.white),
        onPressed: _createCode,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data?.available ?? true) ...[
          SheetNote(t('Registra movimientos desde el chat, como "almuerzo 15 mil".')),
          const SizedBox(height: RindeSpace.s4),
        ],
        body,
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s3), RindeBanner(message: error)],
      ],
    );
  }
}

/// Paso con el código: se le envía al bot y luego se revisa la conexión.
class _CodeStep extends ConsumerWidget {
  const _CodeStep({required this.pending, required this.checking, required this.onCheck});
  final WhatsappCode pending;
  final bool checking;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final chat = pending.chatUrl;
    return Container(
      padding: const EdgeInsets.all(RindeSpace.s4),
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetNote(t('Envíale este código al bot. Vence en 10 minutos y sirve una sola vez.')),
          const SizedBox(height: RindeSpace.s3),
          // Se puede seleccionar y copiar, como `select-all` en la web.
          SelectableText(
            pending.code,
            style: RindeType.title.copyWith(
              fontSize: 20,
              letterSpacing: 1.5,
              color: p.brand,
              fontFeatures: RindeType.tabular,
            ),
          ),
          const SizedBox(height: RindeSpace.s3),
          if (chat != null) ...[
            RindeButton(
              label: t('Abrir WhatsApp'),
              leading: const RindeIcon(RindeIcons.messageCircle, size: 18, color: RindeBrand.white),
              onPressed: () => launchUrl(chat, mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: RindeSpace.s2),
          ],
          RindeButton(
            label: t('Ya lo envié'),
            variant: RindeButtonVariant.soft,
            loading: checking,
            leading: RindeIcon(RindeIcons.refreshCw, size: 18, color: p.brand),
            onPressed: onCheck,
          ),
        ],
      ),
    );
  }
}

/// Qué ve quien todavía no tiene acceso: el equipo lo aprueba para cuidar el cupo de respuestas.
class _AccessStep extends ConsumerWidget {
  const _AccessStep({required this.access, required this.asking, required this.onAsk});
  final WhatsappAccess access;
  final bool asking;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return switch (access) {
      WhatsappAccess.pending => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RindeIcon(RindeIcons.clock, color: p.brand),
          const SizedBox(width: RindeSpace.s2),
          Expanded(
            child: Text(
              t('Ya pediste acceso. Te avisamos por correo cuando esté listo.'),
              style: RindeType.small.copyWith(color: p.ink),
            ),
          ),
        ],
      ),
      WhatsappAccess.rejected => SheetNote(t('Por ahora no hay cupo para tu cuenta.')),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetNote(t('Lo estamos abriendo de a pocos. Pide acceso y te avisamos por correo.')),
          const SizedBox(height: RindeSpace.s3),
          RindeButton(
            label: t('Pedir acceso'),
            loading: asking,
            leading: const RindeIcon(RindeIcons.messageCircle, size: 18, color: RindeBrand.white),
            onPressed: onAsk,
          ),
        ],
      ),
    };
  }
}
