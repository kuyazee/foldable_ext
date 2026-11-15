import 'dart:async';
import 'dart:ui' show DisplayFeature, FlutterView, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import 'division_emulator.dart';
import 'fold_division_api.dart';
import 'fold_division_config.dart';

/// The method channel of the Android plugin.
///
/// `getHingeInfo` answers `{ "hasHingeSensor": bool, "angle": double? }`. The
/// angle is in degrees, 0 closed and 180 flat. It is the last reading, or
/// null before the first one.
const String kFoldDivisionMethodChannel = 'com.kuyazee.foldable_ext/methods';

/// The event channel of the Android plugin.
///
/// It sends the hinge angle in degrees on each change. On a device with no
/// hinge sensor it ends the stream at once.
const String kFoldDivisionHingeAngleChannel =
    'com.kuyazee.foldable_ext/hinge_angle';

/// The `FoldablePlatform` for Android.
///
/// Flutter registers it on Android through `dartPluginClass`, so
/// `Foldable.*`, `FoldableProvider`, `DuoMediaQuery` and `FoldAwareBuilder`
/// read an Android foldable with no extra code. On iOS nobody registers it
/// and the base plugin keeps reporting the real iPhone Duo fold.
///
/// It reads three sources and merges them with `emulateDivision`:
///
/// - `FlutterView.displayFeatures` of the implicit view (or the first view),
///   for the fold bounds, the posture and the cutouts.
/// - The native hinge sensor, over [methodChannel] and [eventChannel].
/// - `FoldDivision.config`.
///
/// Behaviour:
///
/// - [getSnapshot] never throws and is the place to detect support.
/// - [events] is a broadcast stream. It replays the current state to its
///   first listener, then sends one whole snapshot per change.
/// - Off Android every answer is `FoldableData.unsupported` and [events]
///   completes without emitting.
/// - On Android [events] stays open on a device with no hinge, where the
///   base package completes the stream. A window with no fold looks the same
///   on a plain phone as on a foldable showing its cover screen or a window
///   beside the fold, so closing would lose every later posture change. A
///   plain phone gets one snapshot with `isFoldable: false`, and
///   `Foldable.hingeAngleStream` never emits or completes there. Use
///   `Foldable.isFoldable` to detect a hinge.
/// - With no native plugin the display features still give the fold and its
///   posture, and the angle stays null. `getHingeInfo` is called again on
///   each later snapshot and each change of the window until it answers.
class FoldDivisionAndroid extends FoldablePlatform with WidgetsBindingObserver {
  /// Creates the platform. [config] and [viewProvider] are for tests.
  FoldDivisionAndroid({
    ValueListenable<FoldDivisionConfig>? config,
    FlutterView? Function()? viewProvider,
  })  : _config = config,
        _viewProvider = viewProvider;

  /// Makes this class the active `FoldablePlatform`.
  ///
  /// Flutter calls it at startup on Android. Call it yourself only in tests.
  static void registerWith() {
    FoldablePlatform.instance = FoldDivisionAndroid();
  }

