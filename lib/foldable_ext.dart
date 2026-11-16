/// The iPhone Duo fold division on Android foldables.
///
/// The `foldable` package reports the iPhone Duo hinge angle, posture and
/// reserved regions on iOS. This package registers an Android implementation
/// of the same platform interface, so a Galaxy Z Fold or a foldable emulator
/// profile answers through the same API. In division mode the hinge is
/// reported as an iPhone Duo style division: 40 logical pixels across,
/// centred on the fold. Under a `FoldDivisionScope` the app is also rendered
/// as an [EmulatedDevice]: the window size, the safe area and the fold
/// position of an iPhone Duo.
///
/// ```dart
/// FoldDivisionScope(
///   child: FoldAwareBuilder(
///     builder: (context, constraints, fold) => fold.isPartiallyOpen
///         ? const TwoPaneLayout()
///         : const SinglePaneLayout(),
///   ),
/// )
/// ```
///
/// Everything in `package:foldable/foldable.dart` is exported from here too.
library;

export 'package:foldable/foldable.dart';

export 'src/division_emulator.dart';
export 'src/emulated_device.dart';
export 'src/emulated_media_query.dart';
export 'src/emulated_window.dart';
export 'src/fold_division_android.dart';
export 'src/fold_division_api.dart';
export 'src/fold_division_config.dart';
export 'src/fold_division_overlay.dart';
export 'src/fold_division_scope.dart';
