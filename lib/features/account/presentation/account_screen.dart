import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app.dart' show themeModeProvider;
import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show tourRequestedProvider;
import '../../shell/presentation/rinde_tab_scaffold.dart';
import '../application/account_providers.dart';
import '../application/account_writer.dart';
import 'widgets/account_sheet.dart';
import 'widgets/categories_sheet.dart';
import 'widgets/delete_account_sheet.dart';
import 'widgets/profile_sheet.dart';
import 'widgets/region_sheets.dart';
import 'widgets/reminders_sheet.dart';
import 'widgets/whatsapp_sheet.dart';

/// Nombre para mostrar (getDisplayName de la web): el primer nombre, o la parte del correo antes de
/// la @ con mayúscula inicial.
String displayName(String? name, String email) {
  final fromName = name?.trim().split(RegExp(r'\s+')).first ?? '';
  if (fromName.isNotEmpty) return fromName;
  final first = email
      .split('@')
      .first
      .split(RegExp(r'[._\-+\d]+'))
      .firstWhere((p) => p.isNotEmpty, orElse: () => '');
  return first.isEmpty ? '' : first[0].toUpperCase() + first.substring(1).toLowerCase();
}

/// Nombre guardado de quien está dentro: el del perfil (el servidor) cuando ya llegó; si no, el del
/// ingreso. Vigila el perfil.
String? accountName(WidgetRef ref) {
  final account = ref.watch(accountProvider);
  final profile = ref.watch(profileProvider(account));
  return profile.hasValue ? profile.value!.name : account?.user.name;
}