  /// The method channel used for `getHingeInfo`.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    kFoldDivisionMethodChannel,
  );

  /// The event channel carrying hinge angle readings.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    kFoldDivisionHingeAngleChannel,
  );

  final ValueListenable<FoldDivisionConfig>? _config;
  final FlutterView? Function()? _viewProvider;

  ValueListenable<FoldDivisionConfig> get _configListenable =>
      _config ?? FoldDivision.config;

  bool _hasHingeSensor = false;
  double? _angle;

  /// Whether the native side has answered `getHingeInfo`. Until it has, the
  /// absence of a sensor is not a fact and the call is tried again.
  bool _sensorAnswered = false;
  bool _readingSensor = false;

  /// Counts listen and cancel calls, so a start that was overtaken by a
  /// cancel does nothing when its snapshot arrives.
  int _generation = 0;

  StreamController<FoldableData>? _controller;
  StreamSubscription<dynamic>? _angleSubscription;
  FoldableData? _lastEmitted;
  bool _observing = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<FoldableData> getSnapshot() async {
    try {
      if (!_isAndroid) return FoldableData.unsupported;
      // While the angle stream runs it is the freshest source.
      if (_angleSubscription == null) {
        await _readHingeInfo();
        _syncAngleSubscription();
      }
      final FoldableData snapshot = _compute();
      // Listeners see what a one-off read learned, such as a sensor that
      // answered for the first time.
      if (_observing) _emit();
      return snapshot;
    } catch (_) {
      return FoldableData.unsupported;
    }
  }

  @override
  Stream<FoldableData> get events {
    StreamController<FoldableData>? controller = _controller;
    // Only a stream opened off Android closes. It is replaced, so a later
    // listener asks again.
    if (controller == null || controller.isClosed) {
      controller = _createController();
      _controller = controller;
    }
    return controller.stream;
  }

  @override
  Future<Map<String, Object?>> debugDumpNativeApi() async {
    try {
      if (!_isAndroid) {
        return const <String, Object?>{'error': 'not Android'};
      }
      await _readHingeInfo();
      final FlutterView? view = _view();
      return <String, Object?>{
        'strategy': kFoldDivisionStrategy,
        'hasHingeSensor': _hasHingeSensor,
        'angle': _angle,
        'devicePixelRatio': view?.devicePixelRatio,
        'physicalSize': view?.physicalSize.toString(),
        'displayFeatures': <String>[
          for (final DisplayFeature feature
              in view?.displayFeatures ?? const <DisplayFeature>[])
            feature.toString(),
        ],
        'config': _configListenable.value.toString(),
      };
    } catch (error) {
      return <String, Object?>{'error': error.toString()};
    }
  }

  /// Drops cached state so a test can start clean.
  @visibleForTesting
  Future<void> debugReset() async {
    await _stopSources();
    final StreamController<FoldableData>? controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
    _generation++;
    _hasHingeSensor = false;
    _sensorAnswered = false;
    _angle = null;
    _lastEmitted = null;
  }

  @override
  void didChangeMetrics() {
    _emit();
    if (!_sensorAnswered) unawaited(_retrySensor());
  }

  StreamController<FoldableData> _createController() {
    late final StreamController<FoldableData> controller;

    Future<void> start(int generation) async {
      if (!_isAndroid) {
        // Settled: no other platform has this plugin.
        await controller.close();
        return;
      }
      final FoldableData snapshot = await getSnapshot();
      if (controller.isClosed || generation != _generation) return;

      // A window with no fold can still belong to a foldable, so the stream
      // stays open whatever the first snapshot says.
      _lastEmitted = snapshot;
      controller.add(snapshot);
      _startSources();
    }

    controller = StreamController<FoldableData>.broadcast(
      onListen: () {
        unawaited(start(++_generation));
      },
      onCancel: () async {
        _generation++;
        await _stopSources();
      },
    );
    return controller;
  }

  void _startSources() {
    if (!_observing) {
      _observing = true;
      WidgetsFlutterBinding.ensureInitialized().addObserver(this);
      _configListenable.addListener(_emit);
    }
    _syncAngleSubscription();
  }

  /// Starts the angle subscription once there are listeners and the plugin
  /// has reported a sensor.
  ///
  /// Only a plugin that answered `hasHingeSensor: true` gets a listener.
  /// EventChannel reports a missing plugin through FlutterError, never
  /// through the stream, so listening blind would log an error on every
  /// device without the native side.
  void _syncAngleSubscription() {
    if (!_observing || !_hasHingeSensor || _angleSubscription != null) return;
    _angleSubscription = eventChannel.receiveBroadcastStream().listen(
      (Object? event) {
        if (event is! num) return;
        final double angle = event.toDouble();
        if (angle.isNaN || angle == _angle) return;
        _angle = angle;
        _emit();
      },
      onError: (Object error, StackTrace stack) {
        // A native hiccup must not end the stream for every listener.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'foldable_ext',
            context: ErrorDescription('while receiving hinge angles'),
          ),
        );
      },
      onDone: () {
        _angleSubscription = null;
      },
    );
  }

  /// Asks the plugin again after a call that failed.
  Future<void> _retrySensor() async {
    if (_readingSensor || !_observing) return;
    _readingSensor = true;
    try {
      await _readHingeInfo();
    } finally {
      _readingSensor = false;
    }
    if (!_observing) return;
    _syncAngleSubscription();
    _emit();
  }

  Future<void> _stopSources() async {
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
      _configListenable.removeListener(_emit);
    }
    final StreamSubscription<dynamic>? subscription = _angleSubscription;
    _angleSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // The native side may already be gone.
    }
  }

  void _emit() {
    final StreamController<FoldableData>? controller = _controller;
    if (controller == null || controller.isClosed) return;
    final FoldableData next;
    try {
      next = _compute();
    } catch (_) {
      return;
    }
    if (next == _lastEmitted) return;
    _lastEmitted = next;
    controller.add(next);
  }

  Future<void> _readHingeInfo() async {
    try {
      final Map<Object?, Object?>? raw =
          await methodChannel.invokeMapMethod<Object?, Object?>('getHingeInfo');
      _sensorAnswered = raw != null;
      _hasHingeSensor = raw?['hasHingeSensor'] == true;
      final Object? angle = raw?['angle'];
      // Whole numbers arrive as int over the standard codec.
      final double? reading =
          _hasHingeSensor && angle is num && !angle.toDouble().isNaN
              ? angle.toDouble()
              : null;
      // The native side holds no reading until its sensor listener runs. A
      // null answer must not wipe an angle the stream already delivered.
      if (reading != null || !_hasHingeSensor) _angle = reading;
    } catch (_) {
      // No native side yet (a test, or a hot restart race). The next refresh
      // asks again and what is already known stays.
      _sensorAnswered = false;
    }
  }

  FlutterView? _view() {
    final FlutterView? Function()? provider = _viewProvider;
    if (provider != null) return provider();
    final PlatformDispatcher dispatcher =
        WidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    final FlutterView? implicit = dispatcher.implicitView;
    if (implicit != null) return implicit;
    return dispatcher.views.isEmpty ? null : dispatcher.views.first;
  }

  FoldableData _compute() {
    final FlutterView? view = _view();
    final FoldDivisionConfig config = _configListenable.value;
    if (view == null) {
      return emulateDivision(
        logicalFeatures: const <DisplayFeature>[],
        viewSize: Size.zero,
        hingeAngle: _angle,
        hasHingeSensor: _hasHingeSensor,
        config: config,
      );
    }
    final double ratio = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1;
    return emulateDivision(
      logicalFeatures: logicalDisplayFeatures(view.displayFeatures, ratio),
      viewSize: view.physicalSize / ratio,
      hingeAngle: _angle,
      hasHingeSensor: _hasHingeSensor,
      config: config,
    );
  }
}
