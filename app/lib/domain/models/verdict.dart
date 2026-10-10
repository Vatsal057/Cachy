/// Verdict Timeline models (backend schema 1.8): per-window factual-claim
/// verification for YouTube cards. Mirrors backend models/card.py. Parsing is
/// tolerant — a missing or malformed `verdicts` payload yields an empty
/// timeline, never a crash.
library;

/// One dated web source behind a verdict, with its stance toward the claim.
class VerdictEvidence {
  const VerdictEvidence({
    required this.title,
    required this.link,
    this.snippet = '',
    this.source = '',
    this.date = '',
    this.stance = 'supports',
  });

  final String title;
  final String link;
  final String snippet;
  final String source;
  final String date;
  final String stance; // supports | contradicts

  /// Human-readable outlet name: explicit `source` first, else the link host.
  String get displaySource {
    if (source.trim().isNotEmpty) return source.trim();
    try {
      final host = Uri.parse(link).host;
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
  }

  factory VerdictEvidence.fromJson(Map<String, dynamic> json) => VerdictEvidence(
        title: (json['title'] as String?) ?? '',
        link: (json['link'] as String?) ?? '',
        snippet: (json['snippet'] as String?) ?? '',
        source: (json['source'] as String?) ?? '',
        date: (json['date'] as String?) ?? '',
        stance: (json['stance'] as String?) ?? 'supports',
      );
}

/// One checked claim: where in the video, what was claimed, the verdict, and
/// the dated evidence behind it.
class ClaimVerdict {
  const ClaimVerdict({
    required this.windowIndex,
    this.windowStart = 0,
    this.windowEnd = 0,
    required this.claim,
    this.verdict = 'grey',
    this.note = '',
    this.evidence = const [],
  });

  final int windowIndex;
  final double windowStart;
  final double windowEnd;
  final String claim;
  final String verdict; // green | amber | red | grey
  final String note;
  final List<VerdictEvidence> evidence;

  /// "0:00-0:30" style label for the transcript window.
  String get windowLabel {
    String fmt(double s) {
      final min = (s ~/ 60).toString();
      final sec = (s % 60).toInt().toString().padLeft(2, '0');
      return '$min:$sec';
    }

    return '${fmt(windowStart)}-${fmt(windowEnd)}';
  }

  factory ClaimVerdict.fromJson(Map<String, dynamic> json) => ClaimVerdict(
        windowIndex: (json['window_index'] as num?)?.toInt() ?? 0,
        windowStart: (json['window_start'] as num?)?.toDouble() ?? 0,
        windowEnd: (json['window_end'] as num?)?.toDouble() ?? 0,
        claim: (json['claim'] as String?) ?? '',
        verdict: (json['verdict'] as String?) ?? 'grey',
        note: (json['note'] as String?) ?? '',
        evidence: ((json['evidence'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(VerdictEvidence.fromJson)
            .toList(),
      );
}

/// The whole timeline for one video. `null` on the card when the video had no
/// transcript, no checkable claims, or no key — genuinely optional.
class VerdictTimeline {
  const VerdictTimeline({
    this.videoId = '',
    this.checkedAt,
    this.publishedDate = '',
    this.claims = const [],
  });

  final String videoId;
  final DateTime? checkedAt;
  final String publishedDate;
  final List<ClaimVerdict> claims;

  bool get hasContent => claims.isNotEmpty;

  /// Verdict counts for the summary header, e.g. {'green': 2, 'grey': 1}.
  Map<String, int> get counts {
    final m = <String, int>{};
    for (final c in claims) {
      m[c.verdict] = (m[c.verdict] ?? 0) + 1;
    }
    return m;
  }

  factory VerdictTimeline.fromJson(Map<String, dynamic> json) => VerdictTimeline(
        videoId: (json['video_id'] as String?) ?? '',
        checkedAt:
            DateTime.tryParse((json['checked_at'] as String?) ?? ''),
        publishedDate: (json['published_date'] as String?) ?? '',
        claims: ((json['claims'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClaimVerdict.fromJson)
            .where((c) => c.claim.isNotEmpty)
            .toList(),
      );
}
