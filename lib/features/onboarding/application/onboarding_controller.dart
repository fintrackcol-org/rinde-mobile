import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/region/region.dart';
import '../../../core/region/region_provider.dart';
import '../../auth/application/session_controller.dart';
import '../data/draft_store.dart';
import '../data/onboarding_repository.dart';
import '../domain/commitments.dart';
import '../domain/income_sources.dart';
import '../domain/onboarding_draft.dart';
import '../domain/onboarding_flow.dart';

/// Qué está guardando ahora (bloquea Atrás, Omitir y el botón principal).
enum OnboardingBusy { region, finishing, later }

/// Cómo terminó. Se distingue lo que confirmó el servidor de lo que solo simuló la demostración.
enum OnboardingOutcome {
  /// GUARDADO REMOTO confirmado por el servidor.
  saved,

  /// «Ahora no» confirmado por el servidor.
  skipped,

  /// MODO DEMOSTRACIÓN: terminó, pero nada llegó a ningún servidor.
  demoSaved,
  demoSkipped,
}

/// Texto para mostrar: clave en español + variables (se traduce al dibujar), o un mensaje del
/// servidor que ya viene en el idioma pedido.
class OnboardingMessage {
  const OnboardingMessage(this.text, {this.vars = const {}});
  final String text;
  final Map<String, Object> vars;

  String resolve(Tr t) => t(text, vars);
}

class OnboardingState {
  const OnboardingState({
    required this.mode,
    required this.draft,
    this.ready = false,
    this.direction = 1,
    this.busy,
    this.error,
    this.errorItemKey,
    this.outcome,
    this.alreadyDone = false,
    this.isDemo = false,
    this.userName,
  });

  final OnboardingMode mode;
  final OnboardingDraft draft;

  /// El borrador ya se leyó del dispositivo.
  final bool ready;

  /// 1 = avanzando, -1 = volviendo (para la transición).
  final int direction;
  final OnboardingBusy? busy;
  final OnboardingMessage? error;

  /// Pago con el problema (para resaltarlo y llevar el foco).
  final String? errorItemKey;
  final OnboardingOutcome? outcome;

  /// El servidor dice que ya hizo la bienvenida: no se repite (la web sí la repite, deuda D-01).
  final bool alreadyDone;
  final bool isDemo;
  final String? userName;

  int get position => draft.position;
  int get first => OnboardingSteps.first(mode);
  int get step => OnboardingSteps.stepNumber(position, mode);
  int get total => OnboardingSteps.total(mode);

  /// Los pagos ya llegaron al servidor (etapa 1): cambiarlos aquí no tendría efecto (el servidor no
  /// pisa ni borra pagos con el mismo nombre), así que se muestran sin edición.
  bool get paymentsLocked => draft.sentWelcome != null;

  OnboardingState copyWith({
    OnboardingDraft? draft,
    bool? ready,
    int? direction,
    OnboardingBusy? Function()? busy,
    OnboardingMessage? Function()? error,
    String? Function()? errorItemKey,
    OnboardingOutcome? Function()? outcome,
    bool? alreadyDone,
  }) => OnboardingState(
    mode: mode,
    draft: draft ?? this.draft,
    ready: ready ?? this.ready,
    direction: direction ?? this.direction,
    busy: busy != null ? busy() : this.busy,
    error: error != null ? error() : this.error,
    errorItemKey: errorItemKey != null ? errorItemKey() : this.errorItemKey,
    outcome: outcome != null ? outcome() : this.outcome,
    alreadyDone: alreadyDone ?? this.alreadyDone,
    isDemo: isDemo,
    userName: userName,
  );
}

/// Idiomas del sistema (para sugerir el país). Se puede reemplazar en pruebas.
final systemLocalesProvider = Provider<List<Locale>>(
  (ref) => WidgetsBinding.instance.platformDispatcher.locales,
);

/// Tiempo de espera antes de escribir el borrador (evita escribir en cada tecla).
const draftWriteDelay = Duration(milliseconds: 300);

class OnboardingController extends Notifier<OnboardingState> {
  OnboardingController(this.mode);
  final OnboardingMode mode;

