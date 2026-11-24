import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../../design/tokens/rinde_colors.dart';
import '../../../design/tokens/rinde_layout.dart';
import '../../../design/tokens/rinde_typography.dart';
import '../../../design/widgets/rinde_button.dart';
import '../../../design/widgets/rinde_feedback.dart';
import '../../../design/widgets/rinde_icon.dart';
import '../../../design/widgets/rinde_segmented.dart';
import '../../../design/widgets/rinde_skeleton.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../debts/presentation/widgets/debt_date_field.dart';
import '../../debts/presentation/widgets/debt_payment_sheet.dart' show DebtMovementBox;
import '../../home/application/home_providers.dart' show todayProvider;
import '../../home/domain/home_dates.dart';
import '../../home/presentation/widgets/home_money.dart';
import '../../home/presentation/widgets/home_tap.dart' show HomeTap;
import '../../money/presentation/widgets/income_overview_card.dart' show moneyOf;
import '../../money/presentation/widgets/paid_button.dart' show moneyErrorText;
import '../../movements/presentation/list/movement_dates.dart' show MovementPeriod, periodRange;
import '../../shell/presentation/pushed_frame.dart';
import '../data/export_repository.dart';

/// Para qué sirve cada formato (FORMATS de Export.jsx; en el celular la web oculta la lista de qué trae).
const _purpose = {
  ExportFormat.xlsx: 'Analiza y personaliza',
  ExportFormat.pdf: 'Entiende y comparte',
  ExportFormat.csv: 'Lleva tus datos',
};
const _formatIcon = {
  ExportFormat.xlsx: RindeIcons.fileSpreadsheet,
  ExportFormat.pdf: RindeIcons.fileText,
  ExportFormat.csv: RindeIcons.sheet,
};

enum _Period { thisMonth, lastMonth, thisYear, custom }

const _periodLabel = {
  _Period.thisMonth: 'Este mes',
  _Period.lastMonth: 'Mes pasado',
  _Period.thisYear: 'Este año',
  _Period.custom: 'Personalizado',
};

/// Vista previa de `(cuenta, desde, hasta)`: se vuelve a pedir al cambiar el periodo, no el formato
/// (las cifras son las mismas).
final _previewProvider = FutureProvider.autoDispose.family<ReportPreviewData, (Session?, String, String)>((
  ref,
  key,
) {
  if (ref.watch(accountProvider) != key.$1) return Completer<ReportPreviewData>().future;
  return ref.watch(exportRepositoryProvider).preview(key.$2, key.$3);
});

/// «1 de octubre de 2026» (dateText de la web).
String _dateText(String iso, Region region) => region.language == 'en'
    ? '${dayAndMonth(iso, region)}, ${iso.substring(0, 4)}'
    : '${dayAndMonth(iso, region)} de ${iso.substring(0, 4)}';

