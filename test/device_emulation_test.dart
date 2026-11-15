import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

import 'support.dart';

/// The Android status and navigation bars of the test window, in logical
/// pixels.
const double kStatusBar = 24;
const double kNavigationBar = 16;

const EmulatedDevice kDuo = EmulatedDevice.iphoneDuo;

/// Gives the test window its system bars.
void showBars() {
  const FakeViewPadding bars = FakeViewPadding(
    top: kStatusBar * kFoldPixelRatio,
    bottom: kNavigationBar * kFoldPixelRatio,
  );
  testView
    ..padding = bars
    ..viewPadding = bars;
}

/// Makes the test view the inner display turned on its side: the fold runs
/// left to right.
void showInnerDisplayRotated(DisplayFeatureState state) {
  FakeHingePlugin.current?.moveTo(
    state == DisplayFeatureState.postureFlat ? 180 : 95,
  );
  testView
    ..devicePixelRatio = kFoldPixelRatio
    ..physicalSize = kFoldPhysicalSize.flipped
    ..displayFeatures = <DisplayFeature>[
      DisplayFeature(
        bounds: Rect.fromLTRB(0, kFoldCentre, kFoldBounds.bottom, kFoldCentre),
        type: DisplayFeatureType.fold,
        state: state,
      ),
    ];
}

Size get realSize => testView.physicalSize / testView.devicePixelRatio;

/// Where the emulated window [state] lands in the test window.
EmulatedWindowPlacement placementOf(EmulatedDeviceState state) =>
    placeEmulatedWindow(
      realSize: realSize,
      realPadding: const EdgeInsets.only(
        top: kStatusBar,
        bottom: kNavigationBar,
      ),
      emulatedSize: state.windowSize,
    )!;

/// Lets the provider's snapshot and stream replay land.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// What a widget under the scope reads.
class Seen {
  late MediaQueryData media;
  late FoldableData data;
  late DeviceEmulation? emulation;
  late EmulatedDevice? device;
  late ReservedRegion? division;
  late Rect? keepClear;
  late EdgeInsets margins;
}

class Probe extends StatefulWidget {
  const Probe({super.key, required this.seen, this.child});

  final Seen seen;
  final Widget? child;

  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  @override
  Widget build(BuildContext context) {
    widget.seen
      ..media = MediaQuery.of(context)
      ..data = DuoMediaQuery.of(context)
      ..emulation = FoldDivision.emulationOf(context)
      ..device = FoldDivision.emulatedDeviceOf(context)
      ..division = FoldDivision.divisionOf(context)
      ..keepClear = FoldDivision.keepClearRectOf(context)
      ..margins = FoldDivision.marginsOf(context);
    return widget.child ?? const SizedBox.expand();
  }
}

/// The widget types between the probe and the root.
List<Type> ancestorTypes(WidgetTester tester) {
  final List<Type> types = <Type>[];
  tester.element(find.byType(Probe)).visitAncestorElements((Element element) {
    types.add(element.widget.runtimeType);
    return true;
  });
  return types;
}

const Key _shot = Key('shot');

/// Renders the subtree under the `_shot` boundary at one pixel per logical
/// pixel and reads the red, green, blue and alpha of the pixel at [point].
Future<List<int>> rgbaAt(WidgetTester tester, Offset point) async {
  final RenderRepaintBoundary boundary = tester.renderObject(find.byKey(_shot));
  late int width;
  final ByteData bytes = (await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage();
    width = image.width;
    final ByteData? data = await image.toByteData();
    image.dispose();
    return data;
  }))!;
  final int index = (point.dy.round() * width + point.dx.round()) * 4;
  return <int>[
    for (int channel = 0; channel < 4; channel++)
      bytes.getUint8(index + channel),
  ];
}

