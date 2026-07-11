/// Stateless HTTP wrapper around the FastAPI backend (docs/05 endpoints).
/// Returns raw domain models; caching/offline lives in the repository layer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/artifact.dart';
import 'local_store.dart';
import '../../domain/models/card.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/concept.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/feed.dart';
import '../../domain/models/graph.dart';
import 'lan_discovery.dart';
import '../../domain/models/pipeline_event.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message; // raw body — for logs only, never for UI

  /// What users see. Raw bodies (which may include server details or
  /// tracebacks) never leave the data layer.
  String get friendlyMessage => switch (statusCode) {
        401 || 403 => 'Session expired — please sign in again.',
        404 => "That card isn't there anymore.",
        429 => "You've hit today's limit. It resets at midnight UTC.",
        >= 500 => 'Something went wrong on our side. Try again in a moment.',
        _ => "That didn't work. Try again.",
      };

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// UI-safe message for any thrown object. The only thing view-models should
/// ever store in a user-visible error field.
String friendlyError(Object e) => switch (e) {
      ApiException api => api.friendlyMessage,
      _ => "Can't reach Cachy. Check your connection.",
    };

class CreateCardResult {
  const CreateCardResult({
    required this.cardId,
    required this.state,
    required this.cached,
    this.quotaDegraded = false,
  });
  final String cardId;
  final CardState state;
  final bool cached;

  /// Past today's AI budget — server will produce a paragraph fallback card;
  /// the on-device model (if installed) can upgrade it afterwards.
  final bool quotaDegraded;
}

/// One card cited by a library-chat answer.
class LibrarySource {
  const LibrarySource({required this.cardId, required this.oneLiner});
  final String cardId;
  final String oneLiner;
}

/// A library-chat turn result: the reply plus the cards it was grounded on.
class LibraryChatResult {
  const LibraryChatResult({required this.reply, required this.sources});
  final String reply;
  final List<LibrarySource> sources;
}

