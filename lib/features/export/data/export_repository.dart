import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../home/data/home_models.dart' show readList, readMap, readMoney;

/// Formatos que arma el servidor, con el tipo del archivo para compartirlo.
enum ExportFormat {
  xlsx('Excel', '.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  pdf('PDF', '.pdf', 'application/pdf'),
  csv('CSV', '.csv', 'text/csv');

  const ExportFormat(this.label, this.extension, this.mime);
  final String label;
  final String extension;
  final String mime;
}

/// GET /reports/preview: las cifras que traerán los archivos, del mismo modelo del servidor.
class ReportPreviewData {
  const ReportPreviewData({
    required this.income,
    required this.expense,
    required this.balance,
    required this.count,
    required this.categories,
    required this.findings,
  });

  factory ReportPreviewData.fromJson(Object? raw) {
    final json = readMap(raw);
    final totals = readMap(json['totals']);
    return ReportPreviewData(
      income: readMoney(totals['income']) ?? 0,
      expense: readMoney(totals['expense']) ?? 0,
      balance: readMoney(totals['balance']) ?? 0,
      count: totals['count'] is int ? totals['count'] as int : 0,
      categories: [
        for (final c in readList(json['expenseByCategory']))
          if (c is Map && c['name'] is String && readMoney(c['amount']) != null)
            (name: c['name'] as String, amount: readMoney(c['amount'])!),
      ],
      findings: [
        for (final f in readList(json['insights']))
          if (f is Map && f['title'] is String && f['detail'] is String)
            (title: f['title'] as String, detail: f['detail'] as String),
      ],
    );
  }

  final num income;
  final num expense;
  final num balance;
  final int count;

  /// Gastos por categoría, de mayor a menor.
  final List<({String name, num amount})> categories;

  /// «Lo que dicen tus números»: hallazgos con reglas fijas del servidor.
  final List<({String title, String detail})> findings;
}

/// Saca el nombre de `Content-Disposition: attachment; filename="rinde_2026-10.csv"` (filenameFrom
/// de la web), o [fallback] si no llega. Sin barras: el nombre no puede salirse de la carpeta temporal.
String filenameFrom(String? header, String fallback) =>
    (RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(header ?? '')?.group(1) ?? fallback)
        .replaceAll(RegExp(r'[\\/]'), '_');

/// Exportar movimientos (reportService.js de la web, FT-0012). Vista previa y archivo los arma el
/// servidor con el mismo modelo: la app no genera archivos.
///
/// MODO DEMOSTRACIÓN: no hay repositorio demo. Los reportes los arma el servidor; una sesión demo no
/// saca peticiones del dispositivo (ApiClient responde demoNoBackend).
class ExportRepository {
  ExportRepository(this._api);
  final ApiClient _api;

  /// GET /reports/preview?from&to. 422 `NO_DATA` si el periodo no tiene movimientos.
  Future<ReportPreviewData> preview(String from, String to) async =>
      ReportPreviewData.fromJson(await _api.get('/reports/preview', query: {'from': from, 'to': to}));

  /// GET /reports/export?format&from&to[&detail=false]. 422 `NO_DATA` como arriba.
  Future<({Uint8List bytes, String filename})> export(
    ExportFormat format,
    String from,
    String to, {
    bool detail = true,
  }) async {
    final file = await _api.download(
      '/reports/export',
      query: {'format': format.name, 'from': from, 'to': to, if (!detail) 'detail': 'false'},
    );
    return (bytes: file.bytes, filename: filenameFrom(file.disposition, 'rinde_${from}_$to.${format.name}'));
  }
}

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepository(ref.watch(apiClientProvider)),
);
