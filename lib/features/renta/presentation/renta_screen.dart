import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../shell/presentation/pushed_frame.dart';

/// Páginas oficiales de la DIAN (DIAN_LINKS de Renta.jsx). Son las que no cambian de un año a otro:
/// Rinde no muestra topes ni fechas, que cambian cada año y solo la DIAN mantiene al día.
const _dianLinks = [
  (
    title: '¿Debo declarar renta?',
    detail: 'Consulta tu caso en el servicio oficial de la DIAN.',
    label: 'Consultar en la DIAN',
    href: 'https://consultarenta.dian.gov.co/',
    icon: RindeIcons.fileSearch,
  ),
  (
    title: '¿Qué día me toca?',
    detail: 'Las fechas dependen de los últimos dígitos de tu documento.',
    label: 'Ver el calendario tributario',
    href: 'https://www.dian.gov.co/Paginas/CalendarioTributario.aspx',
    icon: RindeIcons.calendarDays,
  ),
];

Future<void> _open(String href) => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);

/// `/app/renta` (Renta.jsx): lleva a los servicios oficiales de la DIAN para la declaración de renta.
/// Sin pantalla anterior, atrás va a Consejos (backPath de la web).
class RentaScreen extends ConsumerWidget {
  const RentaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return PushedFrame(
      title: t('Renta y DIAN'),
      fallback: Routes.insights,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
        children: [
          Text(
            t('Averigua si te toca declarar y cuándo.'),
            style: RindeType.body.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s5),
          for (final link in _dianLinks) ...[
            RindeCard(
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
                        child: RindeIcon(link.icon, color: p.brand),
                      ),
                      const SizedBox(width: RindeSpace.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(t(link.title), style: RindeType.title.copyWith(color: p.ink)),
                            ),
                            const SizedBox(height: RindeSpace.s1),
                            Text(t(link.detail), style: RindeType.small.copyWith(color: p.inkMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RindeSpace.s4),
                  Semantics(
                    label: '${t(link.label)} ${t('(abre la página de la DIAN)')}',
                    excludeSemantics: true,
                    button: true,
                    link: true,
                    onTap: () => _open(link.href),
                    child: RindeButton(
                      label: t(link.label),
                      variant: RindeButtonVariant.outline,
                      leading: const RindeIcon(RindeIcons.externalLink, size: 16),
                      onPressed: () => _open(link.href),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RindeSpace.s5),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: RindeIcon(RindeIcons.lock, size: 16, color: p.inkMuted),
              ),
              const SizedBox(width: RindeSpace.s2),
              Expanded(
                child: Text(
                  t(
                    'Tu documento lo escribes en la página de la DIAN, nunca en Rinde. Esta guía no reemplaza a un contador.',
                  ),
                  style: RindeType.small.copyWith(color: p.inkMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
