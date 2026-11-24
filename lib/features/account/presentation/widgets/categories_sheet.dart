import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../design/tokens/rinde_colors.dart';
import '../../../../design/tokens/rinde_layout.dart';
import '../../../../design/tokens/rinde_typography.dart';
import '../../../../design/widgets/confirm_inline.dart';
import '../../../../design/widgets/rinde_button.dart';
import '../../../../design/widgets/rinde_feedback.dart';
import '../../../../design/widgets/rinde_icon.dart';
import '../../../../design/widgets/rinde_segmented.dart';
import '../../../../design/widgets/rinde_spinner.dart';
import '../../../../design/widgets/rinde_text_field.dart';
import '../../../auth/application/session_controller.dart';
import '../../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../../movements/application/movements_controller.dart' show movementCategoriesProvider;
import '../../../movements/domain/movement.dart' show CategoryOption;
import '../../application/account_writer.dart';
import 'account_sheet.dart';

/// Categorías propias que puede tener cada usuario (MAX_OWN de la web, igual que en la API).
const maxOwnCategories = 20;

/// Largo máximo del nombre (NAME_MAX de NewCategoryDialog.jsx).
const maxCategoryName = 30;

/// Una categoría propia con su tipo (`gasto` o `ingreso`, como la API).
typedef _Own = ({CategoryOption category, String type});

/// fallbackName de la web: adónde pasan los movimientos de una categoría borrada.
String _fallback(Tr t, String type) => type == 'ingreso' ? t('Otros ingresos') : t('Otros');

/// CustomCategories.jsx: las categorías propias para crear, renombrar y eliminar. Las 15 de todos no
/// aparecen porque no se pueden cambiar. El ícono y el color se eligen en la web (la app no los
/// dibuja): las nuevas llevan los que la web propone primero.
class CategoriesSheet extends ConsumerStatefulWidget {
  const CategoriesSheet({super.key});

  @override
  ConsumerState<CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends ConsumerState<CategoriesSheet> {
  String? _status;

  /// null: la lista. Con valor: el formulario, para crear (category null) o renombrar.
  ({CategoryOption? category, String type})? _form;

  Future<void> _delete(_Own own) async {
    final t = ref.read(trProvider);
    final moved = await ref.read(accountWriterProvider).deleteCategory(own.category.key);
    if (!mounted) return;
    setState(
      () => _status = moved == 0
          ? t('Categoría eliminada.')
          : t('Categoría eliminada. {moved} {v2} a {type}.', {
              'moved': moved,
              // TEXTO NUEVO (la web deja el plural sin traducir).
              'v2': moved == 1 ? t('movimiento pasó') : t('movimientos pasaron'),
              'type': _fallback(t, own.type),
            }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final lists = ref.watch(movementCategoriesProvider(ref.watch(accountProvider)));
    final own = lists.value == null
        ? null
        : <_Own>[
            for (final c in lists.value!.expense)
              if (c.custom) (category: c, type: 'gasto'),
            for (final c in lists.value!.income)
              if (c.custom) (category: c, type: 'ingreso'),
          ];
    final count = own?.length ?? 0;

    if (_form case final form?) {
      return _CategoryForm(
        category: form.category,
        initialType: form.type,
        onDone: (status) => setState(() {
          _form = null;
          _status = status;
        }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetNote(
          '${t('Además de las 15 de siempre, puedes crear hasta')} $maxOwnCategories ${t('propias.')}'
          '${own == null ? '' : t(' Tienes {count} de {MAX_OWN}.', {'count': count, 'MAX_OWN': maxOwnCategories})}',
        ),
        const SizedBox(height: RindeSpace.s3),
        RindeButton(
          label: t('Nueva categoría'),
          variant: RindeButtonVariant.soft,
          leading: RindeIcon(RindeIcons.plus, size: 18, color: p.brand),
          onPressed: own == null || count >= maxOwnCategories
              ? null
              : () => setState(() {
                  _status = null;
                  _form = (category: null, type: 'gasto');
                }),
        ),
        if (_status case final status?) ...[
          const SizedBox(height: RindeSpace.s3),
          RindeBanner(message: status, tone: RindeBannerTone.success),
        ],
        const SizedBox(height: RindeSpace.s4),
        if (lists.hasError && !lists.isLoading)
          RindeBanner(
            message: moneyErrorText(lists.error!, t),
            action: RindeTextLink(
              label: t('Reintentar'),
              onPressed: () => ref.invalidate(movementCategoriesProvider),
            ),
          )
        else if (own == null)
          Row(
            children: [
              const RindeSpinner(size: 16),
              const SizedBox(width: RindeSpace.s2),
              SheetNote(t('Cargando tus categorías…')),
            ],
          )
        else if (own.isEmpty)
          // TEXTO NUEVO: la web también invita al botón «Nueva» de movimientos y presupuestos, que la app
          // aún no tiene.
          SheetNote(t('Aún no tienes categorías propias. Créalas aquí.'), tone: p.ink.withValues(alpha: 0.7))
        else
          for (var i = 0; i < own.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
            _CategoryRow(
              own: own[i],
              onEdit: () => setState(() {
                _status = null;
                _form = (category: own[i].category, type: own[i].type);
              }),
              onDelete: () => _delete(own[i]),
            ),
          ],
      ],
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.own, required this.onEdit, required this.onDelete});
  final _Own own;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final name = own.category.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RindeType.bodyMedium.copyWith(color: p.ink),
                    ),
                    SheetNote(own.type == 'gasto' ? t('Gasto') : t('Ingreso')),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: t('Editar {name}', {'name': name}),
                style: IconButton.styleFrom(
                  minimumSize: const Size(RindeSize.tapTarget, RindeSize.tapTarget),
                ),
                icon: RindeIcon(RindeIcons.pencil, size: 18, color: p.inkMuted),
              ),
            ],
          ),
          ConfirmInline(
            compact: true,
            label: t('Eliminar {name}', {'name': name}),
            question:
                '${t('¿Eliminar “')}$name”? ${t('Sus movimientos pasarán a')} ${_fallback(t, own.type)} '
                '${t('y sus presupuestos se borrarán.')}',
            confirmLabel: t('Sí, eliminar'),
            cancelLabel: t('No'),
            onConfirm: onDelete,
            errorText: (e) => moneyErrorText(e, t),
          ),
        ],
      ),
    );
  }
}

