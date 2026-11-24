import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/auth_models.dart';
import '../../home/application/home_providers.dart' show homeBudgetsProvider;
import '../../home/data/home_models.dart';
import '../../home/data/home_repository.dart';
import '../../money/application/money_writer.dart' show inDoubt;
import '../../onboarding/data/onboarding_repository.dart' show pendingSourcesProvider;
import '../data/budgets_repository.dart';
import 'plan_providers.dart';

/// Escrituras de Presupuestos, con el patrón de DebtsWriter:
/// - un solo envío a la vez por operación y cuenta ([_once]);
/// - «en duda» (espera vencida o 5xx) se confirma VOLVIENDO A LEER GET /budgets del mes, nunca
///   reintentando solo: crear vale si la categoría ya tiene ese límite; cambiar, si el límite es el
///   enviado; borrar, si ya no está. Si no, crear y cambiar dan UNCONFIRMED;
/// - borrar: un 404 cuenta como hecho (el de un reintento tras perder la respuesta);
/// - `_sameAccount` antes de cada envío y la bienvenida pendiente bloquea toda escritura.
///
/// Un presupuesto no mueve la plata: después se recargan el mes (con la carga) y los presupuestos del
/// Inicio y de Mi plata (`homeBudgetsProvider`).
class BudgetsWriter {
  BudgetsWriter(this._ref);
  final Ref _ref;
  final _running = <String, Future<void>>{};

  BudgetsRepository get _repo => _ref.read(budgetsRepositoryProvider);

  Future<void> _once(String operation, Future<void> Function() send) {
    final key = '$operation ${_ref.read(accountProvider)?.user.id}';
    // Un segundo toque espera el resultado del primero, sin un segundo envío.
    return _running[key] ??= send().whenComplete(() {
      // Sin devolver el Future quitado: whenComplete lo esperaría y nunca terminaría.
      _running.remove(key);
    });
  }

  /// Al retomarse, la bienvenida a medias reenvía su borrador: primero que termine.
  Future<void> _welcomeDone() async {
    final pending = _ref.read(pendingSourcesProvider(_ref.read(accountProvider)).future);
    if (await pending.catchError((_) => false)) {
      throw const ApiException(
        code: ApiCodes.welcomePending,
        serverMessage: 'Primero terminemos de guardar tu bienvenida.',
      );
    }
  }

  /// Otra cuenta entró mientras se leía: lo que se iba a mandar no es de ella.
  void _sameAccount(Session? account) {
    if (_ref.read(accountProvider)?.user.id != account?.user.id) {
      throw StateError('Cambió la cuenta antes de enviar');
    }
  }

  void _refresh() {
    _ref.container.invalidate(budgetsMonthProvider, asReload: true);
    _ref.container.invalidate(homeBudgetsProvider);
  }

  /// Una lectura fresca del mes, o null si no se pudo (y entonces nada se da por hecho).
  Future<List<BudgetStatus>?> _read(String month) async {
    try {
      return await _ref.read(homeRepositoryProvider).budgets(month);
    } on Object {
      return null;
    }
  }

  static const unconfirmedText = 'No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez.';

  static int _cents(num value) => (value * 100).round();

  Future<void> _send(String operation, Future<void> Function() send, Future<bool> Function() confirmed) =>
      _once(operation, () async {
        final account = _ref.read(accountProvider);
        await _welcomeDone();
        _sameAccount(account);
        try {
          await send();
        } on ApiException catch (e, stack) {
          if (!inDoubt(e)) {
            // 404: lo borraron en otro lado; BUDGET_EXISTS: ya lo crearon (en la web o tras una duda).
            if (e.status == 404 || e.code == 'BUDGET_EXISTS') _refresh();
            rethrow;
          }
          if (!await confirmed()) {
            _refresh();
            Error.throwWithStackTrace(
              ApiException(code: ApiCodes.unconfirmed, status: e.status, serverMessage: unconfirmedText),
              stack,
            );
          }
        }
        _refresh();
      });

  /// POST /budgets.
  Future<void> create({required String category, required String month, required num amount}) => _send(
    'budget-create $category $month',
    () => _repo.create(category: category, month: month, amount: amount),
    () async =>
        (await _read(month))?.any((b) => b.category == category && _cents(b.amount) == _cents(amount)) ??
        false,
  );

  /// PUT /budgets/:id. Un 404 (lo borraron en otro lado) recarga y llega a la hoja.
  Future<void> update(BudgetStatus budget, String month, num amount) => _send(
    'budget-edit ${budget.id}',
    () => _repo.update(budget.id, amount),
    () async =>
        (await _read(month))?.any((b) => b.id == budget.id && _cents(b.amount) == _cents(amount)) ?? false,
  );

  /// DELETE /budgets/:id.
  Future<void> delete(BudgetStatus budget, String month) => _once('budget-delete ${budget.id}', () async {
    final account = _ref.read(accountProvider);
    await _welcomeDone();
    _sameAccount(account);
    try {
      await _repo.delete(budget.id);
    } on ApiException catch (e, stack) {
      if (e.status != 404) {
        if (!inDoubt(e)) rethrow;
        final after = await _read(month);
        if (after == null || after.any((b) => b.id == budget.id)) {
          _refresh();
          Error.throwWithStackTrace(e, stack);
        }
      }
    }
    _refresh();
  });
}

final budgetsWriterProvider = Provider<BudgetsWriter>(BudgetsWriter.new);
