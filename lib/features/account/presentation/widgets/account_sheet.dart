import 'package:material_ui/material_ui.dart';

import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';

/// Abre una hoja de «Yo» (Sheet de la web) con su título.
Future<T?> showAccountSheet<T>(BuildContext context, {required String title, required Widget child}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.surface,
      builder: (_) => AccountSheet(title: title, child: child),
    );

class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      // El contenido sube sobre el teclado.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s6, RindeSpace.s4, RindeSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: RindeType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: RindeSpace.s4),
            child,
          ],
        ),
      ),
    );
  }
}

/// Texto de apoyo (text-sm text-ink/60).
class SheetNote extends StatelessWidget {
  const SheetNote(this.text, {super.key, this.tone});
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: RindeType.small.copyWith(color: tone ?? context.palette.inkMuted));
}
