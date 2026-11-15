import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

// A Galaxy Z Fold inner display in logical pixels, upright: 673 x 841 with a
// zero-width fold down the middle. Samsung reports the fold as a line.
const Size kFoldInner = Size(673, 841);
const Rect kBookFold = Rect.fromLTWH(336.5, 0, 0, 841);

// The same display turned on its side: the fold runs left to right.
const Size kFoldInnerRotated = Size(841, 673);
const Rect kTabletopFold = Rect.fromLTWH(0, 336.5, 841, 0);

const FoldDivisionConfig kOn = FoldDivisionConfig(enabled: true);
const FoldDivisionConfig kOff = FoldDivisionConfig(enabled: false);

DisplayFeature fold(
  Rect bounds,
  DisplayFeatureState state, {
  DisplayFeatureType type = DisplayFeatureType.fold,
}) =>
    DisplayFeature(bounds: bounds, type: type, state: state);

const DisplayFeature kCutout = DisplayFeature(
  bounds: Rect.fromLTWH(600, 10, 30, 30),
  type: DisplayFeatureType.cutout,
  state: DisplayFeatureState.unknown,
);

FoldableData run({
  List<DisplayFeature> features = const <DisplayFeature>[],
  Size size = kFoldInner,
  double? angle,
  bool sensor = true,
  FoldDivisionConfig config = kOn,
}) =>
    emulateDivision(
      logicalFeatures: features,
      viewSize: size,
      hingeAngle: angle,
      hasHingeSensor: sensor,
      config: config,
    );

ReservedRegion divisionOf(FoldableData data) => data.regions.firstWhere(
      (ReservedRegion r) => r.kind == ReservedRegionKind.division,
    );

