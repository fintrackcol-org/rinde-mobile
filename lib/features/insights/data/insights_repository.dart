import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../home/data/home_models.dart' show readList, readMap, readMoney;

/// Un consejo de la IA (insightService.js de la web, FT-0007).
class Insight {
  const Insight({required this.type, required this.title, required this.detail});

  static Insight? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'], title = raw['title'], detail = raw['detail'];
    if (type is! String || title is! String || detail is! String) return null;
    return Insight(type: type, title: title, detail: detail);
  }

  final String type;
  final String title;
  final String detail;
}

/// GET /insights: consejos de la semana (con menos de un mes de historial) o del mes.
class InsightsResult {
  const InsightsResult({required this.period, required this.month, required this.insights});

  factory InsightsResult.fromJson(Object? raw) {
    final json = readMap(raw);
    return InsightsResult(
      period: json['period'] == 'week' ? 'week' : 'month',
      month: json['month'] is String ? json['month'] as String : '',
      insights: [for (final item in readList(json['insights'])) ?Insight.tryParse(item)],
    );
  }

  /// `week` o `month`.
  final String period;

  /// AAAA-MM.
  final String month;
  final List<Insight> insights;
}

/// Cuántos y cuánto.
typedef CountTotal = ({int count, num total});

CountTotal _countTotal(Object? raw) {
  final json = readMap(raw);
  return (count: json['count'] is int ? json['count'] as int : 0, total: readMoney(json['total']) ?? 0);
}

/// Un gasto que no convenció.
typedef Regret = ({String id, String description, num amount, String? emotion});

/// GET /transactions/reflection (FT-0070): los gastos de la semana por emoción y grupo Kakeibo, con
/// preguntas para pensar. Todo lo cuenta el servidor.
class WeekReflection {
  const WeekReflection({
    required this.from,
    required this.to,
    required this.expenses,
    required this.withEmotion,
    required this.emotions,
    required this.kakeibo,
    required this.withoutKakeibo,
    required this.regrets,
    required this.questions,
  });

  factory WeekReflection.fromJson(Object? raw) {
    final json = readMap(raw);
    Map<String, CountTotal> byKey(Object? list) => {
      for (final item in readList(list))
        if (item is Map && item['key'] is String) item['key'] as String: _countTotal(item),
    };
    return WeekReflection(
      from: json['from'] is String ? json['from'] as String : '',
      to: json['to'] is String ? json['to'] as String : '',
      expenses: _countTotal(json['expenses']),
      withEmotion: json['withEmotion'] is int ? json['withEmotion'] as int : 0,
      emotions: byKey(json['emotions']),
      kakeibo: byKey(json['kakeibo']),
      withoutKakeibo: _countTotal(json['withoutKakeibo']),
      regrets: [
        for (final r in readList(json['regrets']))
          if (r is Map && r['id'] is String && readMoney(r['amount']) != null)
            (
              id: r['id'] as String,
              description: r['description'] is String ? r['description'] as String : '',
              amount: readMoney(r['amount'])!,
              emotion: r['emotion'] is String ? r['emotion'] as String : null,
            ),
      ],
      questions: [for (final q in readList(json['questions'])) ?(q is String ? q : null)],
    );
  }

  /// Lunes y domingo, AAAA-MM-DD.
  final String from;
  final String to;
  final CountTotal expenses;
  final int withEmotion;
  final Map<String, CountTotal> emotions;
  final Map<String, CountTotal> kakeibo;
  final CountTotal withoutKakeibo;
  final List<Regret> regrets;
  final List<String> questions;
}

/// Un mensaje del chat con el asistente. La conversación vive en la pantalla: no se guarda.
typedef ChatMessage = ({bool fromUser, String text});

/// Mensajes que acepta la API: los últimos de la conversación (assistantService.js).
const maxChatMessages = 10;

/// Largo máximo de una pregunta, igual que en la API.
const maxQuestionChars = 500;

/// toConversation de la web: los últimos [maxChatMessages], empezando por una pregunta (la IA no
/// entiende una conversación que arranca con su respuesta).
List<ChatMessage> toConversation(List<ChatMessage> messages) {
  final recent = messages.length > maxChatMessages
      ? messages.sublist(messages.length - maxChatMessages)
      : messages;
  final first = recent.indexWhere((m) => m.fromUser);
  return first == -1 ? const [] : recent.sublist(first);
}

/// La API rechaza (422) cualquier mensaje de más de [maxQuestionChars], también las respuestas de la
/// IA, que pueden llegar a 1500: se reenvía solo su comienzo. shortcut: quitar cuando parseChat aplique
/// el tope solo a role 'user'.
String _clip(String text) {
  final clean = text.trim();
  return clean.length > maxQuestionChars ? clean.substring(0, maxQuestionChars) : clean;
}

/// Consejos, reflexión de la semana y asistente (insightService, transactionService.getReflection y
/// assistantService de la web). Solo endpoints del servidor: la app no llama a ningún proveedor de IA.
///
/// MODO DEMOSTRACIÓN: no hay repositorio demo. Los consejos y el chat son de la IA del servidor y la
/// reflexión la cuenta el servidor; una sesión demo no saca peticiones del dispositivo (ApiClient
/// responde demoNoBackend) y la pantalla dice que es una demostración.
class InsightsRepository {
  InsightsRepository(this._api);
  final ApiClient _api;

  /// GET /insights. Errores con `code`: INSUFFICIENT_HISTORY, AI_UNAVAILABLE o RATE_LIMITED.
  Future<InsightsResult> insights() async => InsightsResult.fromJson(await _api.get('/insights'));

  /// GET /transactions/reflection: la semana de hoy.
  Future<WeekReflection> reflection() async =>
      WeekReflection.fromJson(await _api.get('/transactions/reflection'));

  /// POST /assistant/chat `{messages}` → `{reply, toolsUsed}`. Límite por minuto y por día del servidor
  /// (RATE_LIMITED) y AI_UNAVAILABLE si la IA no respondió.
  Future<({String reply, List<String> toolsUsed})> ask(List<ChatMessage> messages) async {
    final json = readMap(
      await _api.post(
        '/assistant/chat',
        auth: true,
        body: {
          'messages': [
            for (final m in toConversation(messages))
              {'role': m.fromUser ? 'user' : 'assistant', 'text': m.fromUser ? m.text : _clip(m.text)},
          ],
        },
      ),
    );
    return (
      reply: json['reply'] is String ? json['reply'] as String : '',
      toolsUsed: [for (final name in readList(json['toolsUsed'])) ?(name is String ? name : null)],
    );
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) => InsightsRepository(ref.watch(apiClientProvider)),
);
