import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

DisplayFeature fold(Rect bounds, {bool hinge = false}) => DisplayFeature(
      bounds: bounds,
      type: hinge ? DisplayFeatureType.hinge : DisplayFeatureType.fold,
      state: DisplayFeatureState.postureHalfOpened,
    );

/// A snapshot of a real 673 x 841 window with a fold down the middle.
FoldableData realData({
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
  FoldDivisionConfig config = const FoldDivisionConfig(enabled: true),
}) =>
    emulateDivision(
      logicalFeatures: <DisplayFeature>[
        DisplayFeature(
          bounds: const Rect.fromLTRB(336.5, 0, 336.5, 841),
          type: DisplayFeatureType.fold,
          state: state,
        ),
        const DisplayFeature(
          bounds: Rect.fromLTWH(600, 10, 30, 30),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ],
      viewSize: const Size(673, 841),
      hingeAngle: state == DisplayFeatureState.postureFlat ? 180 : 95,
      hasHingeSensor: true,
      config: config,
    );

void main() {
  group('EmulatedDevice.iphoneDuo', () {
    const EmulatedDevice duo = EmulatedDevice.iphoneDuo;

    test('outer display, portrait', () {
      final EmulatedDeviceState state = duo.outerPortrait;
      expect(state.windowSize, const Size(466, 678));
      expect(state.safeArea, const EdgeInsets.only(right: 84, bottom: 34));
      expect(state.hasFold, isFalse);
      expect(state.divisionRect(40), isNull);
      expect(state.occlusions, const <Rect>[Rect.fromLTWH(385, 0, 84, 120)]);
    });

    test('outer display, landscape', () {
      final EmulatedDeviceState state = duo.outerLandscape;
      expect(state.windowSize, const Size(678, 466));
      expect(state.safeArea, const EdgeInsets.only(right: 84));
      expect(state.hasFold, isFalse);
      expect(state.occlusions, isEmpty);
    });

    test('inner display, landscape', () {
      final EmulatedDeviceState state = duo.innerLandscape;
      expect(state.windowSize, const Size(951, 669));
      expect(state.safeArea, const EdgeInsets.only(right: 84));
      expect(state.foldAxis, Axis.vertical);
      expect(state.foldCentre, 475.5);
      expect(state.divisionRect(40), const Rect.fromLTRB(455.5, 0, 495.5, 669));
    });

    test('inner display, portrait', () {
      final EmulatedDeviceState state = duo.innerPortrait;
      expect(state.windowSize, const Size(669, 951));
      expect(state.safeArea, const EdgeInsets.only(top: 84, bottom: 95));
      expect(state.foldAxis, Axis.horizontal);
      expect(state.foldCentre, 475.5);
      expect(state.divisionRect(40), const Rect.fromLTRB(0, 455.5, 669, 495.5));
    });

    test('stateFor maps each window kind to its state', () {
      expect(duo.stateFor(EmulatedWindowKind.outerPortrait), duo.outerPortrait);
      expect(
        duo.stateFor(EmulatedWindowKind.outerLandscape),
        duo.outerLandscape,
      );
      expect(
        duo.stateFor(EmulatedWindowKind.innerLandscape),
        duo.innerLandscape,
      );
      expect(duo.stateFor(EmulatedWindowKind.innerPortrait), duo.innerPortrait);
    });
  });

  group('profile model', () {
    test('a division near a window edge is cut to the window', () {
      const EmulatedDeviceState state = EmulatedDeviceState(
        windowSize: Size(100, 200),
        foldAxis: Axis.vertical,
        foldCentre: 10,
      );
      expect(state.divisionRect(40), const Rect.fromLTRB(0, 0, 30, 200));
    });

    test('state copyWith and equality follow the fields', () {
      final EmulatedDeviceState state = EmulatedDevice.iphoneDuo.innerLandscape;
      expect(state.copyWith(), state);
      expect(state.copyWith().hashCode, state.hashCode);
      final EmulatedDeviceState next = state.copyWith(
        windowSize: const Size(900, 600),
        safeArea: EdgeInsets.zero,
        foldCentre: 450,
        occlusions: const <Rect>[Rect.fromLTWH(0, 0, 10, 10)],
      );
      expect(next.windowSize, const Size(900, 600));
      expect(next.safeArea, EdgeInsets.zero);
      expect(next.foldAxis, Axis.vertical);
      expect(next.foldCentre, 450);
      expect(next.occlusions, hasLength(1));
      expect(next, isNot(state));
    });

    test('device copyWith and equality follow the fields', () {
      const EmulatedDevice duo = EmulatedDevice.iphoneDuo;
      expect(duo.copyWith(), duo);
      expect(duo.copyWith().hashCode, duo.hashCode);
      final EmulatedDevice measured = duo.copyWith(
        name: 'iPhone Duo, measured',
        outerPortrait: duo.outerPortrait.copyWith(
          windowSize: const Size(470, 680),
        ),
      );
      expect(measured.name, 'iPhone Duo, measured');
      expect(measured.outerPortrait.windowSize, const Size(470, 680));
      expect(measured.innerLandscape, duo.innerLandscape);
      expect(measured, isNot(duo));
    });
  });

  group('selectEmulatedWindow', () {
    EmulatedWindowKind select(Size size, [List<DisplayFeature>? features]) =>
        selectEmulatedWindow(
          windowSize: size,
          logicalFeatures: features ?? const <DisplayFeature>[],
        );

    test('no fold, taller than wide: outer portrait', () {
      expect(select(const Size(344, 882)), EmulatedWindowKind.outerPortrait);
    });

    test('no fold, wider than tall: outer landscape', () {
      expect(select(const Size(882, 344)), EmulatedWindowKind.outerLandscape);
    });

    test('no fold, square or with no size yet: outer portrait', () {
      expect(select(const Size(500, 500)), EmulatedWindowKind.outerPortrait);
      expect(select(Size.zero), EmulatedWindowKind.outerPortrait);
    });

    test('a fold running top to bottom: inner landscape', () {
      // The Fold held upright: the window is taller than wide, and the fold
      // still decides.
      expect(
        select(
          const Size(673, 841),
          <DisplayFeature>[fold(const Rect.fromLTRB(336.5, 0, 336.5, 841))],
        ),
        EmulatedWindowKind.innerLandscape,
      );
    });

    test('a fold running left to right: inner portrait', () {
      expect(
        select(
          const Size(841, 673),
          <DisplayFeature>[fold(const Rect.fromLTRB(0, 336.5, 841, 336.5))],
        ),
        EmulatedWindowKind.innerPortrait,
      );
    });

    test('a hinge with a width counts as a fold', () {
      expect(
        select(
          const Size(1114, 720),
          <DisplayFeature>[
            fold(const Rect.fromLTRB(540, 0, 574, 720), hinge: true),
          ],
        ),
        EmulatedWindowKind.innerLandscape,
      );
    });

    test('a cutout is not a fold', () {
      expect(
        select(
          const Size(673, 841),
          const <DisplayFeature>[
            DisplayFeature(
              bounds: Rect.fromLTWH(300, 0, 60, 841),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ],
        ),
        EmulatedWindowKind.outerPortrait,
      );
    });

    test('a fold on a window edge crosses nothing: outer display', () {
      expect(
        select(
          const Size(336, 841),
          <DisplayFeature>[fold(const Rect.fromLTRB(336, 0, 336, 841))],
        ),
        EmulatedWindowKind.outerPortrait,
      );
      expect(
        select(
          const Size(841, 336),
          <DisplayFeature>[fold(const Rect.fromLTRB(0, 0, 841, 0))],
        ),
        EmulatedWindowKind.outerLandscape,
      );
    });
  });

  group('emulateDeviceData', () {
    const FoldDivisionConfig config = FoldDivisionConfig(enabled: true);

    test('the inner display gets the division of the device', () {
      final FoldableData data = emulateDeviceData(
        data: realData(),
        state: EmulatedDevice.iphoneDuo.innerLandscape,
        config: config,
      );
      expect(data.regions, const <ReservedRegion>[
        ReservedRegion(
          kind: ReservedRegionKind.division,
          bounds: Rect.fromLTRB(455.5, 0, 495.5, 669),
          isActive: true,
        ),
      ]);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, 95);
      expect(data.capabilities, realData().capabilities);
      expect(data.displayFeatures, isEmpty);
    });

    test('divisionExtent sets how thick the division is', () {
      final FoldableData data = emulateDeviceData(
        data: realData(),
        state: EmulatedDevice.iphoneDuo.innerPortrait,
        config: config.copyWith(divisionExtent: 20),
      );
      expect(
        data.regions.single.bounds,
        const Rect.fromLTRB(0, 465.5, 669, 485.5),
      );
    });

    test('a flat hinge keeps the division and marks it inactive', () {
      final FoldableData data = emulateDeviceData(
        data: realData(state: DisplayFeatureState.postureFlat),
        state: EmulatedDevice.iphoneDuo.innerLandscape,
        config: config,
      );
      expect(data.status, HingeStatus.fullyOpen);
      expect(data.regions.single.isActive, isFalse);
      expect(data.regions.single.bounds.width, 40);
    });

    test('DivisionActivation.always keeps it active on a flat hinge', () {
      final FoldDivisionConfig always = config.copyWith(
        activation: DivisionActivation.always,
      );
      final FoldableData data = emulateDeviceData(
        data: realData(state: DisplayFeatureState.postureFlat, config: always),
        state: EmulatedDevice.iphoneDuo.innerLandscape,
        config: always,
      );
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.regions.single.isActive, isTrue);
    });

    test('the outer display has no division and publishes its occlusion', () {
      final FoldableData data = emulateDeviceData(
        data: realData(),
        state: EmulatedDevice.iphoneDuo.outerPortrait,
        config: config,
      );
      expect(data.regions, const <ReservedRegion>[
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: Rect.fromLTWH(385, 0, 84, 120),
          isActive: true,
        ),
      ]);
    });

    test('the real cutout is dropped', () {
      expect(
        realData().regions.map((ReservedRegion r) => r.kind),
        contains(ReservedRegionKind.occlusion),
      );
      final FoldableData data = emulateDeviceData(
        data: realData(),
        state: EmulatedDevice.iphoneDuo.innerLandscape,
        config: config,
      );
      expect(
        data.regions.map((ReservedRegion r) => r.kind),
        isNot(contains(ReservedRegionKind.occlusion)),
      );
    });

    test('size classes come from the emulated window', () {
      const EmulatedDevice duo = EmulatedDevice.iphoneDuo;
      FoldableData run(EmulatedDeviceState state) =>
          emulateDeviceData(data: realData(), state: state, config: config);

      expect(run(duo.outerPortrait).horizontalSizeClass, SizeClass.compact);
      expect(run(duo.outerPortrait).verticalSizeClass, SizeClass.regular);
      expect(run(duo.outerLandscape).horizontalSizeClass, SizeClass.regular);
      expect(run(duo.outerLandscape).verticalSizeClass, SizeClass.compact);
      expect(run(duo.innerLandscape).horizontalSizeClass, SizeClass.regular);
      expect(run(duo.innerLandscape).verticalSizeClass, SizeClass.regular);
    });
  });

  group('placeEmulatedWindow', () {
    test('fits the width and centres in the real safe area', () {
      final EmulatedWindowPlacement placement = placeEmulatedWindow(
        realSize: const Size(600, 1000),
        realPadding: const EdgeInsets.only(top: 40, bottom: 60),
        emulatedSize: const Size(1200, 600),
      )!;
      expect(placement.scale, 0.5);
      // 600 x 300 in the 600 x 900 between the bars, which starts at y 40.
      expect(placement.rect, const Rect.fromLTWH(0, 340, 600, 300));
    });

    test('fits the height when the window is the wider one', () {
      final EmulatedWindowPlacement placement = placeEmulatedWindow(
        realSize: const Size(1000, 400),
        realPadding: const EdgeInsets.only(left: 100),
        emulatedSize: const Size(400, 800),
      )!;
      expect(placement.scale, 0.5);
      expect(placement.rect, const Rect.fromLTWH(450, 0, 200, 400));
    });

    test('scales up a window smaller than the real one', () {
      final EmulatedWindowPlacement placement = placeEmulatedWindow(
        realSize: const Size(932, 1356),
        realPadding: EdgeInsets.zero,
        emulatedSize: const Size(466, 678),
      )!;
      expect(placement.scale, 2);
      expect(placement.rect, const Rect.fromLTWH(0, 0, 932, 1356));
    });

    test('toEmulated maps a real point into the emulated window', () {
      const EmulatedWindowPlacement placement = EmulatedWindowPlacement(
        scale: 0.5,
        rect: Rect.fromLTWH(0, 340, 600, 300),
      );
      expect(
          placement.toEmulated(const Offset(300, 490)), const Offset(600, 300));
    });

    test('no room gives null', () {
      expect(
        placeEmulatedWindow(
          realSize: Size.zero,
          realPadding: EdgeInsets.zero,
          emulatedSize: const Size(466, 678),
        ),
        isNull,
      );
      expect(
        placeEmulatedWindow(
          realSize: const Size(400, 100),
          realPadding: const EdgeInsets.only(top: 60, bottom: 60),
          emulatedSize: const Size(466, 678),
        ),
        isNull,
      );
      expect(
        placeEmulatedWindow(
          realSize: const Size(400, 800),
          realPadding: EdgeInsets.zero,
          emulatedSize: Size.zero,
        ),
        isNull,
      );
    });
  });

  group('emulatedViewInsets', () {
    const Size realSize = Size(600, 1000);
    const Size emulatedSize = Size(1200, 600);
    // The emulated window covers y 340 to 640 of the real one at half size.
    const EmulatedWindowPlacement placement = EmulatedWindowPlacement(
      scale: 0.5,
      rect: Rect.fromLTWH(0, 340, 600, 300),
    );

    EdgeInsets convert(EdgeInsets real) => emulatedViewInsets(
          realInsets: real,
          realSize: realSize,
          placement: placement,
          emulatedSize: emulatedSize,
        );

    test('no keyboard is no inset', () {
      expect(convert(EdgeInsets.zero), EdgeInsets.zero);
    });

    test('a keyboard below the emulated window is clamped at zero', () {
      // Its top edge is at y 700, under the window that ends at 640.
      expect(convert(const EdgeInsets.only(bottom: 300)), EdgeInsets.zero);
    });

    test('a keyboard that reaches into the window is converted', () {
      // Its top edge is at y 540: 100 real pixels of the window, 200 emulated.
      expect(
        convert(const EdgeInsets.only(bottom: 460)),
        const EdgeInsets.only(bottom: 200),
      );
    });

    test('an inset is never larger than the window', () {
      expect(
        convert(const EdgeInsets.only(bottom: 900)),
        const EdgeInsets.only(bottom: 600),
      );
    });
  });

  test('mergeSafeArea keeps the larger value on each side', () {
    expect(
      mergeSafeArea(
        const EdgeInsets.fromLTRB(0, 24, 0, 48),
        const EdgeInsets.only(right: 84, bottom: 34),
      ),
      const EdgeInsets.fromLTRB(0, 24, 84, 48),
    );
  });
}
