/// Product/artifact lookup (docs/09): turn a catalog entry into a "go find/buy
/// this" link. Routes by [ArtifactType] to a free, keyless web destination
/// (store search, library, IMDb, Maps…) and launches it externally. Best-effort:
/// any failure returns false and the UI shows a brief message — never crashes.
library;

import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/artifact.dart';

/// Build the lookup URL for an artifact. Public so it can be unit-tested without
/// touching url_launcher.
Uri lookupUri(CatalogEntry entry) {
  final q = [entry.title, if (entry.creator != null) entry.creator!]
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  final query = Uri.encodeQueryComponent(q.isEmpty ? entry.title : q);

  switch (entry.type) {
    case ArtifactType.product:
      // Google Shopping search — opens stores to buy.
      return Uri.parse('https://www.google.com/search?tbm=shop&q=$query');
    case ArtifactType.book:
      return Uri.parse('https://www.google.com/search?tbm=bks&q=$query');
    case ArtifactType.movie:
    case ArtifactType.tvShow:
      return Uri.parse('https://www.imdb.com/find/?q=$query');
    case ArtifactType.podcast:
    case ArtifactType.music:
      return Uri.parse('https://music.apple.com/search?term=$query');
    case ArtifactType.app:
      return Uri.parse('https://play.google.com/store/search?q=$query&c=apps');
    case ArtifactType.place:
      return Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$query');
    case ArtifactType.other:
      return Uri.parse('https://www.google.com/search?q=$query');
  }
}

/// Launch the lookup destination for an artifact. Returns false on failure.
Future<bool> openLookup(CatalogEntry entry) async {
  try {
    return await launchUrl(lookupUri(entry), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
