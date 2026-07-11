/// A [ChangeNotifier] that silently ignores `notifyListeners()` once disposed.
///
/// View models kick off async work (a network turn, a bootstrap) and then
/// `notifyListeners()` when it resolves. If the screen is torn down first —
/// the user pops it, or Present mode navigates on before the request
/// finishes — that late notify hits a disposed notifier and throws
/// "used after being disposed". Guarding every call site is error-prone;
/// guarding the notifier once is not.
library;

import 'package:flutter/foundation.dart';

mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// Whether [dispose] has run — useful for bailing out of in-flight async
  /// work before it touches other disposed state.
  bool get disposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
