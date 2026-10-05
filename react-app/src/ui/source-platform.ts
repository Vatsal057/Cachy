/**
 * SourcePlatform — port of Flutter's ui/core/source_platform.dart.
 * Lightweight source detection from a shared URL's host: turns a bare link
 * into a recognizable platform + content-kind label so the capture pipeline
 * can confirm *what* it's fetching.
 */
import {
  BookOpen,
  InstagramLogo,
  LinkedinLogo,
  LinkSimple,
  MediumLogo,
  Newspaper,
  TiktokLogo,
  TwitterLogo,
  YoutubeLogo,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';

export type SourcePlatformKind =
  | 'instagram'
  | 'youtube'
  | 'tiktok'
  | 'twitter'
  | 'linkedin'
  | 'medium'
  | 'substack'
  | 'wikipedia'
  | 'generic';

export interface SourcePlatform {
  kind: SourcePlatformKind;
  /** Display name, e.g. "Instagram". */
  label: string;
  icon: Icon;
  color: string;
  /** Uppercase status line shown while fetching, e.g. "INGESTING VIDEO STREAM". */
  ingestingLabel: string;
}

/**
 * Detects the source platform from a shared URL's host. Falls back to a
 * neutral "generic link" result for unrecognized or malformed URLs.
 */
export function detectSourcePlatform(url: string): SourcePlatform {
  let host = '';
  try {
    host = new URL(url.trim()).host.toLowerCase();
  } catch {
    host = '';
  }
  const has = (needle: string) => host.includes(needle);

  if (has('instagram.com')) {
    return {
      kind: 'instagram',
      label: 'Instagram',
      icon: InstagramLogo,
      color: '#E1306C',
      ingestingLabel: 'INGESTING VIDEO STREAM',
    };
  }
  if (has('youtube.com') || has('youtu.be')) {
    return {
      kind: 'youtube',
      label: 'YouTube',
      icon: YoutubeLogo,
      color: '#E0301E',
      ingestingLabel: 'INGESTING VIDEO STREAM',
    };
  }
  if (has('tiktok.com')) {
    return {
      kind: 'tiktok',
      label: 'TikTok',
      icon: TiktokLogo,
      color: '#1A1A1A',
      ingestingLabel: 'INGESTING VIDEO STREAM',
    };
  }
  if (has('twitter.com') || has('x.com')) {
    return {
      kind: 'twitter',
      label: 'X / Twitter',
      icon: TwitterLogo,
      color: '#1A1A1A',
      ingestingLabel: 'INGESTING POST',
    };
  }
  if (has('linkedin.com')) {
    return {
      kind: 'linkedin',
      label: 'LinkedIn',
      icon: LinkedinLogo,
      color: '#0A66C2',
      ingestingLabel: 'INGESTING POST',
    };
  }
  if (has('medium.com')) {
    return {
      kind: 'medium',
      label: 'Medium',
      icon: MediumLogo,
      color: '#1A8917',
      ingestingLabel: 'INGESTING ARTICLE',
    };
  }
  if (has('substack.com')) {
    return {
      kind: 'substack',
      label: 'Substack',
      icon: Newspaper,
      color: '#FF6719',
      ingestingLabel: 'INGESTING ARTICLE',
    };
  }
  if (has('wikipedia.org')) {
    return {
      kind: 'wikipedia',
      label: 'Wikipedia',
      icon: BookOpen,
      color: '#3A85C8',
      ingestingLabel: 'INGESTING ARTICLE',
    };
  }
  return {
    kind: 'generic',
    label: 'Link',
    icon: LinkSimple,
    color: '#8A8378',
    ingestingLabel: 'FETCHING CONTENT',
  };
}
