/// Small app-wide event channel for cross-screen actions that don't fit the
/// per-screen `State`.
///
/// Cachy keeps each feature's live UI state private inside its own `State`.
/// A few actions need to cross those boundaries — the library's notes column
/// asks the shell to promote a card to fullscreen; the share pipeline asks the
/// library to select the card it just created. Rather than wire a global
/// controller, those screens talk through this bus: the shell sets the
/// callbacks it owns, feature screens register theirs while mounted and clear
/// them on dispose.
library;

import 'package:flutter/widgets.dart';

/// Provided app-wide (see `main.dart`).
class UiBus extends ChangeNotifier {
  /// Promote a card's notes to a fullscreen reader (from the library's side
  /// column). Registered by the shell; invoked by the reader's fullscreen
  /// toggle.
  void Function(String cardId)? onEnterCardFullscreen;

  /// Restore the fullscreen reader back to the side column. Registered by the
  /// shell.
  VoidCallback? onExitCardFullscreen;

  /// Select a card in the library's split-pane detail (the side column) — the
  /// same thing a user tap does. Registered by the library screen while it's
  /// mounted on a wide (split-pane) layout.
  Future<void> Function(String cardId)? onSelectLibraryCard;

  /// Switch the library's top segment (0 = Cards, 1 = Concepts, 2 = Catalog).
  /// Registered by the library screen while mounted.
  void Function(int index)? onLibraryTab;
}
