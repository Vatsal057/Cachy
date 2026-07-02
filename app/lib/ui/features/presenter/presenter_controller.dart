/// Drives the in-app "Present" mode: a self-navigating, spoken tour that
/// actually *operates* Cachy live — creating a card, running a search, scrolling
/// the feed, driving the knowledge graph — while narrating. The audience (or the
/// presenter) can tap the agent glyph any time to ask a question or hand it a
/// task; the agent stops the tour, performs it for real, asks if anything else
/// is needed, and then resumes the tour where it left off.
///
/// Speech uses the browser's Web Speech API via `flutter_tts` (free, any OS, no
/// install). Question answering runs server-side (`/presenter/ask`), which
/// returns a sequence of [AgentBeat]s (say + do) so answers are *performed*, not
/// just spoken. Everything the agent can do goes through the [AgentBus].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../data/repositories/card_repository.dart';
import '../../../domain/models/card.dart' as model;
import '../../../domain/models/concept.dart';
import '../../../domain/models/graph.dart';
import 'agent_bus.dart';

enum PresenterPhase { idle, speaking, thinking, acting, done }

/// The scripted tour. Each beat may switch [view], [say] a line, and/or run an
/// [action]; speech starts first and the action fires while the agent is still
/// talking, the way a human narrates over their own clicks. Lines are written
/// to be *spoken* — contractions, transitions, reactions — and avoid acronyms
/// so both the voice and the on-screen caption read naturally.
const List<AgentBeat> kTour = [
  // ── 1. Home ──────────────────────────────────────────────────────────────
  AgentBeat(
    view: 'library',
    say: "Hey! I'm Cachy's presenter, and instead of a slide deck I'll just "
        "drive the app for real. This is live — tap me any time, ask anything, "
        "and I'll show you.",
  ),
  AgentBeat(
    focus: 'content',
    say: "So this is home. Every reel, short, or article you share into Cachy "
        "comes back as a knowledge card. Let me scroll all the way down through "
        "the shelf so you can see the whole collection... and back up to the "
        "top.",
    action: AgentAction('scroll', {'target': 'library', 'mode': 'full', 'sweep': true}),
  ),

  // ── 2. Open the first card → the reader ──────────────────────────────────
  AgentBeat(
    focus: 'card.first',
    say: "Let me open this first card so you can see what's actually inside "
        "one.",
    action: AgentAction('open_card', {'query': 'auto'}),
  ),
  AgentBeat(
    focus: 'reader.blocks',
    say: "This is the good part. From any source online, Cachy pulls out proper "
        "structured notes — a one-liner, a summary, then clean blocks: steps, "
        "key facts, callouts. Let me scroll through them, block by block, all "
        "the way down.",
    action: AgentAction('scroll', {'target': 'reader', 'mode': 'steps'}),
  ),
  AgentBeat(
    focus: 'reader.insight',
    say: "Near the bottom there's a 'Going deeper' section — that's the AI "
        "adding the analysis the source only hinted at.",
    action: AgentAction('point'),
  ),
  AgentBeat(
    focus: 'reader.insight',
    say: "And 'Dive deeper' — let me open it. Inside are threads you can pull, "
        "a quick quiz, and a jumping-off point for deeper research.",
    action: AgentAction('expand_deep_dive'),
  ),
  AgentBeat(
    focus: 'reader.references',
    say: "Below that, references — books, films, products the card mentions. "
        "The trick: press and hold any reference and it's saved straight to "
        "your catalog.",
    action: AgentAction('point'),
  ),
  AgentBeat(
    focus: 'reader.ask',
    say: "Down on the bottom strip: Ask lets you chat with just this card, and "
        "next to it is whatever action fits the content — share it, turn it "
        "into a shopping list, drop it on a map.",
    action: AgentAction('point'),
  ),
  AgentBeat(
    focus: 'reader.more',
    say: "And the three dots hide the rest — copy, share, shopping list, and "
        "more.",
    action: AgentAction('point'),
  ),

  // ── 3. Concepts (top segment) ────────────────────────────────────────────
  AgentBeat(
    view: 'concepts',
    focus: 'content',
    say: "Back up top there are three segments. This one's Concepts — shared "
        "ideas Cachy mines across your cards and stitches together. Let me "
        "open one and define it on the spot.",
    action: AgentAction('define_concept', {'query': 'auto'}),
  ),

  // ── 4. Catalog (top segment) ─────────────────────────────────────────────
  AgentBeat(
    view: 'catalog',
    focus: 'catalog.item',
    say: "Next segment: the catalog. Remember those references you can hold to "
        "save? They land here. Tap one and the AI fills in everything it can "
        "find about it.",
    action: AgentAction('catalog_item'),
  ),

  // ── 5. Nav bar, one by one ───────────────────────────────────────────────
  AgentBeat(
    view: 'collections',
    focus: 'folders.create',
    say: "Now the bottom bar. Folders — your cards get auto-sorted in here, and "
        "you can make your own. Let me create one.",
    action: AgentAction('create_collection', {'name': 'Demo Folder'}),
  ),
  AgentBeat(
    focus: 'content',
    say: "...and drop a card into it. Done.",
    action: AgentAction('move_card'),
  ),
  AgentBeat(
    view: 'actions',
    focus: 'todo.item',
    say: "To-do. When you mark something as 'track in actions' inside a card, "
        "its tasks show up here. Let me follow one in.",
    action: AgentAction('follow_actions'),
  ),
  AgentBeat(
    focus: 'todo.item',
    say: "Tap an item and it expands to every task from that one note — and "
        "Cachy keeps nudging you until they're done.",
    action: AgentAction('toggle_action_item'),
  ),
  AgentBeat(
    view: 'feed',
    focus: 'feed.page',
    say: "Feed. Think of it like your Instagram feed, but it's your own saved "
        "knowledge — one-liners you can flick through. Let me scroll a few.",
    action: AgentAction('feed_next'),
  ),
  AgentBeat(
    focus: 'feed.page',
    say: "Keep going, or shuffle for a fresh set.",
    action: AgentAction('feed_shuffle'),
  ),
  AgentBeat(
    view: 'profile',
    focus: 'content',
    say: "Last tab is You — settings and your library stats. Nothing fancy, "
        "it's just home base.",
    action: AgentAction('point'),
  ),

  // ── 6. Top icons: Graph, Chat ────────────────────────────────────────────
  AgentBeat(
    view: 'library',
    say: "Back home for a second — up top there are two more.",
  ),
  AgentBeat(
    focus: 'top.graph',
    say: "The graph. Every card and concept is a node, linked by meaning. Watch "
        "the connections — and let me pull into one node's neighborhood.",
    action: AgentAction('graph_wander'),
  ),
  AgentBeat(
    focus: 'graph.canvas',
    action: AgentAction('graph_focus', {'query': 'auto'}),
  ),
  AgentBeat(
    view: 'library',
    say: "And the chat.",
  ),
  AgentBeat(
    focus: 'top.chat',
    say: "This one talks to your whole library at once — ask anything across "
        "everything you've saved and it answers from your own notes.",
    action: AgentAction('library_chat', {
      'query': 'What are the main themes across everything saved here?',
    }),
  ),

  // ── 7. Adding something to Cachy ─────────────────────────────────────────
  AgentBeat(
    view: 'library',
    say: "Last thing — let's add something new, live.",
  ),
  AgentBeat(
    focus: 'home.plus',
    say: "I'll hit the plus button, paste in a link, and Cachy runs the whole "
        "pipeline — fetching the page, pulling the text, and shaping it into a "
        "card while we watch.",
    action: AgentAction('create_card', {
      'url': 'https://en.wikipedia.org/wiki/Spaced_repetition',
    }),
  ),
  AgentBeat(
    focus: 'content',
    say: "Watch the stages run — fetching the page, pulling the text, shaping "
        "it into a card — and in a moment it opens as a brand-new card, built "
        "from nothing. That's Cachy. I'm not going anywhere though — tap me, "
        "ask me anything, or hand me a task.",
    action: AgentAction('point'),
  ),
];

