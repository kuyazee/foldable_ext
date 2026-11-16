import 'dart:ui' show DisplayFeature, FlutterView;

import 'package:flutter/widgets.dart';

/// `MediaQuery` lookups that always describe the window the app is drawn
/// in, the emulated one included.
///
/// Under a `FoldDivisionScope` that renders the app as a device,
/// `MediaQuery.of` already describes the emulated window. Three kinds of
/// code still see the real screen:
///
/// - Code above the scope, such as a `MaterialApp.builder` wrapper.
/// - Code that reads the view: `MediaQueryData.fromView(View.of(context))`,
///   `View.of(context).physicalSize`, `PlatformDispatcher.views`.
/// - Code under a widget that changed `MediaQuery` on purpose (a `Scaffold`
///   body, `MediaQuery.removePadding`) but needs the window behind it.
///
/// Swap the call and each of them gets the emulated window:
///
/// | Instead of | Use |
/// |---|---|
/// | `MediaQuery.of(context)` | `EmulatedMediaQuery.of(context)` |
/// | `MediaQuery.sizeOf(context)` and the other `*Of` lookups | the `EmulatedMediaQuery` lookup of the same name |
/// | `MediaQueryData.fromView(View.of(context))` | `EmulatedMediaQuery.windowOf(context)` |
/// | `MediaQueryData.fromView(view)`, with no context | `EmulatedMediaQuery.fromView(view)` |
///
/// With no device emulated each lookup answers what the `MediaQuery` call
/// it replaces answers. Text scale, brightness and the other settings are
/// never emulated, so keep `MediaQuery` for those.
///
/// Under the scope the lookups depend on `MediaQuery` the same way, so the
/// caller rebuilds when the window changes. Above the scope the caller
/// rebuilds when the real window changes, which is also when the emulated
/// window changes, except for a change of `FoldDivision.config` alone.
abstract final class EmulatedMediaQuery {
  /// The `MediaQueryData` of [context], in the coordinates of the emulated
  /// window while one is in effect.
  ///
  /// Under the scope this is `MediaQuery.of(context)`, local changes
  /// included. Above it, it is the window the scope gives its subtree.
  static MediaQueryData of(BuildContext context) =>
      maybeOf(context) ?? MediaQuery.of(context);

  /// Like [of], or null with no `MediaQuery` above [context].
  static MediaQueryData? maybeOf(BuildContext context) {
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    if (media == null || _isUnderScope(context)) return media;
    return _windowAbove(context) ?? media;
  }

  /// The window the app is drawn in: what
  /// `MediaQueryData.fromView(View.of(context))` answers, with the emulated
  /// window in place of the real screen.
  ///
  /// Local `MediaQuery` changes (a `Scaffold` body, a pane) do not apply.
  /// Use it for a safe area or a bleed that has to reach the window edge.
  static MediaQueryData windowOf(BuildContext context) {
    final EmulatedWindowScope? scope =
        context.dependOnInheritedWidgetOfExactType<EmulatedWindowScope>();
    if (scope != null) return scope.window;
    return fromView(View.of(context));
  }

  /// What `MediaQueryData.fromView` answers for [view], with the emulated
  /// window in place of the real screen while a scope in [view] renders
  /// the app as a device.
  ///
  /// For code with no `BuildContext`. Before the scope has built for the
  /// first time this is the real screen.
  static MediaQueryData fromView(FlutterView view) =>
      EmulatedWindowScope._windows[view] ?? MediaQueryData.fromView(view);

  /// The size of the window, in logical pixels.
  static Size sizeOf(BuildContext context) =>
      _isUnderScope(context) ? MediaQuery.sizeOf(context) : of(context).size;

  /// The orientation of the window.
  static Orientation orientationOf(BuildContext context) =>
      _isUnderScope(context)
          ? MediaQuery.orientationOf(context)
          : of(context).orientation;

  /// Physical pixels per logical pixel of the window. While a window is
  /// emulated at a scale this includes the scale, so physical sizes stay
  /// true.
  static double devicePixelRatioOf(BuildContext context) =>
      _isUnderScope(context)
          ? MediaQuery.devicePixelRatioOf(context)
          : of(context).devicePixelRatio;

  /// The safe area the keyboard leaves uncovered.
  static EdgeInsets paddingOf(BuildContext context) => _isUnderScope(context)
      ? MediaQuery.paddingOf(context)
      : of(context).padding;

  /// The safe area, keyboard or not.
  static EdgeInsets viewPaddingOf(BuildContext context) =>
      _isUnderScope(context)
          ? MediaQuery.viewPaddingOf(context)
          : of(context).viewPadding;

  /// The part of the window the keyboard covers.
  static EdgeInsets viewInsetsOf(BuildContext context) => _isUnderScope(context)
      ? MediaQuery.viewInsetsOf(context)
      : of(context).viewInsets;

  /// The edges where system gestures win over taps. Zero while a window
  /// size is emulated.
  static EdgeInsets systemGestureInsetsOf(BuildContext context) =>
      _isUnderScope(context)
          ? MediaQuery.systemGestureInsetsOf(context)
          : of(context).systemGestureInsets;

  /// The display features of the window: what the scope's `bridgeMode`
  /// asks for while a window size is emulated.
  static List<DisplayFeature> displayFeaturesOf(BuildContext context) =>
      _isUnderScope(context)
          ? MediaQuery.displayFeaturesOf(context)
          : of(context).displayFeatures;

  static bool _isUnderScope(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<EmulatedWindowScope>() !=
      null;

  static MediaQueryData? _windowAbove(BuildContext context) {
    final FlutterView? view = View.maybeOf(context);
    return view == null ? null : EmulatedWindowScope._windows[view];
  }
}

/// Hands the window a `FoldDivisionScope` gives its subtree down the tree.
///
/// `FoldDivisionScope` inserts it. [EmulatedMediaQuery.windowOf] reads it.
class EmulatedWindowScope extends InheritedWidget {
  /// Creates a window scope.
  const EmulatedWindowScope({
    super.key,
    required this.window,
    required super.child,
  });

  /// The `MediaQueryData` of the window, before any change a widget below
  /// the scope makes.
  final MediaQueryData window;

  /// The emulated window of each view a scope renders as a device. Read by
  /// [EmulatedMediaQuery.fromView] and by lookups above the scope.
  static final Map<FlutterView, MediaQueryData> _windows =
      <FlutterView, MediaQueryData>{};

  /// Records the emulated window of [view], or removes it when [window] is
  /// null. `FoldDivisionScope` calls it each time it builds and when it is
  /// removed. App code has no reason to call it.
  static void recordWindow(FlutterView view, MediaQueryData? window) {
    if (window == null) {
      _windows.remove(view);
    } else {
      _windows[view] = window;
    }
  }

  @override
  bool updateShouldNotify(EmulatedWindowScope oldWidget) =>
      window != oldWidget.window;
}