  Timer? _writeTimer;
  bool _disposed = false;
  late String _userId;

  // Se toman al construir: después de cerrarse la pantalla, `ref` y `state` ya no se pueden usar
  // (Riverpod 3), pero una respuesta del servidor que llega tarde igual debe borrar el borrador.
  late OnboardingRepository _repo;
  late DraftStore _store;

  /// Borrador aún no escrito en el dispositivo (se escribe al cerrar sin tocar `ref` ni `state`).
  Map<String, dynamic>? _pending;

  @override
  OnboardingState build() {
    final session = ref.read(sessionControllerProvider).value?.session;
    _userId = session?.user.id ?? 'anon';
    _repo = ref.read(onboardingRepositoryProvider);
    _store = ref.read(draftStoreProvider);
    final store = _store;
    final userId = _userId;
    ref.onDispose(() {
      _disposed = true;
      _writeTimer?.cancel();
      // Lo pendiente se escribe aunque la pantalla se cierre.
      final pending = _pending;
      _pending = null;
      if (pending != null) unawaited(store.write(userId, pending));
    });
    final suggested = suggestCountry(ref.read(systemLocalesProvider));
    unawaited(_load(suggested));
    return OnboardingState(
      mode: mode,
      draft: _freshDraft(suggested),
      isDemo: session?.demo ?? false,
      userName: _firstName(session?.user.name, session?.user.email),
    );
  }

  /// Borrador nuevo. En «solo las preguntas» no hay paso de País: se queda la región de la cuenta
  /// (si no, la interfaz cambiaría al idioma del país sugerido sin poder corregirlo).
  OnboardingDraft _freshDraft(String suggested) {
    if (mode == OnboardingMode.full) return OnboardingDraft.fresh(suggested);
    final region = ref.read(appRegionProvider);
    return OnboardingDraft.fresh(region.country)
        .copyWith(language: region.language, position: OnboardingSteps.income);
  }

  void _previewLanguage(OnboardingDraft draft) => ref
      .read(displayLanguageProvider.notifier)
      .preview(mode == OnboardingMode.full ? draft.language : ref.read(appRegionProvider).language);

  Future<void> _load(String suggested) async {
    final raw = await _store.read(_userId);
    if (_disposed) return;
    var draft = raw == null
        ? _freshDraft(suggested)
        : OnboardingDraft.fromJson(raw, suggestedCountry: suggested);
    // El recorrido abreviado siempre empieza en «¿Cómo te entra la plata?».
    if (mode == OnboardingMode.questions && draft.position < OnboardingSteps.income) {
      draft = draft.copyWith(position: OnboardingSteps.income);
    }
    state = state.copyWith(draft: draft, ready: true);
    _previewLanguage(draft);
    unawaited(_loadStatus());
  }

  /// Propuesta de saldo y guarda de «ya la hizo». Si falla (sin red), se sigue sin ellas.
  Future<void> _loadStatus() async {
    try {
      final status = await ref.read(welcomeStatusProvider.future);
      if (_disposed) return;
      if (status.welcomeDone) {
        // La etapa 1 quedó y la 2 (fuentes) no: se vuelve a Pagos para terminar solo esa etapa.
        if (state.draft.sentWelcome != null) {
          if (state.position != OnboardingSteps.payments) {
            _setDraft(state.draft.copyWith(position: OnboardingSteps.payments));
          }
          return;
        }
        // Ya la hizo (quizás en otro dispositivo): este borrador ya no sirve.
        _writeTimer?.cancel();
        _pending = null;
        await _store.clear(_userId);
        if (_disposed) return;
        state = state.copyWith(alreadyDone: true);
        return;
      }
      final proposal = status.balanceProposal;
      if (proposal != null && state.draft.balance.isEmpty) {
        _setDraft(state.draft.copyWith(balance: proposal.toString()));
      }
    } catch (_) {}
  }

  // ── Borrador ──────────────────────────────────────────────────────────────