/// `/app/transacciones/exportar` (Export.jsx, FT-0012): descarga el reporte del periodo en Excel, PDF
/// o CSV y lo abre en la hoja de compartir del teléfono (guardarlo en Archivos o Drive, abrirlo en
/// Excel, enviarlo). Vista previa y archivo los arma el servidor. Si el periodo no tiene movimientos,
/// lo dice en lugar de bajar un archivo vacío (REQ-033). Sin pantalla anterior, atrás va a Yo.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final _button = GlobalKey();
  var _format = ExportFormat.xlsx;
  var _period = _Period.thisMonth;
  String? _from;
  String? _to;
  var _detail = true;
  var _busy = false;
  String? _error;
  String? _done;

  /// Al cambiar cualquier opción se borra el resultado anterior, para no mostrar uno que ya no aplica.
  void _change(VoidCallback change) => setState(() {
    change();
    _error = null;
    _done = null;
  });

  ({String from, String to}) _range(DateTime today) {
    String iso(DateTime d) => isoDay(d);
    switch (_period) {
      case _Period.thisMonth:
        final r = periodRange(MovementPeriod.month, today);
        return (from: iso(r.from), to: iso(r.to));
      case _Period.lastMonth:
        final r = periodRange(MovementPeriod.month, DateTime(today.year, today.month - 1));
        return (from: iso(r.from), to: iso(r.to));
      case _Period.thisYear:
        return (from: '${today.year}-01-01', to: iso(today));
      case _Period.custom:
        return (from: _from ?? '${isoMonth(today)}-01', to: _to ?? iso(today));
    }
  }

  Future<void> _download(({String from, String to}) range, String rangeText) async {
    final t = ref.read(trProvider);
    final box = _button.currentContext?.findRenderObject() as RenderBox?;
    // El formato puede cambiar mientras baja: se comparte con el que se pidió.
    final format = _format;
    final userId = ref.read(accountProvider)?.user.id;
    _change(() => _busy = true);
    Directory? folder;
    try {
      final file = await ref
          .read(exportRepositoryProvider)
          .export(format, range.from, range.to, detail: _detail);
      // Salió de la pantalla o de la cuenta mientras bajaba: el reporte no se abre encima de otra.
      if (!mounted || ref.read(accountProvider)?.user.id != userId) return;
      // Un archivo propio (XFile.fromData lo deja en la carpeta temporal para siempre) que se borra al
      // terminar: Android lo copia antes de enviarlo y en iOS share() espera a que se cierre la hoja.
      folder = await (await getTemporaryDirectory()).createTemp('rinde-export-');
      final path = '${folder.path}${Platform.pathSeparator}${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: format.mime)],
          // El iPad abre la hoja junto al botón.
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted && result.status != ShareResultStatus.dismissed) {
        setState(() => _done = t('Descargado {filename}', {'filename': file.filename}));
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is ApiException && e.code == ApiCodes.noData
            ? t('No tienes movimientos {rangeText}. Prueba con otro periodo.', {'rangeText': rangeText})
            : moneyErrorText(e, t),
      );
    } finally {
      unawaited(folder?.delete(recursive: true).then((_) {}, onError: (_) {}));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final region = ref.watch(appRegionProvider);
    final account = ref.watch(accountProvider);
    final range = _range(ref.watch(todayProvider));
    final rangeError = _period != _Period.custom
        ? null
        : range.from.compareTo(range.to) > 0
        ? t('La fecha "Desde" debe ser anterior o igual a "Hasta".')
        : null;
    final rangeText = range.from == range.to
        // TEXTO NUEVO: la web deja «el» sin traducir.
        ? t('el {date}', {'date': _dateText(range.from, region)})
        : t('del {from} al {to}', {'from': _dateText(range.from, region), 'to': _dateText(range.to, region)});
    final month = periodRange(MovementPeriod.month, DateTime.parse(range.from));
    final wholeMonth = range.from == isoDay(month.from) && range.to == isoDay(month.to);
    final filename = rangeError != null
        ? 'rinde${_format.extension}'
        : 'rinde_${wholeMonth ? range.from.substring(0, 7) : '${range.from}_${range.to}'}${_format.extension}';
    final preview = rangeError == null ? ref.watch(_previewProvider((account, range.from, range.to))) : null;
    final previewError = preview?.value == null && preview?.isLoading == false ? preview?.error : null;
    final empty = previewError is ApiException && previewError.code == ApiCodes.noData;
    final canDownload = rangeError == null && !_busy && !empty && preview?.isLoading == false;

    final Widget previewBody;
    if (rangeError != null) {
      previewBody = _PreviewMessage(
        icon: RindeIcons.calendarRange,
        title: t('Falta el periodo'),
        text: rangeError,
      );
    } else if (empty) {
      previewBody = _PreviewMessage(
        icon: RindeIcons.inbox,
        title: t('No hay movimientos en este periodo'),
        text: '${t('No tienes movimientos')} $rangeText${t('. Prueba con otro periodo.')}',
      );
    } else if (previewError is ApiException && previewError.isNetwork) {
      previewBody = _PreviewMessage(
        icon: RindeIcons.wifiOff,
        title: t('Sin conexión'),
        text: t(
          'El reporte se arma en el servidor. Cuando vuelvas a tener conexión verás aquí la vista previa.',
        ),
      );
    } else if (previewError != null) {
      previewBody = _PreviewMessage(
        icon: RindeIcons.refreshCw,
        title: t('No pudimos armar la vista previa'),
        text: '${moneyErrorText(previewError, t)} ${t('Igual puedes intentar descargar el archivo.')}',
        action: RindeButton(
          label: t('Reintentar'),
          variant: RindeButtonVariant.soft,
          size: RindeButtonSize.md,
          expand: false,
          onPressed: () => ref.invalidate(_previewProvider((account, range.from, range.to))),
        ),
      );
    } else if (preview?.value case final data?) {
      previewBody = _Preview(data: data, format: _format, detail: _detail);
    } else {
      previewBody = Semantics(
        label: t('Cargando la vista previa'),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RindeSpace.s3,
          children: [
            RindeSkeleton(width: double.infinity, height: 48, radius: RindeRadius.xl),
            RindeSkeleton(width: double.infinity, height: 56, radius: RindeRadius.sm),
            RindeSkeleton(width: double.infinity, height: 112, radius: RindeRadius.xl),
          ],
        ),
      );
    }

    return PushedFrame(
      title: t('Exportar movimientos'),
      fallback: Routes.account,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RindeSpace.s4, RindeSpace.s2, RindeSpace.s4, RindeSpace.s6),
        children: [
          Text(
            t(
              'Tus números, más claros que nunca: elige cómo llevártelos y mira el reporte antes de descargarlo.',
            ),
            style: RindeType.body.copyWith(color: p.inkMuted),
          ),
          const SizedBox(height: RindeSpace.s6),
          RindeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepTitle(number: 1, title: t('Elige el formato')),
                Semantics(
                  container: true,
                  label: t('Formato del archivo'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: RindeSpace.s3,
                    children: [
                      for (final f in ExportFormat.values)
                        _FormatOption(
                          format: f,
                          selected: f == _format,
                          onTap: () => _change(() => _format = f),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RindeSpace.s6),
          RindeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepTitle(number: 2, title: t('Elige el periodo')),
                RindeSegmented<_Period>(
                  semanticLabel: t('Periodo'),
                  options: {for (final e in _periodLabel.entries) e.key: t(e.value)},
                  value: _period,
                  onChanged: (v) => _change(() {
                    _period = v;
                    // Personalizado empieza en el mes hasta hoy, como la web.
                    _from = _to = null;
                  }),
                ),
                if (_period == _Period.custom) ...[
                  const SizedBox(height: RindeSpace.s4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: RindeSpace.s3,
                    children: [
                      Expanded(
                        child: DebtDateField(
                          label: t('Desde'),
                          value: range.from,
                          onChanged: (v) => _change(() => _from = v),
                        ),
                      ),
                      Expanded(
                        child: DebtDateField(
                          label: t('Hasta'),
                          value: range.to,
                          onChanged: (v) => _change(() => _to = v),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: RindeSpace.s4),
                Semantics(
                  liveRegion: rangeError != null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: RindeIcon(
                          RindeIcons.calendarRange,
                          size: 16,
                          color: rangeError != null ? p.negative : p.inkMuted,
                        ),
                      ),
                      const SizedBox(width: RindeSpace.s2),
                      Expanded(
                        child: Text(
                          rangeError ?? '${t('Incluye tus movimientos')} $rangeText.',
                          style: RindeType.small.copyWith(
                            color: rangeError != null ? p.negative : p.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Oculta pero viva fuera del PDF: la casilla guarda lo que se marcó, como la web.
                Visibility(
                  visible: _format == ExportFormat.pdf,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: RindeSpace.s5),
                    child: DebtMovementBox(
                      title: t('Incluir el detalle de movimientos'),
                      detail: t('Quítalo para compartir solo el resumen, sin mostrar cada compra.'),
                      enabled: !_busy,
                      onChanged: (v) => _change(() => _detail = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RindeSpace.s6),
          RindeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconBox(_formatIcon[_format]!, solid: false),
                    const SizedBox(width: RindeSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              '${t('Vista previa ·')} ${_format.label}',
                              style: RindeType.label.copyWith(color: p.inkMuted),
                            ),
                          ),
                          Text(
                            filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RindeSpace.s5),
                previewBody,
                const SizedBox(height: RindeSpace.s5),
                Divider(height: 1, thickness: 1, color: p.line),
                const SizedBox(height: RindeSpace.s5),
                RindeButton(
                  key: _button,
                  label: t('Descargar {label}', {'label': _format.label}),
                  loading: _busy,
                  loadingLabel: t('Preparando archivo…'),
                  leading: const RindeIcon(RindeIcons.download, size: 18, color: Colors.white),
                  onPressed: canDownload ? () => _download(range, rangeText) : null,
                ),
                if (_done case final done?) ...[
                  const SizedBox(height: RindeSpace.s3),
                  RindeBanner(tone: RindeBannerTone.success, message: done),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: RindeSpace.s3),
                  RindeBanner(message: error),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: RindeSpace.s4),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: p.brandSolid, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: RindeType.caption.w(FontWeight.w700).copyWith(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink)),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {required this.solid});
  final RindeIcons icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: solid ? p.brandSolid : p.brandSoft, borderRadius: RindeRadius.brXl),
      alignment: Alignment.center,
      child: RindeIcon(icon, color: solid ? Colors.white : p.brand),
    );
  }
}

/// Una tarjeta para elegir el formato: se lee como opción de un grupo (el radio de la web).
class _FormatOption extends ConsumerWidget {
  const _FormatOption({required this.format, required this.selected, required this.onTap});

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: HomeTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: RindeMotion.fast,
          padding: const EdgeInsets.all(RindeSpace.s4),
          decoration: BoxDecoration(
            color: selected ? p.brandSoft.withValues(alpha: 0.5) : Colors.transparent,
            borderRadius: RindeRadius.brX2,
            border: Border.all(color: selected ? p.brand : p.line, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              _IconBox(_formatIcon[format]!, solid: selected),
              const SizedBox(width: RindeSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: t(format.label),
                            style: RindeType.title.copyWith(color: p.ink),
                          ),
                          TextSpan(
                            text: '  ${format.extension}',
                            style: RindeType.caption.copyWith(color: p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      t(_purpose[format]!),
                      style: RindeType.small.copyWith(color: p.ink.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              ExcludeSemantics(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? p.brandSolid : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? p.brandSolid : p.ink.withValues(alpha: 0.25)),
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? const RindeIcon(RindeIcons.checkBold, size: 12, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensaje que ocupa el lugar de la vista previa cuando no hay nada que mostrar.
class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.icon, required this.title, required this.text, this.action});

  final RindeIcons icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: RindeRadius.brXl,
          border: Border.all(color: p.lineStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s4, vertical: RindeSpace.s8),
          child: Column(
            spacing: RindeSpace.s2,
            children: [
              _IconBox(icon, solid: false),
              Text(
                title,
                textAlign: TextAlign.center,
                style: RindeType.bodyMedium.w(FontWeight.w600).copyWith(color: p.ink),
              ),
              Text(
                text,
                textAlign: TextAlign.center,
                style: RindeType.small.copyWith(color: p.inkMuted),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que traerá el archivo, con las cifras de GET /reports/preview: los cuatro indicadores, los gastos
/// por categoría y, en el PDF, «Lo que dicen tus números» (ReportPreview.jsx, en corto).
class _Preview extends ConsumerWidget {
  const _Preview({required this.data, required this.format, required this.detail});

  final ReportPreviewData data;
  final ExportFormat format;
  final bool detail;

  static const _maxCategories = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(trProvider);
    final p = context.palette;
    final money = moneyOf(ref);
    final kpis = [
      (t('Ingresos'), money(data.income), p.positive.withValues(alpha: 0.1), p.positive),
      (t('Gastos'), money(data.expense), p.brandSoft, p.brand),
      (t('Balance neto'), money(data.balance), p.surfaceMuted, data.balance < 0 ? p.negative : p.ink),
      (t('Movimientos'), '${data.count}', p.surfaceMuted, p.ink),
    ];
    final shown = data.categories.take(_maxCategories).toList();
    Widget blockTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: RindeSpace.s2),
      child: Semantics(
        header: true,
        child: Text(text, style: RindeType.caption.w(FontWeight.w600).copyWith(color: p.brand)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dos por fila; cada celda crece con su texto (letra grande incluida).
        Wrap(
          runSpacing: RindeSpace.s2,
          children: [
            for (final (i, (label, value, background, color)) in kpis.indexed)
              FractionallySizedBox(
                widthFactor: 0.5,
                child: Padding(
                  // 8 entre las dos columnas.
                  padding: EdgeInsetsDirectional.only(
                    end: i.isEven ? RindeSpace.s1 : 0,
                    start: i.isOdd ? RindeSpace.s1 : 0,
                  ),
                  child: MergeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(RindeRadius.sm),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RindeSpace.s3,
                          vertical: RindeSpace.s2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: RindeType.caption.copyWith(color: p.inkMuted)),
                            MoneyText(
                              value,
                              money: money,
                              fit: true,
                              style: RindeType.control.w(FontWeight.w600).copyWith(color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: RindeSpace.s4),
        if (format == ExportFormat.pdf && data.findings.isNotEmpty) ...[
          blockTitle(t('Lo que dicen tus números')),
          for (final f in data.findings)
            Container(
              margin: const EdgeInsets.only(bottom: RindeSpace.s2),
              padding: const EdgeInsets.symmetric(horizontal: RindeSpace.s3, vertical: RindeSpace.s2),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(RindeRadius.sm),
                border: Border(left: BorderSide(color: p.brand, width: 2)),
              ),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.title, style: RindeType.caption.w(FontWeight.w600).copyWith(color: p.ink)),
                    const SizedBox(height: 2),
                    Text(f.detail, style: RindeType.caption.copyWith(color: p.inkMuted)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: RindeSpace.s2),
        ],
        blockTitle(t('Gastos por categoría')),
        if (shown.isEmpty)
          Text(t('Sin gastos en el periodo.'), style: RindeType.caption.copyWith(color: p.inkMuted))
        else ...[
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RindeType.caption.copyWith(color: p.ink),
                      ),
                    ),
                    const SizedBox(width: RindeSpace.s2),
                    Expanded(
                      flex: 4,
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 8,
                            child: ColoredBox(
                              color: p.surfaceMuted,
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: shown.first.amount > 0
                                    ? (c.amount / shown.first.amount).clamp(0.02, 1).toDouble()
                                    : 0.02,
                                child: ColoredBox(color: p.brand),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: RindeSpace.s2),
                    MoneyText(
                      money(c.amount),
                      money: money,
                      style: RindeType.caption.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          if (data.categories.length > _maxCategories)
            Text(
              '${t('y')} ${data.categories.length - _maxCategories} ${t('más en el archivo')}',
              style: RindeType.caption.copyWith(color: p.inkMuted),
            ),
        ],
        if (format == ExportFormat.pdf) ...[
          const SizedBox(height: RindeSpace.s3),
          Text(
            detail
                // TEXTO NUEVO: la web deja «tu movimiento» y «tus N movimientos» sin traducir.
                ? t('Después: movimiento del dinero, gastos destacados y el detalle de {v1}.', {
                    'v1': data.count == 1
                        ? t('tu movimiento')
                        : t('tus {count} movimientos', {'count': data.count}),
                  })
                : t('Después: movimiento del dinero y gastos destacados. Sin el detalle de movimientos.'),
            style: RindeType.caption.copyWith(color: p.inkMuted),
          ),
        ],
      ],
    );
  }
}
