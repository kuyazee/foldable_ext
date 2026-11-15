import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

import 'emulated_device.dart';
import 'emulated_window.dart';
import 'fold_division_android.dart';
import 'fold_division_config.dart';

/// The switchboard of division mode.
///
/// ```dart
/// FoldDivision.enable();
/// FoldDivision.config.value = FoldDivision.config.value.copyWith(
///   activation: DivisionActivation.always,
/// );
/// ```
///
/// On Android a change to [config] sends a new snapshot through the
/// `foldable` API. On iOS this package leaves `FoldablePlatform.instance`
/// alone, so the fold there is the real one from the base plugin and
/// `enabled`, `divisionExtent`, `activation`, `device` and `matchWindowSize`
/// change nothing.
///
/// The base package sends no margins. [marginsOf] and [keepClearRectOf] take
/// them from `config.margins` on every platform, iOS included, so they can
/// differ from what UIKit reports for the device.
abstract final class FoldDivision {
  /// The division mode settings. Listen to it, or set `value` to change them.
  static final ValueNotifier<FoldDivisionConfig> config =
      ValueNotifier<FoldDivisionConfig>(const FoldDivisionConfig());

  /// Turns division mode on.
  static void enable() {
    config.value = config.value.copyWith(enabled: true);
  }

  /// Turns division mode off. The real hinge bounds are reported again.
  static void disable() {
    config.value = config.value.copyWith(enabled: false);
  }

  /// Whether fold data comes from this package with division mode on.
  ///
  /// True when division mode is on and the active `FoldablePlatform` is
  /// [FoldDivisionAndroid]. False on iOS and on every platform where the
  /// plugin is not registered. It does not say whether the device folds.
  static bool get isEmulating =>
      config.value.enabled && FoldablePlatform.instance is FoldDivisionAndroid;

  /// Whether a `FoldDivisionScope` is set to render its subtree as a device.
  ///
  /// True when division mode is on, `config.device` is set and the active
  /// `FoldablePlatform` is [FoldDivisionAndroid]. False on iOS, where the
  /// device is real. It does not say whether this Android device folds: a
  /// scope emulates on a foldable only. [emulatedDeviceOf] answers for one
  /// subtree and takes that into account.
  static bool get isEmulatingDevice =>
      isEmulating && config.value.device != null;

  /// The emulation the `FoldDivisionScope` above [context] has in effect, or
  /// null when it emulates no device or there is no scope.
  ///
  /// The caller rebuilds when the emulation changes: another window of the
  /// device, another scale, on or off.
  static DeviceEmulation? emulationOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DeviceEmulationScope>()
      ?.emulation;

  /// The device the subtree of [context] is rendered as, or null.
  ///
  /// While it is set, the `MediaQuery` of the subtree describes that device.
  /// Use it to pick the layout rules of the emulated platform.
  static EmulatedDevice? emulatedDeviceOf(BuildContext context) =>
      emulationOf(context)?.device;

  /// The bounds of the render box of [context] in the coordinates of its
  /// window, or null before the box is laid out.
  ///
  /// The window is the one `MediaQuery` describes: the emulated window under
  /// a scope that matches the window size, the Flutter view anywhere else.
  /// [divisionOf] and [keepClearRectOf] answer in the same coordinates, so
  /// this is the rect to compare with theirs. `RenderBox.localToGlobal`
  /// answers in the coordinates of the real view, which differ while a
  /// window size is emulated.
  ///
  /// Call it after layout, from a post-frame callback or an event handler.
  static Rect? windowRectOf(BuildContext context) {
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      RenderEmulatedWindow.transformToWindow(object),
      Offset.zero & object.size,
    );
  }

  /// The settings for the subtree of [context].
  ///
  /// Under a `FoldDivisionScope` the caller rebuilds when [config] changes.
  /// Elsewhere this is `config.value`, read once.
  static FoldDivisionConfig configOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FoldDivisionConfigScope>()
          ?.config ??
      config.value;

  /// The first fold division `DuoMediaQuery` holds, active or not, or null.
  ///
  /// Its bounds are in the coordinates of the window `MediaQuery` describes:
  /// the Flutter view, or the emulated window under a scope that matches the
  /// window size of a device.
  static ReservedRegion? divisionOf(BuildContext context) {
    for (final ReservedRegion region in DuoMediaQuery.regionsOf(context)) {
      if (region.kind == ReservedRegionKind.division) return region;
    }
    return null;
  }

  /// The keep-clear room around the division of [context].
  ///
  /// `config.margins`, turned to match the division. Zero when there is no
  /// division. The value comes from the config on every platform, since the
  /// base package sends no margins.
  static EdgeInsets marginsOf(BuildContext context) {
    final ReservedRegion? division = divisionOf(context);
    if (division == null) return EdgeInsets.zero;
    return configOf(context).marginsFor(division.bounds);
  }

  /// The rect interactive content should stay out of: the division bounds
  /// grown by [marginsOf], in the coordinates [divisionOf] uses.
  ///
  /// Null when there is no division in force. A division is in force while
  /// it is active and the posture is `partiallyOpen`, the rule the base
  /// widgets use. Pass [includeInactive] to get the rect of a division that
  /// is not in force too.
  static Rect? keepClearRectOf(
    BuildContext context, {
    bool includeInactive = false,
  }) {
    final ReservedRegion? division = divisionOf(context);
    if (division == null) return null;
    if (!includeInactive) {
      final bool inForce = division.isActive &&
          DuoMediaQuery.statusOf(context) == HingeStatus.partiallyOpen;
      if (!inForce) return null;
    }
    return configOf(context).keepClearRect(division.bounds);
  }
}

/// Hands a [FoldDivisionConfig] down the tree.
///
/// `FoldDivisionScope` inserts it. `FoldDivision.configOf` reads it.
class FoldDivisionConfigScope extends InheritedWidget {
  /// Creates a config scope.
  const FoldDivisionConfigScope({
    super.key,
    required this.config,
    required super.child,
  });

  /// The settings for the subtree.
  final FoldDivisionConfig config;

  @override
  bool updateShouldNotify(FoldDivisionConfigScope oldWidget) =>
      config != oldWidget.config;
}

/// Hands the [DeviceEmulation] in effect down the tree.
///
/// `FoldDivisionScope` inserts it. `FoldDivision.emulationOf` reads it.
class DeviceEmulationScope extends InheritedWidget {
  /// Creates an emulation scope.
  const DeviceEmulationScope({
    super.key,
    required this.emulation,
    required super.child,
  });

  /// The emulation in effect, or null when no device is emulated.
  final DeviceEmulation? emulation;

  @override
  bool updateShouldNotify(DeviceEmulationScope oldWidget) =>
      emulation != oldWidget.emulation;
}
