import 'dart:math' as math;
import 'dart:ui'
    show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Rect, Size;

import 'package:foldable/foldable.dart';

import 'fold_division_config.dart';

/// The `FoldableCapabilities.strategy` of every snapshot this package builds.
const String kFoldDivisionStrategy = 'android-display-features';

/// Hinge angles at or below this many degrees read as `HingeStatus.closed`.
const double kClosedAngleThreshold = 20;

/// Hinge angles at or above this many degrees read as `HingeStatus.fullyOpen`.
const double kFlatAngleThreshold = 160;

/// Windows at least this wide, in logical pixels, are `SizeClass.regular`
/// in width.
const double kRegularWidthBreakpoint = 600;

/// Windows at least this tall, in logical pixels, are `SizeClass.regular`
/// in height.
const double kRegularHeightBreakpoint = 480;

/// The posture a hinge [angle] in degrees stands for.
///
/// - [kClosedAngleThreshold] or less: `closed`.
/// - [kFlatAngleThreshold] or more: `fullyOpen`.
/// - Anything between: `partiallyOpen`.
/// - No reading: `unknown`.
HingeStatus postureForAngle(double? angle) {
  if (angle == null || angle.isNaN) return HingeStatus.unknown;
  if (angle <= kClosedAngleThreshold) return HingeStatus.closed;
  if (angle >= kFlatAngleThreshold) return HingeStatus.fullyOpen;
  return HingeStatus.partiallyOpen;
}

/// The size class of a window [width] logical pixels wide.
///
/// `regular` from [kRegularWidthBreakpoint] up, `compact` below, and
/// `unspecified` for a window with no width yet.
///
/// 600 is where Android's own window size classes leave "compact". It also
/// sorts the iPhone Duo windows the way the `foldable` README says iOS does:
/// the inner display (951 or 669 wide) is regular, the cover display and a
/// Split View half (about 475 wide) are compact.
SizeClass sizeClassForWidth(double width) {
  if (!(width > 0)) return SizeClass.unspecified;
  return width >= kRegularWidthBreakpoint
      ? SizeClass.regular
      : SizeClass.compact;
}

/// The size class of a window [height] logical pixels tall.
///
/// `regular` from [kRegularHeightBreakpoint] up, `compact` below, and
/// `unspecified` for a window with no height yet.
///
/// 480 is Android's compact height breakpoint. iOS reports a compact height
/// for a phone on its side (440 or less) and a regular one for a phone
/// upright and for an iPad. The iPhone Duo inner display is 669 tall at its
/// shortest, which lands on regular. What iOS reports there is not confirmed.
SizeClass sizeClassForHeight(double height) {
  if (!(height > 0)) return SizeClass.unspecified;
  return height >= kRegularHeightBreakpoint
      ? SizeClass.regular
      : SizeClass.compact;
}

/// [features] with their bounds divided by [devicePixelRatio].
///
/// For a feature list that holds physical pixels, such as one read from a
/// platform channel. `FlutterView.displayFeatures` and
/// `MediaQuery.displayFeatures` need no conversion: the engine reports them
/// in logical pixels.
List<DisplayFeature> logicalDisplayFeatures(
  Iterable<DisplayFeature> features,
  double devicePixelRatio,
) {
  final double ratio = devicePixelRatio > 0 ? devicePixelRatio : 1;
  return <DisplayFeature>[
    for (final DisplayFeature feature in features)
      DisplayFeature(
        bounds: Rect.fromLTRB(
          feature.bounds.left / ratio,
          feature.bounds.top / ratio,
          feature.bounds.right / ratio,
          feature.bounds.bottom / ratio,
        ),
        type: feature.type,
        state: feature.state,
      ),
  ];
}