  void _setDraft(OnboardingDraft draft, {bool clearError = false}) {
    state = state.copyWith(
      draft: draft,
      error: clearError ? () => null : null,
      errorItemKey: clearError ? () => null : null,
    );
    if (state.ready && state.outcome == null) _pending = draft.toJson();
    _writeTimer?.cancel();
    _writeTimer = Timer(draftWriteDelay, flush);
  }

  /// Escribe ya el borrador (al pasar la app a segundo plano o antes de guardar).
  Future<void> flush() async {
    _writeTimer?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending != null) await _store.write(_userId, pending);
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  bool get _blocked => state.busy != null || !state.ready;

  void go(int to) {
    if (_blocked) return;
    final clamped = to.clamp(OnboardingSteps.hello, OnboardingSteps.payments);
    state = state.copyWith(
      direction: clamped > state.position ? 1 : -1,
      error: () => null,
      errorItemKey: () => null,
    );
    _setDraft(state.draft.copyWith(position: clamped));
  }

  void start() => go(OnboardingSteps.country);
  void next() => go(state.position + 1);

  /// Atrás. Devuelve false si ya no hay a dónde volver dentro de la bienvenida (la pantalla decide:
  /// en el abreviado vuelve al inicio; en el saludo, el sistema).
  bool back() {
    if (_blocked) return true;
    if (state.position > state.first) {
      go(state.position - 1);
      return true;
    }
    if (mode == OnboardingMode.full && state.position == OnboardingSteps.country) {
      go(OnboardingSteps.hello);
      return true;
    }
    return false;
  }

  /// Omitir, como en la web: en País no guarda la región; en el recorrido salta las 5 escenas;
  /// en Ingresos borra las fuentes; en Saldo borra el saldo; en Pagos guarda SIN los pagos.
  Future<void> skip() async {
    if (_blocked) return;
    final p = state.position;
    if (p == OnboardingSteps.country) return go(OnboardingSteps.tour);
    if (OnboardingSteps.isTour(p)) return go(OnboardingSteps.income);
    if (p == OnboardingSteps.income) {
      _setDraft(state.draft.copyWith(sources: const {}));
      return go(OnboardingSteps.balance);
    }
    if (p == OnboardingSteps.balance) {
      _setDraft(state.draft.copyWith(balance: ''));
      return go(OnboardingSteps.payments);
    }
    if (p == OnboardingSteps.payments) return _save(withCommitments: false);
  }

  // ── País e idioma ─────────────────────────────────────────────────────────

  void pickCountry(String code) {
    if (_blocked || findCountry(code) == null) return;
    final draft = state.draft;
    final language = draft.languagePicked ? draft.language : regionForCountry(code).language;
    _setDraft(
      draft.copyWith(
        country: code,
        language: language,
        items: _relabel(draft.items, draft.language, language),
      ),
      clearError: true,
    );
    ref.read(displayLanguageProvider.notifier).preview(language);
  }

  void pickLanguage(String code) {
    if (_blocked || !isAppLanguage(code)) return;
    final draft = state.draft;
    _setDraft(
      draft.copyWith(
        language: code,
        languagePicked: true,
        items: _relabel(draft.items, draft.language, code),
      ),
      clearError: true,
    );
    // La interfaz cambia al instante, sin recargar (la web recarga la página).
    ref.read(displayLanguageProvider.notifier).preview(code);
  }

