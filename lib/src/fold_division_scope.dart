import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import 'division_emulator.dart';
import 'emulated_device.dart';
import 'emulated_window.dart';
import 'fold_division_android.dart';
import 'fold_division_api.dart';
import 'fold_division_config.dart';
import 'fold_division_overlay.dart';

/// A `FoldableProvider` with division mode wired in.
///
/// Place it where you would place `FoldableProvider`:
///
/// ```dart
/// FoldDivisionScope(
///   child: MaterialApp(home: HomePage()),
/// )
/// ```
///
/// The scope:
///
/// - Wraps [child] in the base `FoldableProvider`, passing [bridgeMode],
///   [platform] and [debugData] through.
/// - Rebuilds `FoldDivision.configOf`, `marginsOf` and `keepClearRectOf`
///   callers when `FoldDivision.config` changes.
/// - Paints a [FoldDivisionOverlay] when [showOverlay] is true.
/// - Makes `MediaQuery.displayFeatures` match what the same [bridgeMode]
///   gives on iPhone Duo (see [emulateDisplayFeatures]).
/// - Renders [child] as the device in `FoldDivisionConfig.device`.
///
/// ## Device emulation
///
/// On an Android foldable, with division mode on and a device set, the
/// subtree is rendered as that device. `selectEmulatedWindow` picks the
/// window of the device from the real window and its fold.
///
/// With `FoldDivisionConfig.matchWindowSize` on:
///
/// - [child] is laid out at the window size of the device, scaled by one
///   factor to fit the real window less its system bars, and centred over
///   black. Hit testing goes through the scale.
/// - `MediaQuery` describes the emulated window: its `size`, the safe area
///   of the device as `padding` and `viewPadding`, a `devicePixelRatio`
///   multiplied by the scale so that physical pixels stay true, the keyboard
///   inset converted to emulated coordinates, and no system gesture insets.
///   The text scale is left as the user set it.
/// - `MediaQuery.displayFeatures` holds what [bridgeMode] asks for, built
///   from the emulated regions. The real fold and cutouts are never in it.
/// - `DuoMediaQuery`, the `FoldDivision` helpers and the overlay work in the
///   coordinates of the emulated window. The division sits on the fold of
///   the device and the occlusions of the device are `occlusion` regions.
///
/// With `matchWindowSize` off the window keeps its real size. The safe area
/// is the larger of the real one and the one of the device on each side, and
/// the division sits on the real hinge.
///
/// The scope has to fill the Flutter view for the emulated window to line
/// up with it. Code that reads the view directly (`View.of`,
/// `RenderBox.localToGlobal`, pointer positions in global coordinates) sees
/// the real window. `FoldDivision.windowRectOf` gives the bounds of a widget
/// in the coordinates `MediaQuery` describes.
///
/// A phone with no hinge is never emulated, and neither is a subtree driven
/// by [debugData]. The wrappers the scope inserts are the same in every
/// case, so turning emulation on or off, folding and unfolding keep the
/// state of [child].
class FoldDivisionScope extends StatelessWidget {
  /// Creates a scope.
  const FoldDivisionScope({
    super.key,
    required this.child,
    this.bridgeMode = DisplayFeatureBridgeMode.none,
    this.platform,
    this.debugData,
    this.showOverlay = kDebugMode,
    this.emulateDisplayFeatures = true,
  });

  /// The subtree that can read fold state.
  final Widget child;

  /// Whether fold geometry is also published to `MediaQuery.displayFeatures`.
  /// Same meaning as `FoldableProvider.bridgeMode`.
  final DisplayFeatureBridgeMode bridgeMode;

  /// Overrides the platform implementation, for tests.
  final FoldablePlatform? platform;

  /// Drives the provider from a stream instead of the platform.
  final Stream<FoldableData>? debugData;

  /// Whether the debug overlay is painted. Defaults to [kDebugMode].
  final bool showOverlay;