/// Builds the `FoldableData` an Android window stands for.
///
/// A pure function: the same inputs give the same snapshot.
///
/// - [logicalFeatures]: the window's display features, bounds in logical
///   pixels, as `FlutterView.displayFeatures` holds them.
/// - [viewSize]: the window size in logical pixels.
/// - [hingeAngle]: the last hinge sensor reading in degrees (0 closed, 180
///   flat), or null.
/// - [hasHingeSensor]: whether the device has a hinge angle sensor.
/// - [config]: the division mode settings.
///
/// ## Posture
///
/// With a fold or hinge feature in the window:
///
/// - `postureHalfOpened` gives `partiallyOpen`.
/// - `postureFlat` gives `fullyOpen`.
/// - An `unknown` state falls back to [postureForAngle]. A `closed` answer
///   becomes `partiallyOpen` there, since a closed device shows no fold.
///
/// With no fold or hinge feature in the window:
///
/// - A device with a hinge sensor follows the angle. [kClosedAngleThreshold]
///   or less reads `closed` (the cover screen). Above it [postureForAngle]
///   decides, which covers an open device whose window sits on one side of
///   the fold.
/// - A device with a hinge sensor and no angle reading yet reads `unknown`.
///   The base widgets treat `unknown` as no fold in effect.
/// - A device with no hinge sensor has no hinge: `unknown`, `isFoldable`
///   false.
///
/// `DivisionActivation.always` reports `partiallyOpen` whenever a fold is in
/// the window.
///
/// ## Regions
///
/// - Division mode on: each fold or hinge becomes a `division` region,
///   centred on the centre line of the feature and running the full window
///   along the fold.
///   - It is `config.divisionExtent` across, or as wide as the hinge when
///     the hinge is wider.
///   - It stands upright when the feature reaches the top and bottom window
///     edges, and lies flat when it reaches the left and right ones. The
///     shape of the feature decides when the edges do not.
///   - It is cut to the window, so a fold near an edge gives a narrower
///     division.
/// - Division mode off: each fold or hinge becomes a `division` region with
///   the feature's own bounds.
/// - Either way `isActive` is true while the posture is `partiallyOpen`.
/// - Each cutout becomes an active `occlusion` region.
///
/// ## The rest
///
/// - `displayFeatures` is empty. `FoldableProvider` fills it from its bridge
///   mode, as it does on iOS.
/// - Size classes come from [sizeClassForWidth] and [sizeClassForHeight],
///   with or without a hinge.
/// - `supportLevel` is `available` with a hinge and `availableNoHinge`
///   without one.
FoldableData emulateDivision({
  required List<DisplayFeature> logicalFeatures,
  required Size viewSize,
  required double? hingeAngle,
  required bool hasHingeSensor,
  required FoldDivisionConfig config,
}) {
  final List<DisplayFeature> folds = <DisplayFeature>[
    for (final DisplayFeature feature in logicalFeatures)
      if (feature.type == DisplayFeatureType.fold ||
          feature.type == DisplayFeatureType.hinge)
        feature,
  ];
  final bool isFoldable = hasHingeSensor || folds.isNotEmpty;
  final double? angle =
      (hingeAngle == null || hingeAngle.isNaN) ? null : hingeAngle;

  final List<ReservedRegion> occlusions = <ReservedRegion>[
    for (final DisplayFeature feature in logicalFeatures)
      if (feature.type == DisplayFeatureType.cutout)
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: feature.bounds,
          isActive: true,
        ),
  ];

  final SizeClass horizontal = sizeClassForWidth(viewSize.width);
  final SizeClass vertical = sizeClassForHeight(viewSize.height);

  if (!isFoldable) {
    return FoldableData(
      capabilities: const FoldableCapabilities(
        supportLevel: FoldableSupportLevel.availableNoHinge,
        isFoldable: false,
        hingeApiPresent: false,
        regionApiPresent: true,
        angleUnitVerified: false,
        strategy: kFoldDivisionStrategy,
      ),
      status: HingeStatus.unknown,
      angleDegrees: null,
      regions: List<ReservedRegion>.unmodifiable(occlusions),
      displayFeatures: const <DisplayFeature>[],
      horizontalSizeClass: horizontal,
      verticalSizeClass: vertical,
    );
  }

  final HingeStatus status = _posture(folds, angle, config);
  final bool divisionActive = status == HingeStatus.partiallyOpen;

  final List<ReservedRegion> regions = <ReservedRegion>[
    for (final DisplayFeature fold in folds)
      ReservedRegion(
        kind: ReservedRegionKind.division,
        bounds: config.enabled
            ? _divisionBounds(fold.bounds, viewSize, config.divisionExtent)
            : fold.bounds,
        isActive: divisionActive,
      ),
    ...occlusions,
  ];

  return FoldableData(
    capabilities: FoldableCapabilities(
      supportLevel: FoldableSupportLevel.available,
      isFoldable: true,
      hingeApiPresent: hasHingeSensor,
      regionApiPresent: true,
      // Android documents its hinge angle sensor in degrees, 0 closed.
      angleUnitVerified: hasHingeSensor,
      strategy: kFoldDivisionStrategy,
    ),
    status: status,
    angleDegrees: angle,
    regions: List<ReservedRegion>.unmodifiable(regions),
    displayFeatures: const <DisplayFeature>[],
    horizontalSizeClass: horizontal,
    verticalSizeClass: vertical,
  );
}

