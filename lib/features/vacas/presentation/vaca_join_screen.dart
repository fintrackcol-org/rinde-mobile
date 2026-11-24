import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_spinner.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeSurface;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../shell/presentation/pushed_frame.dart';
import '../application/vacas_providers.dart';
import '../application/vacas_writer.dart';
import '../domain/vaca_rules.dart';
import 'vacas_screens.dart' show VacaArrival;

/// `/app/vacas/unirse/:code` (VacaJoin.jsx): la vaca y quién invita antes de unirse. Se llega con
/// «Tengo un código»; el enlace de invitación abre la web (los enlaces profundos del sistema quedan
/// pendientes). Si ya se es miembro, pasa directo al detalle.
class VacaJoinScreen extends ConsumerStatefulWidget {
  const VacaJoinScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<VacaJoinScreen> createState() => _VacaJoinScreenState();
}

class _VacaJoinScreenState extends ConsumerState<VacaJoinScreen> {
  bool _joining = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final vaca = await ref.read(vacasWriterProvider).join(widget.code);
      if (mounted) context.pushReplacement(Routes.vaca(vaca.id), extra: VacaArrival.joined);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = moneyErrorText(e, ref.read(trProvider));
          _joining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final async = ref.watch(
      invitationPreviewProvider((ref.watch(accountProvider), widget.code.toUpperCase())),
    );
    final preview = async.value;
    if (preview != null && preview.isMember) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement(Routes.vaca(preview.id));
      });
    }
    void toList() => context.canPop() ? context.pop() : context.go(Routes.vacas);

    final Widget body;
    if (preview == null && async.hasError) {
      body = Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              moneyErrorText(async.error!, t),
              textAlign: TextAlign.center,
              style: RindeType.bodyMedium.copyWith(color: p.negative),
            ),
          ),
          const SizedBox(height: RindeSpace.s2),
          Text(
            t('Pídele a quien te invitó el enlace o el código nuevo.'),
            textAlign: TextAlign.center,
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s5),
          RindeButton(label: t('Ir a mis vacas'), variant: RindeButtonVariant.outline, onPressed: toList),
        ],
      );
    } else if (preview == null) {
      body = Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RindeSpinner(size: 16, color: p.inkMuted),
            const SizedBox(width: RindeSpace.s2),
            Flexible(
              child: Text(t('Cargando la invitación…'), style: RindeType.small.copyWith(color: p.inkMuted)),
            ),
          ],
        ),
      );
    } else {
      final region = ref.watch(appRegionProvider);
      final today = isoDay(ref.watch(todayProvider));
      Widget stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(label, style: RindeType.caption.copyWith(color: p.inkMuted)),
            MoneyText(
              value,
              money: money,
              style: RindeType.bodyMedium.w(FontWeight.w600).tabular.copyWith(color: p.ink),
            ),
          ],
        ),
      );
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            preview.createdBy != null
                ? t('{createdBy} te invitó a', {'createdBy': preview.createdBy})
                : t('Te invitaron a'),
            textAlign: TextAlign.center,
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s1),
          Semantics(
            header: true,
            child: Text(
              preview.name,
              textAlign: TextAlign.center,
              style: RindeType.headline.copyWith(color: p.ink),
            ),
          ),
          if (preview.description case final description?) ...[
            const SizedBox(height: RindeSpace.s2),
            Text(
              description,
              textAlign: TextAlign.center,
              style: RindeType.body.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: RindeSpace.s5),
          DecoratedBox(
            decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.05), borderRadius: RindeRadius.brXl),
            child: Padding(
              padding: const EdgeInsets.all(RindeSpace.s4),
              child: Row(
                children: [
                  stat(t('Meta'), pesos(money, preview.goal)),
                  stat(t('Reunido'), pesos(money, preview.total)),
                  stat(t('Miembros'), '${preview.membersCount}'),
                ],
              ),
            ),
          ),
          if (preview.deadline case final deadline?) ...[
            const SizedBox(height: RindeSpace.s3),
            Text(
              '${t('Fecha límite:')} ${vacaDate(deadline, today, region)}',
              textAlign: TextAlign.center,
              style: RindeType.small.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: RindeSpace.s4),
          Text(
            t(
              'Los demás verán tu nombre y tus aportes. Cada aporte también queda como un gasto en tus movimientos.',
            ),
            textAlign: TextAlign.center,
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: RindeSpace.s3),
            RindeBanner(message: error),
          ],
          const SizedBox(height: RindeSpace.s5),
          RindeButton(
            label: t('Unirme a la vaca'),
            loading: _joining,
            loadingLabel: t('Unirme a la vaca'),
            onPressed: _join,
          ),
          const SizedBox(height: RindeSpace.s2),
          RindeButton(
            label: t('Ahora no'),
            variant: RindeButtonVariant.outline,
            onPressed: _joining ? null : toList,
          ),
        ],
      );
    }

    return PushedFrame(
      fallback: Routes.vacas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s4, RindeSpace.s4, RindeSpace.s6),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 512),
              child: HomeSurface(
                radius: RindeRadius.brX3,
                padding: const EdgeInsets.all(RindeSpace.s5),
                child: Column(
                  children: [
                    RindeIcon(RindeIcons.users, size: 48, color: p.brand),
                    const SizedBox(height: RindeSpace.s4),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
