import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The four windows a book-style foldable shows an app.
enum EmulatedWindowKind {
  /// The outer (cover) display, held upright.
  outerPortrait,

  /// The outer (cover) display, on its side.
  outerLandscape,

  /// The inner display with the fold running top to bottom, open like a book.
  innerLandscape,

  /// The inner display with the fold running left to right, as in tabletop
  /// posture.
  innerPortrait,
}

/// What one window of an [EmulatedDevice] looks like to an app.
///
/// Every value is in logical pixels (points on iOS), in the coordinates of
/// the window itself: the origin is its top left corner.
@immutable
class EmulatedDeviceState {
  /// Creates the metrics of one window.
  ///
  /// [foldAxis] and [foldCentre] go together: give both for a window the fold
  /// crosses, and neither for a window with no fold.
  const EmulatedDeviceState({
    required this.windowSize,
    this.safeArea = EdgeInsets.zero,
    this.foldAxis,
    this.foldCentre,
    this.occlusions = const <Rect>[],
  }) : assert(
          (foldAxis == null) == (foldCentre == null),
          'foldAxis and foldCentre must be given together',
        );

  /// The size of the window.
  final Size windowSize;

  /// The safe area insets of the window.
  ///
  /// Reported as both `MediaQuery.padding` and `MediaQuery.viewPadding`.
  final EdgeInsets safeArea;

  /// The direction the fold runs in, or null for a window with no fold.
  ///
  /// [Axis.vertical] is a fold that runs top to bottom and splits the window
  /// into a left and a right pane. [Axis.horizontal] is a fold that runs left
  /// to right and splits it into a top and a bottom pane.
  final Axis? foldAxis;

  /// The centre line of the fold, or null for a window with no fold.
  ///
  /// An x coordinate for a vertical fold and a y coordinate for a horizontal
  /// one.
  final double? foldCentre;

  /// Areas the system draws over, such as the clock and Wi-Fi indicators.
  final List<Rect> occlusions;

  /// Whether the fold crosses this window.
  bool get hasFold => foldAxis != null && foldCentre != null;

