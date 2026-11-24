import 'package:rinde_mobile/features/money/data/money_models.dart';
import 'package:rinde_mobile/features/money/data/money_repository.dart';
import 'package:rinde_mobile/features/onboarding/domain/income_sources.dart';
import 'package:rinde_mobile/features/plan/data/plan_models.dart';

/// Repositorio de Mi plata con respuestas a la medida. Guarda cada llamada y lo que se envió.
class FakeMoneyRepository implements MoneyRepository {
  final calls = <String>[];
  final sentSources = <List<Map<String, dynamic>>>[];
  final sentCommitments = <Map<String, dynamic>>[];
  final sentProfiles = <Map<String, dynamic>>[];

  /// (id, cuerpo) de cada PUT /commitments/:id.
  final sentUpdates = <(String, Map<String, dynamic>)>[];
  final deleted = <String>[];

  Future<MoneyProfile> Function() onProfile = () async => const MoneyProfile(welcomeDone: true);
  Future<IncomeOverview> Function() onIncome = () async => incomeOf();
  Future<void> Function(List<Map<String, dynamic>> sources) onSaveSources = (_) async {};
  Future<void> Function(Map<String, dynamic> body) onCreateCommitment = (_) async {};
  Future<void> Function(Map<String, dynamic> body) onSaveProfile = (_) async {};
  Future<List<CalendarPayment>> Function(String month) onCalendar = (_) async => const [];
  Future<PaymentCalendar> Function(String month) onMonthCalendar = (month) async => PaymentCalendar(
    month: month,
    today: '$month-15',
    events: const [],
    cardDates: const [],
    pending: 0,
    payments: const [],
  );
  Future<Liquidity> Function() onLiquidity = () async => const Liquidity(ready: false);
  Future<void> Function(String id, Map<String, dynamic> body) onUpdateCommitment = (_, _) async {};
  Future<void> Function(String id) onDeleteCommitment = (_) async {};
  Future<List<BalanceAdjustment>> Function(String from, String to) onAdjustments = (_, _) async => const [];

  int count(String call) => calls.where((c) => c == call || c.startsWith('$call ')).length;

  @override
  bool get isDemo => false;

  @override
  Future<MoneyProfile> profile() {
    calls.add('profile');
    return onProfile();
  }

  @override
  Future<IncomeOverview> income() {
    calls.add('income');
    return onIncome();
  }

  @override
  Future<void> saveSources(List<Map<String, dynamic>> sources) {
    calls.add('saveSources');
    sentSources.add(sources);
    return onSaveSources(sources);
  }

  @override
  Future<void> createCommitment(Map<String, dynamic> body) {
    calls.add('createCommitment');
    sentCommitments.add(body);
    return onCreateCommitment(body);
  }

  @override
  Future<PaymentCalendar> monthCalendar(String month) {
    calls.add('monthCalendar $month');
    return onMonthCalendar(month);
  }

  @override
  Future<Liquidity> liquidity() {
    calls.add('liquidity');
    return onLiquidity();
  }

  @override
  Future<List<CalendarPayment>> calendar(String month) {
    calls.add('calendar $month');
    return onCalendar(month);
  }

  @override
  Future<void> updateCommitment(String id, Map<String, dynamic> body) {
    calls.add('updateCommitment');
    sentUpdates.add((id, body));
    return onUpdateCommitment(id, body);
  }

  @override
  Future<void> deleteCommitment(String id) {
    calls.add('deleteCommitment');
    deleted.add(id);
    return onDeleteCommitment(id);
  }

  @override
  Future<void> saveProfile(Map<String, dynamic> body) {
    calls.add('saveProfile');
    sentProfiles.add(body);
    return onSaveProfile(body);
  }

  @override
  Future<List<BalanceAdjustment>> adjustments({required String from, required String to}) {
    calls.add('adjustments $from $to');
    return onAdjustments(from, to);
  }
}

/// Un independiente con proyectos: mes normal y flaco, sueldo propio, colchón por crear y PILA.
IncomeOverview incomeOf({
  List<IncomeSource> sources = const [
    IncomeSource(
      id: 's1',
      kind: IncomeKind.proyectos,
      frequency: 'irregular',
      lastMonths: [700000, 650000, 800000],
    ),
  ],
  num? normal = 700000,
  num? lean = 650000,
  String basis = 'declared',
  bool estimated = false,
  num? ownSalary = 600000,
  Cushion? cushion = const Cushion(goal: 2250000, suggestedGoal: 2250000, saved: 0),
  SocialSecurity? socialSecurity = const SocialSecurity(health: 218863, pension: 280145, total: 499008),
  WorkDay? workDay,
}) => IncomeOverview(
  sources: sources,
  normal: normal,
  lean: lean,
  basis: basis,
  estimated: estimated,
  ownSalary: ownSalary,
  cushion: cushion,
  socialSecurity: socialSecurity,
  workDay: workDay,
);

/// Aún no dijo cómo le entra la plata.
const noIncome = IncomeOverview(cushion: Cushion(goal: 0, suggestedGoal: 0, saved: 0));
