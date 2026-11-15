import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

import 'support.dart';

const double kViewHeight = 2208 / kFoldPixelRatio;

/// Lets the provider's snapshot and stream replay land.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

FoldableData emulated({
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
  FoldDivisionConfig config = const FoldDivisionConfig(enabled: true),
  Size size = const Size(673, 841),
}) =>
    emulateDivision(
      logicalFeatures: <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTWH(size.width / 2, 0, 0, size.height),
          type: DisplayFeatureType.fold,
          state: state,
        ),
        const DisplayFeature(
          bounds: Rect.fromLTWH(600, 10, 30, 30),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ],
      viewSize: size,
      hingeAngle: state == DisplayFeatureState.postureFlat ? 180 : 95,
      hasHingeSensor: true,
      config: config,
    );

/// A fold down the middle of a 673 x 841 view.
FoldableData bookFold() => emulateDivision(
      logicalFeatures: const <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTRB(336.5, 0, 336.5, 841),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      viewSize: const Size(673, 841),
      hingeAngle: 90,
      hasHingeSensor: true,
      config: const FoldDivisionConfig(enabled: true),
    );

/// A fold lying across a 673 x 841 view. Its division runs from y 280 to 320.
FoldableData tabletopFold() => emulateDivision(
      logicalFeatures: const <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTRB(0, 300, 673, 300),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      viewSize: const Size(673, 841),
      hingeAngle: 90,
      hasHingeSensor: true,
      config: const FoldDivisionConfig(enabled: true),
    );

const Key _shot = Key('shot');

/// Renders the subtree under the `_shot` boundary and reads the alpha of the
/// pixel at [point]. The overlay is the only thing these tests paint, so a
/// non-zero alpha means a band covers the point.
Future<int> alphaAt(WidgetTester tester, Offset point) async {
  final RenderRepaintBoundary boundary = tester.renderObject(find.byKey(_shot));
  final ByteData bytes = (await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? data = await image.toByteData();
    image.dispose();
    return data;
  }))!;
  final int width = boundary.size.width.round();
  final int index = (point.dy.round() * width + point.dx.round()) * 4;
  return bytes.getUint8(index + 3);
}