class PresenterController extends ChangeNotifier {
  PresenterController({required CardRepository repository, required AgentBus bus})
      : _repo = repository,
        _bus = bus {
    _initTts();
  }

  final CardRepository _repo;
  final AgentBus _bus;
  final FlutterTts _tts = FlutterTts();

  PresenterPhase phase = PresenterPhase.idle;

  /// The line currently being spoken / last spoken — shown as an on-screen
  /// caption beside the glyph.
  String caption = '';

  /// Spotlight target the agent is currently presenting: a widget id
  /// registered on the [AgentBus] (e.g. 'search.field', 'graph.canvas'),
  /// a pseudo-region ('content', 'nav') the spotlight resolves to a coarse
  /// rect, or null for no spotlight. Set for the *whole* beat — narration and
  /// action — so the light behaves like a tour guide's pointer, gliding from
  /// target to target instead of flashing per action.
  String? focusId;

  /// True for the brief moment the agent "taps" the focused target — the
  /// overlay renders a tap ripple on the cursor. Every screen change / effect
  /// is preceded by one of these so the audience sees the click that caused it.
  bool tapping = false;

  bool _active = false;
  int _tourIndex = 0;
  final List<String> _questionQueue = [];

  // Cached library snapshot for resolving fuzzy targets ("open the coffee card").
  List<model.Card>? _cards;
  List<ConceptEntry>? _conceptCache;

  // The card the agent is currently demonstrating (opened/created), so reader,
  // chat, and rabbit-hole actions act on a coherent subject.
  String? _currentCardId;

  // The collection the agent most recently created, so it can move a card into
  // it on the next beat.
  String? _lastCollectionId;

  // A generation token distinguishes a natural utterance end from one we cut
  // short (to handle a barge-in). Each utterance bumps it; the awaiter checks
  // whether its token still matches when the completer resolves.
  int _gen = 0;
  Completer<void>? _speakCompleter;

  bool get isActive => _active;

  bool _voicePicked = false;

  Future<void> _initTts() async {
    _tts.setCompletionHandler(_finishUtterance);
    _tts.setCancelHandler(_finishUtterance);
    _tts.setErrorHandler((_) => _finishUtterance());
    try {
      // Rate scale differs by engine: the browser's Web Speech API treats 1.0
      // as normal speed (0.5 is half-speed — that's what felt sluggish), while
      // the native mobile engines treat ~0.5 as normal.
      await _tts.setSpeechRate(kIsWeb ? 1.0 : 0.52);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _selectNaturalVoice();
    } catch (e, st) {
      // Voice params are best-effort; speech still works with defaults.
      _logError('TTS init', e, st);
    }
  }

