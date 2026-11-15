import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import 'division_emulator.dart';
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
            // gets `none` there and the mirror below does the work.
            bridgeMode: android ? DisplayFeatureBridgeMode.none : bridgeMode,
            platform: platform,
            debugData: debugData,
            child: _DisplayFeatureMirror(
              mode: bridgeMode,
              active: android && emulateDisplayFeatures && config.enabled,
              child: FoldDivisionOverlay(visible: showOverlay, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Replaces the engine's display features with the emulated ones.
///
/// The `MediaQuery` and `DuoMediaQuery` are always in the tree, active or
/// not, so turning division mode on and off keeps the State below.
class _DisplayFeatureMirror extends StatefulWidget {
  const _DisplayFeatureMirror({
    required this.mode,
    required this.active,
    required this.child,
  });

  final DisplayFeatureBridgeMode mode;
  final bool active;
  final Widget child;

  @override
  State<_DisplayFeatureMirror> createState() => _DisplayFeatureMirrorState();
}

class _DisplayFeatureMirrorState extends State<_DisplayFeatureMirror> {
  List<DisplayFeature> _features = const <DisplayFeature>[];

  @override
  Widget build(BuildContext context) {
    final FoldableData data = DuoMediaQuery.of(context);
    final MediaQueryData ambient = MediaQuery.of(context);
    // Only a foldable is mirrored. On a plain Android phone the engine's
    // list (its camera cutout) stays as it is.
    final bool mirror = widget.active &&
        data.isFoldable &&
        data.capabilities.strategy == kFoldDivisionStrategy;

    if (!mirror) {
      return MediaQuery(
        data: ambient,
        child: DuoMediaQuery(data: data, child: widget.child),
      );
    }

    final List<DisplayFeature> features = <DisplayFeature>[
      ...DisplayFeatureBridge.build(
        mode: widget.mode,
        regions: data.regions,
        status: data.status,
      ),
      // Features of a type this package does not know stay. iOS has none, so
      // keeping them costs no parity, and dropping them would hide whatever
      // a newer Android reports.
      for (final DisplayFeature feature in ambient.displayFeatures)
        if (feature.type == DisplayFeatureType.unknown) feature,
    ];
    // MediaQuery compares this list by identity. Keep the old instance while
    // the contents are the same.
    if (!listEquals(features, _features)) {
      _features = features;
    }

    return MediaQuery(
      data: ambient.copyWith(displayFeatures: _features),
      child: DuoMediaQuery(
        data: data.copyWith(displayFeatures: _features),
        child: widget.child,
      ),
    );
  }
}