/// NewCategoryDialogPanel.jsx sin ícono ni color: tipo (solo al crear) y nombre.
class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({required this.category, required this.initialType, required this.onDone});
  final CategoryOption? category;
  final String initialType;

  /// Con el aviso para la lista; null si se canceló.
  final ValueChanged<String?> onDone;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _type = widget.initialType;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = ref.read(trProvider);
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _error = t('Escribe un nombre para la categoría.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final writer = ref.read(accountWriterProvider);
    try {
      if (widget.category case final category?) {
        await writer.renameCategory(category.key, name);
      } else {
        await writer.createCategory(name: name, type: _type);
      }
      if (mounted) widget.onDone(_editing ? t('Cambios guardados.') : t('Categoría creada.'));
    } on Object catch (e) {
      if (mounted) setState(() => _error = moneyErrorText(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return PopScope(
      canPop: !_saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing ? t('Editar categoría') : t('Nueva categoría de {typeLabel}', {'typeLabel': _type}),
            style: RindeType.bodyMedium.copyWith(color: p.ink),
          ),
          if (!_editing) ...[
            const SizedBox(height: RindeSpace.s4),
            RindeSegmented<String>(
              semanticLabel: t('Tipo'),
              options: {'gasto': t('Gasto'), 'ingreso': t('Ingreso')},
              value: _type,
              onChanged: _saving ? null : (type) => setState(() => _type = type),
            ),
          ],
          const SizedBox(height: RindeSpace.s4),
          RindeTextField(
            label: t('Nombre'),
            hint: _type == 'gasto' ? t('Mascotas, Gimnasio, Universidad…') : t('Ventas, Arriendo recibido…'),
            controller: _name,
            maxLength: maxCategoryName,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            serverError: _error,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: RindeSpace.s4),
          Row(
            children: [
              Expanded(
                child: RindeButton(
                  label: t('Cancelar'),
                  variant: RindeButtonVariant.outline,
                  onPressed: _saving ? null : () => widget.onDone(null),
                ),
              ),
              const SizedBox(width: RindeSpace.s3),
              Expanded(
                child: RindeButton(
                  label: _editing ? t('Guardar') : t('Crear'),
                  loading: _saving,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
          if (!_editing) ...[
            const SizedBox(height: RindeSpace.s3),
            Text(
              t('Puedes tener hasta 20 categorías propias.'),
              textAlign: TextAlign.center,
              style: RindeType.caption.copyWith(color: p.ink.withValues(alpha: 0.55)),
            ),
          ],
        ],
      ),
    );
  }
}