HingeStatus _posture(
  List<DisplayFeature> folds,
  double? angle,
  FoldDivisionConfig config,
) {
  if (folds.isEmpty) {
    // No reading says nothing about the hinge. `closed` needs an angle.
    if (angle == null) return HingeStatus.unknown;
    if (angle <= kClosedAngleThreshold) return HingeStatus.closed;
    return postureForAngle(angle);
  }

  if (config.enabled && config.activation == DivisionActivation.always) {
    return HingeStatus.partiallyOpen;
  }

  final DisplayFeatureState state = folds.first.state;
  if (state == DisplayFeatureState.postureHalfOpened) {
    return HingeStatus.partiallyOpen;
  }
  if (state == DisplayFeatureState.postureFlat) {
    return HingeStatus.fullyOpen;
  }
  final HingeStatus fromAngle = postureForAngle(angle);
  return fromAngle == HingeStatus.closed
      ? HingeStatus.partiallyOpen
      : fromAngle;
}

/// Whether [fold] runs top to bottom in a window of [viewSize].
///
/// The window edges decide: a feature that reaches the top and the bottom
/// edge stands upright, one that reaches the left and the right edge lies
/// flat. A feature that reaches both pairs, or neither, or a window with no
/// size yet, falls back to the shape of the feature.
bool _standsUpright(Rect fold, Size viewSize) {
  if (viewSize.width > 0 && viewSize.height > 0) {
    final bool spansHeight = fold.top <= 0 && fold.bottom >= viewSize.height;
    final bool spansWidth = fold.left <= 0 && fold.right >= viewSize.width;
    if (spansHeight != spansWidth) return spansHeight;
  }
  return fold.height >= fold.width;
}

Rect _divisionBounds(Rect fold, Size viewSize, double extent) {
  final bool hasSize = viewSize.width > 0 && viewSize.height > 0;
  final Rect division;
  if (_standsUpright(fold, viewSize)) {
    // Never narrower than a hinge that hides pixels.
    final double half = math.max(extent, fold.width) / 2;
    final double centre = fold.center.dx;
    division = Rect.fromLTRB(
      centre - half,
      hasSize ? 0 : fold.top,
      centre + half,
      hasSize ? viewSize.height : fold.bottom,
    );
  } else {
    final double half = math.max(extent, fold.height) / 2;
    final double centre = fold.center.dy;
    division = Rect.fromLTRB(
      hasSize ? 0 : fold.left,
      centre - half,
      hasSize ? viewSize.width : fold.right,
      centre + half,
    );
  }
  if (!hasSize) return division;
  // A fold near an edge would reach outside the window. Cut it to fit.
  return Rect.fromLTRB(
    division.left.clamp(0.0, viewSize.width),
    division.top.clamp(0.0, viewSize.height),
    division.right.clamp(0.0, viewSize.width),
    division.bottom.clamp(0.0, viewSize.height),
  );
}