/// `/app/cuenta`, pestaña «Yo» (MobileAccount de Account.jsx, lienzo «Tu cuenta»): quién eres, lo que
/// más se cambia a la vista (WhatsApp con su estado y el tema) y lo demás en hojas. Cerrar sesión pide
/// confirmación porque lo anotado sin conexión se queda en el celular.
///
/// No se portan: instalar la app (PWA), «Pagos con Apple Pay» (atajo de iOS), los recordatorios
/// diarios y el permiso de notificaciones de este dispositivo (solo llegan por push, que la app no
/// tiene) ni los enlaces de Ayuda a pantallas que la app no tiene (invitar, planes, lo que viene).
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  Future<void> _sheet(String title, Widget child) =>
      showAccountSheet<void>(context, title: title, child: child);

  Future<void> _whatsapp(Tr t) async {
    await _sheet(t('Anotar por WhatsApp'), const WhatsappSheet());
    // Como la web al cerrar la hoja: vuelve a leer si quedó conectado.
    if (mounted) ref.read(accountWriterProvider).reloadWhatsapp();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final account = ref.watch(accountProvider);
    final region = ref.watch(appRegionProvider);
    final demo = account?.demo ?? false;
    final email = account?.user.email ?? '';
    final name = displayName(accountName(ref), email);
    final whatsapp = ref.watch(whatsappLinkProvider(account));
    final linked = whatsapp.value?.linked ?? false;
    final country = findCountry(region.country);
    final language = kLanguages.where((l) => l.code == region.language).firstOrNull;

    return RindeTabScaffold(
      current: RindeTab.account,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          RindeSpace.s4,
          RindeSpace.s6,
          RindeSpace.s4,
          RindeTabScaffold.bottomInset(context),
        ),
        children: [
          // El h1 sr-only de la web.
          Semantics(header: true, label: t('Tu cuenta'), child: const SizedBox.shrink()),
          _ProfileHeader(
            name: name.isEmpty ? t('Tu cuenta') : name,
            email: email,
            edit: t('Editar'),
            onTap: () => _sheet(t('Tu perfil'), const ProfileSheet()),
          ),
          const SizedBox(height: RindeSpace.s6),
          _RowGroup(
            label: t('Tu app'),
            children: [
              // Si el bot no está para esta cuenta, la fila no sale (WhatsappLink.jsx no se muestra).
              if (whatsapp.value?.available ?? true)
                _Row(
                  icon: RindeIcons.messageCircle,
                  label: t('Anotar por WhatsApp'),
                  end: whatsapp.hasValue
                      ? _StatusChip(linked: linked, label: linked ? t('Conectado') : t('Conectar'))
                      : null,
                  onTap: () => _whatsapp(t),
                ),
              _AppearanceRow(
                label: t('Apariencia'),
                options: {
                  ThemeMode.light: t('Claro'),
                  ThemeMode.dark: t('Oscuro'),
                  ThemeMode.system: t('Auto'),
                },
                value: ref.watch(themeModeProvider),
                // La demostración no deja su tema en el dispositivo.
                onChanged: (mode) => demo
                    ? ref.read(themeModeProvider.notifier).set(mode)
                    : ref.read(themeModeProvider.notifier).choose(mode),
              ),
              _Row(
                icon: RindeIcons.bell,
                label: t('Avisos y recordatorios'),
                onTap: () => _sheet(t('Avisos y recordatorios'), const RemindersSheet()),
              ),
              _Row(
                icon: RindeIcons.tags,
                label: t('Mis categorías'),
                onTap: () => _sheet(t('Mis categorías'), const CategoriesSheet()),
              ),
              _Row(
                icon: RindeIcons.download,
                label: t('Exportar reportes'),
                onTap: () => context.push(Routes.export),
              ),
              _Row(
                icon: RindeIcons.globe,
                label: t('País'),
                end: Text(
                  '${country?.name(region.language) ?? region.country} · ${region.currency}',
                  overflow: TextOverflow.ellipsis,
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
                onTap: () => _sheet(t('Tu país'), const CountrySheet()),
              ),
              _Row(
                icon: RindeIcons.languages,
                label: t('Idioma'),
                end: Text(
                  language?.name ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
                onTap: () => _sheet(t('Idioma'), const LanguageSheet()),
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s6),
          _RowGroup(
            label: t('Ayuda'),
            children: [
              _Row(
                icon: RindeIcons.graduationCap,
                label: t('Ver el tutorial otra vez'),
                onTap: () {
                  ref.read(tourRequestedProvider.notifier).request();
                  context.go(Routes.app);
                },
              ),
            ],
          ),
          const SizedBox(height: RindeSpace.s6),
          RindeButton(
            label: t('Cerrar sesión'),
            pill: true,
            leading: const RindeIcon(RindeIcons.logOut, size: 18, color: RindeBrand.white),
            onPressed: () => _sheet(t('¿Cerrar sesión?'), const SignOutSheet()),
          ),
          const SizedBox(height: RindeSpace.s1),
          Center(
            child: TextButton(
              onPressed: () => _sheet(t('¿Eliminar tu cuenta?'), const DeleteAccountSheet()),
              style: TextButton.styleFrom(
                foregroundColor: p.negative,
                minimumSize: const Size(RindeSize.tapTarget, RindeSize.tapTarget),
                textStyle: RindeType.label,
              ),
              child: Text(t('Eliminar cuenta')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quién eres: inicial, nombre y correo; tocarlo abre «Tu perfil».
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.email, required this.edit, required this.onTap});
  final String name;
  final String email;
  final String edit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: '$name, $email. $edit',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: RindeRadius.brX2,
        child: Row(
          children: [
            ProfileInitial(name: name, email: email),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RindeType.title.copyWith(fontSize: 20, color: p.ink),
                  ),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RindeType.small.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: RindeSpace.s2),
            Text(
              edit,
              style: RindeType.label.copyWith(color: p.brand, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Círculo con la inicial (getInitial de la web), en orquídea.
class ProfileInitial extends StatelessWidget {
  const ProfileInitial({super.key, required this.name, required this.email});
  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final source = name.isNotEmpty ? name : (email.isNotEmpty ? email : '?');
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: RindeBrand.orchid, shape: BoxShape.circle),
        child: Text(
          source.characters.first.toUpperCase(),
          style: RindeType.headline.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: RindeBrand.obsidian,
          ),
        ),
      ),
    );
  }
}

/// Grupo de filas en una tarjeta, con su nombre arriba (RowGroup de la web).
class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(RindeSpace.s1, 0, RindeSpace.s1, RindeSpace.s2),
          child: Semantics(
            header: true,
            child: Text(label, style: RindeType.label.copyWith(color: p.inkMuted)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: RindeRadius.brX2,
            border: Border.all(color: p.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila: ícono, texto, algo a la derecha (estado o valor) y la flecha.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.end});
  final RindeIcons icon;
  final String label;
  final VoidCallback onTap;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            RindeIcon(icon, color: p.ink.withValues(alpha: 0.7)),
            const SizedBox(width: RindeSpace.s3),
            Expanded(
              child: Text(label, style: RindeType.control.copyWith(color: p.ink)),
            ),
            if (end case final end?) ...[const SizedBox(width: RindeSpace.s2), Flexible(child: end)],
            const SizedBox(width: RindeSpace.s2),
            RindeIcon(RindeIcons.chevronRight, size: 18, color: p.ink.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

/// Apariencia: el tema se cambia aquí mismo. Si no cabe al lado (pantalla angosta o letra grande), el
/// selector baja debajo del nombre.
class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Map<ThemeMode, String> options;
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _selectorWidth = 188.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = Row(
      children: [
        RindeIcon(RindeIcons.palette, color: p.ink.withValues(alpha: 0.7)),
        const SizedBox(width: RindeSpace.s3),
        Expanded(
          child: Text(label, style: RindeType.control.copyWith(color: p.ink)),
        ),
      ],
    );
    final selector = RindeSegmented<ThemeMode>(
      semanticLabel: label,
      options: options,
      value: value,
      onChanged: onChanged,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Lo que necesita la etiqueta (ícono, espacio y unas 9 letras) a la escala de letra actual.
        final inline =
            constraints.maxWidth >= _selectorWidth + 32 + MediaQuery.textScalerOf(context).scale(110);
        if (inline) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: RindeSpace.s2),
                SizedBox(width: _selectorWidth, child: selector),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: RindeSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: RindeSpace.s3),
              selector,
            ],
          ),
        );
      },
    );
  }
}

