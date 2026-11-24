import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../data/insights_repository.dart';
import '../insights_screen.dart' show insightsErrorText;

/// Preguntas para empezar: se tocan y se envían (AssistantChat.jsx).
const _suggestions = [
  '¿En qué gasto más?',
  '¿A cómo está el dólar hoy?',
  '¿Cuánto paga un CDT a un año?',
  'Si invierto lo que me sobra al mes, ¿cuánto gano?',
];

/// Cómo se llama, para la persona, cada fuente que puede consultar el asistente.
const _sources = {
  'resumen_de_movimientos': 'Tus movimientos',
  'ahorro_promedio': 'Tu ahorro promedio',
  'dolar_hoy': 'TRM · Superfinanciera',
  'tasas_cdt': 'Tasas de CDT · Superfinanciera',
  'simular_cdt': 'Simulador de CDT',
};

/// «Pregúntale a Rinde» en una hoja (la variante de celular de la web). La conversación vive solo en
/// la hoja: al cerrarla se borra.
Future<void> showAssistantSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.palette.surface,
  builder: (_) => const AssistantSheet(),
);

class AssistantSheet extends ConsumerStatefulWidget {
  const AssistantSheet({super.key});

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final _messages = <ChatMessage>[];

  /// Fuentes que consultó cada respuesta, por su posición en [_messages].
  final _sourcesOf = <int, List<String>>{};
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  /// Envía la conversación (con la pregunta nueva, o la última otra vez al reintentar).
  Future<void> _send() async {
    final t = ref.read(trProvider);
    setState(() => (_pending = true, _error = null));
    _toEnd();
    try {
      final answer = await ref.read(insightsRepositoryProvider).ask(List.of(_messages));
      if (!mounted) return;
      setState(() {
        _sourcesOf[_messages.length] = [
          ...{for (final name in answer.toolsUsed) ?_sources[name]},
        ];
        _messages.add((fromUser: false, text: answer.reply));
      });
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = insightsErrorText(
            e,
            t,
            offline: 'Sin conexión. El asistente necesita internet.',
            unavailable: 'El asistente no está disponible ahora. Inténtalo en unos minutos.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
      _toEnd();
    }
  }

  void _ask(String question) {
    final text = question.trim();
    if (text.isEmpty || _pending) return;
    _draft.clear();
    setState(() => _messages.add((fromUser: true, text: text)));
    _send();
  }

  void _restart() => setState(() {
    _messages.clear();
    _sourcesOf.clear();
    _error = null;
    _draft.clear();
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final media = MediaQuery.of(context);

    return Padding(
      // La caja para preguntar sube sobre el teclado.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.85 - media.viewInsets.bottom,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s5, RindeSpace.s4, RindeSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: p.brandSoft, borderRadius: RindeRadius.brXl),
                    alignment: Alignment.center,
                    child: RindeIcon(RindeIcons.sparkles, color: p.brand),
                  ),
                  const SizedBox(width: RindeSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(t('Pregúntale a Rinde'), style: RindeType.title.copyWith(color: p.ink)),
                        ),
                        Text(
                          t('Responde con los totales de tu mes.'),
                          style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  if (_messages.isNotEmpty)
                    RindeButton(
                      label: t('Nueva'),
                      variant: RindeButtonVariant.ghost,
                      size: RindeButtonSize.sm,
                      expand: false,
                      leading: const RindeIcon(RindeIcons.rotateCcw, size: 16),
                      onPressed: _restart,
                    ),
                ],
              ),
              const SizedBox(height: RindeSpace.s4),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: ListView(
                    controller: _scroll,
                    children: [
                      if (_messages.isEmpty) ...[
                        Text(
                          t('Prueba con una de estas preguntas:'),
                          style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: RindeSpace.s3),
                        Wrap(
                          spacing: RindeSpace.s2,
                          runSpacing: RindeSpace.s2,
                          children: [
                            for (final s in _suggestions)
                              OutlinedButton(
                                onPressed: () => _ask(t(s)),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  foregroundColor: p.ink.withValues(alpha: 0.8),
                                  side: BorderSide(color: p.lineStrong),
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: RindeSpace.s2,
                                  ),
                                ),
                                child: Text(t(s), style: RindeType.small),
                              ),
                          ],
                        ),
                      ],
                      for (final (i, m) in _messages.indexed)
                        _Bubble(message: m, sources: _sourcesOf[i] ?? const []),
                      if (_pending)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            label: t('Rinde está escribiendo…'),
                            child: ExcludeSemantics(
                              child: Container(
                                margin: const EdgeInsets.only(top: RindeSpace.s3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: RindeSpace.s4,
                                  vertical: RindeSpace.s3,
                                ),
                                decoration: BoxDecoration(
                                  color: p.surfaceMuted,
                                  borderRadius: RindeRadius.brX2,
                                ),
                                child: Text('• • •', style: RindeType.small.copyWith(color: p.inkMuted)),
                              ),
                            ),
                          ),
                        ),
                      if (_error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(top: RindeSpace.s3),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(error, style: RindeType.small.copyWith(color: p.negative)),
                              RindeTextLink(label: t('Reintentar'), onPressed: _send),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s3),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.canvas,
                  borderRadius: BorderRadius.circular(RindeRadius.pill),
                  border: Border.all(color: p.lineStrong),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(RindeSpace.s4, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _draft,
                          maxLength: maxQuestionChars,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _ask,
                          onChanged: (_) => setState(() {}),
                          style: RindeType.body.copyWith(color: p.ink),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            counterText: '',
                            hintText: t('¿Cuánto llevo en domicilios?'),
                            hintStyle: RindeType.body.copyWith(color: p.ink.withValues(alpha: 0.45)),
                            semanticCounterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t('Enviar pregunta'),
                        onPressed: _pending || _draft.text.trim().isEmpty ? null : () => _ask(_draft.text),
                        style: IconButton.styleFrom(
                          backgroundColor: p.brandSolid,
                          disabledBackgroundColor: p.brandSolid.withValues(alpha: 0.4),
                          minimumSize: const Size(40, 40),
                        ),
                        icon: const RindeIcon(RindeIcons.arrowUp, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RindeSpace.s2),
              Text(
                t('Es orientación, no asesoría financiera. No escribas cédulas ni números de cuenta.'),
                style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.sources});

  final ChatMessage message;
  final List<String> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final user = message.fromUser;
    return Align(
      alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: 0.85,
        alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Align(
          alignment: user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.only(top: RindeSpace.s3),
            padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: 10),
            decoration: BoxDecoration(
              color: user ? p.brandSolid : p.surfaceMuted,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(RindeRadius.x2),
                topRight: const Radius.circular(RindeRadius.x2),
                bottomLeft: Radius.circular(user ? RindeRadius.x2 : 6),
                bottomRight: Radius.circular(user ? 6 : RindeRadius.x2),
              ),
            ),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    semanticsLabel: '${user ? t('Tú: ') : t('Rinde: ')}${message.text}',
                    style: RindeType.small.copyWith(color: user ? Colors.white : p.ink, height: 1.6),
                  ),
                  if (sources.isNotEmpty) ...[
                    const SizedBox(height: RindeSpace.s2),
                    Divider(height: 1, thickness: 1, color: p.line),
                    const SizedBox(height: RindeSpace.s2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: RindeIcon(RindeIcons.database, size: 14, color: p.inkMuted),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${t('Consultó:')} ${sources.map(t.call).join(' · ')}',
                            style: RindeType.caption.copyWith(color: p.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
