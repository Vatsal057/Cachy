/// Lightweight source detection from a shared URL's host — turns a bare link
/// into a recognizable platform + content-kind label so the capture pipeline
/// can confirm *what* it's fetching instead of a generic "video stream" for
/// every link (articles, posts, and videos all get accurate wording).
library;

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';

enum SourcePlatformKind {
  instagram,
  youtube,
  tiktok,
  twitter,
  linkedin,
  medium,
  substack,
  wikipedia,
  generic,
}

class SourcePlatform {
  const SourcePlatform({
    required this.kind,
    required this.label,
    required this.icon,
    required this.color,
    required this.ingestingLabel,
  });

  final SourcePlatformKind kind;

  /// Display name, e.g. "Instagram".
  final String label;
  final PhosphorIconData icon;
  final Color color;

  /// Uppercase status line shown while fetching, e.g. "INGESTING VIDEO STREAM".
  final String ingestingLabel;

  /// Detects the source platform from a shared URL's host. Falls back to a
  /// neutral "generic link" result for unrecognized or malformed URLs.
  static SourcePlatform detect(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';

    bool has(String needle) => host.contains(needle);

    if (has('instagram.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.instagram,
        label: 'Instagram',
        icon: PhosphorIconsRegular.instagramLogo,
        color: Color(0xFFE1306C),
        ingestingLabel: 'INGESTING VIDEO STREAM',
      );
    }
    if (has('youtube.com') || has('youtu.be')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.youtube,
        label: 'YouTube',
        icon: PhosphorIconsRegular.youtubeLogo,
        color: Color(0xFFE0301E),
        ingestingLabel: 'INGESTING VIDEO STREAM',
      );
    }
    if (has('tiktok.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.tiktok,
        label: 'TikTok',
        icon: PhosphorIconsRegular.tiktokLogo,
        color: Color(0xFF1A1A1A),
        ingestingLabel: 'INGESTING VIDEO STREAM',
      );
    }
    if (has('twitter.com') || has('x.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.twitter,
        label: 'X / Twitter',
        icon: PhosphorIconsRegular.xLogo,
        color: Color(0xFF1A1A1A),
        ingestingLabel: 'INGESTING POST',
      );
    }
    if (has('linkedin.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.linkedin,
        label: 'LinkedIn',
        icon: PhosphorIconsRegular.linkedinLogo,
        color: Color(0xFF0A66C2),
        ingestingLabel: 'INGESTING POST',
      );
    }
    if (has('medium.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.medium,
        label: 'Medium',
        icon: PhosphorIconsRegular.mediumLogo,
        color: Color(0xFF1A8917),
        ingestingLabel: 'INGESTING ARTICLE',
      );
    }
    if (has('substack.com')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.substack,
        label: 'Substack',
        icon: PhosphorIconsRegular.newspaper,
        color: Color(0xFFFF6719),
        ingestingLabel: 'INGESTING ARTICLE',
      );
    }
    if (has('wikipedia.org')) {
      return const SourcePlatform(
        kind: SourcePlatformKind.wikipedia,
        label: 'Wikipedia',
        icon: PhosphorIconsRegular.bookOpenText,
        color: Color(0xFF3A85C8),
        ingestingLabel: 'INGESTING ARTICLE',
      );
    }
    return const SourcePlatform(
      kind: SourcePlatformKind.generic,
      label: 'Link',
      icon: PhosphorIconsRegular.linkSimple,
      color: Color(0xFF8A8378),
      ingestingLabel: 'FETCHING CONTENT',
    );
  }
}
