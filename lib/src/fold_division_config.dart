import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
  /// [divisionExtent] across and centred on the hinge.
  /// Off: the real hinge bounds are reported unchanged.
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
  FoldDivisionConfig copyWith({
    bool? enabled,
    double? divisionExtent,
    EdgeInsets? margins,
    DivisionActivation? activation,
  }) {
    return FoldDivisionConfig(
      enabled: enabled ?? this.enabled,
      divisionExtent: divisionExtent ?? this.divisionExtent,
      margins: margins ?? this.margins,
      activation: activation ?? this.activation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldDivisionConfig &&
          other.enabled == enabled &&
          other.divisionExtent == divisionExtent &&
          other.margins == margins &&
          other.activation == activation;

  @override
  int get hashCode => Object.hash(enabled, divisionExtent, margins, activation);

  @override
  String toString() =>
      'FoldDivisionConfig(enabled: $enabled, extent: $divisionExtent, '
      'margins: $margins, activation: ${activation.name})';
}
