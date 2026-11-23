import 'dart:async';
import 'dart:convert';
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
import '../../home/application/home_providers.dart' show invalidateHome;
import '../../home/data/home_models.dart' show readMoney;

import 'dart:math' as math;

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

  /// Los pagos salieron en la etapa 1: se muestran sin edición (ver OnboardingDraft.sentCommitments).
  bool get paymentsLocked => draft.sentCommitments != null;

  /// El servidor los tiene; mientras esté en duda no se dice que quedaron guardados.
  bool get paymentsSaved => paymentsLocked && draft.welcomeConfirmed;

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
  late ProviderContainer _container;

  /// Borrador aún no escrito en el dispositivo (se escribe al cerrar sin tocar `ref` ni `state`).
  Map<String, dynamic>? _pending;

  @override
  OnboardingState build() {
    final session = ref.read(sessionControllerProvider).value?.session;
    _userId = session?.user.id ?? 'anon';
    _repo = ref.read(onboardingRepositoryProvider);
    _store = ref.read(draftStoreProvider);
    _container = ref.container;
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
    if (mode == OnboardingMode.questions) {
      // El idioma de la cuenta puede llegar con las preguntas abiertas: las sugerencias marcadas lo
      // siguen, o se agregaría dos veces el mismo pago con dos nombres.
      ref.listen(appRegionProvider.select((r) => r.language), (_, language) {
        final draft = state.draft;
        if (!state.ready || state.busy != null) return; // guardando: no se escribe sobre la marca
        if (draft.sentCommitments != null || draft.language == language) return;
        _setDraft(draft.copyWith(language: language, items: _relabel(draft, language)));
      });
    }
    unawaited(_load(suggested));
    return OnboardingState(
      mode: mode,
      draft: _freshDraft(suggested),
      isDemo: session?.demo ?? false,
      userName: _firstName(session?.user.name, session?.user.email),
    );
  }

  /// Borrador nuevo, en el idioma en que ya se ve la app: el país sugerido no lo cambia hasta que la
  /// persona elija un país. En «solo las preguntas» no hay paso de País: se queda la región de la cuenta.
  OnboardingDraft _freshDraft(String suggested) {
    final region = ref.read(appRegionProvider);
    final full = mode == OnboardingMode.full;
    return OnboardingDraft.fresh(full ? suggested : region.country)
        .copyWith(language: region.language, position: full ? null : OnboardingSteps.income);
  }

  void _previewLanguage(OnboardingDraft draft) => ref
      .read(displayLanguageProvider.notifier)
      .preview(mode == OnboardingMode.full ? draft.language : ref.read(appRegionProvider).language);

  /// Al abrir se pudo leer un borrador. Sin eso no se borra nada: pudo fallar el llavero.
  bool _hadDraft = false;

  /// No se pudo leer el borrador: no se escribe encima solo. Un envío sí anota su marca.
  bool _unreadable = false;

  Future<void> _load(String suggested) async {
    final raw = await _store.read(_userId);
    if (_disposed) return;
    _unreadable = raw == draftUnreadable;
    _hadDraft = raw != null && !_unreadable;
    var draft = !_hadDraft
        ? _freshDraft(suggested)
        : OnboardingDraft.fromJson(raw, suggestedCountry: suggested);
    if (mode == OnboardingMode.questions) {
      // El recorrido abreviado siempre empieza en «¿Cómo te entra la plata?».
      if (draft.position < OnboardingSteps.income) draft = draft.copyWith(position: OnboardingSteps.income);
      // Aquí se ve el idioma de la cuenta: un borrador escrito en otro se pasa a ese, para que las
      // sugerencias sigan marcadas y no se dupliquen.
      final language = ref.read(appRegionProvider).language;
      if (draft.sentCommitments == null && draft.language != language) {
        draft = draft.copyWith(language: language, items: _relabel(draft, language));
      }
    }
    state = state.copyWith(draft: draft, ready: true);
    _previewLanguage(draft);
    unawaited(_loadStatus());
  }

  /// Propuesta de saldo y guarda de «ya la hizo». Si falla (sin red), se sigue sin ellas.
  Future<void> _loadStatus() async {
    try {
      final status = await ref.read(welcomeStatusProvider(ref.read(accountProvider)).future);
      // Si ya está guardando, escribir aquí pisaría la marca de lo que va en camino.
      if (_disposed || state.busy != null) return;
      if (status.welcomeDone) {
        // La etapa 1 se envió y falta terminar. Saldo y pagos se comprueban por separado: los pagos que
        // están quedan guardados; un saldo distinto se le muestra a la persona antes de pisarlo.
        final draft = state.draft;
        if (draft.sentWelcome case final mark?) {
          final payments = draft.sentCommitments;
          final balance = _sentBalance(mark);
          final balanceSaved =
              balance == null || balance == status.balance || balance == draft.confirmedBalance;
          final confirmed =
              draft.welcomeConfirmed ||
              (_hasPayments(status, payments) && (balanceSaved || payments != null));
          final next = draft.copyWith(
            position: balanceSaved ? OnboardingSteps.payments : OnboardingSteps.balance,
            welcomeConfirmed: confirmed,
            // Saldo sin comprobar: la marca no puede igualar la huella, o no se volvería a enviar.
            sentWelcome: balanceSaved ? null : () => _asEdited(mark),
          );
          if (next.position != state.position ||
              next.welcomeConfirmed != draft.welcomeConfirmed ||
              next.sentWelcome != mark) {
            _setDraft(next);
          }
          return;
        }
        // Ya la hizo (quizás en otro dispositivo): este borrador ya no sirve.
        _writeTimer?.cancel();
        _pending = null;
        if (_hadDraft) {
          await _store.clear(_userId);
        } else {
          // No se borra lo que no se leyó; y sin esto la entrada lo devolvería aquí una y otra vez.
          ref.read(resumeDeferredProvider.notifier).defer();
        }
        if (_disposed) return;
        _refreshEntry();
        state = state.copyWith(alreadyDone: true);
        return;
      }
      final proposal = status.balanceProposal;
      // Pasado el Saldo, vacío es una respuesta: la propuesta viajaría sin que nadie la viera.
      if (proposal != null && state.draft.balance.isEmpty && state.position <= OnboardingSteps.balance) {
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
    if (state.ready && !_unreadable && state.outcome == null) _pending = draft.toJson();
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
      draft.copyWith(country: code, language: language, items: _relabel(draft, language)),
      clearError: true,
    );
    ref.read(displayLanguageProvider.notifier).preview(language);
  }

  void pickLanguage(String code) {
    if (_blocked || !isAppLanguage(code)) return;
    final draft = state.draft;
    _setDraft(
      draft.copyWith(language: code, languagePicked: true, items: _relabel(draft, code)),
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
  /// Si la etapa 1 ya salió hacia el servidor no se renombra nada: con otro nombre, el servidor
  /// guardaría el mismo pago por segunda vez y apartaría la plata dos veces.
  List<CommitmentItem> _relabel(OnboardingDraft draft, String to) {
    final from = draft.language;
    if (draft.sentCommitments != null || from == to || draft.items.isEmpty) return draft.items;
    final translations = ref.read(translationsProvider);
    final before = Tr(from, translations.of(from));
    final after = Tr(to, translations.of(to));
    return [
      for (final item in draft.items)
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
                name: name == null ? null : clipCommitmentName(name),
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
    final locked = state.draft.sentCommitments;
    // Lo que ya salió se repite igual: ni se vuelve a validar ni «Omitir» lo quita.
    var commitments = locked;
    if (locked == null && withCommitments) {
      final read = readCommitments(state.draft.items);
      if (read.problem != null) {
        state = state.copyWith(
          error: () => OnboardingMessage(read.problem!.message, vars: read.problem!.vars),
          errorItemKey: () => read.problem!.key,
        );
        return;
      }
      // Ninguno es lo mismo que omitirlos: con otra huella se reenviaría lo que ya quedó.
      commitments = read.commitments.isEmpty ? null : read.commitments;
    }
    final body = welcomeBody(balance: state.draft.balance, commitments: commitments);
    final print = fingerprint(body);
    state = state.copyWith(busy: () => OnboardingBusy.finishing, error: () => null, errorItemKey: () => null);
    await flush();
    // Copias locales: si la pantalla se cierra mientras espera al servidor, se sigue sin `ref` ni `state`.
    final repo = _repo;
    var draft = state.draft;
    final before = draft.sentWelcome;
    final wasConfirmed = draft.welcomeConfirmed;
    // La etapa 1 salió y todavía no se sabe si el servidor la guardó.
    var inDoubt = false;
    var sent = const <String, dynamic>{};
    final balanceBefore = draft.confirmedBalance;
    // Un PUT de fuentes salió en este intento, y si antes ya había salido alguno.
    var sendingSources = false;
    final sentSourcesBefore = draft.sourcesSent;
    // «Omitir» con los pagos en duda: no se reenvían (pudo haberlos cambiado en la web).
    final withoutPayments = locked != null && !withCommitments && !wasConfirmed;
    try {
      if (!(wasConfirmed && before == print)) {
        // Con los pagos ya guardados solo viaja el saldo: repetirlos reviviría los que la persona
        // haya renombrado o borrado después en Mi plata.
        final balanceOnly = wasConfirmed && locked != null;
        // Si cambia algo que ya había salido, la marca no puede ser igual a la huella: lo que pruebe
        // que llegó el intento anterior no prueba que llegó este, y hay que volver a enviarlo.
        final mark = before == null || before == print ? print : fingerprint({...body, 'edited': true});
        sent = {...(balanceOnly || withoutPayments ? welcomeBody(balance: draft.balance) : body)};
        final balance = readMoney(sent['balance']);
        if (balance != null && balance == draft.confirmedBalance) {
          // Ya lo guardó: sin saldo el servidor conserva el que tenga (quizás corregido después).
          sent['balance'] = null;
        } else if (balance != null) {
          // Los nulos de la bienvenida borrarían el tipo de ingreso y los días guardados por otro
          // camino si las fuentes no llegan después. Si no se pueden leer, no se envía nada.
          final current = await repo.status();
          final other = current.balance;
          if (before == print && current.welcomeDone && other != null && other != balance) {
            // Reintento sin cambios y el servidor ya tiene otro saldo (corregido después): se le
            // muestra antes de pisarlo, como al reabrir.
            await _keep(
              draft.copyWith(
                position: OnboardingSteps.balance,
                sentWelcome: () => _asEdited(print),
                welcomeConfirmed: wasConfirmed || (locked != null && _hasPayments(current, locked)),
              ),
            );
            if (!_disposed) state = state.copyWith(busy: () => null);
            return;
          }
          if (current.incomeType != null) {
            sent['incomeType'] = current.incomeType;
            sent['payDays'] = current.payDays;
          }
        }
        final sendsBalance = sent['balance'] != null;
        // Se anota ANTES de enviar: si la respuesta no llega (espera vencida, app cerrada), al reabrir
        // se sabe que pudo quedar guardada y las fuentes no se pierden.
        // La llave va ligada a lo que se envía y a la marca: idéntico, la misma; si no, una nueva.
        final what = fingerprint({'mark': mark, 'sent': sent});
        final saved = draft.welcomeKey?.split(' ');
        final key = saved != null && saved.length == 2 && saved[1] == what ? saved[0] : _newKey();
        draft = await _keep(
          draft.copyWith(
            sentWelcome: () => mark,
            welcomeConfirmed: balanceOnly,
            confirmedBalance: sendsBalance ? () => null : null,
            welcomeKey: '$key $what',
          ),
        );
        inDoubt = !balanceOnly;
        await repo.finishWelcome(sent, idempotencyKey: draft.welcomeKey!.split(' ').first);
        inDoubt = false;
        // Etapa 1 confirmada: no se repite si la 2 falla. Sin los pagos en duda sigue sin confirmar.
        draft = await _keep(
          draft.copyWith(
            sentWelcome: () => print,
            welcomeConfirmed: !withoutPayments,
            confirmedBalance: sendsBalance ? () => readMoney(sent['balance']) : null,
          ),
        );
      }
      final sources = [for (final f in draft.sources.values) f.toApi()];
      if (sources.isNotEmpty || draft.sourcesSent) {
        if (!draft.sourcesSent) draft = await _keep(draft.copyWith(sourcesSent: true));
        sendingSources = true;
        await repo.saveSources(sources);
      }
      await _done(repo.isDemo ? OnboardingOutcome.demoSaved : OnboardingOutcome.saved);
    } on Object catch (e) {
      final status = e is ApiException ? e.status ?? 0 : 0;
      final notSent = e is ApiException && e.code == ApiCodes.network;
      // 409 de llave reusada: la llave ya se usó con otro cuerpo (pudo aplicarse). Se suelta para que
      // el próximo intento saque otra, y se trata como en duda, no como «seguro no se guardó».
      final reused = e is ApiException && e.code == 'IDEMPOTENCY_KEY_REUSED';
      if (reused) draft = await _keep(draft.copyWith(welcomeKey: ''));
      final rejected = !reused && (notSent || (status >= 400 && status < 500));
      if (sendingSources && rejected && !sentSourcesBefore) {
        // Seguro no se aplicó: «Omitir» después no puede borrar fuentes que esta app no escribió.
        await _keep(draft.copyWith(sourcesSent: false));
      }
      if (inDoubt) {
        Future<void> revert({bool release = false}) => _keep(
          draft.copyWith(
            sentWelcome: () => release ? null : before,
            welcomeConfirmed: !release && wasConfirmed,
            confirmedBalance: () => balanceBefore,
          ),
        );
        if (rejected) {
          // No salió del teléfono o el servidor la rechazó: seguro no quedó guardada. Si rechazó por
          // inválido el mismo envío de antes, aquel tampoco quedó: se sueltan los pagos para arreglarlos.
          final invalidAgain =
              (status == 400 || status == 422) && !wasConfirmed && !withoutPayments && before == print;
          // Y solo si el servidor dice que no tiene bienvenida: si no, aquel envío sí pudo quedar.
          final release = invalidAgain && (await _statusOrNull(repo))?.welcomeDone == false;
          await revert(release: release);
        } else if (await _statusOrNull(repo) case final saved?) {
          if (!withoutPayments && saved.welcomeDone && _landed(saved, fingerprint(sent))) {
            // Llegó aunque la respuesta se perdió: falta solo la etapa 2.
            final balance = _sentBalance(fingerprint(sent));
            await _keep(
              draft.copyWith(
                welcomeConfirmed: true,
                confirmedBalance: balance == null ? null : () => balance,
              ),
            );
          } else if (status == 500 &&
              (!saved.welcomeDone || !_hasPayments(saved, sent['commitments'] as List<Object?>?))) {
            // El servidor falló y deshizo la operación: se puede corregir. Con una espera vencida no,
            // porque todavía puede llegar.
            await revert();
          }
        }
      }
      if (_disposed) return;
      state = state.copyWith(busy: () => null, error: () => _problem(e));
    }
  }

  /// Deja el borrador en el dispositivo ya (sin esperar el temporizador) y en pantalla si sigue abierta.
  Future<OnboardingDraft> _keep(OnboardingDraft draft) async {
    await _store.write(_userId, draft.toJson());
    // La marca de la etapa 1 cambió: la entrada y el Inicio ya no pueden responder con lo de antes.
    _refreshEntry();
    if (!_disposed) state = state.copyWith(draft: draft);
    return draft;
  }

  /// Tras un fallo sin respuesta clara (espera vencida, 5xx): qué tiene el servidor. Si tampoco se
  /// puede saber, la marca del borrador queda y se revisa al reabrir.
  Future<WelcomeStatus?> _statusOrNull(OnboardingRepository repo) async {
    try {
      return await repo.status();
    } on Object {
      return null;
    }
  }

  /// La entrada vuelve a preguntar si falta la bienvenida. Con el contenedor y no con `ref`: la
  /// respuesta puede llegar con la pantalla ya cerrada, y el dato viejo devolvería a la bienvenida.
  void _refreshEntry() {
    try {
      _container.invalidate(pendingSourcesProvider);
      // Todo el Inicio, y como carga nueva: lo de antes de responder ya no es cierto ni para mostrarlo
      // mientras llega lo nuevo.
      invalidateHome((provider) => _container.invalidate(provider, asReload: true));
    } on StateError {
      // La app entera ya se cerró: no queda nadie a quien avisar.
    }
  }

  Future<void> _done(OnboardingOutcome outcome) async {
    _writeTimer?.cancel();
    _pending = null;
    // Solo ahora, con la confirmación, se borra el borrador. Primero se vacía: si el llavero no deja
    // borrar, lo que quede no tiene marca y no se retoma una bienvenida terminada.
    await _store.write(_userId, const {'v': 0});
    await _store.clear(_userId);
    _refreshEntry();
    if (_disposed) return;
    state = state.copyWith(busy: () => null, outcome: () => outcome);
  }

  /// MODO DEMOSTRACIÓN: borra el borrador y vuelve a empezar desde el saludo.
  Future<void> restartDemo() async {
    // Mientras guarda no: la respuesta en camino volvería a escribir lo que se acaba de borrar.
    if (!state.isDemo || state.busy != null) return;
    _writeTimer?.cancel();
    _pending = null;
    await _store.clear(_userId);
    if (_disposed) return;
    final draft = _freshDraft(suggestCountry(ref.read(systemLocalesProvider)));
    state = OnboardingState(mode: mode, draft: draft, ready: true, isDemo: true, userName: state.userName);
    _previewLanguage(draft);
    // El escenario puede traer una propuesta de saldo: se vuelve a leer como al abrir.
    unawaited(_loadStatus());
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

/// 128 bits al azar en hexadecimal: la llave de idempotencia de un envío.
String _newKey() {
  final random = math.Random.secure();
  return 'w-${[for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join()}';
}

/// ¿El servidor tiene ESTE envío de la etapa 1? `welcomeDone` solo no lo prueba: pudo hacerse por
/// otro camino («Ahora no», otro dispositivo). Se exige el mismo saldo y todos los pagos: que haya
/// algún saldo no prueba nada (pudo ser el de antes). Ante la duda no se dice «guardado».
bool _landed(WelcomeStatus status, String sent) {
  final balance = _sentBalance(sent);
  if (balance != null && balance != status.balance) return false;
  try {
    if (jsonDecode(sent) case final Map<String, dynamic> body) {
      return _hasPayments(status, body['commitments'] as List<Object?>?);
    }
  } on FormatException {
    // Una marca ilegible no prueba nada.
  }
  return false;
}

/// El servidor tiene todos esos pagos (por nombre, como su ON CONFLICT). Sin pagos, cierto.
bool _hasPayments(WelcomeStatus status, List<Object?>? payments) {
  final saved = {for (final name in status.commitmentNames) name.trim().toLowerCase()};
  return (payments ?? const []).every((c) => c is Map && saved.contains('${c['name']}'.trim().toLowerCase()));
}

num? _sentBalance(String mark) {
  try {
    if (jsonDecode(mark) case {'balance': final num balance}) return readMoney(balance);
  } on FormatException {
    // Una marca ilegible no prueba nada.
  }
  return null;
}

String _asEdited(String mark) {
  try {
    if (jsonDecode(mark) case final Map<String, dynamic> body) return fingerprint({...body, 'edited': true});
  } on FormatException {
    // Se deja como está.
  }
  return mark;
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