  /// Pick the most natural-sounding English voice the platform offers, instead
  /// of the robotic default. Web voices load asynchronously, so this is retried
  /// before the first utterance (see [_speak]).
  Future<void> _selectNaturalVoice() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      final voices = raw
          .whereType<Map>()
          .map((v) => v.map((k, val) => MapEntry('$k', '$val')))
          .toList();
      if (voices.isEmpty) return; // not loaded yet — try again next utterance
      final english = voices
          .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en'))
          .toList();
      final pool = english.isNotEmpty ? english : voices;

      int score(Map<String, String> v) {
        final name = (v['name'] ?? '').toLowerCase();
        if (name.contains('natural')) return 6; // Edge/Azure "… Natural"
        if (name.contains('google')) return 5; // Chrome's higher-quality set
        if (name.contains('samantha') || name.contains('ava')) return 4; // Apple
        if (name.contains('aria') || name.contains('jenny')) return 4; // MS
        if (name.contains('female')) return 2;
        return 1;
      }

      pool.sort((a, b) => score(b).compareTo(score(a)));
      final best = pool.first;
      await _tts.setVoice({
        'name': best['name'] ?? '',
        'locale': best['locale'] ?? 'en-US',
      });
      _voicePicked = true;
    } catch (e, st) {
      // Default voice is fine if selection isn't supported.
      _logError('voice selection', e, st);
    }
  }

  void _setPhase(PresenterPhase p, {String? caption}) {
    phase = p;
    if (caption != null) this.caption = caption;
    notifyListeners();
  }

  /// Log a presenter error into the backend's pipeline console (`start.py`'s
  /// terminal) — errors during Present mode are largely swallowed so one bad
  /// action/network call doesn't kill a live demo, but that means they'd
  /// otherwise vanish silently. Relayed to `/presenter/log` because
  /// `debugPrint` alone depends on the browser's DWDS forwarding actually
  /// reaching the terminal, which isn't reliable; also mirrored to
  /// `debugPrint` for anyone watching the browser console instead.
  void _logError(String where, Object error, [StackTrace? st]) {
    final line = '$where failed: $error';
    debugPrint('[Presenter] $line');
    if (st != null) debugPrintStack(stackTrace: st, label: '[Presenter] $where');
    _repo.api.presenterLog(line, level: 'error');
  }

  /// Trace an action the agent is about to take (navigate, run a search,
  /// scroll, open a card…) into the same pipeline console — so the log reads
  /// as a live transcript of the demo, not just a silence broken by errors.
  void _logInfo(String message) {
    debugPrint('[Presenter] $message');
    _repo.api.presenterLog(message);
  }

  /// A component the agent expected to act on never showed up in time (screen
  /// didn't mount, data never loaded) — the action just gets skipped rather
  /// than throwing, so this is the only trace that it happened.
  void _logWarn(String message) {
    debugPrint('[Presenter] $message');
    _repo.api.presenterLog(message, level: 'warning');
  }

  /// Run [fn], logging and swallowing any error under [label] instead of
  /// letting it escape — used to tag individual screen-hook calls (graph,
  /// feed, search, reader, the shell's onOpen* callbacks) so a failure names
  /// exactly which hook broke, not just the outer action type.
  Future<void> _try(String label, FutureOr<void> Function() fn) async {
    try {
      await fn();
    } catch (e, st) {
      _logError(label, e, st);
    }
  }

  void _finishUtterance() {
    final c = _speakCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Speak [text]; resolve true if it finished naturally, false if superseded by
  /// a barge-in.
  Future<bool> _speak(String text) async {
    if (text.trim().isEmpty) return true;
    if (!_voicePicked) await _selectNaturalVoice(); // web voices load late
    final myGen = ++_gen;
    _setPhase(PresenterPhase.speaking, caption: text);
    final completer = Completer<void>();
    _speakCompleter = completer;
    try {
      await _tts.speak(text);
    } catch (e, st) {
      // Web without a user gesture, or an unavailable engine, can throw here —
      // don't let it break the beat; treat the utterance as finished.
      _logError('tts.speak', e, st);
      _finishUtterance();
    }
    // Watchdog: on web the browser sometimes never fires the "end" event, which
    // would hang the whole tour on this completer forever. Cap the wait at a
    // generous estimate of how long the line takes to read so the beat always
    // advances.
    final words = text.trim().split(RegExp(r'\s+')).length;
    final capMs = (words * 420 + 2500).clamp(4000, 30000);
    await Future.any<void>([
      completer.future,
      Future<void>.delayed(Duration(milliseconds: capMs)),
    ]);
    return _gen == myGen && _active;
  }

  Future<void> _stopSpeaking() async {
    _gen++; // supersede whatever is (or was) speaking
    await _tts.stop();
    _finishUtterance();
  }

  // ── Public control ──────────────────────────────────────────────────────── //

  /// Begin the tour from the top.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _tourIndex = 0;
    // A heartbeat the moment Present mode loads — confirms the log relay is
    // wired before any error would need it.
    _repo.api.presenterLog('Present mode started');
    unawaited(_warmCards());
    // Lock in the natural voice before the first line, so the tour doesn't
    // open in the default (legacy) voice and switch part-way through.
    await _ensureVoice();
    await _runTour();
  }

  /// Web voices load asynchronously; poll until they're available and the
  /// natural one is chosen, so line one already speaks in the good voice.
  Future<void> _ensureVoice() async {
    for (var i = 0; i < 12 && _active && !_voicePicked; i++) {
      await _selectNaturalVoice();
      if (_voicePicked) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// The audience/presenter submitted a question or task. Interrupts the tour,
  /// gets handled, then the tour resumes.
  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || !_active) return;
    _questionQueue.add(q);
    if (phase == PresenterPhase.speaking) {
      await _stopSpeaking(); // tour/answer loop detects the barge-in and drains
    } else if (phase == PresenterPhase.idle) {
      await _handleQuestions();
      if (_active) _setPhase(PresenterPhase.idle, caption: _idlePrompt);
    }
    // If acting/thinking, the current loop drains the queue when it next checks.
  }

  /// End the presentation and silence any speech.
  Future<void> stop() async {
    _active = false;
    _questionQueue.clear();
    await _stopSpeaking();
    _setFocus(null);
    _setPhase(PresenterPhase.done);
    _repo.api.presenterLog('Present mode ended');
  }

  // ── Tour loop ─────────────────────────────────────────────────────────── //

  static const String _idlePrompt = 'Ask me anything, or tap to wrap up.';

  Future<void> _runTour() async {
    while (_active && _tourIndex < kTour.length) {
      final completed = await _runBeat(kTour[_tourIndex]);
      if (!_active) return;
      if (!completed || _questionQueue.isNotEmpty) {
        await _handleQuestions();
      } else {
        // A short breath between beats so the tour doesn't feel read off a
        // teleprompter.
        await _settle(ms: 450);
      }
      _tourIndex++;
    }
    if (!_active) return;
    _setFocus(null);
    _setPhase(PresenterPhase.idle, caption: _idlePrompt);
    // Idle floor: any later question is handled by ask().
  }

  /// Answer queued questions/tasks by performing them, then offer more before
  /// returning to the tour's natural flow.
  Future<void> _handleQuestions() async {
    while (_active && _questionQueue.isNotEmpty) {
      final q = _questionQueue.removeAt(0);
      _setFocus(null);
      _setPhase(PresenterPhase.thinking, caption: 'Thinking…');
      List<AgentBeat> beats;
      try {
        final raw = await _repo.api.presenterAsk(q);
        beats = raw.map(AgentBeat.fromJson).toList();
      } catch (e, st) {
        _logError('ask("$q")', e, st);
        beats = const [
          AgentBeat(say: "I couldn't reach the backend to answer that."),
        ];
      }
      if (!_active) return;
      for (final beat in beats) {
        final completed = await _runBeat(beat);
        if (!_active) return;
        if (!completed) break; // a fresh barge-in — loop drains it next
      }
      if (!_active) return;
      if (_questionQueue.isEmpty) {
        // Offer the floor; if they stay quiet we resume the tour.
        await _runBeat(const AgentBeat(
          say: "Anything else? Otherwise I'll carry on.",
        ));
      }
    }
  }

  /// Run one beat: switch view, light the spotlight target, then speak *while*
  /// performing the action — narration leads, the "hands" follow half a second
  /// later, like a human demoing. Returns false if speech was interrupted by a
  /// barge-in (so the caller can drain questions).
  Future<bool> _runBeat(AgentBeat beat) async {
    if (!_active) return false;
    // Navigation is itself a visible tap on the nav control that reaches it,
    // so a screen change never appears out of nowhere.
    if (beat.view != null) {
      await _gesture(_navTargetFor(beat.view!), () async {
        _logInfo('navigate → ${beat.view}');
        _bus.onNavigate?.call(beat.view!);
        await _settle();
      });
      if (!_active) return false;
    }
    // Light the target the narration is about, so the cursor glides onto it
    // while the agent talks.
    _setFocus(beat.focus ??
        (beat.action != null ? _targetFor(beat.action!.type) : null));
    Future<bool>? speech;
    if (beat.say != null && beat.say!.isNotEmpty) {
      speech = _speak(beat.say!);
    }
    if (beat.action != null) {
      if (speech != null) {
        // Let the narration lead before the hand moves. Scrolling gets a longer
        // lead so the glide starts *as* the agent says "let me scroll down",
        // not before it.
        final lead = beat.action!.type == 'scroll' ? 1300 : 550;
        await Future<void>.delayed(Duration(milliseconds: lead));
      } else {
        _setPhase(PresenterPhase.acting);
      }
      if (_active) {
        // Tap the lit target, then fire the effect — the click precedes the
        // change the audience sees.
        await _tap();
        try {
          await _execute(beat.action!);
        } catch (e, st) {
          // A live action failing shouldn't kill the presentation.
          _logError('action "${beat.action!.type}"', e, st);
        }
      }
    }
    final spoken = speech == null || await speech;
    if (!spoken) return false;
    return _active && _questionQueue.isEmpty;
  }

  void _setFocus(String? id) {
    if (focusId == id) return;
    focusId = id;
    tapping = false; // moving to a new target cancels any in-flight tap
    notifyListeners();
  }

  void _setTapping(bool v) {
    if (tapping == v) return;
    tapping = v;
    notifyListeners();
  }

  /// A visible "click" on the currently-focused target: pulse the tap ripple,
  /// hold briefly, then release. Callers fire the real effect right after so
  /// the audience sees the tap that caused the change. No-op if nothing's lit.
  Future<void> _tap() async {
    if (focusId == null || !_active) return;
    _setTapping(true);
    await _settle(ms: 220);
    _setTapping(false);
  }

  /// Glide the cursor to [targetId], tap it, then run [effect] — the full
  /// point-tap-act gesture used for navigation, so a screen change reads as a
  /// tap on the nav control that triggered it rather than a magic swap.
  Future<void> _gesture(String? targetId, FutureOr<void> Function() effect) async {
    _setFocus(targetId);
    await _settle(ms: 620); // let the cursor glide onto the target
    if (!_active) return;
    await _tap();
    if (!_active) return;
    await effect();
  }

  /// The nav control the agent taps to reach [view]: a bottom-nav tab, one of
  /// the library's top segments (Concepts/Catalog), or a top-bar icon
  /// (Graph/Chat/Search). Falls back to the coarse 'nav' region.
  String _navTargetFor(String view) => switch (view) {
        'library' => 'nav.home',
        'collections' => 'nav.folders',
        'actions' => 'nav.todo',
        'feed' => 'nav.feed',
        'profile' => 'nav.you',
        'concepts' => 'library.tab.concepts',
        'catalog' => 'library.tab.catalog',
        'graph' => 'top.graph',
        'search' => 'top.search',
        'connections' || 'chat' => 'top.chat',
        _ => 'nav',
      };

  /// Map an action to the spotlight target it visibly affects, so the light
  /// guides the audience to the right widget (with coarse fallbacks).
  String? _targetFor(String type) => switch (type) {
        'search' => 'search.field',
        'search_filter' => 'search.filters',
        'navigate' => 'nav',
        'graph_focus' ||
        'graph_open' ||
        'graph_wander' ||
        'graph_reset' ||
        'graph_cluster' ||
        'graph_concepts' =>
          'graph.canvas',
        'feed_next' || 'feed_prev' || 'feed_shuffle' => 'feed.page',
        'open_card' => 'card.first',
        'create_card' => 'home.plus',
        'reader_toggle' => 'reader.blocks',
        'rabbit_hole' || 'expand_deep_dive' => 'reader.insight',
        'card_chat' => 'reader.ask',
        'catalog_item' => 'catalog.item',
        'create_collection' => 'folders.create',
        'follow_actions' || 'toggle_action_item' => 'todo.item',
        'library_chat' => 'top.chat',
        // 'point' and 'scroll' rely on the beat's explicit focus.
        'point' || 'scroll' || 'wait' => null,
        _ => 'content',
      };

  // ── Action executor ───────────────────────────────────────────────────── //

  Future<void> _execute(AgentAction a) async {
    _logInfo('action → ${a.type}${a.args.isEmpty ? '' : ' ${a.args}'}');
    switch (a.type) {
      case 'navigate':
        if (a.view != null) {
          _bus.onNavigate?.call(a.view!);
          await _settle();
        }
      case 'wait':
        final ms = (a.args['ms'] as num?)?.toInt() ?? 800;
        await Future<void>.delayed(Duration(milliseconds: ms));
      case 'scroll':
        await _scrollSurface(a);
      case 'create_card':
        final url = a.url;
        if (url != null && url.isNotEmpty) {
          final id = await _bus.onCreateCard?.call(url);
          if (id != null && id.isNotEmpty) _currentCardId = id;
          await _settle(ms: 600);
        }
      case 'search':
        await _runSearch(a.query);
      case 'search_filter':
        await _searchFilter();
      case 'open_card':
        await _openCard(a.query);
      case 'reader_toggle':
        await _readerToggle();
      case 'graph_focus':
        await _graphFocus(a.query, open: false);
      case 'graph_open':
        await _graphFocus(a.query, open: true);
      case 'graph_wander':
        await _graphWander();
      case 'graph_reset':
        await _ensureGraph();
        await _try('graph.reset', () => _bus.graph?.reset());
        await _settle(ms: 700);
      case 'graph_cluster':
        await _ensureGraph();
        await _try('graph.filterCluster', () => _bus.graph?.filterCluster());
      case 'graph_concepts':
        await _ensureGraph();
        await _try('graph.toggleConcepts', () => _bus.graph?.toggleConcepts());
      case 'feed_next':
        await _feedStep(forward: true);
      case 'feed_prev':
        await _feedStep(forward: false);
      case 'feed_shuffle':
        await _feedShuffle();
      case 'open_concept':
      case 'define_concept':
        await _demoConcept(a.query);
      case 'create_collection':
        await _createCollection(a.args['name'] as String?);
      case 'move_card':
        await _moveCard();
      case 'follow_actions':
        await _followActions();
      case 'toggle_action_item':
        await _toggleActionItem();
      case 'card_chat':
        await _cardChat(a.query);
      case 'library_chat':
        await _libraryChat(a.query);
      case 'rabbit_hole':
        await _rabbitHole(a.query);
      case 'open_connections':
        _bus.onNavigate?.call('connections');
        await _settle(ms: 700);
      case 'catalog_item':
        await _try('onOpenCatalogItem', () => _bus.onOpenCatalogItem?.call());
        await _settle(ms: 900);
      case 'expand_deep_dive':
        await _try('onExpandDeepDive', () => _bus.onExpandDeepDive?.call());
        await _settle(ms: 700);
      case 'point':
        // Explain-only beat: the tap pulse already fired in _runBeat; nothing
        // to execute. The lit target is what the audience is looking at.
        break;
      default:
        break;
    }
  }

  /// Scroll a registered surface ('library' grid, 'reader' body) by `dy`
  /// pixels; with `sweep: true` it glides down, pauses, and glides back — the
  /// browsing gesture a human makes while talking over a screen.
  /// Scroll a registered surface. Modes:
  ///  * `steps` — page down a screenful at a time, pausing between each, all the
  ///    way to the bottom (block-by-block browsing of a card's notes).
  ///  * `full`  — glide all the way to the bottom in one motion.
  ///  * default — glide down by `dy`.
  /// With `sweep: true` it then glides back to where it started.
  Future<void> _scrollSurface(AgentAction a) async {
    final target = (a.args['target'] as String?) ?? 'library';
    final mode = (a.args['mode'] as String?) ?? 'sweep';
    final dy = (a.args['dy'] as num?)?.toDouble() ?? 600;
    final sweep = a.args['sweep'] == true;
    // The surface may have just navigated/opened; give it a moment to lay out
    // so there's something to scroll (otherwise it no-ops instantly).
    await _waitFor(() => _bus.scrollRoom(target) > 8,
        what: 'scrollable "$target"', timeoutMs: 2500);
    if (!_active) return;

    var moved = 0.0;
    if (mode == 'steps') {
      // Page down block by block until we reach the bottom (bounded so a huge
      // card can't loop forever).
      for (var i = 0; i < 14 && _active && _bus.scrollRoom(target) > 8; i++) {
        double step = 0;
        await _try('scroll($target step)', () async {
          step = await _bus.scrollBy(target, 300,
              duration: const Duration(milliseconds: 700));
        });
        moved += step;
        if (step.abs() < 1) break;
        await _settle(ms: 650); // a beat to "read" each block
      }
    } else {
      // 'full' clamps to the bottom; otherwise glide down by dy.
      final distance = mode == 'full' ? 1000000.0 : dy;
      await _try('scroll($target)', () async {
        moved = await _bus.scrollBy(target, distance,
            duration: const Duration(milliseconds: 1600));
      });
    }

    if (sweep && moved.abs() > 1 && _active) {
      await _settle(ms: 800);
      if (!_active) return;
      await _try('scroll($target, back)', () async {
        await _bus.scrollBy(target, -moved,
            duration: const Duration(milliseconds: 1300));
      });
    }
  }

  Future<void> _runSearch(String? query) async {
    _bus.onNavigate?.call('search');
    final ready =
        await _waitFor(() => _bus.search != null, what: 'search screen', timeoutMs: 4000);
    if (!ready) return;
    final q = _resolveSearchQuery(query);
    await _try('search.run("$q")', () => _bus.search?.run(q));
    await _settle(ms: 900);
  }

  Future<void> _searchFilter() async {
    _bus.onNavigate?.call('search');
    final ready =
        await _waitFor(() => _bus.search != null, what: 'search screen', timeoutMs: 4000);
    if (!ready) return;
    await _try('search.filter', () => _bus.search?.filter());
    await _settle(ms: 700);
  }

  Future<void> _openCard(String? query) async {
    final cards = await _warmCards();
    final match = _bestCard(query, cards);
    if (match == null) {
      _logWarn('open_card: no cards to open yet — skipped');
      return;
    }
    _currentCardId = match.cardId;
    await _try('onOpenCard(${match.cardId})',
        () => _bus.onOpenCard?.call(match.cardId));
    // Wait for the reader to mount and load the card before moving on, so the
    // block-by-block scroll and deep-dive beats act on a fully-open reader
    // instead of racing a half-built one.
    await _waitFor(() => _bus.reader?.isReady() == true,
        what: 'reader (open_card)', timeoutMs: 6000);
    await _settle(ms: 400);
  }

  Future<void> _readerToggle() async {
    final card = await _cardForDemo();
    if (card == null) return;
    _currentCardId = card.cardId;
    await _try(
        'onOpenCard(${card.cardId})', () => _bus.onOpenCard?.call(card.cardId));
    final ready =
        await _waitFor(() => _bus.reader?.isReady() == true, what: 'reader');
    final r = _bus.reader;
    // No nested _speak here: actions may now run concurrently with narration,
    // and a second utterance would orphan the first one's completer.
    if (!ready || r == null) return;
    var did = false;
    await _try('reader.toggleCheck', () async => did = await r.toggleCheck());
    if (!did) await _try('reader.toggleStep', () => r.toggleStep());
    await _settle(ms: 600);
  }

  Future<void> _graphFocus(String? query, {required bool open}) async {
    await _ensureGraph();
    final g = _bus.graph;
    if (g == null) return;
    final nodes = g.nodes();
    if (nodes.isEmpty) return;
    final target = query == null || query.isEmpty || query == 'auto'
        ? _mostConnected(nodes)
        : _bestNode(query, nodes);
    if (target == null) return;
    if (open) {
      if (target.isCard) _currentCardId = target.id;
      await _try('graph.open(${target.id})', () => g.open(target.id));
    } else {
      await _try('graph.focus(${target.id})', () => g.focus(target.id));
    }
    await _settle(ms: 400);
  }

  Future<void> _graphWander() async {
    await _ensureGraph();
    await _try('graph.wander', () => _bus.graph?.wander());
  }

  Future<void> _feedStep({required bool forward}) async {
    _bus.onNavigate?.call('feed');
    final ready =
        await _waitFor(() => _bus.feed != null, what: 'feed screen', timeoutMs: 4000);
    final f = _bus.feed;
    if (!ready || f == null) return;
    await _try(forward ? 'feed.next' : 'feed.prev',
        () => forward ? f.next() : f.prev());
    await _settle(ms: 900);
  }

  Future<void> _feedShuffle() async {
    _bus.onNavigate?.call('feed');
    final ready =
        await _waitFor(() => _bus.feed != null, what: 'feed screen', timeoutMs: 4000);
    if (!ready) return;
    await _try('feed.shuffle', () => _bus.feed?.shuffle());
    await _settle(ms: 1200);
  }

  Future<void> _ensureGraph() async {
    _bus.onNavigate?.call('graph');
    await _waitFor(() => _bus.graph?.isReady() == true,
        what: 'graph screen', timeoutMs: 9000);
  }

  Future<void> _demoConcept(String? query) async {
    final concepts = await _warmConcepts();
    if (concepts.isEmpty) return; // nothing mined yet — skip quietly
    final match = (query == null || query.isEmpty || query == 'auto')
        ? concepts.first
        : (_bestBy(query, concepts, (c) => c.name) ?? concepts.first);
    try {
      await _repo.defineConcept(match.id);
    } catch (e, st) {
      // best-effort; the detail screen still opens and can define on demand.
      _logError('defineConcept(${match.id})', e, st);
    }
    await _try('onOpenConcept(${match.id})',
        () => _bus.onOpenConcept?.call(match.id, match.name));
    await _settle(ms: 700);
  }

  Future<void> _createCollection(String? name) async {
    final n = (name == null || name.isEmpty) ? 'Demo Folder' : name;
    try {
      final col = await _repo.createCollection(n);
      _lastCollectionId = col.id;
    } catch (e, st) {
      _logError('createCollection("$n")', e, st);
    }
    _bus.onNavigate?.call('collections');
    await _settle(ms: 900);
  }

  Future<void> _moveCard() async {
    final card = await _cardForDemo();
    if (card == null) return;
    var colId = _lastCollectionId;
    if (colId == null) {
      try {
        final col = await _repo.createCollection('Demo Folder');
        colId = col.id;
        _lastCollectionId = colId;
      } catch (e, st) {
        _logError('createCollection (for move)', e, st);
        return;
      }
    }
    try {
      await _repo.moveCardToCollection(card.cardId, colId);
    } catch (e, st) {
      _logError('moveCardToCollection(${card.cardId})', e, st);
    }
    _bus.onNavigate?.call('collections');
    await _settle(ms: 900);
  }

  Future<void> _followActions() async {
    final card = await _cardWithActions();
    _bus.onNavigate?.call('actions');
    if (card == null || card.actionItems.items.isEmpty) {
      await _settle(ms: 700);
      return;
    }
    _currentCardId = card.cardId;
    try {
      await _repo.patchActionItems(
        card.cardId,
        model.ActionItems(followed: true, items: card.actionItems.items).toJson(),
      );
    } catch (e, st) {
      _logError('patchActionItems (follow, ${card.cardId})', e, st);
    }
    // The hub caches its list on load — reload it so the card we just followed
    // actually appears, otherwise the To-do screen looks empty.
    await _try('onRefreshActions', () => _bus.onRefreshActions?.call());
    await _settle(ms: 900);
  }

  Future<void> _toggleActionItem() async {
    final card = await _cardWithActions();
    if (card == null || card.actionItems.items.isEmpty) return;
    // Expand the card's group first, so all of that note's to-dos are visible —
    // the "tap an item and it expands" beat.
    _bus.onExpandActionGroup?.call(card.cardId);
    await _settle(ms: 550);
    final first = card.actionItems.items.first;
    final updated = model.ActionItems(
      followed: true,
      items: [
        for (final it in card.actionItems.items)
          it.id == first.id
              ? model.ActionItem(id: it.id, text: it.text, done: !it.done)
              : it,
      ],
    );
    try {
      await _repo.patchActionItems(card.cardId, updated.toJson());
    } catch (e, st) {
      _logError('patchActionItems (toggle, ${card.cardId})', e, st);
    }
    await _try('onRefreshActions', () => _bus.onRefreshActions?.call());
    await _settle(ms: 800);
  }

  Future<void> _cardChat(String? query) async {
    final card = await _cardForDemo();
    if (card == null) return;
    final seed = (query == null || query.isEmpty)
        ? 'What is the single most useful takeaway here?'
        : query;
    final title =
        card.base.oneLiner.isNotEmpty ? card.base.oneLiner : 'This card';
    await _try('onOpenCardChat(${card.cardId})',
        () => _bus.onOpenCardChat?.call(card.cardId, title, seed));
    await _settle(ms: 1000);
  }

  Future<void> _libraryChat(String? query) async {
    final seed = (query == null || query.isEmpty)
        ? 'What are the main themes across everything saved here?'
        : query;
    await _try('onOpenLibraryChat', () => _bus.onOpenLibraryChat?.call(seed));
    await _settle(ms: 1000);
  }

  Future<void> _rabbitHole(String? query) async {
    final card = await _cardForDemo();
    if (card == null) return;
    final seed = (query == null || query.isEmpty || query == 'auto')
        ? (card.base.oneLiner.isNotEmpty ? card.base.oneLiner : 'Tell me more')
        : query;
    await _try('onOpenRabbitHole(${card.cardId})',
        () => _bus.onOpenRabbitHole?.call(card.cardId, seed));
    await _settle(ms: 1000);
  }

  // ── Target resolution ─────────────────────────────────────────────────── //

  Future<List<model.Card>> _warmCards() async {
    if (_cards != null) return _cards!;
    try {
      _cards = await _repo.list();
    } catch (e, st) {
      _logError('warmCards (repo.list)', e, st);
      _cards = const [];
    }
    return _cards!;
  }

  Future<List<ConceptEntry>> _warmConcepts() async {
    if (_conceptCache != null) return _conceptCache!;
    try {
      _conceptCache = await _repo.concepts();
    } catch (e, st) {
      _logError('warmConcepts (repo.concepts)', e, st);
      _conceptCache = const [];
    }
    return _conceptCache!;
  }

  /// The card the agent should demonstrate: the one it's currently on, else the
  /// first in the library.
  Future<model.Card?> _cardForDemo() async {
    final cards = await _warmCards();
    if (cards.isEmpty) return null;
    if (_currentCardId != null) {
      for (final c in cards) {
        if (c.cardId == _currentCardId) return c;
      }
    }
    return cards.first;
  }

  /// The first card that actually has to-do items (for the Actions demo), else
  /// any card.
  Future<model.Card?> _cardWithActions() async {
    final cards = await _warmCards();
    for (final c in cards) {
      if (c.actionItems.items.isNotEmpty) return c;
    }
    return cards.isEmpty ? null : cards.first;
  }

  String _resolveSearchQuery(String? query) {
    if (query != null && query.isNotEmpty && query != 'auto') return query;
    final cards = _cards ?? const [];
    for (final c in cards) {
      if (c.base.tags.isNotEmpty) return c.base.tags.first;
    }
    if (cards.isNotEmpty) {
      final words = cards.first.base.oneLiner.split(RegExp(r'\s+'));
      final word = words.firstWhere((w) => w.length > 4, orElse: () => 'idea');
      return word.replaceAll(RegExp(r'[^A-Za-z]'), '');
    }
    return 'idea';
  }

  model.Card? _bestCard(String? query, List<model.Card> cards) {
    if (cards.isEmpty) return null;
    if (query == null || query.isEmpty) return cards.first;
    String label(model.Card c) =>
        '${c.base.oneLiner} ${c.source.caption} ${c.base.tags.join(' ')}';
    return _bestBy(query, cards, label) ?? cards.first;
  }

  GraphNode? _bestNode(String query, List<GraphNode> nodes) =>
      _bestBy(query, nodes, (n) => '${n.label} ${n.tags.join(' ')}');

  GraphNode? _mostConnected(List<GraphNode> nodes) {
    final sorted = [...nodes]..sort((a, b) => b.degree.compareTo(a.degree));
    return sorted.isEmpty ? null : sorted.first;
  }

  /// Simple token-overlap fuzzy match — good enough to point the agent at the
  /// right card/node from a spoken query.
  T? _bestBy<T>(String query, List<T> items, String Function(T) labelOf) {
    final qTokens = _tokens(query);
    if (qTokens.isEmpty) return null;
    T? best;
    var bestScore = 0.0;
    for (final item in items) {
      final label = labelOf(item).toLowerCase();
      final lTokens = _tokens(label);
      var score = 0.0;
      for (final t in qTokens) {
        if (lTokens.contains(t)) {
          score += 2;
        } else if (label.contains(t)) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return bestScore > 0 ? best : null;
  }

  Set<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 2)
      .toSet();

  // ── Timing helpers ────────────────────────────────────────────────────── //

  /// Give a freshly-navigated screen a beat to mount/animate in.
  Future<void> _settle({int ms = 320}) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Poll [ready] until true or [timeoutMs] elapses; returns whether it
  /// became ready. A screen/hook that never mounts doesn't throw — the
  /// dependent action just quietly no-ops — so this is the only trace that a
  /// component failed to show up in time, logged under [what].
  Future<bool> _waitFor(
    bool Function() ready, {
    required String what,
    int timeoutMs = 5000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (_active && !ready() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final ok = ready();
    if (!ok && _active) {
      _logWarn('$what never became ready after ${timeoutMs}ms — skipped');
    }
    return ok;
  }

  @override
  void dispose() {
    _active = false;
    _tts.stop();
    super.dispose();
  }
}
