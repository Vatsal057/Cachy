/// Enums mirroring the backend schema contract (docs/04, backend models/card.py).
/// Parsing is tolerant: an unknown wire value degrades to a safe default rather
/// than throwing, so a card always renders.
library;

enum CardState {
  queued,
  processing,
  ready,
  failed;

  static CardState fromWire(String? value) {
    switch (value) {
      case 'queued':
        return CardState.queued;
      case 'processing':
        return CardState.processing;
      case 'ready':
        return CardState.ready;
      case 'failed':
        return CardState.failed;
      default:
        return CardState.queued;
    }
  }

  String get wire => name;
}

enum FailureReason {
  unavailable,
  noContent,
  unsupported,
  timeout;

  static FailureReason? fromWire(String? value) {
    switch (value) {
      case 'unavailable':
        return FailureReason.unavailable;
      case 'no_content':
        return FailureReason.noContent;
      case 'unsupported':
        return FailureReason.unsupported;
      case 'timeout':
        return FailureReason.timeout;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case FailureReason.unavailable:
        return 'Video unavailable';
      case FailureReason.noContent:
        return 'No readable content';
      case FailureReason.unsupported:
        return 'Unsupported source';
      case FailureReason.timeout:
        return 'Timed out';
    }
  }
}

enum ContentType {
  recipe,
  workout,
  tutorial,
  tip,
  productList,
  travel,
  newsExplainer,
  other;

  static ContentType fromWire(String? value) {
    switch (value) {
      case 'recipe':
        return ContentType.recipe;
      case 'workout':
        return ContentType.workout;
      case 'tutorial':
        return ContentType.tutorial;
      case 'tip':
        return ContentType.tip;
      case 'product_list':
        return ContentType.productList;
      case 'travel':
        return ContentType.travel;
      case 'news_explainer':
        return ContentType.newsExplainer;
      default:
        return ContentType.other;
    }
  }

  String get wire {
    switch (this) {
      case ContentType.productList:
        return 'product_list';
      case ContentType.newsExplainer:
        return 'news_explainer';
      default:
        return name;
    }
  }

  String get label {
    switch (this) {
      case ContentType.recipe:
        return 'Recipe';
      case ContentType.workout:
        return 'Workout';
      case ContentType.tutorial:
        return 'Tutorial';
      case ContentType.tip:
        return 'Tip';
      case ContentType.productList:
        return 'Products';
      case ContentType.travel:
        return 'Travel';
      case ContentType.newsExplainer:
        return 'Explainer';
      case ContentType.other:
        return 'Note';
    }
  }
}

enum PrimaryActionKind {
  shoppingList,
  schedule,
  savePlace,
  reminder,
  export,
  none;

  static PrimaryActionKind fromWire(String? value) {
    switch (value) {
      case 'shopping_list':
        return PrimaryActionKind.shoppingList;
      case 'schedule':
        return PrimaryActionKind.schedule;
      case 'save_place':
        return PrimaryActionKind.savePlace;
      case 'reminder':
        return PrimaryActionKind.reminder;
      case 'export':
        return PrimaryActionKind.export;
      default:
        return PrimaryActionKind.none;
    }
  }

  String get wire {
    switch (this) {
      case PrimaryActionKind.shoppingList:
        return 'shopping_list';
      case PrimaryActionKind.savePlace:
        return 'save_place';
      default:
        return name;
    }
  }
}
