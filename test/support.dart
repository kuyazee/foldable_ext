import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

/// A Galaxy Z Fold inner display: 1768 x 2208 physical pixels at 2.625, which
/// is 673.5 x 841.1 logical pixels, with a zero-width fold down the middle.
const Size kFoldPhysicalSize = Size(1768, 2208);
const double kFoldPixelRatio = 2.625;

/// The fold centre line in logical pixels.
const double kFoldCentre = 884 / kFoldPixelRatio;

/// The fold as the engine reports it: bounds in logical pixels.
const Rect kFoldBounds = Rect.fromLTRB(
  kFoldCentre,
  0,
  kFoldCentre,
  2208 / kFoldPixelRatio,
);

/// The Fold cover display: 904 x 2316 physical pixels, no fold.
const Size kCoverPhysicalSize = Size(904, 2316);

DisplayFeature engineFold(DisplayFeatureState state) => DisplayFeature(
      bounds: kFoldBounds,
      type: DisplayFeatureType.fold,
      state: state,
    );

/// A camera cutout near the top right corner, in logical pixels.
const DisplayFeature kEngineCutout = DisplayFeature(
  bounds: Rect.fromLTWH(600, 8, 30, 30),
  type: DisplayFeatureType.cutout,
  state: DisplayFeatureState.unknown,
);

/// The test view every `FoldDivisionAndroid` reads by default.
TestFlutterView get testView =>
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;

/// Makes the test view an open Fold showing the inner display.
void showInnerDisplay(
  DisplayFeatureState state, {
  bool withCutout = false,
}) {
  testView
    ..devicePixelRatio = kFoldPixelRatio
    ..physicalSize = kFoldPhysicalSize
    ..displayFeatures = <DisplayFeature>[
      engineFold(state),
      if (withCutout) kEngineCutout,
    ];
}

/// Makes the test view a closed Fold showing the cover display.
void showCoverDisplay() {
  testView
    ..devicePixelRatio = kFoldPixelRatio
    ..physicalSize = kCoverPhysicalSize
    ..displayFeatures = const <DisplayFeature>[];
}

/// A stand-in for the Kotlin side of the plugin.
class FakeHingePlugin {
  FakeHingePlugin({this.hasHingeSensor = true, this.angle});

  bool hasHingeSensor;
  double? angle;
  int infoCalls = 0;
  int listenCalls = 0;
  int cancelCalls = 0;

  static const MethodChannel _methods = MethodChannel(
    kFoldDivisionMethodChannel,
  );
  static const MethodChannel _events = MethodChannel(
    kFoldDivisionHingeAngleChannel,
  );
  static const StandardMethodCodec _codec = StandardMethodCodec();

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(_methods, (MethodCall call) async {
      if (call.method != 'getHingeInfo') return null;
      infoCalls++;
      return <String, Object?>{
        'hasHingeSensor': hasHingeSensor,
        'angle': angle,
      };
    });
    _messenger.setMockMethodCallHandler(_events, (MethodCall call) async {
      if (call.method == 'listen') listenCalls++;
      if (call.method == 'cancel') cancelCalls++;
      return null;
    });
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockMethodCallHandler(_events, null);
  }

  /// Sends one hinge angle reading, as the sensor listener does.
  Future<void> sendAngle(Object value) {
    if (value is num) angle = value.toDouble();
    return _messenger.handlePlatformMessage(
      kFoldDivisionHingeAngleChannel,
      _codec.encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  /// Ends the angle stream, as the native side does with no sensor.
  Future<void> endAngles() => _messenger.handlePlatformMessage(
        kFoldDivisionHingeAngleChannel,
        null,
        (_) {},
      );
}