  /// Whether `MediaQuery.displayFeatures` is rewritten on Android while
  /// division mode is on.
  ///
  /// The Android engine fills `MediaQuery.displayFeatures` with the real
  /// fold. iOS fills nothing, and the base provider adds what [bridgeMode]
  /// asks for. With this flag on, the scope replaces the engine's list with
  /// what `DisplayFeatureBridge` builds from the emulated regions. The result
  /// is what an iPhone Duo app sees:
  ///
  /// - `none`: no display features, so dialogs and sheets are not split.
  /// - `cutoutsOnly`: the cutouts.
  /// - `full`: the cutouts, plus the division as a half opened fold while
  ///   the posture is `partiallyOpen`.
  ///
  /// The engine's list stays as it is in three cases: division mode is off,
  /// this flag is off, or the device is not a foldable. A plain Android
  /// phone keeps its camera cutout. The rewrite applies to data that came
  /// from [FoldDivisionAndroid] only.
  ///
  /// Engine features of the type `unknown` are kept in the rewritten list.
  ///
  /// While the scope matches the window size of a device the list always
  /// holds the emulated features, whatever this flag says: the engine's
  /// bounds are in the coordinates of the real window.
  final bool emulateDisplayFeatures;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FoldDivisionConfig>(
      valueListenable: FoldDivision.config,
      builder: (BuildContext context, FoldDivisionConfig config, _) {
        final bool android = debugData == null &&
            (platform ?? FoldablePlatform.instance) is FoldDivisionAndroid;
        return FoldDivisionConfigScope(
          config: config,
          child: FoldableProvider(
            // The Android engine publishes display features itself. The base
            // provider then ignores its bridge mode and logs a warning, so it
            // gets `none` there and the emulator below does the work.
            bridgeMode: android ? DisplayFeatureBridgeMode.none : bridgeMode,
            platform: platform,
            debugData: debugData,
            child: _DeviceEmulator(
              mode: bridgeMode,
              android: android,
              config: config,
              emulateDisplayFeatures: emulateDisplayFeatures,
              child: FoldDivisionOverlay(visible: showOverlay, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Gives the subtree the window of the emulated device.
///
/// It always builds the same chain: the window box, a `MediaQuery`, a
/// `DuoMediaQuery` and a [DeviceEmulationScope]. With nothing to emulate
/// each of them passes on what it got, so a config change, a fold or an
/// unfold never rebuilds the State below from scratch.
class _DeviceEmulator extends StatefulWidget {
  const _DeviceEmulator({
    required this.mode,
    required this.android,
    required this.config,
    required this.emulateDisplayFeatures,
    required this.child,
  });

  final DisplayFeatureBridgeMode mode;

  /// Whether the fold data comes from [FoldDivisionAndroid].
  final bool android;
  final FoldDivisionConfig config;
  final bool emulateDisplayFeatures;
  final Widget child;

  @override
  State<_DeviceEmulator> createState() => _DeviceEmulatorState();
}

class _DeviceEmulatorState extends State<_DeviceEmulator> {
  List<DisplayFeature> _features = const <DisplayFeature>[];

  /// MediaQuery compares its display feature list by identity. Hands back
  /// the old instance while the contents are the same.
  List<DisplayFeature> _stable(List<DisplayFeature> features) {
    if (!listEquals(features, _features)) _features = features;
    return _features;
  }

  @override
  Widget build(BuildContext context) {
    final FoldableData data = DuoMediaQuery.of(context);
    final MediaQueryData ambient = MediaQuery.of(context);
    final FoldDivisionConfig config = widget.config;

    // Only a foldable is touched. On a plain Android phone the window, its
    // safe area and the engine's display features (its camera cutout) stay
    // as they are.
    final bool emulating = widget.android &&
        config.enabled &&
        data.isFoldable &&
        data.capabilities.strategy == kFoldDivisionStrategy;

    final EmulatedDevice? device = emulating ? config.device : null;
    EmulatedWindowKind? kind;
    EmulatedDeviceState? state;
    EmulatedWindowPlacement? placement;
    if (device != null) {
      kind = selectEmulatedWindow(
        windowSize: ambient.size,
        logicalFeatures: ambient.displayFeatures,
      );
      state = device.stateFor(kind);
      if (config.matchWindowSize) {
        placement = placeEmulatedWindow(
          realSize: ambient.size,
          realPadding: ambient.viewPadding,
          emulatedSize: state.windowSize,
        );
      }
    }

    final MediaQueryData media;
    final FoldableData shown;
    DeviceEmulation? emulation;

    if (device != null && kind != null && state != null && placement != null) {
      // The whole window is emulated. Everything below is in its coordinates.
      final FoldableData emulated = emulateDeviceData(
        data: data,
        state: state,
        config: config,
      );
      final List<DisplayFeature> features = _stable(
        DisplayFeatureBridge.build(
          mode: widget.mode,
          regions: emulated.regions,
          status: emulated.status,
        ),
      );
      final EdgeInsets viewInsets = emulatedViewInsets(
        realInsets: ambient.viewInsets,
        realSize: ambient.size,
        placement: placement,
        emulatedSize: state.windowSize,
      );
      media = ambient.copyWith(
        size: state.windowSize,
        // The subtree is drawn `scale` times its logical size, so one of its
        // logical pixels covers that many more physical ones.
        devicePixelRatio: ambient.devicePixelRatio * placement.scale,
        viewPadding: state.safeArea,
        viewInsets: viewInsets,
        padding: _clear(state.safeArea, viewInsets),
        systemGestureInsets: EdgeInsets.zero,
        displayFeatures: features,
      );
      shown = emulated.copyWith(displayFeatures: features);
      emulation = DeviceEmulation(
        device: device,
        kind: kind,
        matchesWindowSize: true,
        windowSize: state.windowSize,
        safeArea: state.safeArea,
        scale: placement.scale,
      );
    } else {
      MediaQueryData real = ambient;
      FoldableData realData = data;
      if (emulating && widget.emulateDisplayFeatures) {
        final List<DisplayFeature> features = _stable(<DisplayFeature>[
          ...DisplayFeatureBridge.build(
            mode: widget.mode,
            regions: data.regions,
            status: data.status,
          ),
          // Features of a type this package does not know stay. iOS has
          // none, so keeping them costs no parity, and dropping them would
          // hide whatever a newer Android reports.
          for (final DisplayFeature feature in ambient.displayFeatures)
            if (feature.type == DisplayFeatureType.unknown) feature,
        ]);
        real = real.copyWith(displayFeatures: features);
        realData = data.copyWith(displayFeatures: features);
      }
      if (device != null && kind != null && state != null) {
        // The window keeps its size and takes the safe area of the device.
        // The real system bars still have to stay clear, so each side keeps
        // the larger of the two.
        final EdgeInsets viewPadding = mergeSafeArea(
          ambient.viewPadding,
          state.safeArea,
        );
        real = real.copyWith(
          viewPadding: viewPadding,
          padding: mergeSafeArea(
            ambient.padding,
            _clear(state.safeArea, ambient.viewInsets),
          ),
        );
        emulation = DeviceEmulation(
          device: device,
          kind: kind,
          matchesWindowSize: false,
          windowSize: ambient.size,
          safeArea: viewPadding,
        );
      }
      media = real;
      shown = realData;
    }

    return _EmulatedWindow(
      windowSize: emulation != null && emulation.matchesWindowSize
          ? emulation.windowSize
          : null,
      padding: ambient.viewPadding,
      child: MediaQuery(
        data: media,
        child: DuoMediaQuery(
          data: shown,
          child: DeviceEmulationScope(
            emulation: emulation,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  /// The part of [viewPadding] that [viewInsets] (the keyboard) leaves
  /// uncovered, which is how Flutter defines `MediaQuery.padding`.
  static EdgeInsets _clear(EdgeInsets viewPadding, EdgeInsets viewInsets) {
    return EdgeInsets.fromLTRB(
      math.max(0.0, viewPadding.left - viewInsets.left),
      math.max(0.0, viewPadding.top - viewInsets.top),
      math.max(0.0, viewPadding.right - viewInsets.right),
      math.max(0.0, viewPadding.bottom - viewInsets.bottom),
    );
  }
}

class _EmulatedWindow extends SingleChildRenderObjectWidget {
  const _EmulatedWindow({
    required this.windowSize,
    required this.padding,
    required super.child,
  });

  final Size? windowSize;
  final EdgeInsets padding;

  @override
  RenderEmulatedWindow createRenderObject(BuildContext context) =>
      RenderEmulatedWindow(windowSize: windowSize, padding: padding);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEmulatedWindow renderObject,
  ) {
    renderObject
      ..windowSize = windowSize
      ..padding = padding;
  }
}
