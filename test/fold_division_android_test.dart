import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

import 'support.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHingePlugin plugin;
  late FoldDivisionAndroid platform;
  late FoldablePlatform previousPlatform;

  setUp(() {
    previousPlatform = FoldablePlatform.instance;
    FoldDivision.config.value = const FoldDivisionConfig(enabled: true);
    plugin = FakeHingePlugin(angle: 95)..install();
    platform = FoldDivisionAndroid();
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
  });

  tearDown(() async {
    await platform.debugReset();
    plugin.uninstall();
    testView.reset();
    FoldablePlatform.instance = previousPlatform;
    FoldDivision.config.value = const FoldDivisionConfig();
    debugDefaultTargetPlatformOverride = null;
  });

  group('registerWith', () {
    test('makes FoldDivisionAndroid the active platform', () {
      expect(FoldablePlatform.instance, isNot(isA<FoldDivisionAndroid>()));
      FoldDivisionAndroid.registerWith();
      expect(FoldablePlatform.instance, isA<FoldDivisionAndroid>());
      expect(FoldDivision.isEmulating, isTrue);
      FoldDivision.disable();
      expect(FoldDivision.isEmulating, isFalse);
    });

    test('the Foldable API answers from the Android fold', () async {
      FoldDivisionAndroid.registerWith();
      final FoldDivisionAndroid registered =
          FoldablePlatform.instance as FoldDivisionAndroid;
      addTearDown(registered.debugReset);

      expect(await Foldable.isFoldable, isTrue);
      expect(await Foldable.hingeStatus, HingeStatus.partiallyOpen);
      expect(
        (await Foldable.capabilities).strategy,
        'android-display-features',
      );
      final FoldableData snapshot = await Foldable.snapshot;
      expect(snapshot.angleDegrees, 95);
      expect(snapshot.activeDivisions.single.bounds.width, 40);

      final List<double> angles = <double>[];
      final List<HingeStatus> statuses = <HingeStatus>[];
      final StreamSubscription<double> angleSub =
          Foldable.hingeAngleStream.listen(angles.add);
      final StreamSubscription<HingeStatus> statusSub =
          Foldable.hingeStatusStream.listen(statuses.add);
      await settle();
      await plugin.sendAngle(120.5);
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await plugin.sendAngle(180);
      await settle();
      await angleSub.cancel();
      await statusSub.cancel();

      expect(angles, <double>[95, 120.5, 120.5, 180]);
      expect(statuses, <HingeStatus>[
        HingeStatus.partiallyOpen,
        HingeStatus.fullyOpen,
      ]);
    });
  });

  group('getSnapshot', () {
    test('reads the fold of the view in logical pixels', () async {
      final FoldableData data = await platform.getSnapshot();
      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, 95);

      final ReservedRegion division = data.regions.single;
      expect(division.kind, ReservedRegionKind.division);
      expect(division.isActive, isTrue);
      expect(division.bounds.left, closeTo(kFoldCentre - 20, 1e-9));
      expect(division.bounds.right, closeTo(kFoldCentre + 20, 1e-9));
      expect(division.bounds.top, 0);
      expect(division.bounds.bottom, closeTo(2208 / kFoldPixelRatio, 1e-9));
      expect(data.horizontalSizeClass, SizeClass.regular);
      expect(data.verticalSizeClass, SizeClass.regular);
      expect(data.displayFeatures, isEmpty);
    });

    test('division mode off reports the real hinge bounds', () async {
      FoldDivision.disable();
      final FoldableData data = await platform.getSnapshot();
      final ReservedRegion division = data.regions.single;
      expect(division.bounds.width, 0);
      expect(division.bounds.left, closeTo(kFoldCentre, 1e-9));
      expect(division.isActive, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
    });

    test('a cutout becomes an occlusion in logical pixels', () async {
      showInnerDisplay(DisplayFeatureState.postureFlat, withCutout: true);
      final FoldableData data = await platform.getSnapshot();
      final ReservedRegion occlusion = data.regions.last;
      expect(occlusion.kind, ReservedRegionKind.occlusion);
      expect(occlusion.bounds.left, closeTo(1600 / kFoldPixelRatio, 1e-9));
      expect(occlusion.bounds.width, closeTo(80 / kFoldPixelRatio, 1e-9));
    });

    test('the cover display of a device with a hinge is closed', () async {
      showCoverDisplay();
      plugin.angle = 0;
      final FoldableData data = await platform.getSnapshot();
      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.closed);
      expect(data.regions, isEmpty);
      expect(data.horizontalSizeClass, SizeClass.compact);
    });

    test('a whole number angle arriving as int is read', () async {
      plugin.uninstall();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        platform.methodChannel,
        (_) async => <String, Object?>{'hasHingeSensor': true, 'angle': 90},
      );
      final FoldableData data = await platform.getSnapshot();
      expect(data.angleDegrees, 90.0);
    });

    test('a missing plugin is tolerated: features still give the fold',
        () async {
      plugin.uninstall();
      final FoldableData data = await platform.getSnapshot();
      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, isNull);
      expect(data.capabilities.hingeApiPresent, isFalse);
    });

    test('a missing plugin and no fold is a device with no hinge', () async {
      plugin.uninstall();
      showCoverDisplay();
      final FoldableData data = await platform.getSnapshot();
      expect(data.isFoldable, isFalse);
      expect(
        data.capabilities.supportLevel,
        FoldableSupportLevel.availableNoHinge,
      );
      expect(data.status, HingeStatus.unknown);
      expect(data.horizontalSizeClass, SizeClass.compact);
    });

    test('a malformed reply does not throw', () async {
      plugin.uninstall();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        platform.methodChannel,
        (_) async => <String, Object?>{
          'hasHingeSensor': 'yes',
          'angle': 'wide',
        },
      );
      final FoldableData data = await platform.getSnapshot();
      expect(data.angleDegrees, isNull);
      expect(data.capabilities.hingeApiPresent, isFalse);
    });

    test('off Android everything is unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await platform.getSnapshot(), FoldableData.unsupported);
      final List<FoldableData> events = await platform.events.toList();
      expect(events, isEmpty);
      expect(plugin.infoCalls, 0);
      expect(await platform.debugDumpNativeApi(),
          containsPair('error', 'not Android'));
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('events', () {
    test('is a broadcast stream', () {
      expect(platform.events.isBroadcast, isTrue);
    });

    test('replays the current state to the first listener', () async {
      final FoldableData first = await platform.events.first;
      expect(first, await platform.getSnapshot());
      expect(first.isPartiallyOpen, isTrue);
    });

    test('emits one whole snapshot per hinge angle change', () async {
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
      );
      await settle();
      expect(plugin.listenCalls, 1);

      await plugin.sendAngle(110.0);
      await plugin.sendAngle(110.0);
      await plugin.sendAngle(120);
      await settle();
      await sub.cancel();

      expect(
        seen.map((FoldableData d) => d.angleDegrees),
        <double>[95, 110, 120],
      );
      expect(seen.every((FoldableData d) => d.regions.length == 1), isTrue);
      expect(plugin.cancelCalls, 1);
    });

    test('emits when the view metrics change', () async {
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
      );
      await settle();

      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle();
      await plugin.sendAngle(0);
      showCoverDisplay();
      await settle();
      await sub.cancel();

      // The test view takes its size and its features in separate steps, so
      // a state can repeat. A real engine sends them in one update.
      final List<HingeStatus> statuses = <HingeStatus>[];
      for (final FoldableData data in seen) {
        if (statuses.isEmpty || statuses.last != data.status) {
          statuses.add(data.status);
        }
      }
      expect(statuses, <HingeStatus>[
        HingeStatus.partiallyOpen,
        HingeStatus.fullyOpen,
        HingeStatus.closed,
      ]);
      expect(seen[1].regions.single.isActive, isFalse);
      expect(seen.last.regions, isEmpty);
      expect(seen.last.horizontalSizeClass, SizeClass.compact);
    });

    test('emits when the config changes', () async {
      showInnerDisplay(DisplayFeatureState.postureFlat);
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
      );
      await settle();

      FoldDivision.config.value = FoldDivision.config.value.copyWith(
        activation: DivisionActivation.always,
      );
      FoldDivision.disable();
      // Margins are not part of the snapshot, so this sends nothing.
      FoldDivision.config.value = FoldDivision.config.value.copyWith(
        margins: EdgeInsets.zero,
      );
      await settle();
      await sub.cancel();

      expect(seen, hasLength(3));
      expect(seen[0].status, HingeStatus.fullyOpen);
      expect(seen[0].regions.single.bounds.width, 40);
      expect(seen[1].status, HingeStatus.partiallyOpen);
      expect(seen[1].regions.single.isActive, isTrue);
      expect(seen[2].status, HingeStatus.fullyOpen);
      expect(seen[2].regions.single.bounds.width, 0);
    });

    test('stays open on an Android phone with no hinge', () async {
      plugin.hasHingeSensor = false;
      showCoverDisplay();
      bool done = false;
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
        onDone: () => done = true,
      );
      await settle();
      await settle();

      expect(done, isFalse);
      expect(seen.single.isFoldable, isFalse);
      expect(
        seen.single.capabilities.supportLevel,
        FoldableSupportLevel.availableNoHinge,
      );
      expect(seen.single.horizontalSizeClass, SizeClass.compact);
      expect(plugin.listenCalls, 0);
      await sub.cancel();
    });

    test('off Android a later listener asks again', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await platform.events.toList(), isEmpty);

      debugDefaultTargetPlatformOverride = null;
      final FoldableData first = await platform.events.first;
      expect(first.status, HingeStatus.partiallyOpen);
    });

    test('keeps running on display features with no hinge sensor', () async {
      plugin.hasHingeSensor = false;
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
      );
      await settle();
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle();
      await sub.cancel();

      expect(plugin.listenCalls, 0);
      expect(seen.map((FoldableData d) => d.status), <HingeStatus>[
        HingeStatus.partiallyOpen,
        HingeStatus.fullyOpen,
      ]);
    });

    test('an angle stream that ends leaves the events open', () async {
      bool done = false;
      final List<FoldableData> seen = <FoldableData>[];
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        seen.add,
        onDone: () => done = true,
      );
      await settle();
      await plugin.endAngles();
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle();
      await sub.cancel();

      expect(done, isFalse);
      expect(seen.last.status, HingeStatus.fullyOpen);
    });

    test('stops listening to its sources when the last listener leaves',
        () async {
      final StreamSubscription<FoldableData> sub = platform.events.listen(
        (_) {},
      );
      await settle();
      await sub.cancel();
      // ignore: invalid_use_of_protected_member
      expect(FoldDivision.config.hasListeners, isFalse);
      expect(plugin.cancelCalls, 1);
    });

    test('listen, cancel and listen in one turn replays once', () async {
      final List<FoldableData> got = <FoldableData>[];
      final StreamSubscription<FoldableData> a = platform.events.listen((_) {});
      await a.cancel();
      final StreamSubscription<FoldableData> b =
          platform.events.listen(got.add);
      await settle();
      await settle();
      await b.cancel();
      expect(got, hasLength(1));
    });

    test('a later getSnapshot retries a getHingeInfo call that failed',
        () async {
      // The first call throws, as in a hot restart race. Later ones answer.
      plugin.uninstall();
      final List<FoldableData> got = <FoldableData>[];
      final StreamSubscription<FoldableData> sub =
          platform.events.listen(got.add);
      await settle();
      await settle();
      expect(got.single.angleDegrees, isNull);

      plugin.install();
      // A one-off read, as FoldableProvider does on resume.
      final FoldableData snap = await platform.getSnapshot();
      await settle();
      await plugin.sendAngle(120);
      await settle();
      final int listens = plugin.listenCalls;
      await sub.cancel();

      expect(snap.capabilities.hingeApiPresent, isTrue);
      expect(listens, 1, reason: 'angle channel never listened to');
      expect(got.last.angleDegrees, 120);
    });

    test('a change of the window retries a getHingeInfo call that failed',
        () async {
      plugin.uninstall();
      final List<FoldableData> got = <FoldableData>[];
      final StreamSubscription<FoldableData> sub =
          platform.events.listen(got.add);
      await settle();
      await settle();

      plugin.install();
      showInnerDisplay(DisplayFeatureState.postureFlat);
      await settle();
      await settle();
      await plugin.sendAngle(170);
      await settle();
      final int listens = plugin.listenCalls;
      await sub.cancel();

      expect(listens, 1);
      expect(got.last.angleDegrees, 170);
      expect(got.last.capabilities.hingeApiPresent, isTrue);
    });
  });

  test('debugDumpNativeApi describes the sources', () async {
    final Map<String, Object?> dump = await platform.debugDumpNativeApi();
    expect(dump['strategy'], 'android-display-features');
    expect(dump['hasHingeSensor'], isTrue);
    expect(dump['angle'], 95);
    expect(dump['devicePixelRatio'], kFoldPixelRatio);
    expect(dump['displayFeatures'], hasLength(1));
  });
}
