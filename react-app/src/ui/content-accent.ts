/**
 * Per-content-type accent + label + icon (mirrors Flutter's ContentAccent).
 * One accent per type — nothing more.
 */
import {
  Article,
  Barbell,
  Bookmark,
  CookingPot,
  GraduationCap,
  Lightbulb,
  MapPin,
  ShoppingBag,
} from 'phosphor-react';
import type { Icon } from 'phosphor-react';
import { ContentType } from '../api/types';

export interface ContentAccent {
  color: string;
  label: string;
  Icon: Icon;
}

const ACCENTS: Record<ContentType, ContentAccent> = {
  [ContentType.RECIPE]: { color: '#B6502E', label: 'Recipe', Icon: CookingPot },
  [ContentType.WORKOUT]: { color: '#4F6B4A', label: 'Workout', Icon: Barbell },
  [ContentType.TUTORIAL]: {
    color: '#3E5C73',
    label: 'Tutorial',
    Icon: GraduationCap,
  },
  [ContentType.TIP]: { color: '#B08227', label: 'Tip', Icon: Lightbulb },
  [ContentType.PRODUCT_LIST]: {
    color: '#7A5A86',
    label: 'Products',
    Icon: ShoppingBag,
  },
  [ContentType.TRAVEL]: { color: '#2F7E80', label: 'Travel', Icon: MapPin },
  [ContentType.NEWS_EXPLAINER]: {
    color: '#6B6359',
    label: 'Explainer',
    Icon: Article,
  },
  [ContentType.OTHER]: { color: '#8A5A3C', label: 'Note', Icon: Bookmark },
};

export function contentAccent(type: ContentType | undefined): ContentAccent {
  if (type && ACCENTS[type]) return ACCENTS[type];
  return ACCENTS[ContentType.OTHER];
}

/** Failure-reason labels (mirrors Flutter's FailureReason.label). */
export function failureLabel(reason: string | null | undefined): string {
  switch (reason) {
    case 'unavailable':
      return 'Video unavailable';
    case 'no_content':
      return 'No readable content';
    case 'unsupported':
      return 'Unsupported source';
    case 'timeout':
      return 'Timed out';
    default:
      return 'Failed';
  }
}