  /// The division of this window: a band [extent] thick, centred on the fold
  /// and running the whole window along it, cut to the window.
  ///
  /// Null for a window with no fold.
  Rect? divisionRect(double extent) {
    final Axis? axis = foldAxis;
    final double? centre = foldCentre;
    if (axis == null || centre == null) return null;
    final double half = math.max(extent, 0) / 2;
    if (axis == Axis.vertical) {
      return Rect.fromLTRB(
        (centre - half).clamp(0.0, windowSize.width),
        0,
        (centre + half).clamp(0.0, windowSize.width),
        windowSize.height,
      );
    }
    return Rect.fromLTRB(
      0,
      (centre - half).clamp(0.0, windowSize.height),
      windowSize.width,
      (centre + half).clamp(0.0, windowSize.height),
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// The fold cannot be removed this way. Build a new state for that.
  EmulatedDeviceState copyWith({
    Size? windowSize,
    EdgeInsets? safeArea,
    Axis? foldAxis,
    double? foldCentre,
    List<Rect>? occlusions,
  }) {
    return EmulatedDeviceState(
      windowSize: windowSize ?? this.windowSize,
      safeArea: safeArea ?? this.safeArea,
      foldAxis: foldAxis ?? this.foldAxis,
      foldCentre: foldCentre ?? this.foldCentre,
      occlusions: occlusions ?? this.occlusions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmulatedDeviceState &&
          other.windowSize == windowSize &&
          other.safeArea == safeArea &&
          other.foldAxis == foldAxis &&
          other.foldCentre == foldCentre &&
          listEquals(other.occlusions, occlusions);

  @override
  int get hashCode => Object.hash(
        windowSize,
        safeArea,
        foldAxis,
        foldCentre,
        Object.hashAll(occlusions),
      );

  @override
  String toString() => 'EmulatedDeviceState($windowSize, safeArea: $safeArea, '
      'fold: ${foldAxis?.name} at $foldCentre, '
      'occlusions: ${occlusions.length})';
}

/// The metrics of a foldable device an app can be rendered as.
///
/// One [EmulatedDeviceState] per window the device shows an app. Set it as
/// `FoldDivisionConfig.device`. `FoldDivisionScope` then gives its subtree
/// the window size, the safe area and the fold of the matching state.
///
/// [iphoneDuo] is built in. For another device, or for corrected iPhone Duo
/// numbers, build a profile of your own or change one state with [copyWith].
@immutable
class EmulatedDevice {
  /// Creates a device profile.
  const EmulatedDevice({
    required this.name,
    required this.outerPortrait,
    required this.outerLandscape,
    required this.innerLandscape,
    required this.innerPortrait,
  });

  /// The iPhone Duo.
  ///
  /// | State | Window | Safe area | Fold |
  /// |---|---|---|---|
  /// | Outer display, portrait | 466 x 678 | right 84, bottom 34 | none |
  /// | Outer display, landscape | 678 x 466 | right 84 | none |
  /// | Inner display, landscape | 951 x 669 | right 84 | vertical, x 475.5 |
  /// | Inner display, portrait | 669 x 951 | top 84, bottom 95 | horizontal, y 475.5 |
  ///
  /// The outer display has a system strip on its trailing edge. The clock
  /// and the Wi-Fi indicator sit at the top of the strip, which the outer
  /// portrait state lists as the occlusion `(385, 0, 84, 120)`. No other
  /// state lists an occlusion.
  ///
  /// Several of these numbers are unverified against hardware. The 951 x 669
  /// inner window and the 40 point division are what the `foldable` package
  /// measured on the simulator. The outer window sizes, the safe areas and
  /// the occlusion have not been checked on a device, and the occlusion
  /// reaches 3 points past the right edge of the 466 point window as given.
  /// Every number is a field: pass a corrected profile through
  /// `FoldDivisionConfig.device` once a real reading exists.
  static const EmulatedDevice iphoneDuo = EmulatedDevice(
    name: 'iPhone Duo',
    outerPortrait: EmulatedDeviceState(
      windowSize: Size(466, 678),
      safeArea: EdgeInsets.only(right: 84, bottom: 34),
      occlusions: <Rect>[Rect.fromLTWH(385, 0, 84, 120)],
    ),
    outerLandscape: EmulatedDeviceState(
      windowSize: Size(678, 466),
      safeArea: EdgeInsets.only(right: 84),
    ),
    innerLandscape: EmulatedDeviceState(
      windowSize: Size(951, 669),
      safeArea: EdgeInsets.only(right: 84),
      foldAxis: Axis.vertical,
      foldCentre: 475.5,
    ),
    innerPortrait: EmulatedDeviceState(
      windowSize: Size(669, 951),
      safeArea: EdgeInsets.only(top: 84, bottom: 95),
      foldAxis: Axis.horizontal,
      foldCentre: 475.5,
    ),
  );

  /// A name for logs and debug screens.
  final String name;

  /// The outer display, held upright.
  final EmulatedDeviceState outerPortrait;

  /// The outer display, on its side.
  final EmulatedDeviceState outerLandscape;

  /// The inner display with the fold running top to bottom.
  final EmulatedDeviceState innerLandscape;

  /// The inner display with the fold running left to right.
  final EmulatedDeviceState innerPortrait;

  /// The metrics of the window [kind].
  EmulatedDeviceState stateFor(EmulatedWindowKind kind) {
    switch (kind) {
      case EmulatedWindowKind.outerPortrait:
        return outerPortrait;
      case EmulatedWindowKind.outerLandscape:
        return outerLandscape;
      case EmulatedWindowKind.innerLandscape:
        return innerLandscape;
      case EmulatedWindowKind.innerPortrait:
        return innerPortrait;
    }
  }

  /// Returns a copy with the given fields replaced.
  EmulatedDevice copyWith({
    String? name,
    EmulatedDeviceState? outerPortrait,
    EmulatedDeviceState? outerLandscape,
    EmulatedDeviceState? innerLandscape,
    EmulatedDeviceState? innerPortrait,
  }) {
    return EmulatedDevice(
      name: name ?? this.name,
      outerPortrait: outerPortrait ?? this.outerPortrait,
      outerLandscape: outerLandscape ?? this.outerLandscape,
      innerLandscape: innerLandscape ?? this.innerLandscape,
      innerPortrait: innerPortrait ?? this.innerPortrait,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmulatedDevice &&
          other.name == name &&
          other.outerPortrait == outerPortrait &&
          other.outerLandscape == outerLandscape &&
          other.innerLandscape == innerLandscape &&
          other.innerPortrait == innerPortrait;

  @override
  int get hashCode => Object.hash(
        name,
        outerPortrait,
        outerLandscape,
        innerLandscape,
        innerPortrait,
      );

  @override
  String toString() => 'EmulatedDevice($name)';
}

/// The device emulation in effect under a `FoldDivisionScope`.
///
/// Read it with `FoldDivision.emulationOf`.
@immutable
class DeviceEmulation {
  /// Creates the description of an emulation.
  const DeviceEmulation({
    required this.device,
    required this.kind,
    required this.matchesWindowSize,
    required this.windowSize,
    required this.safeArea,
    this.scale = 1,
  });

  /// The device the subtree is rendered as.
  final EmulatedDevice device;

  /// The window of [device] that stands for the real one.
  final EmulatedWindowKind kind;

  /// Whether the subtree is laid out at the window size of [state].
  ///
  /// False when `FoldDivisionConfig.matchWindowSize` is off, and when the
  /// real window has no room for the emulated one. The window then keeps its
  /// real size and takes the safe area of [state] only.
  final bool matchesWindowSize;

  /// The window size `MediaQuery` reports under the scope.
  final Size windowSize;

  /// The safe area `MediaQuery.viewPadding` reports under the scope.
  final EdgeInsets safeArea;

  /// Real logical pixels per logical pixel under the scope. 1 while the
  /// window keeps its real size.
  final double scale;

  /// The metrics of the window [kind] of [device].
  EmulatedDeviceState get state => device.stateFor(kind);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceEmulation &&
          other.device == device &&
          other.kind == kind &&
          other.matchesWindowSize == matchesWindowSize &&
          other.windowSize == windowSize &&
          other.safeArea == safeArea &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(
        device,
        kind,
        matchesWindowSize,
        windowSize,
        safeArea,
        scale,
      );

  @override
  String toString() => 'DeviceEmulation(${device.name}, ${kind.name}, '
      '$windowSize, safeArea: $safeArea, scale: $scale)';
}

/// Where an emulated window sits inside the real one.
@immutable
class EmulatedWindowPlacement {
  /// Creates a placement.
  const EmulatedWindowPlacement({required this.scale, required this.rect});

  /// Real logical pixels per emulated logical pixel.
  final double scale;

  /// The area the emulated window covers, in the coordinates of the real
  /// window.
  final Rect rect;

  /// A point of the real window in the coordinates of the emulated one.
  Offset toEmulated(Offset real) => (real - rect.topLeft) / scale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmulatedWindowPlacement &&
          other.scale == scale &&
          other.rect == rect;

  @override
  int get hashCode => Object.hash(scale, rect);

  @override
  String toString() => 'EmulatedWindowPlacement(scale: $scale, $rect)';
}

/// Fits a window of [emulatedSize] into a real window of [realSize].
///
/// The emulated window is scaled by one factor on both axes until it touches
/// two opposite edges of the real safe area ([realSize] less [realPadding]),
/// and is centred in it. The Android status and navigation bars are in
/// [realPadding], so they never cover the emulated window.
///
/// Null when there is no room: a size with no area, or padding that leaves
/// none.
EmulatedWindowPlacement? placeEmulatedWindow({
  required Size realSize,
  required EdgeInsets realPadding,
  required Size emulatedSize,
}) {
  final Rect available = Rect.fromLTRB(
    math.max(realPadding.left, 0),
    math.max(realPadding.top, 0),
    realSize.width - math.max(realPadding.right, 0),
    realSize.height - math.max(realPadding.bottom, 0),
  );
  if (!(available.width > 0) || !(available.height > 0)) return null;
  if (!(emulatedSize.width > 0) || !(emulatedSize.height > 0)) return null;
  if (!available.width.isFinite || !available.height.isFinite) return null;

  final double scale = math.min(
    available.width / emulatedSize.width,
    available.height / emulatedSize.height,
  );
  final Size fitted = emulatedSize * scale;
  return EmulatedWindowPlacement(
    scale: scale,
    rect: Rect.fromLTWH(
      available.left + (available.width - fitted.width) / 2,
      available.top + (available.height - fitted.height) / 2,
      fitted.width,
      fitted.height,
    ),
  );
}

/// The real window's [realInsets] (the keyboard) as the emulated window sees
/// them.
///
/// Each side is how far the inset reaches into the emulated window, in
/// emulated logical pixels. A side the inset does not reach is zero, and no
/// side is larger than the window.
EdgeInsets emulatedViewInsets({
  required EdgeInsets realInsets,
  required Size realSize,
  required EmulatedWindowPlacement placement,
  required Size emulatedSize,
}) {
  final Rect rect = placement.rect;
  final double scale = placement.scale;
  double side(double reach, double limit) =>
      (reach / scale).clamp(0.0, limit).toDouble();
  return EdgeInsets.fromLTRB(
    side(realInsets.left - rect.left, emulatedSize.width),
    side(realInsets.top - rect.top, emulatedSize.height),
    side(rect.right - (realSize.width - realInsets.right), emulatedSize.width),
    side(
      rect.bottom - (realSize.height - realInsets.bottom),
      emulatedSize.height,
    ),
  );
}

/// The larger of [real] and [emulated] on each side.
///
/// The safe area of a window that keeps its real size while it takes the
/// safe area of an emulated device: the real system bars still have to stay
/// clear.
EdgeInsets mergeSafeArea(EdgeInsets real, EdgeInsets emulated) {
  return EdgeInsets.fromLTRB(
    math.max(real.left, emulated.left),
    math.max(real.top, emulated.top),
    math.max(real.right, emulated.right),
    math.max(real.bottom, emulated.bottom),
  );
}