void main() {
  late FakeHingePlugin plugin;
  late FoldDivisionAndroid platform;
  late Seen seen;

  setUp(() {
    FoldDivision.config.value = const FoldDivisionConfig(enabled: true);
    plugin = FakeHingePlugin(angle: 95)..install();
    platform = FoldDivisionAndroid();
    seen = Seen();
  });

  tearDown(() async {
    await platform.debugReset();
    plugin.uninstall();
    FoldDivision.config.value = const FoldDivisionConfig();
  });

  Future<void> pumpScope(
    WidgetTester tester, {
    DisplayFeatureBridgeMode mode = DisplayFeatureBridgeMode.none,
    bool showOverlay = false,
    Widget? child,
  }) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FoldDivisionScope(
        platform: platform,
        bridgeMode: mode,
        showOverlay: showOverlay,
        child: MaterialApp(home: Probe(seen: seen, child: child)),
      ),
    );
    await settle(tester);
  }

  /// Unmounts the scope so the platform stream closes before the teardown.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  group('window of the emulated device', () {
    testWidgets('a fold down the window: the inner display, open like a book', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester);

      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerLandscape,
      );
      // The real window is 673.5 wide, so the 951 wide window is scaled down.
      expect(placement.scale, closeTo(673.5238 / 951, 1e-4));

      expect(seen.media.size, const Size(951, 669));
      expect(seen.media.padding, const EdgeInsets.only(right: 84));
      expect(seen.media.viewPadding, const EdgeInsets.only(right: 84));
      expect(seen.media.viewInsets, EdgeInsets.zero);
      expect(seen.media.systemGestureInsets, EdgeInsets.zero);
      expect(
        seen.media.devicePixelRatio,
        closeTo(kFoldPixelRatio * placement.scale, 1e-9),
      );
      // One emulated window in physical pixels is what it covers on screen.
      expect(
        seen.media.size.width * seen.media.devicePixelRatio,
        closeTo(kFoldPhysicalSize.width, 1e-6),
      );

      expect(seen.device, kDuo);
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.emulation!.matchesWindowSize, isTrue);
      expect(seen.emulation!.scale, placement.scale);
      expect(seen.emulation!.state, kDuo.innerLandscape);

      // The division is on the fold of the device. The real hinge is at
      // x 336.8.
      expect(seen.division!.bounds, const Rect.fromLTRB(455.5, 0, 495.5, 669));
      expect(seen.division!.isActive, isTrue);
      expect(seen.keepClear, const Rect.fromLTRB(443.5, 0, 507.5, 669));
      expect(seen.margins, const EdgeInsets.symmetric(horizontal: 12));
      expect(seen.data.regions, hasLength(1));
      expect(seen.data.status, HingeStatus.partiallyOpen);
      expect(seen.data.angleDegrees, 95);
      expect(seen.data.horizontalSizeClass, SizeClass.regular);

      // The subtree is laid out at the emulated size and shown inside the
      // real safe area, centred.
      final RenderBox box = tester.renderObject(find.byType(Probe));
      expect(box.size, const Size(951, 669));
      final Rect onScreen = tester.getRect(find.byType(Probe));
      expect(onScreen.left, closeTo(placement.rect.left, 1e-6));
      expect(onScreen.top, closeTo(placement.rect.top, 1e-6));
      expect(onScreen.width, closeTo(placement.rect.width, 1e-6));
      expect(onScreen.height, closeTo(placement.rect.height, 1e-6));
      expect(onScreen.top, greaterThan(kStatusBar));
      expect(
        onScreen.bottom,
        lessThan(realSize.height - kNavigationBar),
      );
      expect(
        onScreen.center.dy,
        closeTo(
          kStatusBar + (realSize.height - kStatusBar - kNavigationBar) / 2,
          1e-6,
        ),
      );

      await unmount(tester);
    });

    testWidgets('a fold across the window: the inner display in tabletop', (
      WidgetTester tester,
    ) async {
      showInnerDisplayRotated(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester);

      expect(seen.emulation!.kind, EmulatedWindowKind.innerPortrait);
      expect(seen.media.size, const Size(669, 951));
      expect(seen.media.padding, const EdgeInsets.only(top: 84, bottom: 95));
      expect(
        seen.media.viewPadding,
        const EdgeInsets.only(top: 84, bottom: 95),
      );
      expect(seen.division!.bounds, const Rect.fromLTRB(0, 455.5, 669, 495.5));
      // The margins are turned for a division that lies flat.
      expect(seen.margins, const EdgeInsets.symmetric(vertical: 12));
      expect(seen.keepClear, const Rect.fromLTRB(0, 443.5, 669, 507.5));

      // The real window is the wider one here, so the height is what fits.
      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerPortrait,
      );
      final Rect onScreen = tester.getRect(find.byType(Probe));
      expect(onScreen.top, closeTo(kStatusBar, 1e-6));
      expect(
        onScreen.bottom,
        closeTo(realSize.height - kNavigationBar, 1e-6),
      );
      expect(onScreen.center.dx, closeTo(realSize.width / 2, 1e-6));
      expect(onScreen.width, closeTo(669 * placement.scale, 1e-6));

      await unmount(tester);
    });

    testWidgets('no fold, upright: the outer display in portrait', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      showBars();
      await pumpScope(tester);

      expect(seen.emulation!.kind, EmulatedWindowKind.outerPortrait);
      expect(seen.media.size, const Size(466, 678));
      expect(
        seen.media.padding,
        const EdgeInsets.only(right: 84, bottom: 34),
      );
      expect(
        seen.media.viewPadding,
        const EdgeInsets.only(right: 84, bottom: 34),
      );
      expect(seen.division, isNull);
      expect(seen.keepClear, isNull);
      // The clock and Wi-Fi strip of the outer display.
      expect(seen.data.regions, const <ReservedRegion>[
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: Rect.fromLTWH(385, 0, 84, 120),
          isActive: true,
        ),
      ]);
      expect(seen.data.horizontalSizeClass, SizeClass.compact);
      expect(seen.media.displayFeatures, isEmpty);

      final RenderBox box = tester.renderObject(find.byType(Probe));
      expect(box.size, const Size(466, 678));

      await unmount(tester);
    });

    testWidgets('no fold, on its side: the outer display in landscape', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      testView.physicalSize = kCoverPhysicalSize.flipped;
      await pumpScope(tester);

      expect(seen.emulation!.kind, EmulatedWindowKind.outerLandscape);
      expect(seen.media.size, const Size(678, 466));
      expect(seen.media.padding, const EdgeInsets.only(right: 84));
      expect(seen.data.regions, isEmpty);

      await unmount(tester);
    });

    testWidgets('unfolding switches from the outer to the inner display', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      await pumpScope(tester);
      expect(seen.media.size, const Size(466, 678));

      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await tester.pumpAndSettle();
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.media.size, const Size(951, 669));
      expect(seen.division!.bounds.center.dx, 475.5);

      await unmount(tester);
    });

    testWidgets('a custom profile replaces the built-in numbers', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      final EmulatedDevice custom = kDuo.copyWith(
        name: 'custom',
        innerLandscape: const EmulatedDeviceState(
          windowSize: Size(1000, 700),
          safeArea: EdgeInsets.only(left: 10, right: 90),
          foldAxis: Axis.vertical,
          foldCentre: 500,
        ),
      );
      FoldDivision.config.value = FoldDivisionConfig(
        enabled: true,
        device: custom,
        divisionExtent: 30,
      );
      await pumpScope(tester);

      expect(seen.device, custom);
      expect(seen.media.size, const Size(1000, 700));
      expect(seen.media.padding, const EdgeInsets.only(left: 10, right: 90));
      expect(seen.division!.bounds, const Rect.fromLTRB(485, 0, 515, 700));

      await unmount(tester);
    });
  });

  group('engine list that disagrees with the hinge sensor', () {
    testWidgets('a hinge at 90 with the fold listed as flat is partly open', (
      WidgetTester tester,
    ) async {
      // What a foldable emulator reports at 90 degrees.
      plugin.angle = 90;
      testView
        ..devicePixelRatio = kFoldPixelRatio
        ..physicalSize = kFoldPhysicalSize
        ..displayFeatures = const <DisplayFeature>[
          DisplayFeature(
            bounds: Rect.fromLTRB(336.8, 0, 337.1, 841.1),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ];
      await pumpScope(tester, mode: DisplayFeatureBridgeMode.full);

      expect(seen.data.status, HingeStatus.partiallyOpen);
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.division!.isActive, isTrue);
      expect(seen.keepClear, const Rect.fromLTRB(443.5, 0, 507.5, 669));
      expect(seen.media.displayFeatures.single.bounds.center.dx, 475.5);

      await unmount(tester);
    });

    testWidgets('a flat hinge with an empty list keeps the inner display', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await pumpScope(tester);
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);

      // What a foldable emulator reports at 180 degrees: no fold at all.
      testView.displayFeatures = const <DisplayFeature>[];
      await plugin.sendAngle(180.0);
      await tester.pumpAndSettle();

      // The window is taller than wide. The axis seen before decides.
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.media.size, const Size(951, 669));
      expect(seen.data.status, HingeStatus.fullyOpen);
      expect(seen.division!.bounds, const Rect.fromLTRB(455.5, 0, 495.5, 669));
      expect(seen.division!.isActive, isFalse);

      await unmount(tester);
    });

    testWidgets('an open hinge with no fold ever listed follows the aspect', (
      WidgetTester tester,
    ) async {
      plugin.angle = 180;
      testView
        ..devicePixelRatio = kFoldPixelRatio
        ..physicalSize = kFoldPhysicalSize
        ..displayFeatures = const <DisplayFeature>[];
      await pumpScope(tester);
      expect(seen.emulation!.kind, EmulatedWindowKind.innerPortrait);
      expect(seen.media.size, const Size(669, 951));

      testView.physicalSize = kFoldPhysicalSize.flipped;
      await tester.pumpAndSettle();
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.media.size, const Size(951, 669));

      await unmount(tester);
    });

    testWidgets('a shut hinge with a stale fold listed is the outer display', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await pumpScope(tester);
      expect(seen.media.size, const Size(951, 669));

      await plugin.sendAngle(10.0);
      await tester.pumpAndSettle();

      expect(seen.emulation!.kind, EmulatedWindowKind.outerPortrait);
      expect(seen.media.size, const Size(466, 678));
      expect(seen.data.status, HingeStatus.closed);
      expect(seen.division, isNull);

      await unmount(tester);
    });

    testWidgets('DivisionActivation.always holds with an empty list', (
      WidgetTester tester,
    ) async {
      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        activation: DivisionActivation.always,
      );
      plugin.angle = 180;
      testView
        ..devicePixelRatio = kFoldPixelRatio
        ..physicalSize = kFoldPhysicalSize.flipped
        ..displayFeatures = const <DisplayFeature>[];
      await pumpScope(tester);

      expect(seen.division!.isActive, isTrue);
      expect(seen.keepClear, const Rect.fromLTRB(443.5, 0, 507.5, 669));

      await unmount(tester);
    });
  });

  group('MediaQuery under the emulated window', () {
    testWidgets('display features hold the emulated fold only', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(
        DisplayFeatureState.postureHalfOpened,
        withCutout: true,
      );

      // Bridge mode none: nothing, as on iPhone Duo. The engine's fold and
      // cutout are gone.
      await pumpScope(tester);
      expect(seen.media.displayFeatures, isEmpty);
      expect(seen.data.displayFeatures, isEmpty);

      await pumpScope(tester, mode: DisplayFeatureBridgeMode.full);
      expect(seen.media.displayFeatures, const <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTRB(455.5, 0, 495.5, 669),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ]);
      expect(seen.data.displayFeatures, seen.media.displayFeatures);

      // Laid flat: the fold leaves the list and the division goes inactive.
      showInnerDisplay(DisplayFeatureState.postureFlat, withCutout: true);
      await settle(tester);
      expect(seen.media.displayFeatures, isEmpty);
      expect(seen.division!.isActive, isFalse);
      expect(seen.keepClear, isNull);

      await unmount(tester);
    });

    testWidgets('DivisionActivation.always keeps the division on a flat hinge',
        (WidgetTester tester) async {
      showInnerDisplay(DisplayFeatureState.postureFlat);
      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        activation: DivisionActivation.always,
      );
      await pumpScope(tester, mode: DisplayFeatureBridgeMode.full);

      expect(seen.division!.isActive, isTrue);
      expect(seen.data.status, HingeStatus.partiallyOpen);
      expect(seen.keepClear, const Rect.fromLTRB(443.5, 0, 507.5, 669));
      expect(seen.media.displayFeatures.single.bounds.center.dx, 475.5);

      await unmount(tester);
    });

    testWidgets('the keyboard inset is converted and the padding follows', (
      WidgetTester tester,
    ) async {
      showInnerDisplayRotated(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester);

      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerPortrait,
      );
      // The emulated window ends where the navigation bar starts.
      expect(
        placement.rect.bottom,
        closeTo(realSize.height - kNavigationBar, 1e-6),
      );

      // A keyboard 30 tall covers the navigation bar and 14 real pixels of
      // the emulated window.
      testView.viewInsets = const FakeViewPadding(
        bottom: 30 * kFoldPixelRatio,
      );
      await tester.pump();
      final double shallow = (30 - kNavigationBar) / placement.scale;
      expect(seen.media.viewInsets.bottom, closeTo(shallow, 1e-6));
      expect(seen.media.viewInsets.top, 0);
      expect(seen.media.viewPadding.bottom, 95);
      expect(seen.media.padding.bottom, closeTo(95 - shallow, 1e-6));
      expect(seen.media.padding.top, 84);

      // A keyboard 200 tall covers more than the bottom safe area.
      testView.viewInsets = const FakeViewPadding(
        bottom: 200 * kFoldPixelRatio,
      );
      await tester.pump();
      expect(
        seen.media.viewInsets.bottom,
        closeTo((200 - kNavigationBar) / placement.scale, 1e-6),
      );
      expect(seen.media.padding.bottom, 0);
      expect(seen.media.viewPadding.bottom, 95);
      // The window does not move or resize under the keyboard.
      expect(seen.media.size, const Size(669, 951));

      await unmount(tester);
    });

    testWidgets('a keyboard that stays below the window gives no inset', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester);

      // The inner landscape window is letterboxed: it ends well above the
      // bottom of the real one.
      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerLandscape,
      );
      expect(realSize.height - placement.rect.bottom, greaterThan(100));
      testView.viewInsets = const FakeViewPadding(
        bottom: 100 * kFoldPixelRatio,
      );
      await tester.pump();
      expect(seen.media.viewInsets, EdgeInsets.zero);

      await unmount(tester);
    });

    testWidgets('the text scale stays as the user set it', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScope(tester);

      expect(seen.media.size, const Size(951, 669));
      expect(seen.media.textScaler.scale(10), 15);

      await unmount(tester);
    });
  });

  group('hit testing and coordinates', () {
    const Key target = Key('target');

    Widget tappable(VoidCallback onTap) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 100, top: 50),
            child: GestureDetector(
              key: target,
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        );

    testWidgets('a tap reaches the widget through the scale', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      int taps = 0;
      await pumpScope(tester, child: tappable(() => taps++));

      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerLandscape,
      );
      Offset onScreen(Offset emulated) =>
          placement.rect.topLeft + emulated * placement.scale;

      // The middle of the target, which covers (100, 50) to (200, 110) of
      // the emulated window.
      await tester.tapAt(onScreen(const Offset(150, 80)));
      expect(taps, 1);
      // Just inside two of its corners.
      await tester.tapAt(onScreen(const Offset(101, 51)));
      await tester.tapAt(onScreen(const Offset(199, 109)));
      expect(taps, 3);
      // Just outside it.
      await tester.tapAt(onScreen(const Offset(97, 80)));
      await tester.tapAt(onScreen(const Offset(150, 113)));
      expect(taps, 3);
      // Where the target would be with no scale and no offset.
      await tester.tapAt(const Offset(190, 100));
      expect(taps, 3);
      // The finder goes through the same transform.
      await tester.tap(find.byKey(target));
      expect(taps, 4);

      await unmount(tester);
    });

    testWidgets('the backdrop beside the window takes no tap for the app', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      int taps = 0;
      await pumpScope(
        tester,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        ),
      );

      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerLandscape,
      );
      await tester.tapAt(placement.rect.center);
      expect(taps, 1);
      // Above and below the letterboxed window.
      await tester.tapAt(Offset(300, placement.rect.top - 20));
      await tester.tapAt(Offset(300, placement.rect.bottom + 20));
      expect(taps, 1);

      await unmount(tester);
    });

    testWidgets('windowRectOf answers in the coordinates of the division', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester, child: tappable(() {}));

      final BuildContext context = tester.element(find.byKey(target));
      final Rect inWindow = FoldDivision.windowRectOf(context)!;
      expect(inWindow.left, closeTo(100, 1e-6));
      expect(inWindow.top, closeTo(50, 1e-6));
      expect(inWindow.width, closeTo(100, 1e-6));
      expect(inWindow.height, closeTo(60, 1e-6));
      // The global rect is in the real window: scaled and offset.
      expect(tester.getRect(find.byKey(target)).width, lessThan(80));

      // With no emulated window the two agree.
      FoldDivision.disable();
      await settle(tester);
      expect(
        FoldDivision.windowRectOf(context),
        tester.getRect(find.byKey(target)),
      );

      await unmount(tester);
    });
  });

  group('one tree shape', () {
    testWidgets('switches, a fold and an unfold keep the State below', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await pumpScope(tester, showOverlay: true);

      final State<Probe> state = tester.state(find.byType(Probe));
      final List<Type> shape = ancestorTypes(tester);
      expect(seen.media.size, const Size(951, 669));

      Future<void> check(String step, {required bool emulated}) async {
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(Probe)), same(state), reason: step);
        expect(ancestorTypes(tester), shape, reason: step);
        expect(seen.device, emulated ? kDuo : isNull, reason: step);
      }

      const FoldDivisionConfig on = FoldDivisionConfig(enabled: true);

      FoldDivision.config.value = on.copyWith(matchWindowSize: false);
      await check('window size no longer matched', emulated: true);
      expect(seen.media.size, realSize);

      FoldDivision.config.value = on.copyWith(clearDevice: true);
      await check('no device', emulated: false);

      FoldDivision.disable();
      await check('division mode off', emulated: false);
      expect(seen.media.size, realSize);

      FoldDivision.config.value = on;
      await check('back on', emulated: true);
      expect(seen.media.size, const Size(951, 669));

      showCoverDisplay();
      await check('folded shut', emulated: true);
      expect(seen.media.size, const Size(466, 678));

      showInnerDisplayRotated(DisplayFeatureState.postureHalfOpened);
      await check('unfolded on its side', emulated: true);
      expect(seen.media.size, const Size(669, 951));

      showInnerDisplay(DisplayFeatureState.postureFlat);
      await check('laid flat', emulated: true);
      expect(seen.media.size, const Size(951, 669));

      await unmount(tester);
    });
  });

  group('buffer of the emulated window', () {
    Iterable<ClipRectLayer> bufferedClips(WidgetTester tester) =>
        tester.layers.whereType<ClipRectLayer>().where(
              (ClipRectLayer layer) =>
                  layer.clipBehavior == Clip.antiAliasWithSaveLayer,
            );

    testWidgets('the window is composited into a layer with its own bounds', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      // A backdrop filter flush with the top of the window, as a blurred
      // top bar is.
      await pumpScope(
        tester,
        child: Align(
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox(width: double.infinity, height: 56),
            ),
          ),
        ),
      );

      // The save layer is what keeps the blur from sampling the black
      // around the window: a filter inside reads that buffer only.
      final EmulatedSpaceLayer space =
          tester.layers.whereType<EmulatedSpaceLayer>().single;
      final ClipRectLayer buffer = bufferedClips(tester).single;
      expect(buffer.parent, same(space));
      expect(buffer.clipRect, const Rect.fromLTWH(0, 0, 951, 669));
      final BackdropFilterLayer filter =
          tester.layers.whereType<BackdropFilterLayer>().single;
      bool inside = false;
      for (Layer? layer = filter; layer != null; layer = layer.parent) {
        if (identical(layer, buffer)) inside = true;
      }
      expect(inside, isTrue);

      // Not emulating: no buffer and no transform layer are left behind.
      FoldDivision.disable();
      await settle(tester);
      expect(bufferedClips(tester), isEmpty);
      expect(tester.layers.whereType<EmulatedSpaceLayer>(), isEmpty);
      expect(tester.layers.whereType<BackdropFilterLayer>(), hasLength(1));

      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        matchWindowSize: false,
      );
      await settle(tester);
      expect(bufferedClips(tester), isEmpty);
      expect(tester.layers.whereType<EmulatedSpaceLayer>(), isEmpty);

      await unmount(tester);
    });
  });

  group('matchWindowSize off', () {
    testWidgets('keeps the real window and takes the emulated safe area', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        matchWindowSize: false,
      );
      await pumpScope(tester);

      expect(seen.device, kDuo);
      expect(seen.emulation!.kind, EmulatedWindowKind.innerLandscape);
      expect(seen.emulation!.matchesWindowSize, isFalse);
      expect(seen.emulation!.scale, 1);
      expect(seen.emulation!.windowSize, realSize);

      expect(seen.media.size, realSize);
      expect(seen.media.devicePixelRatio, kFoldPixelRatio);
      // The larger of the real bars and the emulated safe area on each side.
      const EdgeInsets merged = EdgeInsets.fromLTRB(
        0,
        kStatusBar,
        84,
        kNavigationBar,
      );
      expect(seen.media.viewPadding, merged);
      expect(seen.media.padding, merged);
      expect(seen.emulation!.safeArea, merged);

      // The division is on the real hinge.
      expect(seen.division!.bounds.width, 40);
      expect(seen.division!.bounds.center.dx, closeTo(kFoldCentre, 1e-9));
      expect(seen.division!.bounds.height, closeTo(realSize.height, 1e-9));
      expect(seen.media.displayFeatures, isEmpty);

      final RenderBox box = tester.renderObject(find.byType(Probe));
      expect(box.size.width, closeTo(realSize.width, 1e-6));
      expect(tester.getTopLeft(find.byType(Probe)), Offset.zero);

      await unmount(tester);
    });

    testWidgets('the outer display adds its bottom inset to the real bars', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      showBars();
      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        matchWindowSize: false,
      );
      await pumpScope(tester);

      expect(
        seen.media.viewPadding,
        const EdgeInsets.fromLTRB(0, kStatusBar, 84, 34),
      );
      // The occlusion of the profile belongs to the emulated window, which
      // is not on screen.
      expect(seen.data.regions, isEmpty);

      await unmount(tester);
    });
  });

  group('no emulation', () {
    testWidgets('division mode off leaves the window as Android reports it', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      FoldDivision.disable();
      await pumpScope(tester);

      expect(seen.device, isNull);
      expect(seen.emulation, isNull);
      expect(seen.media.size, realSize);
      expect(seen.media.devicePixelRatio, kFoldPixelRatio);
      expect(
        seen.media.viewPadding,
        const EdgeInsets.only(top: kStatusBar, bottom: kNavigationBar),
      );
      expect(seen.media.displayFeatures.single.bounds, kFoldBounds);
      expect(seen.division!.bounds.width, 0);
      expect(tester.getTopLeft(find.byType(Probe)), Offset.zero);

      await unmount(tester);
    });

    testWidgets('a phone with no hinge is not emulated', (
      WidgetTester tester,
    ) async {
      plugin
        ..hasHingeSensor = false
        ..angle = null;
      showCoverDisplay();
      testView.displayFeatures = const <DisplayFeature>[kEngineCutout];
      await pumpScope(tester);

      expect(seen.device, isNull);
      expect(seen.media.size, realSize);
      expect(seen.media.padding, EdgeInsets.zero);
      expect(seen.media.displayFeatures.single.type, DisplayFeatureType.cutout);

      await unmount(tester);
    });

    testWidgets('a subtree driven by debugData is not emulated', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await tester.pumpWidget(
        FoldDivisionScope(
          debugData: Stream<FoldableData>.value(await platform.getSnapshot()),
          showOverlay: false,
          child: MaterialApp(home: Probe(seen: seen)),
        ),
      );
      await settle(tester);

      expect(seen.device, isNull);
      expect(seen.media.size, realSize);

      await unmount(tester);
    });
  });

  group('overlay under the emulated window', () {
    RenderFoldDivisionOverlay renderOverlay(WidgetTester tester) =>
        tester.renderObject<RenderFoldDivisionOverlay>(
          find.byType(FoldDivisionOverlay),
        );

    testWidgets('the band is on the fold of the device', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      await pumpScope(tester, showOverlay: true);

      const FoldDivisionOverlayBand band = FoldDivisionOverlayBand(
        division: Rect.fromLTRB(455.5, 0, 495.5, 669),
        keepClear: Rect.fromLTRB(443.5, 0, 507.5, 669),
        inForce: true,
      );
      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.bands, const <FoldDivisionOverlayBand>[band]);
      // The overlay fills the emulated window, so its own coordinates are
      // the window's.
      expect(render.debugLocalBands(), const <FoldDivisionOverlayBand>[band]);
      expect(render.occlusions, isEmpty);
      // The inner landscape safe area has one inset, on the right.
      expect(render.safeAreaEdges, const <Rect>[
        Rect.fromLTRB(867, 0, 867, 669),
      ]);

      await unmount(tester);
    });

    testWidgets('the outer display shows its occlusion and safe area edges', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      await pumpScope(tester, showOverlay: true);

      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.bands, isEmpty);
      expect(render.occlusions, const <Rect>[Rect.fromLTWH(385, 0, 84, 120)]);
      expect(render.safeAreaEdges, const <Rect>[
        Rect.fromLTRB(382, 0, 382, 678),
        Rect.fromLTRB(0, 644, 466, 644),
      ]);
      expect(
        render,
        paints
          // The subtree paints rects of its own first.
          ..something(
            (Symbol method, List<dynamic> arguments) =>
                method == #drawRect &&
                arguments[0] == const Rect.fromLTWH(385, 0, 84, 120),
          )
          ..line(p1: const Offset(382, 0), p2: const Offset(382, 678))
          ..line(p1: const Offset(0, 644), p2: const Offset(466, 644)),
      );

      await unmount(tester);
    });

    testWidgets('a hidden overlay draws none of it', (
      WidgetTester tester,
    ) async {
      showCoverDisplay();
      await pumpScope(tester);

      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.occlusions, isEmpty);
      expect(render.safeAreaEdges, isEmpty);

      await unmount(tester);
    });

    testWidgets('with the real window kept it draws the merged safe area', (
      WidgetTester tester,
    ) async {
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      FoldDivision.config.value = const FoldDivisionConfig(
        enabled: true,
        matchWindowSize: false,
      );
      await pumpScope(tester, showOverlay: true);

      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.occlusions, isEmpty);
      expect(render.safeAreaEdges.single.left, realSize.width - 84);
      expect(
          render.bands.single.division.center.dx, closeTo(kFoldCentre, 1e-9));

      await unmount(tester);
    });

    testWidgets('the pixels of the band land on the emulated fold on screen', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      showBars();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _shot,
          child: FoldDivisionScope(
            platform: platform,
            showOverlay: true,
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      await settle(tester);

      final EmulatedWindowPlacement placement = placementOf(
        kDuo.innerLandscape,
      );
      Offset onScreen(Offset emulated) =>
          placement.rect.topLeft + emulated * placement.scale;

      // On the division: the red band over the black backdrop.
      final List<int> onFold = await rgbaAt(
        tester,
        onScreen(const Offset(475.5, 300)),
      );
      expect(onFold[0], greaterThan(60));
      expect(onFold[3], 255);
      // Clear of the keep-clear band: black.
      expect(
        await rgbaAt(tester, onScreen(const Offset(300, 300))),
        <int>[0, 0, 0, 255],
      );
      // On the real hinge, which the emulated fold does not follow in y: the
      // letterbox above the window is black.
      expect(
        await rgbaAt(tester, Offset(kFoldCentre, placement.rect.top - 30)),
        <int>[0, 0, 0, 255],
      );

      await unmount(tester);
    });
  });
}
