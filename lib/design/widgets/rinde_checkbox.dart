import 'package:material_ui/material_ui.dart';

import '../tokens/rinde_colors.dart';
import '../tokens/rinde_layout.dart';
import '../tokens/rinde_typography.dart';
import 'rinde_icon.dart';

/// Casilla con etiqueta tocable. En la web la casilla mide 16 px; aquí 22 dentro de un área
/// táctil de 48, para que se pueda marcar con el dedo.
class RindeCheckboxField extends FormField<bool> {
  RindeCheckboxField({
    super.key,
    required Widget label,
    required String semanticLabel,
    super.validator,
    bool initialValue = false,
    ValueChanged<bool>? onChanged,
  }) : super(
         initialValue: initialValue,
         builder: (state) {
           final context = state.context;
           final p = context.palette;
           final checked = state.value ?? false;
           void toggle() {
             state.didChange(!checked);
             onChanged?.call(!checked);
           }

           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               // Para el lector: la casilla es un nodo propio (estado + nombre) y la etiqueta queda
               // aparte, así sus enlaces (términos, privacidad) se pueden recorrer y abrir.
               InkWell(
                 onTap: toggle,
                 excludeFromSemantics: true,
                 borderRadius: RindeRadius.brXl,
                 child: ConstrainedBox(
                   constraints: const BoxConstraints(minHeight: RindeSize.tapTarget),
                   child: Row(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Semantics(
                         checked: checked,
                         label: semanticLabel,
                         onTap: toggle,
                         excludeSemantics: true,
                         child: Padding(
                           padding: const EdgeInsets.only(top: 13, right: RindeSpace.s3),
                           child: AnimatedContainer(
                             duration: RindeMotion.fast,
                             width: 22,
                             height: 22,
                             decoration: BoxDecoration(
                               color: checked ? RindeBrand.violet : Colors.transparent,
                               borderRadius: BorderRadius.circular(5),
                               border: Border.all(
                                 color: state.hasError
                                     ? p.negative
                                     : checked
                                     ? RindeBrand.violet
                                     : const Color(0xFF666666),
                                 width: 1.5,
                               ),
                             ),
                             alignment: Alignment.center,
                             child: checked
                                 ? const RindeIcon(RindeIcons.checkBold, size: 15, color: RindeBrand.white)
                                 : null,
                           ),
                         ),
                       ),
                       Expanded(
                         child: Padding(
                           padding: const EdgeInsets.symmetric(vertical: 12),
                           child: DefaultTextStyle.merge(
                             style: RindeType.label.copyWith(
                               color: p.ink.withValues(alpha: 0.55),
                               height: 1.4,
                             ),
                             child: label,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
               ),
               if (state.hasError)
                 Semantics(
                   liveRegion: true,
                   child: Padding(
                     padding: const EdgeInsets.only(left: 34),
                     child: Text(state.errorText!, style: RindeType.small.copyWith(color: p.negative)),
                   ),
                 ),
             ],
           );
         },
       );
}