void main() {
  group('posture', () {
    test('a half opened fold is partiallyOpen', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
        angle: 95,
      );
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.isPartiallyOpen, isTrue);
      expect(data.angleDegrees, 95);
    });

    test('a flat fold is fullyOpen', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
        angle: 180,
      );
      expect(data.status, HingeStatus.fullyOpen);
      expect(data.isFullyOpen, isTrue);
    });

    test('the feature state wins over the angle', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
        angle: 100,
      );
      expect(data.status, HingeStatus.fullyOpen);
    });

    test('an unknown feature state falls back to the angle', () {
      FoldableData at(double? angle) => run(
            features: <DisplayFeature>[
              fold(kBookFold, DisplayFeatureState.unknown),
            ],
            angle: angle,
          );
      expect(at(90).status, HingeStatus.partiallyOpen);
      expect(at(159.9).status, HingeStatus.partiallyOpen);
      expect(at(160).status, HingeStatus.fullyOpen);
      expect(at(180).status, HingeStatus.fullyOpen);
      // A fold in the window rules out a closed device.
      expect(at(5).status, HingeStatus.partiallyOpen);
      expect(at(null).status, HingeStatus.unknown);
    });

    test('a hinge sensor with no fold in the window is the cover screen', () {
      expect(
        run(size: const Size(360, 800), angle: 0).status,
        HingeStatus.closed,
      );
      expect(
        run(size: const Size(360, 800), angle: 20).status,
        HingeStatus.closed,
      );
    });

    test('no fold in the window and no angle reading is unknown', () {
      final FoldableData data = run(size: const Size(360, 800));
      expect(data.status, HingeStatus.unknown);
      expect(data.isFoldable, isTrue);
      expect(data.regions, isEmpty);
    });

    test(
        'a hinge sensor with no fold in the window needs an angle to be closed',
        () {
      FoldableData at(double? angle) => emulateDivision(
            logicalFeatures: const <DisplayFeature>[],
            viewSize: const Size(360, 800),
            hingeAngle: angle,
            hasHingeSensor: true,
            config: const FoldDivisionConfig(enabled: true),
          );
      expect(at(null).status, HingeStatus.unknown);
      expect(at(null).isFoldable, isTrue);
      expect(at(0).status, HingeStatus.closed);
      expect(at(20).status, HingeStatus.closed);

      // The base bridge treats unknown as no fold in effect.
      expect(
        DisplayFeatureBridge.build(
          mode: DisplayFeatureBridgeMode.full,
          regions: at(null).regions,
          status: at(null).status,
        ),
        isEmpty,
      );
    });

    test('an open device with the window beside the fold follows the angle',
        () {
      expect(
        run(size: const Size(336, 841), angle: 180).status,
        HingeStatus.fullyOpen,
      );
      expect(
        run(size: const Size(336, 841), angle: 100).status,
        HingeStatus.partiallyOpen,
      );
    });

    test('no hinge sensor and no fold is not a foldable', () {
      final FoldableData data = run(sensor: false, size: const Size(411, 890));
      expect(data.isFoldable, isFalse);
      expect(data.status, HingeStatus.unknown);
      expect(data.angleDegrees, isNull);
      expect(data.regions, isEmpty);
      expect(
        data.capabilities.supportLevel,
        FoldableSupportLevel.availableNoHinge,
      );
    });

    test('a fold with no hinge sensor is still a foldable', () {
      final FoldableData data = run(
        sensor: false,
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, isNull);
      expect(data.capabilities.hingeApiPresent, isFalse);
      expect(data.capabilities.angleUnitVerified, isFalse);
    });

    test('postureForAngle thresholds', () {
      expect(postureForAngle(null), HingeStatus.unknown);
      expect(postureForAngle(double.nan), HingeStatus.unknown);
      expect(postureForAngle(0), HingeStatus.closed);
      expect(postureForAngle(kClosedAngleThreshold), HingeStatus.closed);
      expect(postureForAngle(20.1), HingeStatus.partiallyOpen);
      expect(postureForAngle(159.9), HingeStatus.partiallyOpen);
      expect(postureForAngle(kFlatAngleThreshold), HingeStatus.fullyOpen);
      expect(postureForAngle(200), HingeStatus.fullyOpen);
    });
  });

  group('division mode on', () {
    test('a zero-width book fold becomes a 40 wide upright division', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      final ReservedRegion division = divisionOf(data);
      expect(division.bounds, const Rect.fromLTRB(316.5, 0, 356.5, 841));
      expect(division.bounds.center.dx, kBookFold.center.dx);
      expect(division.isActive, isTrue);
      expect(division.wouldSplitLayout, isTrue);
      expect(data.activeDivisions, hasLength(1));
    });

    test('a rotated fold becomes a 40 tall division lying flat', () {
      final FoldableData data = run(
        size: kFoldInnerRotated,
        features: <DisplayFeature>[
          fold(kTabletopFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      expect(
        divisionOf(data).bounds,
        const Rect.fromLTRB(0, 316.5, 841, 356.5),
      );
    });

    test('the division spans the whole window along the fold', () {
      // A feature a few pixels short of the window edges.
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(
            const Rect.fromLTRB(336.5, 24, 336.5, 800),
            DisplayFeatureState.postureHalfOpened,
          ),
        ],
      );
      expect(divisionOf(data).bounds.top, 0);
      expect(divisionOf(data).bounds.bottom, 841);
    });

    test('a hinge with a width is centred on its centre line', () {
      final FoldableData data = run(
        size: const Size(1114, 720),
        features: <DisplayFeature>[
          fold(
            const Rect.fromLTWH(540, 0, 34, 720),
            DisplayFeatureState.postureHalfOpened,
            type: DisplayFeatureType.hinge,
          ),
        ],
      );
      expect(divisionOf(data).bounds, const Rect.fromLTRB(537, 0, 577, 720));
    });

    test('divisionExtent sets the width', () {
      final FoldableData data = run(
        config: kOn.copyWith(divisionExtent: 24),
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      expect(
          divisionOf(data).bounds, const Rect.fromLTRB(324.5, 0, 348.5, 841));
    });

    test('a flat device keeps the division but marks it inactive', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
        angle: 180,
      );
      final ReservedRegion division = divisionOf(data);
      expect(division.bounds.width, 40);
      expect(division.isActive, isFalse);
      expect(data.activeDivisions, isEmpty);
    });

    test('DivisionActivation.always is active and partiallyOpen when flat', () {
      final FoldableData data = run(
        config: kOn.copyWith(activation: DivisionActivation.always),
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
        angle: 180,
      );
      expect(data.status, HingeStatus.partiallyOpen);
      expect(divisionOf(data).isActive, isTrue);
      // The real angle is kept.
      expect(data.angleDegrees, 180);
    });

    test('DivisionActivation.always leaves the cover screen closed', () {
      final FoldableData data = run(
        config: kOn.copyWith(activation: DivisionActivation.always),
        size: const Size(360, 800),
        angle: 0,
      );
      expect(data.status, HingeStatus.closed);
      expect(data.regions, isEmpty);
    });

    test('a window with no size yet keeps the length of the feature', () {
      final FoldableData data = run(
        size: Size.zero,
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      expect(
          divisionOf(data).bounds, const Rect.fromLTRB(316.5, 0, 356.5, 841));
      expect(data.horizontalSizeClass, SizeClass.unspecified);
      expect(data.verticalSizeClass, SizeClass.unspecified);
    });

    test('division bounds near a window edge and for a hinge with a width', () {
      FoldableData at(Rect bounds, Size size, DisplayFeatureType type) =>
          emulateDivision(
            logicalFeatures: <DisplayFeature>[
              DisplayFeature(
                bounds: bounds,
                type: type,
                state: DisplayFeatureState.postureHalfOpened,
              ),
            ],
            viewSize: size,
            hingeAngle: 90,
            hasHingeSensor: true,
            config: const FoldDivisionConfig(enabled: true),
          );

      // A fold 5 logical pixels from the left edge of a 300 wide window: the
      // division is cut to the window.
      final FoldableData edge = at(
        const Rect.fromLTRB(5, 0, 5, 800),
        const Size(300, 800),
        DisplayFeatureType.fold,
      );
      expect(edge.regions.first.bounds, const Rect.fromLTRB(0, 0, 25, 800));

      // A hinge 60 wide: the division is never narrower than the hinge.
      final FoldableData wide = at(
        const Rect.fromLTRB(370, 0, 430, 600),
        const Size(800, 600),
        DisplayFeatureType.hinge,
      );
      expect(wide.regions.first.bounds, const Rect.fromLTRB(370, 0, 430, 600));

      // The same hinge clipped by a short window is 60 wide and 40 tall. It
      // reaches the top and bottom edges, so it still stands upright.
      final FoldableData clipped = at(
        const Rect.fromLTRB(370, 0, 430, 40),
        const Size(800, 40),
        DisplayFeatureType.hinge,
      );
      expect(
        clipped.regions.first.bounds,
        const Rect.fromLTRB(370, 0, 430, 40),
      );

      // The mirror case: a tall hinge strip in a narrow window lies flat.
      final FoldableData narrow = at(
        const Rect.fromLTRB(0, 370, 40, 430),
        const Size(40, 800),
        DisplayFeatureType.hinge,
      );
      expect(narrow.regions.first.bounds, const Rect.fromLTRB(0, 370, 40, 430));
    });
  });

  group('division mode off', () {
    test('the real hinge bounds are reported unchanged', () {
      final FoldableData data = run(
        config: kOff,
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
        ],
      );
      final ReservedRegion division = divisionOf(data);
      expect(division.bounds, kBookFold);
      expect(division.isActive, isTrue);
      expect(division.wouldSplitLayout, isFalse);
      expect(data.status, HingeStatus.partiallyOpen);
    });

    test('DivisionActivation.always has no effect', () {
      final FoldableData data = run(
        config: kOff.copyWith(activation: DivisionActivation.always),
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
      );
      expect(data.status, HingeStatus.fullyOpen);
      expect(divisionOf(data).isActive, isFalse);
    });
  });

  group('cutouts and capabilities', () {
    test('a cutout becomes an active occlusion', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
          kCutout,
        ],
      );
      expect(data.regions, hasLength(2));
      expect(
        data.regions.last,
        const ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: Rect.fromLTWH(600, 10, 30, 30),
          isActive: true,
        ),
      );
    });

    test('a cutout is reported on a device with no hinge too', () {
      final FoldableData data = run(
        sensor: false,
        features: const <DisplayFeature>[kCutout],
      );
      expect(data.isFoldable, isFalse);
      expect(data.regions.single.kind, ReservedRegionKind.occlusion);
    });

    test('capabilities of a foldable', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
        angle: 180,
      );
      expect(
        data.capabilities,
        const FoldableCapabilities(
          supportLevel: FoldableSupportLevel.available,
          isFoldable: true,
          hingeApiPresent: true,
          regionApiPresent: true,
          angleUnitVerified: true,
          strategy: 'android-display-features',
        ),
      );
    });

    test('displayFeatures is left empty for the provider to fill', () {
      final FoldableData data = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureHalfOpened),
          kCutout,
        ],
      );
      expect(data.displayFeatures, isEmpty);
    });

    test('the same inputs give equal snapshots', () {
      FoldableData once() => run(
            features: <DisplayFeature>[
              fold(kBookFold, DisplayFeatureState.postureHalfOpened),
              kCutout,
            ],
            angle: 100,
          );
      expect(once(), once());
    });
  });

  group('size classes', () {
    test('the iPhone Duo windows sort the way iOS sorts them', () {
      // Inner display, open on its side and upright.
      expect(sizeClassForWidth(951), SizeClass.regular);
      expect(sizeClassForWidth(669), SizeClass.regular);
      expect(sizeClassForHeight(669), SizeClass.regular);
      // A Split View half.
      expect(sizeClassForWidth(475), SizeClass.compact);
      // A phone on its side.
      expect(sizeClassForHeight(440), SizeClass.compact);
    });

    test('breakpoints', () {
      expect(sizeClassForWidth(599.9), SizeClass.compact);
      expect(sizeClassForWidth(kRegularWidthBreakpoint), SizeClass.regular);
      expect(sizeClassForHeight(479.9), SizeClass.compact);
      expect(sizeClassForHeight(kRegularHeightBreakpoint), SizeClass.regular);
      expect(sizeClassForWidth(0), SizeClass.unspecified);
      expect(sizeClassForHeight(0), SizeClass.unspecified);
    });

    test('a Fold reports compact on the cover and regular inside', () {
      final FoldableData cover = run(size: const Size(360, 800), angle: 0);
      expect(cover.horizontalSizeClass, SizeClass.compact);
      expect(cover.verticalSizeClass, SizeClass.regular);

      final FoldableData inner = run(
        features: <DisplayFeature>[
          fold(kBookFold, DisplayFeatureState.postureFlat),
        ],
      );
      expect(inner.horizontalSizeClass, SizeClass.regular);
      expect(inner.verticalSizeClass, SizeClass.regular);
    });

    test('a device with no hinge still gets size classes', () {
      final FoldableData data = run(sensor: false, size: const Size(411, 890));
      expect(data.horizontalSizeClass, SizeClass.compact);
      expect(data.verticalSizeClass, SizeClass.regular);
    });
  });

  test('logicalDisplayFeatures divides bounds by the pixel ratio', () {
    final List<DisplayFeature> logical = logicalDisplayFeatures(
      const <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTRB(884, 0, 884, 2208),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      2.625,
    );
    expect(logical.single.bounds.left, closeTo(336.76, 0.01));
    expect(logical.single.bounds.width, 0);
    expect(logical.single.bounds.bottom, closeTo(841.14, 0.01));
    expect(logical.single.type, DisplayFeatureType.fold);
    expect(logical.single.state, DisplayFeatureState.postureHalfOpened);
  });
}
