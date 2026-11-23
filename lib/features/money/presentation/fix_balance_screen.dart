import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/money_text.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_money_field.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../home/application/home_providers.dart';
import '../../home/data/home_models.dart' show readMoney;
import '../../home/presentation/widgets/home_money.dart';
import '../../shell/presentation/pushed_frame.dart';
import '../application/money_providers.dart';
import '../application/money_writer.dart';
import '../data/money_models.dart';
import 'widgets/income_overview_card.dart' show moneyOf;

/// Qué le falta al saldo escrito, o null si se puede guardar. El 0 es un saldo válido.
String? balanceProblem(String raw, Tr t, MoneyFormat format) {
  final value = moneyValue(raw);
  if (value == null) return t('Escribe cuánta plata tienes.');
  if (value > maxAmount) {
    return t('Supera el máximo permitido ({MAX_AMOUNT}).', {'MAX_AMOUNT': format.money(maxAmount)});
  }
  return null;
}

/// `/app/mi-plata/corregir` (FixBalance.jsx): decir cuánta plata hay de verdad. Se aparta de la web en
/// el campo: el teclado del sistema con [RindeMoneyField] (acepta 0 y decimales) en vez del teclado
/// propio, y «Guardar saldo» nunca se apaga: si falta el monto, lo dice en el campo.
///
/// Escribir el saldo solo se permite si [canWriteBalance]: en una cuenta real, mientras el servidor no
/// mande la versión del perfil, la pantalla muestra la plata y dice dónde corregirla.
class FixBalanceScreen extends ConsumerStatefulWidget {
  const FixBalanceScreen({super.key});

  @override
  ConsumerState<FixBalanceScreen> createState() => _FixBalanceScreenState();
}

class _FixBalanceScreenState extends ConsumerState<FixBalanceScreen> {
  final _focus = FocusNode();

  /// El perfil con que se llenó el campo: el que se compara antes de enviar.
  MoneyProfile? _seed;
  String _raw = '';
  String? _fieldError;
  String? _error;
  bool _saving = false;

  /// Hay un perfil guardado de antes (p. ej. de Mi plata) que todavía no se ha vuelto a leer.
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    // Como FixBalance.jsx, se lee al abrir: un movimiento (de aquí, la web o el bot) cambia la plata
    // sin tocar lo que compara la comprobación previa, y el campo traería una cifra vieja. Si ya había
    // uno guardado, no se muestra y se pide después del primer cuadro (durante la construcción no se
    // puede invalidar).
    final profile = moneyProfileProvider(ref.read(accountProvider));
    if (!ref.read(profile.exists)) return;
    _stale = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(profile, asReload: true);
      setState(() => _stale = false);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String _message(ApiException e, Tr t) {
    return t(
      e.messageFor(
        byCode: const {
          ApiCodes.unauthorized: ApiMessages.sessionExpired,
          ApiCodes.tokenExpired: ApiMessages.sessionExpired,
          // TEXTO NUEVO
          ApiCodes.profileChanged: 'Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.',
        },
        fallback: ApiMessages.generic,
      ),
    );
  }