  /// «Seguir» en País: PATCH /users/me y, si el servidor lo confirma, la región queda en el dispositivo.
  Future<void> saveRegion() async {
    if (_blocked) return;
    state = state.copyWith(busy: () => OnboardingBusy.region, error: () => null);
    try {
      final saved = await _repo.saveRegion(country: state.draft.country, language: state.draft.language);
      if (_disposed) return;
      // En la demostración la región vive solo en memoria: la próxima cuenta real no la hereda.
      await ref.read(appRegionProvider.notifier).set(saved, persist: !_repo.isDemo);
      state = state.copyWith(busy: () => null);
      go(OnboardingSteps.tour);
    } on Object catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: () => null, error: () => _problem(e));
    }
  }

  /// Las sugerencias se guardan con el nombre traducido (como la web): al cambiar de idioma se
  /// renombran, para que sigan marcadas y no se dupliquen. Lo escrito en «Otro» no se toca.
  List<CommitmentItem> _relabel(List<CommitmentItem> items, String from, String to) {
    if (from == to || items.isEmpty) return items;
    final translations = ref.read(translationsProvider);
    final before = Tr(from, translations.of(from));
    final after = Tr(to, translations.of(to));
    return [
      for (final item in items)
        if (item.custom)
          item
        else
          switch (suggestedCommitments.where((s) => before(s) == item.name).firstOrNull) {
            final key? => item.copyWith(name: after(key)),
            null => item,
          },
    ];
  }

  // ── Ingresos, saldo y pagos ───────────────────────────────────────────────

  void toggleSource(IncomeKind kind) {
    if (_blocked) return;
    _setDraft(state.draft.copyWith(sources: toggleKind(state.draft.sources, kind)));
  }

  void updateSource(IncomeSourceForm form) {
    if (_blocked || !state.draft.sources.containsKey(form.kind)) return;
    _setDraft(state.draft.copyWith(sources: {...state.draft.sources, form.kind: form}));
  }

  void setBalance(String raw) {
    if (_blocked) return;
    _setDraft(state.draft.copyWith(balance: raw));
  }

  /// Sugerencia (con el nombre ya traducido): la agrega o quita la que no es «Otro».
  /// La web quita también los «Otro» con el mismo nombre; aquí no se borra lo escrito a mano.
  void toggleSuggestion(String localizedName) {
    if (_blocked || state.paymentsLocked) return;
    final items = state.draft.items;
    final existing = items.where((i) => !i.custom && i.name == localizedName).toList();
    if (existing.isNotEmpty) {
      _setDraft(
        state.draft.copyWith(items: items.where((i) => !existing.contains(i)).toList()),
        clearError: true,
      );
    } else if (items.length < maxCommitments) {
      _setDraft(
        state.draft.copyWith(items: [...items, CommitmentItem.create(localizedName)]),
        clearError: true,
      );
    }
  }

  /// «Otro»: un pago con nombre editable. Devuelve su clave (para enfocar el campo).
  String? addCustom() {
    if (_blocked || state.paymentsLocked || state.draft.items.length >= maxCommitments) return null;
    final item = CommitmentItem.create('', custom: true);
    _setDraft(state.draft.copyWith(items: [...state.draft.items, item]), clearError: true);
    return item.key;
  }

  void updateItem(String key, {String? name, String? amount, String? dayOfMonth}) {
    if (_blocked || state.paymentsLocked) return;
    final items = [
      for (final i in state.draft.items)
        i.key == key
            ? i.copyWith(
                name: name == null ? null : (name.length > commitmentNameMax ? name.substring(0, 60) : name),
                amount: amount,
                dayOfMonth: dayOfMonth?.replaceAll(RegExp(r'\D'), ''),
              )
            : i,
    ];
    _setDraft(state.draft.copyWith(items: items), clearError: true);
  }

  void removeItem(String key) {
    if (_blocked || state.paymentsLocked) return;
    _setDraft(
      state.draft.copyWith(items: state.draft.items.where((i) => i.key != key).toList()),
      clearError: true,
    );
  }

  // ── Guardar ───────────────────────────────────────────────────────────────

  /// «Ver mi plata».
  Future<void> finish() => _save(withCommitments: true);

  /// «Ahora no» en el saludo: marca la bienvenida sin respuestas (POST {}). Las respuestas del
  /// borrador solo se borran DESPUÉS de que el servidor lo confirma.
  Future<void> later() async {
    if (_blocked) return;
    state = state.copyWith(busy: () => OnboardingBusy.later, error: () => null);
    final repo = _repo;
    try {
      await repo.finishWelcome(const {});
      await _done(repo.isDemo ? OnboardingOutcome.demoSkipped : OnboardingOutcome.skipped);
    } on Object catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: () => null, error: () => _problem(e));
    }
  }

  /// Dos etapas, en este orden, como la web (la segunda fija el tipo de ingreso; al revés lo borraría):
  /// 1. POST /money-profile/welcome — se salta si un intento anterior ya guardó exactamente lo mismo.
  /// 2. PUT /money-profile/sources — solo si eligió fuentes.
  /// No hay reintentos automáticos: si algo falla, el borrador queda y la persona decide.
  Future<void> _save({required bool withCommitments}) async {
    if (_blocked) return;
    List<Map<String, dynamic>>? commitments;
    if (withCommitments) {
      final read = readCommitments(state.draft.items);
      if (read.problem != null) {
        state = state.copyWith(
          error: () => OnboardingMessage(read.problem!.message, vars: read.problem!.vars),
          errorItemKey: () => read.problem!.key,
        );
        return;
      }
      commitments = read.commitments;
    }
    final body = welcomeBody(balance: state.draft.balance, commitments: commitments);
    final print = fingerprint(body);
    state = state.copyWith(busy: () => OnboardingBusy.finishing, error: () => null, errorItemKey: () => null);
    await flush();
    // Copias locales: si la pantalla se cierra mientras espera al servidor, se sigue sin `ref` ni `state`.
    final repo = _repo;
    var draft = state.draft;
    try {
      if (draft.sentWelcome != print) {
        await repo.finishWelcome(body);
        // Etapa 1 confirmada: se anota en el borrador para no repetirla si la 2 falla.
        draft = draft.copyWith(sentWelcome: () => print);
        await _store.write(_userId, draft.toJson());
        if (!_disposed) state = state.copyWith(draft: draft);
      }
      final sources = [for (final f in draft.sources.values) f.toApi()];
      if (sources.isNotEmpty) await repo.saveSources(sources);
      await _done(repo.isDemo ? OnboardingOutcome.demoSaved : OnboardingOutcome.saved);
    } on Object catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: () => null, error: () => _problem(e));
    }
  }

  Future<void> _done(OnboardingOutcome outcome) async {
    _writeTimer?.cancel();
    _pending = null;
    // Solo ahora, con la confirmación, se borra el borrador.
    await _store.clear(_userId);
    if (_disposed) return;
    ref
      ..invalidate(welcomeStatusProvider)
      ..invalidate(pendingSourcesProvider);
    state = state.copyWith(busy: () => null, outcome: () => outcome);
  }

  /// MODO DEMOSTRACIÓN: borra el borrador y vuelve a empezar desde el saludo.
  Future<void> restartDemo() async {
    if (!state.isDemo) return;
    _writeTimer?.cancel();
    _pending = null;
    await _store.clear(_userId);
    final draft = _freshDraft(suggestCountry(ref.read(systemLocalesProvider)));
    state = OnboardingState(mode: mode, draft: draft, ready: true, isDemo: true, userName: state.userName);
    _previewLanguage(draft);
  }

  OnboardingMessage _problem(Object e) {
    if (e is ApiException) {
      // Solo sin conexión: una espera vencida puede haber llegado al servidor.
      if (e.code == ApiCodes.network) {
        return const OnboardingMessage(
          'Estás sin conexión. Tus respuestas quedaron guardadas en este dispositivo: inténtalo de nuevo cuando vuelva.',
        );
      }
      if (e.code == ApiCodes.rateLimited) return const OnboardingMessage(ApiMessages.rateLimited);
      // t() deja igual un texto del servidor que no sea clave y traduce los de respaldo.
      return OnboardingMessage(e.messageFor(fallback: ApiMessages.generic));
    }
    return const OnboardingMessage(ApiMessages.generic);
  }
}

/// Primer nombre para el saludo (getDisplayName de la web): el nombre, o la parte del correo.
String? _firstName(String? name, String? email) {
  final fromName = name?.trim().split(RegExp(r'\s+')).first;
  if (fromName != null && fromName.isNotEmpty) return fromName;
  final local = email
      ?.split('@')
      .first
      .split(RegExp(r'[._\-+\d]+'))
      .firstWhere((p) => p.isNotEmpty, orElse: () => '');
  if (local == null || local.isEmpty) return null;
  return local[0].toUpperCase() + local.substring(1).toLowerCase();
}

final onboardingControllerProvider = NotifierProvider.autoDispose
    .family<OnboardingController, OnboardingState, OnboardingMode>(OnboardingController.new);