void main() {
  late FakeHingePlugin plugin;
  late FoldDivisionAndroid platform;

  setUp(() {
    FoldDivision.config.value = const FoldDivisionConfig(enabled: true);
    plugin = FakeHingePlugin(angle: 95)..install();
    platform = FoldDivisionAndroid();
  });

  tearDown(() async {
    await platform.debugReset();
    plugin.uninstall();
    FoldDivision.config.value = const FoldDivisionConfig();
  });

  group('base widgets on FoldDivisionAndroid', () {
    testWidgets('FoldableProvider feeds DuoMediaQuery from the Android fold', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      late FoldableData data;
      late HingeStatus status;
      late double? angle;
      late SizeClass width;
      late bool foldable;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            platform: platform,
            child: Builder(
              builder: (BuildContext context) {
                data = DuoMediaQuery.of(context);
                status = DuoMediaQuery.statusOf(context);
                angle = DuoMediaQuery.angleOf(context);
                width = DuoMediaQuery.horizontalSizeClassOf(context);
                foldable = DuoMediaQuery.isFoldableOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await settle(tester);

      expect(foldable, isTrue);
      expect(status, HingeStatus.partiallyOpen);
      expect(angle, 95);
      expect(width, SizeClass.regular);
      expect(data.activeDivisions.single.bounds.width, 40);

      // The hinge moves.
      await plugin.sendAngle(130.0);
      await settle(tester);
      expect(angle, 130);

      // The device is laid flat.
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle(tester);
      expect(status, HingeStatus.fullyOpen);
      expect(data.activeDivisions, isEmpty);
      expect(data.regions.single.bounds.width, 40);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('FoldAwareBuilder gets the division, on and off', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      late FoldInfo seen;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            platform: platform,
            child: FoldAwareBuilder(
              builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
                seen = fold;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await settle(tester);

      expect(seen.isFoldable, isTrue);
      expect(seen.isPartiallyOpen, isTrue);
      expect(seen.isRegularWidth, isTrue);
      expect(seen.spansDivision, isTrue);
      expect(seen.divisionRect!.width, 40);
      expect(seen.divisionRect!.center.dx, closeTo(kFoldCentre, 1e-9));
      expect(seen.divisionRect!.height, closeTo(kViewHeight, 1e-9));

      // Division mode off: the real fold, a line with no width.
      FoldDivision.disable();
      await settle(tester);
      expect(seen.isPartiallyOpen, isTrue);
      expect(seen.divisionRect!.width, 0);
      expect(seen.divisionRect!.left, closeTo(kFoldCentre, 1e-9));
      expect(seen.spansDivision, isFalse);

      // Back on, laid flat: no division rect, as on iPhone Duo.
      FoldDivision.enable();
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle(tester);
      expect(seen.isFullyOpen, isTrue);
      expect(seen.divisionRects, isEmpty);

      // Always active: the division shows on the flat device.
      FoldDivision.config.value = FoldDivision.config.value.copyWith(
        activation: DivisionActivation.always,
      );
      await settle(tester);
      expect(seen.isPartiallyOpen, isTrue);
      expect(seen.divisionRect!.width, 40);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a device with no hinge leaves the base widgets at rest', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      plugin.hasHingeSensor = false;
      showCoverDisplay();

      late FoldInfo seen;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            platform: platform,
            child: FoldAwareBuilder(
              builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
                seen = fold;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await settle(tester);

      expect(seen.isFoldable, isFalse);
      expect(seen.status, HingeStatus.unknown);
      expect(seen.divisionRects, isEmpty);
      expect(seen.horizontalSizeClass, SizeClass.compact);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a foldable with no hinge sensor that starts on the cover display '
        'reports later posture changes', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      plugin
        ..hasHingeSensor = false
        ..angle = null;
      showCoverDisplay();

      late FoldableData seen;
      await tester.pumpWidget(
        FoldableProvider(
          platform: platform,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (BuildContext context) {
                seen = DuoMediaQuery.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen.isFoldable, isFalse);

      // Unfolding changes the window size, so the provider reads a snapshot.
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(seen.isFoldable, isTrue);
      expect(seen.status, HingeStatus.partiallyOpen);

      // Laying flat changes the display feature only, so the event stream
      // has to carry it.
      testView.displayFeatures = <DisplayFeature>[
        engineFold(DisplayFeatureState.postureFlat),
      ];
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(seen.status, HingeStatus.fullyOpen);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('DisplayFeatureBridge on emulated regions', () {
    test('full mode publishes the 40 wide division while partially open', () {
      final FoldableData data = emulated();
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: data.regions,
        status: data.status,
      );
      expect(features, hasLength(2));
      expect(features.first.type, DisplayFeatureType.cutout);
      expect(features.last.type, DisplayFeatureType.fold);
      expect(features.last.state, DisplayFeatureState.postureHalfOpened);
      expect(features.last.bounds, const Rect.fromLTRB(316.5, 0, 356.5, 841));
    });

    test('a flat device publishes no fold', () {
      final FoldableData data = emulated(
        state: DisplayFeatureState.postureFlat,
      );
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: data.regions,
        status: data.status,
      );
      expect(features.single.type, DisplayFeatureType.cutout);
    });

    test('division mode off never publishes the zero-width fold', () {
      final FoldableData data = emulated(
        config: const FoldDivisionConfig(enabled: false),
      );
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: data.regions,
        status: data.status,
      );
      expect(features.single.type, DisplayFeatureType.cutout);
    });

    testWidgets('FoldableProvider bridges emulated data fed as debugData', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late List<DisplayFeature> media;
      late FoldableData data;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            bridgeMode: DisplayFeatureBridgeMode.full,
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                media = MediaQuery.of(context).displayFeatures;
                data = DuoMediaQuery.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      feed.add(emulated());
      await settle(tester);

      expect(media, hasLength(2));
      expect(media.last.bounds.width, 40);
      expect(data.displayFeatures, media);
    });
  });

  group('FoldDivisionScope', () {
    Future<void> pumpScope(
      WidgetTester tester, {
      required DisplayFeatureBridgeMode mode,
      required void Function(BuildContext context) probe,
      bool emulateDisplayFeatures = true,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: FoldDivisionScope(
              platform: platform,
              bridgeMode: mode,
              emulateDisplayFeatures: emulateDisplayFeatures,
              child: Builder(
                builder: (BuildContext context) {
                  probe(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );

    testWidgets('mirrors what iPhone Duo puts in MediaQuery, per bridge mode', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(
        DisplayFeatureState.postureHalfOpened,
        withCutout: true,
      );

      late List<DisplayFeature> media;
      late FoldableData data;
      void probe(BuildContext context) {
        media = MediaQuery.of(context).displayFeatures;
        data = DuoMediaQuery.of(context);
      }

      await pumpScope(tester,
          mode: DisplayFeatureBridgeMode.none, probe: probe);
      await settle(tester);
      expect(media, isEmpty);
      expect(data.displayFeatures, isEmpty);
      expect(data.activeDivisions.single.bounds.width, 40);

      await pumpScope(
        tester,
        mode: DisplayFeatureBridgeMode.cutoutsOnly,
        probe: probe,
      );
      await settle(tester);
      expect(media.single.type, DisplayFeatureType.cutout);

      await pumpScope(tester,
          mode: DisplayFeatureBridgeMode.full, probe: probe);
      await settle(tester);
      expect(media, hasLength(2));
      expect(media.last.type, DisplayFeatureType.fold);
      expect(media.last.state, DisplayFeatureState.postureHalfOpened);
      expect(media.last.bounds.width, 40);
      expect(media.last.bounds.center.dx, closeTo(kFoldCentre, 1e-9));
      expect(data.displayFeatures, media);

      // Laid flat: the fold leaves MediaQuery, the cutout stays.
      showInnerDisplay(DisplayFeatureState.postureFlat, withCutout: true);
      await settle(tester);
      expect(media.single.type, DisplayFeatureType.cutout);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaves the engine display features alone with the mode off', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);
      FoldDivision.disable();

      late List<DisplayFeature> media;
      late FoldableData data;
      await pumpScope(
        tester,
        mode: DisplayFeatureBridgeMode.full,
        probe: (BuildContext context) {
          media = MediaQuery.of(context).displayFeatures;
          data = DuoMediaQuery.of(context);
        },
      );
      await settle(tester);

      // The engine's own fold, in logical pixels, with no width.
      expect(media.single.type, DisplayFeatureType.fold);
      expect(media.single.bounds.width, 0);
      expect(data.regions.single.bounds.width, 0);
      expect(data.status, HingeStatus.partiallyOpen);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('emulateDisplayFeatures: false keeps the engine list', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      late List<DisplayFeature> media;
      await pumpScope(
        tester,
        mode: DisplayFeatureBridgeMode.none,
        emulateDisplayFeatures: false,
        probe: (BuildContext context) {
          media = MediaQuery.of(context).displayFeatures;
        },
      );
      await settle(tester);
      expect(media.single.bounds.width, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('turning the mode on and off keeps the State below', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldDivisionScope(
            platform: platform,
            bridgeMode: DisplayFeatureBridgeMode.full,
            child: const _Counter(),
          ),
        ),
      );
      await settle(tester);
      final State<_Counter> before = tester.state(find.byType(_Counter));

      FoldDivision.disable();
      await settle(tester);
      FoldDivision.enable();
      await settle(tester);

      expect(tester.state(find.byType(_Counter)), same(before));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('marginsOf and keepClearRectOf follow the config', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      late EdgeInsets margins;
      late Rect? keepClear;
      late Rect? keepClearAny;
      late ReservedRegion? division;
      await pumpScope(
        tester,
        mode: DisplayFeatureBridgeMode.none,
        probe: (BuildContext context) {
          margins = FoldDivision.marginsOf(context);
          keepClear = FoldDivision.keepClearRectOf(context);
          keepClearAny = FoldDivision.keepClearRectOf(
            context,
            includeInactive: true,
          );
          division = FoldDivision.divisionOf(context);
        },
      );
      await settle(tester);

      expect(margins, const EdgeInsets.symmetric(horizontal: 12));
      expect(division!.bounds.width, 40);
      expect(keepClear!.width, 64);
      expect(keepClear!.center.dx, closeTo(kFoldCentre, 1e-9));
      expect(keepClear!.height, closeTo(kViewHeight, 1e-9));

      // A config change alone rebuilds the readers.
      FoldDivision.config.value = FoldDivision.config.value.copyWith(
        margins: const EdgeInsets.symmetric(horizontal: 20),
      );
      await settle(tester);
      expect(margins, const EdgeInsets.symmetric(horizontal: 20));
      expect(keepClear!.width, 80);

      // Laid flat: nothing in force, the inactive rect is still on offer.
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle(tester);
      expect(keepClear, isNull);
      expect(keepClearAny!.width, 80);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('readers work with no scope and no provider', (
      WidgetTester tester,
    ) async {
      late EdgeInsets margins;
      late Rect? keepClear;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            margins = FoldDivision.marginsOf(context);
            keepClear = FoldDivision.keepClearRectOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(margins, EdgeInsets.zero);
      expect(keepClear, isNull);
    });

    testWidgets('passes debugData through to the base provider', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late List<DisplayFeature> media;
      late FoldableData data;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldDivisionScope(
            bridgeMode: DisplayFeatureBridgeMode.full,
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                media = MediaQuery.of(context).displayFeatures;
                data = DuoMediaQuery.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      feed.add(emulated());
      await settle(tester);

      expect(data.isPartiallyOpen, isTrue);
      expect(media, hasLength(2));
      expect(media.last.bounds.width, 40);
    });

    testWidgets('keeps the engine cutout on a phone with no hinge', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      plugin
        ..hasHingeSensor = false
        ..angle = null;
      testView
        ..devicePixelRatio = 2
        ..physicalSize = const Size(800, 1600)
        ..displayFeatures = const <DisplayFeature>[kEngineCutout];
      final FoldablePlatform previous = FoldablePlatform.instance;
      FoldablePlatform.instance = platform;
      addTearDown(() => FoldablePlatform.instance = previous);

      late List<DisplayFeature> features;
      await tester.pumpWidget(
        FoldDivisionScope(
          showOverlay: false,
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext c) {
                features = MediaQuery.displayFeaturesOf(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(features, hasLength(1));
      expect(features.single.type, DisplayFeatureType.cutout);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('keeps engine display features of an unknown type', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      testView
        ..devicePixelRatio = kFoldPixelRatio
        ..physicalSize = kFoldPhysicalSize
        ..displayFeatures = <DisplayFeature>[
          engineFold(DisplayFeatureState.postureHalfOpened),
          const DisplayFeature(
            bounds: Rect.fromLTWH(0, 0, 100, 100),
            type: DisplayFeatureType.unknown,
            state: DisplayFeatureState.unknown,
          ),
        ];

      late List<DisplayFeature> features;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldDivisionScope(
            platform: platform,
            showOverlay: false,
            child: Builder(
              builder: (BuildContext c) {
                features = MediaQuery.displayFeaturesOf(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Bridge mode none removes the fold, as on iPhone Duo. The unknown
      // feature stays.
      expect(features.single.type, DisplayFeatureType.unknown);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('FoldDivisionOverlay', () {
    RenderFoldDivisionOverlay renderOverlay(WidgetTester tester) =>
        tester.renderObject<RenderFoldDivisionOverlay>(
          find.byWidgetPredicate(
            (Widget w) => w.runtimeType.toString() == '_OverlayRenderWidget',
          ),
        );

    Widget host(FoldableData data, {required Widget child}) => Directionality(
          textDirection: TextDirection.ltr,
          child: DuoMediaQuery(data: data, child: child),
        );

    testWidgets('paints the division and its margin band', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(673, 841);

      await tester.pumpWidget(
        host(
          emulated(),
          child: const FoldDivisionOverlay(child: SizedBox.expand()),
        ),
      );

      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.debugLocalBands(), const <FoldDivisionOverlayBand>[
        FoldDivisionOverlayBand(
          division: Rect.fromLTRB(316.5, 0, 356.5, 841),
          keepClear: Rect.fromLTRB(304.5, 0, 368.5, 841),
          inForce: true,
        ),
      ]);
      expect(
        render,
        paints
          ..rect(
            rect: const Rect.fromLTRB(304.5, 0, 368.5, 841),
            color: const Color(0x33F5A524),
          )
          ..rect(
            rect: const Rect.fromLTRB(316.5, 0, 356.5, 841),
            color: const Color(0x66E5484D),
          ),
      );
    });

    testWidgets('maps view coordinates into an inset subtree', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(673, 841);

      await tester.pumpWidget(
        host(
          emulated(),
          child: const Padding(
            padding: EdgeInsets.only(left: 100, top: 50),
            child: FoldDivisionOverlay(child: SizedBox.expand()),
          ),
        ),
      );

      expect(
        renderOverlay(tester).debugLocalBands().single.division,
        const Rect.fromLTRB(216.5, 0, 256.5, 791),
      );
    });

    testWidgets('paints nothing when hidden, flat or without a fold', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          emulated(),
          child: const FoldDivisionOverlay(
            visible: false,
            child: SizedBox.expand(),
          ),
        ),
      );
      expect(renderOverlay(tester).bands, isEmpty);
      expect(renderOverlay(tester), paintsNothing);

      await tester.pumpWidget(
        host(
          emulated(state: DisplayFeatureState.postureFlat),
          child: const FoldDivisionOverlay(child: SizedBox.expand()),
        ),
      );
      expect(renderOverlay(tester).bands, isEmpty);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FoldDivisionOverlay(child: SizedBox.expand()),
        ),
      );
      expect(renderOverlay(tester).bands, isEmpty);
    });

    testWidgets('showInactive outlines a division on a flat device', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          emulated(state: DisplayFeatureState.postureFlat),
          child: const FoldDivisionOverlay(
            showInactive: true,
            child: SizedBox.expand(),
          ),
        ),
      );
      final RenderFoldDivisionOverlay render = renderOverlay(tester);
      expect(render.bands.single.inForce, isFalse);
      expect(render, paints..rect(style: PaintingStyle.stroke));
    });

    testWidgets('never intercepts pointers', (WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(673, 841);

      int taps = 0;
      await tester.pumpWidget(
        host(
          emulated(),
          child: FoldDivisionOverlay(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // In the division, in the margin band, and clear of both.
      await tester.tapAt(const Offset(336, 400));
      await tester.tapAt(const Offset(310, 400));
      await tester.tapAt(const Offset(50, 400));
      expect(taps, 3);
    });

    testWidgets('the scope shows the overlay when asked', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      showInnerDisplay(DisplayFeatureState.postureHalfOpened);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldDivisionScope(
            platform: platform,
            showOverlay: true,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await settle(tester);
      expect(renderOverlay(tester).bands.single.keepClear.width, 64);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldDivisionScope(
            platform: platform,
            showOverlay: false,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await settle(tester);
      expect(renderOverlay(tester).bands, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('keeps the band on the fold when a list scrolls the overlay', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      testView
        ..devicePixelRatio = 1
        ..physicalSize = const Size(673, 841)
        ..displayFeatures = const <DisplayFeature>[];
      final ScrollController scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: _shot,
            child: DuoMediaQuery(
              data: tabletopFold(),
              child: ListView(
                controller: scroll,
                children: const <Widget>[
                  SizedBox(
                    height: 700,
                    child: FoldDivisionOverlay(
                      visible: true,
                      child: SizedBox.expand(),
                    ),
                  ),
                  SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      expect(await alphaAt(tester, const Offset(100, 300)), greaterThan(0));
      expect(await alphaAt(tester, const Offset(100, 200)), 0);

      // The list item moves up 100. The fold does not move.
      scroll.jumpTo(100);
      await tester.pump();
      expect(
        await alphaAt(tester, const Offset(100, 300)),
        greaterThan(0),
        reason: 'the band left the fold when the overlay scrolled',
      );
      expect(await alphaAt(tester, const Offset(100, 200)), 0);
      // Above the keep-clear band, which reaches 12 past the division.
      expect(await alphaAt(tester, const Offset(100, 260)), 0);
    });

    testWidgets('keeps the band on the fold under a scale', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      testView
        ..devicePixelRatio = 1
        ..physicalSize = const Size(673, 841)
        ..displayFeatures = const <DisplayFeature>[];

      // A book fold: the division stands from x 316.5 to 356.5.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: _shot,
            child: DuoMediaQuery(
              data: bookFold(),
              child: Transform.scale(
                scale: 0.75,
                alignment: Alignment.topLeft,
                child: const FoldDivisionOverlay(
                  visible: true,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(await alphaAt(tester, const Offset(336, 100)), greaterThan(0));
      // Where a shift of the origin alone would put it: 336.5 * 0.75.
      expect(await alphaAt(tester, const Offset(252, 100)), 0);
      // The overlay box ends at 841 * 0.75. Below it nothing is painted.
      expect(await alphaAt(tester, const Offset(336, 700)), 0);
    });

    testWidgets('adds no layer while hidden', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          bookFold(),
          child: const FoldDivisionOverlay(
            visible: false,
            child: SizedBox.expand(),
          ),
        ),
      );
      expect(renderOverlay(tester).needsCompositing, isFalse);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
