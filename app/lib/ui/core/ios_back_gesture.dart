/// A genuine iOS-style interactive back gesture for all platforms.
///
/// Unlike a plain "swipe → pop" (which fires instantly with no feedback), this
/// drives the route's transition animation directly: the top screen tracks your
/// finger, the previous screen parallax-slides in behind it, and the gesture
/// commits (pops) or springs back based on how far / how fast you dragged — the
/// real iOS "back screen" feel.
///
/// Adapted from Flutter's private CupertinoPageTransitionsBuilder internals
/// (flutter/lib/src/cupertino/route.dart), with two deliberate changes:
///   1. it's used on every platform (the app wants iOS transitions everywhere), and
///   2. the edge activation zone is a little wider than iOS's 20dp for an easier
///      grab — but still EDGE-based, so it never fights horizontal content like
///      the library's tab swipe or horizontal lists.
library;

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// Width of the left-edge zone that starts the back gesture. iOS uses ~20; a bit
/// wider is easier to hit without interfering with centre-screen content.
const double _kBackGestureWidth = 44.0;
const double _kMinFlingVelocity = 1.0; // screen widths per second
const int _kMaxDroppedSwipePageForwardAnimationTime = 800; // ms
const int _kMaxPageBackAnimationTime = 300; // ms

/// Routes whose back gesture is mid-drag — used to switch the transition to a
/// linear curve so it tracks the finger 1:1 while dragging.
final Set<PageRoute<dynamic>> _gesturesInProgress = <PageRoute<dynamic>>{};

class IOSPageTransitionsBuilder extends PageTransitionsBuilder {
  const IOSPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      // Linear (no easing) while the user is actively dragging so the page
      // stays glued to the finger; eased otherwise.
      linearTransition: _gesturesInProgress.contains(route),
      child: _BackGestureDetector<T>(
        enabledCallback: () => _isPopGestureEnabled<T>(route),
        onStartPopGesture: () => _startPopGesture<T>(route),
        child: child,
      ),
    );
  }
}

bool _isPopGestureEnabled<T>(PageRoute<T> route) {
  // Can't go back from the first route, or one handling its own pop, or a
  // fullscreen dialog; and only when the route is settled and idle.
  if (route.isFirst) return false;
  if (route.willHandlePopInternally) return false;
  if (route.popDisposition == RoutePopDisposition.doNotPop) return false;
  if (route.fullscreenDialog) return false;
  if (route.animation!.status != AnimationStatus.completed) return false;
  if (route.secondaryAnimation!.status != AnimationStatus.dismissed) return false;
  if (_gesturesInProgress.contains(route)) return false;
  return true;
}

_BackGestureController<T> _startPopGesture<T>(PageRoute<T> route) {
  _gesturesInProgress.add(route);
  return _BackGestureController<T>(
    navigator: route.navigator!,
    // The transition animation the route is driven by. Protected on
    // TransitionRoute, but reading it here mirrors what Cupertino does internally.
    // ignore: invalid_use_of_protected_member
    controller: route.controller!,
    onEnded: () => _gesturesInProgress.remove(route),
  );
}

/// Drives the route's [AnimationController] from drag input, then settles it
/// forward (cancel) or in reverse (pop) on release. Mirrors Cupertino's
/// `_CupertinoBackGestureController`.
class _BackGestureController<T> {
  _BackGestureController({
    required this.navigator,
    required this.controller,
    required this.onEnded,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final VoidCallback onEnded;

  /// Fraction of screen width dragged this frame (positive = toward dismiss).
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.fastLinearToSlowEaseIn;

    final bool animateForward;
    if (velocity.abs() >= _kMinFlingVelocity) {
      // A fling: direction wins over position.
      animateForward = velocity <= 0;
    } else {
      // Released: past the halfway point commits the pop.
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      final int droppedPageForwardAnimationTime = min(
        lerpDouble(
          _kMaxDroppedSwipePageForwardAnimationTime,
          0,
          controller.value,
        )!.floor(),
        _kMaxPageBackAnimationTime,
      );
      controller.animateTo(
        1.0,
        duration: Duration(milliseconds: droppedPageForwardAnimationTime),
        curve: animationCurve,
      );
    } else {
      navigator.pop();
      if (controller.isAnimating) {
        final int droppedPageBackAnimationTime = lerpDouble(
          0,
          _kMaxDroppedSwipePageForwardAnimationTime,
          controller.value,
        )!.floor();
        controller.animateBack(
          0.0,
          duration: Duration(milliseconds: droppedPageBackAnimationTime),
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (AnimationStatus status) {
        _finish();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      _finish();
    }
  }

  void _finish() {
    onEnded();
    navigator.didStopUserGesture();
  }
}

/// Left-edge drag recognizer that hands input to a [_BackGestureController].
class _BackGestureDetector<T> extends StatefulWidget {
  const _BackGestureDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController<T>> onStartPopGesture;
  final Widget child;

  @override
  State<_BackGestureDetector<T>> createState() => _BackGestureDetectorState<T>();
}

class _BackGestureDetectorState<T> extends State<_BackGestureDetector<T>> {
  _BackGestureController<T>? _backGestureController;
  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _backGestureController?.dragUpdate(
      _convertToLogical(details.primaryDelta! / context.size!.width),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    _backGestureController?.dragEnd(
      _convertToLogical(details.velocity.pixelsPerSecond.dx / context.size!.width),
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  double _convertToLogical(double value) {
    return switch (Directionality.of(context)) {
      TextDirection.rtl => -value,
      TextDirection.ltr => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final double dragAreaWidth = Directionality.of(context) == TextDirection.ltr
        ? MediaQuery.paddingOf(context).left + _kBackGestureWidth
        : MediaQuery.paddingOf(context).right + _kBackGestureWidth;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          width: dragAreaWidth,
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