/// One step down the rabbit hole (docs/14): the tapped [topic], its
/// [explanation], and the fresh [threads] that branch onward from it.
class RabbitHoleStep {
  const RabbitHoleStep({
    required this.topic,
    required this.explanation,
    required this.threads,
  });
  final String topic;
  final String explanation;
  final List<String> threads;
}

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    LocalStore? store,
    this.tokenProvider,
  })  : baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _store = store;

  /// Supplies the Firebase ID token (uid = backend owner_id). `forceRefresh`
  /// mints a fresh token after a 401. Null when signed out.
  final Future<String?> Function({bool forceRefresh})? tokenProvider;

  /// Default backend for end users: the hosted Hugging Face Space, so a plain
  /// `flutter build apk` connects with zero config. Override at build time with
  /// `--dart-define=CACHY_API_BASE=https://host` (empty = same-origin, for the
  /// web deploy).
  static const String _hostedDefault = 'https://vatxzz-cachy.hf.space';
  static const String _defaultBaseUrl = String.fromEnvironment(
    'CACHY_API_BASE',
    defaultValue: _hostedDefault,
  );

  /// The build-time default backend (hosted Space, or a `--dart-define`), used
  /// by Developer settings to reset a manual override.
  static String get defaultBaseUrl => _defaultBaseUrl;

  /// Resolve the backend URL at launch. A manual override set in Developer
  /// settings (persisted) wins so it sticks across launches; otherwise use the
  /// build-time default (the hosted Space, or a `--dart-define` for local dev).
  static Future<String> resolveBaseUrl({LocalStore? store}) async {
    final stored = store?.apiBaseUrl;
    if (stored != null && stored.isNotEmpty) return stored;
    return _defaultBaseUrl;
  }

  String baseUrl;
  final http.Client _client;
  final LocalStore? _store;

  void setBaseUrl(String url) {
    baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    if (_store != null) unawaited(_store.setApiBaseUrl(baseUrl));
  }

  Future<String?> discoverAndUpdateBaseUrl() async {
    final discovered = await discoverBackend();
    if (discovered != null) setBaseUrl(discovered);
    return discovered;
  }

  Future<Map<String, String>> _authHeader({bool forceRefresh = false}) async {
    final token = await tokenProvider?.call(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) return const {};
    return {'authorization': 'Bearer $token'};
  }

  /// All verbs funnel through here: auth header + one refresh-retry on 401.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) go, {
    Map<String, String> extra = const {},
  }) async {
    var resp = await go({...extra, ...await _authHeader()});
    if (resp.statusCode == 401 && tokenProvider != null) {
      resp = await go({...extra, ...await _authHeader(forceRefresh: true)});
    }
    return resp;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse('$baseUrl$path')
      .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));

  /// Resolve a media reference returned by the backend. Absolute URLs pass
  /// through; bare paths are joined onto the base host (forward-compatible with
  /// a static media mount or an absolute R2 URL).
  String resolveMedia(String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    final path = ref.startsWith('/') ? ref : '/$ref';
    return '$baseUrl$path';
  }

  // ------------------------------------------------------------------------- //
  // Cards
  // ------------------------------------------------------------------------- //

  Future<CreateCardResult> createCard(String url) async {
    final resp = await _send(
      (h) => _client.post(_uri('/cards'), headers: h, body: jsonEncode({'url': url})),
      extra: const {'content-type': 'application/json'},
    );
    final json = _decodeMap(resp);
    return CreateCardResult(
      cardId: (json['card_id'] as String?) ?? '',
      state: CardState.fromWire(json['state'] as String?),
      cached: (json['cached'] as bool?) ?? false,
      quotaDegraded: (json['quota_degraded'] as bool?) ?? false,
    );
  }

  /// Stored extraction bundle of a quota-degraded card, or null when the
  /// server has none (not degraded / already upgraded / not the owner).
  Future<Map<String, String>?> getBundle(String cardId) async {
    final resp = await _send((h) => _client.get(_uri('/cards/$cardId/bundle'), headers: h));
    if (resp.statusCode == 404) return null;
    final json = _decodeMap(resp);
    return {
      'bundle': (json['bundle'] as String?) ?? '',
      'transcript': (json['transcript'] as String?) ?? '',
      'caption': (json['caption'] as String?) ?? '',
    };
  }

  /// Upload a device-generated structured card. The server re-validates and
  /// throws [ApiException] (422) when the payload doesn't survive validation.
  Future<Card> uploadStructure(String cardId, Map<String, dynamic> payload) async {
    final resp = await _send(
      (h) => _client.post(_uri('/cards/$cardId/structure'), headers: h, body: jsonEncode(payload)),
      extra: const {'content-type': 'application/json'},
    );
    return Card.fromJson(_decodeMap(resp));
  }

  Future<Card> getCard(String cardId) async {
    final resp = await _send((h) => _client.get(_uri('/cards/$cardId'), headers: h));
    return Card.fromJson(_decodeMap(resp));
  }

  Future<List<Card>> listCards({
    CardState? state,
    String? contentType,
    String? collectionId,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _send((h) => _client.get(
          _uri('/cards', {
            'state': ?state?.wire,
            'content_type': ?contentType,
            'collection_id': ?collectionId,
            'limit': limit,
            'offset': offset,
          }),
          headers: h,
        ));
    return _decodeList(resp).map(Card.fromJson).toList();
  }

  /// Persist user-mutable block state (e.g. checked items). Sends raw block JSON.
  Future<Card> patchCardBlocks(
    String cardId,
    List<Map<String, dynamic>> blocks,
  ) async {
    final resp = await _send(
      (h) => _client.patch(_uri('/cards/$cardId'), headers: h, body: jsonEncode({'blocks': blocks})),
      extra: const {'content-type': 'application/json'},
    );
    return Card.fromJson(_decodeMap(resp));
  }

  /// Persist the card's action list (docs/13): follow toggle + per-item done.
  Future<Card> patchCardActionItems(
    String cardId,
    Map<String, dynamic> actionItems,
  ) async {
    final resp = await _send(
      (h) => _client.patch(_uri('/cards/$cardId'),
          headers: h, body: jsonEncode({'action_items': actionItems})),
      extra: const {'content-type': 'application/json'},
    );
    return Card.fromJson(_decodeMap(resp));
  }

  Future<void> deleteCard(String cardId) async {
    final resp = await _send((h) => _client.delete(_uri('/cards/$cardId'), headers: h));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> importCards(List<Map<String, dynamic>> cards) async {
    if (cards.isEmpty) return;
    final resp = await _send(
      (h) => _client.post(_uri('/cards/import'), headers: h, body: jsonEncode({'cards': cards})),
      extra: const {'content-type': 'application/json'},
    );
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
  }

  Future<List<Card>> search(String query, {int limit = 30}) async {
    final resp = await _send(
        (h) => _client.get(_uri('/search', {'q': query, 'limit': limit}), headers: h));
    return _decodeList(resp).map(Card.fromJson).toList();
  }

  /// Grounded Q&A over one card (docs/13). Send the full history each turn as
  /// [{'role','content'}]; returns the assistant's reply text. The conversation
  /// is persisted server-side per owner (docs/14).
  Future<String> chat(String cardId, List<Map<String, String>> messages) async {
    final resp = await _send(
      (h) => _client.post(_uri('/cards/$cardId/chat'),
          headers: h, body: jsonEncode({'messages': messages})),
      extra: const {'content-type': 'application/json'},
    );
    return (_decodeMap(resp)['reply'] as String?) ?? '';
  }

  /// Restore this owner's saved chat for a card (docs/14) as
  /// [{'role','content'}] maps, oldest → newest. Empty when none saved.
  Future<List<Map<String, String>>> chatHistory(String cardId) async {
    final resp = await _send((h) => _client.get(_uri('/cards/$cardId/chat'), headers: h));
    return _decodeMessages(_decodeMap(resp)['messages']);
  }

  /// Explore one thread of the rabbit hole (docs/14). Unlike [chat], this is not
  /// confined to the card: it returns an [explanation] drawn from general
  /// knowledge plus fresh follow-on [threads]. Send the [trail] of threads
  /// already explored plus the [root] topic; the exploration is persisted
  /// server-side per owner, keyed by root.
  Future<RabbitHoleStep> exploreRabbitHole(
    String cardId,
    String topic,
    List<String> trail,
    String root,
  ) async {
    final resp = await _send(
      (h) => _client.post(_uri('/cards/$cardId/rabbithole'),
          headers: h, body: jsonEncode({'topic': topic, 'trail': trail, 'root': root})),
      extra: const {'content-type': 'application/json'},
    );
    final json = _decodeMap(resp);
    return RabbitHoleStep(
      topic: topic,
      explanation: (json['explanation'] as String?) ?? '',
      threads: ((json['threads'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Restore this owner's saved rabbit-hole trail for a card + [root] topic
  /// (docs/14), oldest → deepest. Empty when none saved.
  Future<List<RabbitHoleStep>> rabbitHoleHistory(String cardId, String root) async {
    final resp = await _send((h) =>
        _client.get(_uri('/cards/$cardId/rabbithole', {'root': root}), headers: h));
    return ((_decodeMap(resp)['steps'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((s) => RabbitHoleStep(
              topic: (s['topic'] as String?) ?? '',
              explanation: (s['explanation'] as String?) ?? '',
              threads: ((s['threads'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList(),
            ))
        .toList();
  }

  // ------------------------------------------------------------------------- //
  // Collections
  // ------------------------------------------------------------------------- //

  Future<List<CollectionEntry>> listCollections() async {
    final resp = await _send((h) => _client.get(_uri('/collections'), headers: h));
    return _decodeList(resp).map(CollectionEntry.fromJson).toList();
  }

  Future<CollectionEntry> renameCollection(String id, String name) async {
    final resp = await _send(
      (h) => _client.patch(_uri('/collections/$id'), headers: h, body: jsonEncode({'name': name})),
      extra: const {'content-type': 'application/json'},
    );
    return CollectionEntry.fromJson(_decodeMap(resp));
  }

  Future<CollectionEntry> createCollection(String name) async {
    final resp = await _send(
      (h) => _client.post(_uri('/collections'), headers: h, body: jsonEncode({'name': name})),
      extra: const {'content-type': 'application/json'},
    );
    return CollectionEntry.fromJson(_decodeMap(resp));
  }

  Future<void> moveCardToCollection(String cardId, String? collectionId) async {
    final resp = await _send(
      (h) => _client.post(_uri('/collections/cards/$cardId/move'),
          headers: h, body: jsonEncode({'collection_id': collectionId})),
      extra: const {'content-type': 'application/json'},
    );
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
  }

  // ------------------------------------------------------------------------- //
  // Catalog — referenced artifacts aggregated across cards (docs/12)
  // ------------------------------------------------------------------------- //

  Future<List<CatalogEntry>> listCatalog({
    ArtifactType? type,
    int limit = 200,
    int offset = 0,
  }) async {
    final resp = await _send((h) => _client.get(
          _uri('/catalog', {
            'type': ?type?.wire,
            'limit': limit,
            'offset': offset,
          }),
          headers: h,
        ));
    return _decodeList(resp).map(CatalogEntry.fromJson).toList();
  }

  Future<void> deleteCatalogEntry(String artifactId) async {
    final resp = await _send((h) => _client.delete(_uri('/catalog/$artifactId'), headers: h));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
  }

  /// Save a referenced artifact into the catalog tab (long-press to save).
  Future<CatalogEntry> saveCatalogEntry(String artifactId) async {
    final resp = await _send((h) => _client.post(_uri('/catalog/$artifactId/save'), headers: h));
    return CatalogEntry.fromJson(_decodeMap(resp));
  }

  /// Generate + persist the on-demand LLM detail for an artifact (Fetch info).
  Future<CatalogEntry> fetchCatalogInfo(String artifactId) async {
    final resp =
        await _send((h) => _client.post(_uri('/catalog/$artifactId/fetch-info'), headers: h));
    return CatalogEntry.fromJson(_decodeMap(resp));
  }

  /// Artifacts a single card references (docs/12) — the reader "References" strip.
  Future<List<CatalogEntry>> cardArtifacts(String cardId, {int limit = 50}) async {
    final resp = await _send((h) =>
        _client.get(_uri('/catalog', {'card_id': cardId, 'limit': limit}), headers: h));
    return _decodeList(resp).map(CatalogEntry.fromJson).toList();
  }

  // ------------------------------------------------------------------------- //
  // Concepts — evergreen ideas aggregated across cards
  // ------------------------------------------------------------------------- //

  Future<List<ConceptEntry>> listConcepts({String? cardId, int limit = 200}) async {
    final resp = await _send((h) => _client.get(
          _uri('/concepts', {
            'card_id': ?cardId,
            'limit': limit,
          }),
          headers: h,
        ));
    return _decodeList(resp).map(ConceptEntry.fromJson).toList();
  }

  Future<ConceptDetail> getConcept(String conceptId) async {
    final resp = await _send((h) => _client.get(_uri('/concepts/$conceptId'), headers: h));
    return ConceptDetail.fromJson(_decodeMap(resp));
  }

  Future<ConceptEntry> defineConcept(String conceptId) async {
    final resp = await _send((h) => _client.post(_uri('/concepts/$conceptId/define'), headers: h));
    return ConceptEntry.fromJson(_decodeMap(resp));
  }

  Future<void> deleteConcept(String conceptId) async {
    final resp = await _send((h) => _client.delete(_uri('/concepts/$conceptId'), headers: h));
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
  }

  // ------------------------------------------------------------------------- //
  // Knowledge graph — cards as nodes, similarity as edges
  // ------------------------------------------------------------------------- //

  Future<GraphData> graph({double threshold = 0.55, int topK = 4}) async {
    final resp = await _send((h) =>
        _client.get(_uri('/graph', {'threshold': threshold, 'top_k': topK}), headers: h));
    return GraphData.fromJson(_decodeMap(resp));
  }

  // ------------------------------------------------------------------------- //
  // Library chat — cross-card grounded Q&A (docs/09)
  // ------------------------------------------------------------------------- //

  /// Cross-card Q&A. Stateless like single-card chat: replay the full history.
  /// Returns the reply plus the cards it was grounded on.
  Future<LibraryChatResult> libraryChat(
      List<Map<String, String>> messages) async {
    final resp = await _send(
      (h) => _client.post(_uri('/library/chat'),
          headers: h, body: jsonEncode({'messages': messages})),
      extra: const {'content-type': 'application/json'},
    );
    final json = _decodeMap(resp);
    final sources = ((json['sources'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((s) => LibrarySource(
              cardId: (s['card_id'] as String?) ?? '',
              oneLiner: (s['one_liner'] as String?) ?? '',
            ))
        .toList();
    return LibraryChatResult(
      reply: (json['reply'] as String?) ?? '',
      sources: sources,
    );
  }

  /// Restore this owner's saved library chat (docs/14) as [{'role','content'}]
  /// maps, oldest → newest. Empty when none saved.
  Future<List<Map<String, String>>> libraryChatHistory() async {
    final resp = await _send((h) => _client.get(_uri('/library/chat'), headers: h));
    return _decodeMessages(_decodeMap(resp)['messages']);
  }

  // ------------------------------------------------------------------------- //
  // Knowledge Feed + Connections (serendipity)
  // ------------------------------------------------------------------------- //

  /// The reel-style knowledge feed: a shuffled stream of moments built from the
  /// owner's cards. Owner-scoped.
  Future<List<FeedItem>> feed({int limit = 40}) async {
    final resp =
        await _send((h) => _client.get(_uri('/feed', {'limit': limit}), headers: h));
    return ((_decodeMap(resp)['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedItem.fromJson)
        .toList();
  }

  /// Surprising links between the owner's cards. [refresh] spends a little more
  /// LLM budget to surface fresh connections.
  Future<List<Connection>> connections({int limit = 12, bool refresh = false}) async {
    final resp = await _send((h) => _client.get(
          _uri('/connections', {'limit': limit, if (refresh) 'refresh': true}),
          headers: h,
        ));
    return ((_decodeMap(resp)['connections'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Connection.fromJson)
        .toList();
  }


  // ------------------------------------------------------------------------- //
  // SSE pipeline stream — GET /cards/{id}/stream
  // ------------------------------------------------------------------------- //

  /// Subscribe to the transparent pipeline. Yields a [PipelineEvent] per stage
  /// and completes when the card reaches a terminal state. Caller cancels the
  /// subscription to disconnect early.
  Stream<PipelineEvent> streamCard(String cardId) async* {
    final request = http.Request('GET', _uri('/cards/$cardId/stream'))
      ..headers['accept'] = 'text/event-stream'
      ..headers.addAll(await _authHeader());
    final response = await _client.send(request);
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, 'stream failed');
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final dataBuffer = StringBuffer();
    await for (final line in lines) {
      if (line.isEmpty) {
        // Blank line terminates an SSE event; flush the accumulated data.
        if (dataBuffer.isNotEmpty) {
          final event = _parseEvent(dataBuffer.toString());
          dataBuffer.clear();
          if (event != null) {
            yield event;
            if (event.isTerminal) return;
          }
        }
        continue;
      }
      if (line.startsWith(':')) continue; // comment / keep-alive frame
      if (line.startsWith('data:')) {
        dataBuffer.write(line.substring(5).trimLeft());
      }
    }
  }

  PipelineEvent? _parseEvent(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return PipelineEvent.fromJson(decoded);
    } catch (_) {
      // Ignore malformed frames; the stream stays alive.
    }
    return null;
  }

  // ------------------------------------------------------------------------- //
  // Decoding helpers
  // ------------------------------------------------------------------------- //

  Map<String, dynamic> _decodeMap(http.Response resp) {
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException(resp.statusCode, 'expected object, got ${decoded.runtimeType}');
  }

  /// Normalise a decoded `messages` array into role/content string maps.
  List<Map<String, String>> _decodeMessages(Object? raw) {
    return ((raw as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((m) => {
              'role': (m['role'] as String?) ?? '',
              'content': (m['content'] as String?) ?? '',
            })
        .where((m) => m['content']!.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _decodeList(http.Response resp) {
    if (resp.statusCode >= 400) throw ApiException(resp.statusCode, resp.body);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is List) return decoded.whereType<Map<String, dynamic>>().toList();
    throw ApiException(resp.statusCode, 'expected list, got ${decoded.runtimeType}');
  }

  void close() => _client.close();
}
