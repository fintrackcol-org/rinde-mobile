import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';

/// Cuerpo de "Revisa tu correo" (CheckInbox.jsx): consejos, reenvío con cuenta regresiva de 60 s
/// desde que aparece y "Usar otro correo". El título y el subtítulo los pone la pantalla.
class CheckInbox extends ConsumerStatefulWidget {
  const CheckInbox({super.key, required this.tips, required this.onResend, required this.onUseOtherEmail});

  /// Ya traducidos.
  final List<String> tips;

  /// Reenvía el enlace. Lanza ApiException si falla.
  final Future<void> Function() onResend;
  final VoidCallback onUseOtherEmail;

  static const resendSeconds = 60;

  @override
  ConsumerState<CheckInbox> createState() => _CheckInboxState();
}

class _CheckInboxState extends ConsumerState<CheckInbox> {
  int _left = CheckInbox.resendSeconds;
  Timer? _timer;
  bool _sending = false;

  /// Clave en español o mensaje del servidor; se traduce al mostrarlo.
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _left = CheckInbox.resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      setState(() => _left -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() {
        _failed = false;
        _message = 'Te enviamos un enlace nuevo. El anterior ya no sirve.';
      });
      _start();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = e.messageFor(fallback: 'No pudimos enviar el enlace. Inténtalo de nuevo.');
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _clock => '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: RindeBrand.white.withValues(alpha: 0.03),
            borderRadius: RindeRadius.brX2,
            border: Border.all(color: RindeBrand.white.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(RindeSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, tip) in widget.tips.indexed) ...[
                  if (i > 0) const SizedBox(height: RindeSpace.s2),
                  Text(tip, style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.65))),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: RindeSpace.s6),
        if (_message != null) ...[
          RindeBanner(message: t(_message!), tone: _failed ? RindeBannerTone.error : RindeBannerTone.success),
          const SizedBox(height: RindeSpace.s4),
        ],
        RindeButton(
          label: _left > 0 ? '${t('Reenviar enlace en')} $_clock' : t('Reenviar enlace'),
          variant: RindeButtonVariant.outline,
          loading: _sending,
          onPressed: _left > 0 ? null : _resend,
        ),
        const SizedBox(height: RindeSpace.s2),
        Center(
          child: RindeTextLink(
            label: t('Usar otro correo'),
            color: p.ink.withValues(alpha: 0.7),
            onPressed: widget.onUseOtherEmail,
          ),
        ),
      ],
    );
  }
}
