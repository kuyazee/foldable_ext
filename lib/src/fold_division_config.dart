import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'emulated_device.dart';

/// When the emulated division counts as active.
enum DivisionActivation {
  /// The division is active while the hinge is partially open, as on iPhone
  /// Duo. A flat device reports the division with `isActive: false`.
  followPosture,

  /// The division is active whenever the fold is inside the window.
  ///
  /// The posture is also reported as `HingeStatus.partiallyOpen` in this mode,
  /// whatever the hinge does. The base widgets (`FoldAwareBuilder`,
  /// `DisplayFeatureBridge`) trust the posture over `isActive`, so a division
  /// that is active on a flat device would stay hidden from them otherwise.
  /// Use it to check a layout against the division with the Fold lying flat.
  /// The hinge angle keeps its real value.
  always,
}

/// The settings of division mode.
///
/// Set it through `FoldDivision.config`. Every change sends a new snapshot to
/// the listeners of the `foldable` API.
@immutable
class FoldDivisionConfig {
  /// Creates a config.
  const FoldDivisionConfig({
    this.enabled = kDebugMode,
    this.divisionExtent = defaultDivisionExtent,
    this.margins = defaultMargins,
    this.activation = DivisionActivation.followPosture,
    this.device = EmulatedDevice.iphoneDuo,
    this.matchWindowSize = true,
  }) : assert(divisionExtent >= 0, 'divisionExtent must not be negative');

  /// The width of the iPhone Duo division, in logical pixels.
  ///
  /// The `foldable` package measured 40pt on the 951x669pt inner display.
  static const double defaultDivisionExtent = 40;

  /// The default keep-clear room on each side of the division.
  ///
  /// 12 logical pixels on the two sides that face the panes. The value
  /// is assumed: nobody has measured it on iPhone Duo hardware. Override it
  /// once a real reading exists.
  static const EdgeInsets defaultMargins = EdgeInsets.symmetric(horizontal: 12);

  /// Whether division mode is on.
  ///
  /// On: an Android fold is reported as an iPhone Duo style division,
  /// [divisionExtent] across and centred on the hinge, and a
  /// `FoldDivisionScope` on an Android foldable renders its subtree as
  /// [device].
  /// Off: the real hinge bounds are reported unchanged and no device is
  /// emulated.
  ///
  /// Defaults to [kDebugMode], so release builds report the real hinge unless
  /// the app turns the mode on.
  final bool enabled;

  /// How far the emulated division reaches across the fold, in logical pixels.
  final double divisionExtent;

  /// The room interactive content should keep clear around the division.
  ///
  /// Written for a division that runs top to bottom (book orientation):
  /// `left` and `right` face the two panes. [marginsFor] turns the value for a
  /// division that runs left to right.
  ///
  /// The `foldable` package sends no margins, on iOS or anywhere else. This
  /// value is the only source of margins on every platform.
  final EdgeInsets margins;

  /// When the emulated division counts as active.
  final DivisionActivation activation;

  /// The device a `FoldDivisionScope` renders its subtree as, on an Android
  /// foldable while [enabled] is true.
  ///
  /// Defaults to [EmulatedDevice.iphoneDuo], so turning division mode on
  /// gives the window size, the safe area and the fold of an iPhone Duo.
  /// Null emulates no device: the window and its safe area stay real and the
  /// division sits on the hinge.
  final EmulatedDevice? device;

  /// Whether the subtree of a `FoldDivisionScope` gets the window size of
  /// [device].
  ///
  /// On: the subtree is laid out at the window size of the device, scaled to
  /// fit the real window, and the division sits on the fold of the device.
  /// Off: the window keeps its real size, the safe area is the larger of the
  /// real one and the one of the device on each side, and the division sits
  /// on the real hinge.
  ///
  /// It has no effect while [device] is null.
  final bool matchWindowSize;

  /// [margins] turned to match a division with the bounds [division].
  ///
  /// A division at least as tall as it is wide gets [margins] as written. A
  /// wider one gets them transposed: `left` becomes `top`, `right` becomes
  /// `bottom`, `top` becomes `left` and `bottom` becomes `right`.
  EdgeInsets marginsFor(Rect division) {
    if (division.height >= division.width) return margins;
    return EdgeInsets.fromLTRB(
      margins.top,
      margins.left,
      margins.bottom,
      margins.right,
    );
  }

  /// The keep-clear rect: [division] grown by [marginsFor] it.
  Rect keepClearRect(Rect division) =>
      marginsFor(division).inflateRect(division);

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass [clearDevice] to emulate no device. A null [device] keeps the
  /// current one.
  FoldDivisionConfig copyWith({
    bool? enabled,
    double? divisionExtent,
    EdgeInsets? margins,
    DivisionActivation? activation,
    EmulatedDevice? device,
    bool clearDevice = false,
    bool? matchWindowSize,
  }) {
    return FoldDivisionConfig(
      enabled: enabled ?? this.enabled,
      divisionExtent: divisionExtent ?? this.divisionExtent,
      margins: margins ?? this.margins,
      activation: activation ?? this.activation,
      device: clearDevice ? null : (device ?? this.device),
      matchWindowSize: matchWindowSize ?? this.matchWindowSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldDivisionConfig &&
          other.enabled == enabled &&
          other.divisionExtent == divisionExtent &&
          other.margins == margins &&
          other.activation == activation &&
          other.device == device &&
          other.matchWindowSize == matchWindowSize;

  @override
  int get hashCode => Object.hash(
        enabled,
        divisionExtent,
        margins,
        activation,
        device,
        matchWindowSize,
      );

  @override
  String toString() =>
      'FoldDivisionConfig(enabled: $enabled, extent: $divisionExtent, '
      'margins: $margins, activation: ${activation.name}, '
      'device: ${device?.name}, matchWindowSize: $matchWindowSize)';
}