/// «Conectado» con su punto verde, o «Conectar».
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.linked, required this.label});
  final bool linked;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: RindeSpace.s1),
      decoration: BoxDecoration(
        color: linked ? RindeBrand.success.withValues(alpha: 0.15) : p.wash,
        borderRadius: BorderRadius.circular(RindeRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (linked) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: RindeBrand.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: RindeType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: linked ? p.positive : p.ink.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «¿Cerrar sesión?» con su explicación, «Cancelar» y «Cerrar sesión».
class SignOutSheet extends ConsumerStatefulWidget {
  const SignOutSheet({super.key});

  @override
  ConsumerState<SignOutSheet> createState() => _SignOutSheetState();
}

class _SignOutSheetState extends ConsumerState<SignOutSheet> {
  bool _leaving = false;

  Future<void> _signOut() async {
    // Avisar al servidor puede tardar unos segundos si está dormido; la salida en el teléfono es segura.
    setState(() => _leaving = true);
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return PopScope(
      canPop: !_leaving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Lo que anotaste sin conexión se queda en este celular y se sube cuando vuelvas a entrar.'),
            style: RindeType.control.copyWith(
              color: p.ink.withValues(alpha: 0.7),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: RindeSpace.s5),
          Row(
            children: [
              Expanded(
                child: RindeButton(
                  label: t('Cancelar'),
                  variant: RindeButtonVariant.outline,
                  onPressed: _leaving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: RindeSpace.s3),
              Expanded(
                child: RindeButton(
                  label: t('Cerrar sesión'),
                  loading: _leaving,
                  loadingLabel: t('Cerrando sesión…'),
                  onPressed: _signOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