  /// [value]: el de «Usar lo que dicen mis movimientos»; si no, lo escrito.
  Future<void> _save(MoneyProfile opened, {num? value}) async {
    if (_saving) return;
    final t = ref.read(trProvider);
    if (value == null) {
      final problem = balanceProblem(_raw, t, formatFor(ref.read(appRegionProvider)));
      if (problem != null) {
        setState(() => _fieldError = problem);
        _focus.requestFocus();
        return;
      }
    }
    final balance = value ?? moneyValue(_raw)!;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await ref.read(moneyWriterProvider).saveBalance(opened, balance);
      if (!mounted) return;
      // Abierta desde Mi plata, se vuelve a ella (ya recargada) y no quedan dos seguidas; si no, como
      // el `replace` de la web: Atrás no vuelve a esta pantalla.
      final matches = GoRouter.of(context).routerDelegate.currentConfiguration.matches;
      if (matches.length > 1 && matches[matches.length - 2].matchedLocation == Routes.myMoney) {
        context.pop();
      } else {
        context.pushReplacement(Routes.myMoney);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.fields['balance'];
      setState(() {
        _fieldError = field == null ? null : t(field);
        _error = field != null && e.fields.length == 1 ? null : _message(e, t);
      });
      if (field != null) _focus.requestFocus();
    } catch (_) {
      if (mounted) setState(() => _error = t(ApiMessages.generic));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final format = formatFor(region);
    final account = ref.watch(accountProvider);
    final async = ref.watch(moneyProfileProvider(account));
    final planAsync = ref.watch(homePlanProvider(account));
    final money = moneyOf(ref);
    // Solo un perfil vigente: con uno viejo la comprobación previa siempre daría «cambió».
    final profile = _stale || async.isLoading || async.hasError ? null : async.value;
    if (profile != null && !identical(profile, _seed)) {
      // Lo releído (al abrir, tras un conflicto o una duda) llena el campo de nuevo.
      _seed = profile;
      final current = profile.money;
      _raw = current == null || current < 0 ? '' : '${readMoney(current)}';
      _fieldError = null;
    }

    final children = <Widget>[
      Semantics(
        header: true,
        child: Text(t('¿Cuánta plata tienes?'), style: RindeType.headline.copyWith(color: p.ink)),
      ),
      const SizedBox(height: RindeSpace.s1),
      Text(
        t('Suma banco, Nequi y efectivo. Desde ahí sumamos y restamos lo que anotes.'),
        style: RindeType.lead.copyWith(color: p.ink.withValues(alpha: 0.7)),
      ),
      const SizedBox(height: RindeSpace.s1),
      Text(
        t('No la anotes como ingreso: si no, tus reportes dirán que ese mes te entró esa plata.'),
        style: RindeType.small.copyWith(color: p.inkMuted),
      ),
      const SizedBox(height: RindeSpace.s5),
      // Tras un conflicto o una duda se relee: si tarda o falla, lo del guardado se sigue viendo.
      if (profile == null && _error != null) ...[
        RindeBanner(message: _error!),
        const SizedBox(height: RindeSpace.s3),
      ],
    ];

    if (profile == null && async.hasError && !async.isLoading && !_stale) {
      children.add(
        RindeBanner(
          message: t(
            async.error is ApiException
                ? (async.error! as ApiException).messageFor(fallback: ApiMessages.generic)
                : ApiMessages.generic,
          ),
          action: RindeTextLink(
            label: t('Reintentar'),
            onPressed: () => ref.invalidate(moneyProfileProvider(account)),
          ),
        ),
      );
    } else if (profile == null) {
      children.add(
        Semantics(
          container: true,
          label: t('Cargando…'),
          child: const ExcludeSemantics(
            child: RindeSkeleton(width: double.infinity, height: RindeSize.field),
          ),
        ),
      );
    } else if (!canWriteBalance(account, profile)) {
      // Solo lectura: la plata de hoy y dónde corregirla, sin campo ni «Guardar».
      final current = profile.money;
      children.addAll([
        if (current == null) ...[
          ExcludeSemantics(
            child: Text('—', style: RindeType.amount.copyWith(color: p.ink)),
          ),
          Text(
            t('Todavía no sabemos cuánta plata tienes.'),
            style: RindeType.small.copyWith(color: p.inkMuted),
          ),
        ] else
          MoneyText(
            money(current),
            money: money,
            fit: true,
            style: RindeType.amount.copyWith(color: p.ink),
          ),
        const SizedBox(height: RindeSpace.s4),
        RindeBanner(
          tone: RindeBannerTone.info,
          // TEXTO NUEVO
          message: t(
            'Por ahora corrige tu saldo en la web de Rinde, con tu misma cuenta. En la app llega pronto.',
          ),
        ),
      ]);
    } else {
      final plan = planAsync.hasError ? null : planAsync.value;
      final ledger = plan != null && plan.ready ? plan.ledger : null;
      // Como la web: solo si los movimientos dicen otra cosa que la plata de hoy.
      final useLedger = ledger != null && ledger.round() > 0 && ledger.round() != profile.money?.round();
      final hint = describeAmount(_raw, format: format, inPesos: region.currency == 'COP', t: t);
      children.addAll([
        RindeMoneyField(
          value: _raw,
          onChanged: (raw) => setState(() {
            _raw = raw;
            _fieldError = null;
          }),
          format: format,
          semanticLabel: t('¿Cuánta plata tienes?'),
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.done,
          errorText: _fieldError,
          message: hint?.message,
          messageTone: hint?.tone ?? RindeMoneyMessageTone.info,
        ),
        if (useLedger) ...[
          const SizedBox(height: RindeSpace.s3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RindeButton(
              label: t('Usar lo que dicen mis movimientos'),
              variant: RindeButtonVariant.soft,
              size: RindeButtonSize.sm,
              pill: true,
              expand: false,
              onPressed: _saving ? null : () => _save(profile, value: ledger),
            ),
          ),
        ],
        if (_error case final error?) ...[const SizedBox(height: RindeSpace.s3), RindeBanner(message: error)],
        const SizedBox(height: RindeSpace.s6),
        RindeButton(label: t('Guardar saldo'), loading: _saving, onPressed: () => _save(profile)),
      ]);
    }

    return PushedFrame(
      title: t('Corregir saldo'),
      fallback: Routes.myMoney,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s4, RindeSpace.s4, RindeSpace.s6),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}
