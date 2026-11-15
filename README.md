# foldable_ext

Build and debug iPhone Duo layouts on an Android foldable.

[![Licence: Apache-2.0](https://img.shields.io/badge/licence-Apache--2.0-blue)](LICENSE)
![Platforms: Android and iOS](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)
![Flutter 3.24 and later](https://img.shields.io/badge/Flutter-%E2%89%A5%203.24-02569B)
![Status: 0.1.0, untested on hardware](https://img.shields.io/badge/status-0.1.0%2C%20untested%20on%20hardware-orange)

The [`foldable`](https://pub.dev/packages/foldable) package reports the iPhone Duo fold to
Flutter: the hinge angle, the posture and the reserved regions, including the `.division` rect
down the middle of the inner display. It is iOS only. `foldable_ext` adds an Android
implementation of the same API, so a Samsung Galaxy Z Fold or a foldable emulator profile answers
`Foldable`, `FoldableProvider`, `DuoMediaQuery` and `FoldAwareBuilder` the way an iPhone Duo does.

It adds two things on top:

- **Division mode.** A runtime switch that reports the Android hinge as an iPhone Duo style
  division: 40 logical pixels across, centred on the fold.
- **A debug overlay.** It draws the division rect and its keep-clear margins over your app, so
  you can see when a button sits in the zone.

```text
  inner display, half open, fold running top to bottom

  +---------------------------+----+------+----+---------------------------+
  |                           |    |......|    |                           |
  |       leading pane        |    |......|    |       trailing pane       |
  |                           |    |......|    |                           |
  +---------------------------+----+------+----+---------------------------+
                               12     40    12
                              margin division margin

                              |<- keep clear: 64 ->|
```

The numbers are the defaults, in logical pixels. The overlay paints the division in red and the
margins in amber.

**Status:** version 0.1.0. Not on pub.dev yet, and not yet run on a real foldable or a foldable
emulator profile. See [Limits](#limits).

## Contents

- [Quick start](#quick-start)
- [Install](#install)
- [Usage](#usage)
  - [Read the fold](#read-the-fold)
  - [Division mode](#division-mode)
  - [The overlay](#the-overlay)
- [Platform support](#platform-support)
  - [iOS](#ios)
  - [Android](#android)
  - [Other platforms](#other-platforms)
- [The Android emulator](#the-android-emulator)
- [Limits](#limits)
- [Supported Flutter versions](#supported-flutter-versions)
- [Contributing](#contributing)
- [Credit](#credit)
- [Licence](#licence)

## Quick start

Add the dependency to `pubspec.yaml`:

```yaml
dependencies:
  foldable_ext:
    git:
      url: https://github.com/kuyazee/foldable_ext.git
```

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:foldable_ext/foldable_ext.dart';

void main() {
  runApp(
    FoldDivisionScope(
      child: MaterialApp(
        home: Scaffold(
          body: FoldAwareBuilder(
            builder: (context, constraints, fold) {
              final Rect? keepClear = FoldDivision.keepClearRectOf(context);
              return Center(
                child: Text(
                  'posture: ${fold.status.name}\n'
                  'angle: ${fold.angleDegrees}\n'
                  'spans division: ${fold.spansDivision}\n'
                  'keep clear: $keepClear',
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
```

Run it in debug mode on an Android foldable or a foldable emulator profile and half open the
hinge. Debug builds start with division mode and the overlay on, so the red and amber bands
appear over the fold and the text follows the posture.

## Install

`foldable_ext` is not on pub.dev yet. Depend on the repository:

```yaml
dependencies:
  foldable_ext:
    git:
      url: https://github.com/kuyazee/foldable_ext.git
```

Or on a local copy:

```yaml
dependencies:
  foldable_ext:
    path: ../foldable_ext
```

`foldable_ext` depends on `foldable` and exports all of it. One import covers both:

```dart
import 'package:foldable_ext/foldable_ext.dart';
```

There is no Android manifest entry, permission or Gradle setting to add.

## Usage

Put `FoldDivisionScope` where a `FoldableProvider` would go:

```dart
FoldDivisionScope(
  child: MaterialApp(home: HomePage()),
)
```

`FoldDivisionScope` takes the same `bridgeMode`, `platform` and `debugData` arguments as
`FoldableProvider` and passes them through. It adds two of its own:

| Argument | Default | Meaning |
|---|---|---|
| `showOverlay` | `kDebugMode` | Paints [the overlay](#the-overlay) over `child`. |
| `emulateDisplayFeatures` | `true` | On Android, with division mode on, replaces `MediaQuery.displayFeatures` with what the same `bridgeMode` gives on iPhone Duo. See [Android](#android). |

An app that already uses `FoldableProvider` keeps working on Android without the scope. It then
gets the fold data, without the overlay and without the `MediaQuery` rewrite.

### Read the fold

Everything below the scope reads fold state through the base API, with no platform checks:

```dart
FoldAwareBuilder(
  builder: (context, constraints, fold) {
    if (!fold.spansDivision) return const SinglePane();
    return Row(
      children: const [Expanded(child: Leading()), Expanded(child: Trailing())],
    );
  },
)
```

```dart
final HingeStatus status = DuoMediaQuery.statusOf(context);
final double? angle = DuoMediaQuery.angleOf(context);
final List<ReservedRegion> regions = DuoMediaQuery.regionsOf(context);
```

The `Foldable` statics work outside the widget tree:

```dart
if (await Foldable.isFoldable) {
  Foldable.hingeAngleStream.listen((double degrees) {
    // 0 is folded shut, 180 is flat.
  });
}
```

On Android, check `Foldable.isFoldable` before you wait on a stream. The
[Android](#android) section explains why.

### Division mode

`FoldDivision.config` is a `ValueNotifier<FoldDivisionConfig>`. Set its value at any time and
every listener of the base API gets a new snapshot.

```dart
FoldDivision.config.value = FoldDivision.config.value.copyWith(
  enabled: true,
  activation: DivisionActivation.always,
);
```

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `kDebugMode` | On: the fold is reported as a division `divisionExtent` across. Off: the real hinge bounds are reported. |
| `divisionExtent` | `40` | Width of the division in logical pixels. 40 is what the `foldable` package measured on the iPhone Duo simulator. |
| `margins` | 12 on the two sides that face the panes | Keep-clear room around the division. Written for a fold that runs top to bottom. For a fold that runs left to right the package turns them, so the same two values face the panes. |
| `activation` | `followPosture` | `followPosture`: the division is active while the hinge is partially open, as on iPhone Duo. `always`: active whenever the fold is inside the window, for checking a layout with the Fold lying flat. The posture is then reported as `partiallyOpen` whatever the hinge does, and the hinge angle keeps its real value. |

`FoldDivision.enable()` and `FoldDivision.disable()` are shortcuts for the `enabled` field.

Release builds start with division mode off, because `enabled` defaults to `kDebugMode`. To offer
it as a developer setting in a release build, set `enabled` from your own setting.

Helpers that read the division from a `BuildContext`:

```dart
final ReservedRegion? division = FoldDivision.divisionOf(context);
final EdgeInsets margins = FoldDivision.marginsOf(context);
final Rect? keepClear = FoldDivision.keepClearRectOf(context);
final FoldDivisionConfig config = FoldDivision.configOf(context);
```

- `divisionOf` returns the first division region, active or not, or null.
- `marginsOf` returns `config.margins` turned to match the division, or zero with no division.
- `keepClearRectOf` returns the division bounds grown by the margins, in the coordinates of the
  Flutter view. It is null while no division is in force. Pass `includeInactive: true` to get the
  rect of a division that is not in force too.
- `configOf` returns the current config. Under a `FoldDivisionScope` the caller rebuilds when the
  config changes.

`FoldDivision.isEmulating` is true while division mode is on and the fold data comes from this
package's Android implementation. It is false on iOS. It does not say whether the device folds.

### The overlay

`FoldDivisionScope` paints the overlay when `showOverlay` is true. The default is `kDebugMode`.

```dart
FoldDivisionScope(
  showOverlay: showFoldOverlay,
  child: MaterialApp(home: HomePage()),
)
```

The division is drawn in red and the keep-clear margins in amber. The overlay does not take
touches. The bands stay on the fold when the overlay sits in a scrolling list or under a
transform. To cover part of the tree only, or to change the colours, use the widget directly
below a scope or a `FoldableProvider`:

```dart
FoldDivisionOverlay(
  visible: true,
  showInactive: true,
  divisionColor: const Color(0x663E63DD),
  marginColor: const Color(0x3330A46C),
  child: child,
)
```

`showInactive` also outlines a division that is not in force, such as the one a flat device
reports. `inactiveColor` sets the colour of that outline.

## Platform support

| | iOS (iPhone Duo) | Android foldable | Android phone | Other |
|---|---|---|---|---|
| Fold data comes from | the `foldable` plugin | this package | this package | nothing |
| `isFoldable` | true | true | false | false |
| Hinge angle | yes | Android 11 (API 30) and later | no | no |
| Division mode switch | no effect, the division is real | yes | no fold to report | no |
| Overlay and `FoldDivision` helpers | yes | yes | draw nothing | draw nothing |
| Margins | from `config.margins` | from `config.margins` | none | none |

### iOS

`foldable_ext` registers nothing on iOS. The `foldable` plugin reports the real iPhone Duo fold
and this package passes it through.

- `enabled`, `divisionExtent` and `activation` change nothing.
- `FoldDivisionScope`, the overlay and the `FoldDivision` helpers work, and they draw and measure
  the real division.
- Margins come from `config.margins`. See [Limits](#limits).

### Android

The package registers itself as the `foldable` platform implementation. It merges three sources:

- The fold bounds, the posture and the cutouts, from the display features Flutter already reports
  in `dart:ui`.
- The hinge angle, from `Sensor.TYPE_HINGE_ANGLE`. The Kotlin side of the plugin reads that
  sensor and nothing else, and it has no dependencies. The sensor needs Android 11 (API 30). On
  older versions the angle is null and the posture comes from the display features alone.
- `FoldDivision.config`.

How the data is converted:

- **Posture.** A half opened fold is `partiallyOpen` and a flat one is `fullyOpen`. With no fold
  in the window, a device that has a hinge sensor follows the angle: 20 degrees or less is
  `closed`, which is the cover screen. With no fold and no angle reading yet the posture is
  `unknown`.
- **Regions.** Each fold or hinge becomes a `division` region. With division mode on it is
  `divisionExtent` across and centred on the fold. A hinge wider than `divisionExtent` keeps its
  own width, and a fold near a window edge gives a division cut to the window. With division
  mode off it keeps the bounds Android reports, which on a Galaxy Z Fold is a zero-width line.
  Each cutout becomes an `occlusion` region.
- **Size classes.** A window 600 logical pixels wide or more is `regular` in width, and 480 tall
  or more is `regular` in height. These are Android's window size class breakpoints.
- **`MediaQuery.displayFeatures`.** iOS reports none, so on iPhone Duo the list holds what
  `bridgeMode` asks for and nothing else. Android fills it with the real fold, which splits
  dialogs and sheets. With division mode on, `FoldDivisionScope` on a foldable replaces the list
  with what the same `bridgeMode` gives on iPhone Duo. Features of a type Flutter reports as
  `unknown` are kept. Pass `emulateDisplayFeatures: false` to keep Android's own list.

What each `bridgeMode` puts in the rewritten list:

| `bridgeMode` | `MediaQuery.displayFeatures` under the scope |
|---|---|
| `none` (default) | Empty, so dialogs and sheets are not split. |
| `cutoutsOnly` | The cutouts. |
| `full` | The cutouts, plus the division as a half opened fold while the posture is `partiallyOpen`. |

On an Android phone that does not fold:

- `isFoldable` is false and the posture is `unknown`. Size classes and cutouts are still
  reported.
- `FoldDivisionScope` leaves `MediaQuery.displayFeatures` as Android filled it, so the camera
  cutout stays.
- `Foldable.changes` sends one snapshot and stays open. `Foldable.hingeAngleStream` never emits
  and never completes. The base package completes both on an iPhone with no hinge. Android
  cannot tell a plain phone from a foldable that shows its cover screen and has no hinge
  sensor, so the stream stays open to catch the device unfolding. Check `Foldable.isFoldable`
  before you wait on a stream.

### Other platforms

Unsupported. `isFoldable` is false, snapshots are `FoldableData.unsupported` and the streams
complete without emitting, as the base package does off iOS. The widgets render their child and
the overlay draws nothing.

## The Android emulator

Division mode reads the same display features and the same sensor on an emulator as on a device.

1. Create a virtual device from a foldable profile in the Android Studio Device Manager, for
   example a Pixel Fold or one of the generic "Fold-in" profiles, on a system image with API 30
   or later.
2. Run the app, open **Extended controls**, then **Virtual sensors**, and move the hinge angle
   slider or pick a posture.

The example app in [`example/`](example/) shows the posture, the angle and the regions as they
change, with switches for division mode and the overlay.

## Limits

- **Not yet checked on a real Fold.** The Dart side is covered by unit and widget tests and the
  Kotlin side by unit tests with a mocked sensor. Nobody has run the package on a Galaxy Z Fold
  or on a foldable emulator profile yet, so treat the Android behaviour as untested on hardware.
- **Margins come from the config on every platform.** UIKit reports keep-clear margins with the
  `.division` region, but the `foldable` package does not send them to Dart. `marginsOf`,
  `keepClearRectOf` and the overlay use `config.margins` on iOS too. The default of 12 logical
  pixels is a guess that nobody has confirmed on iPhone Duo hardware. Set your own value once you
  have a real reading.
- **Posture needs a fold in the window.** In split screen, a window that sits on one side of the
  fold has no display feature. The posture then comes from the hinge angle alone.
- **A one-off read may have no angle.** The Android sensor reports only while something
  listens to the stream. `Foldable.snapshot` and `Foldable.hingeStatus` called with no listener
  get a null angle, unless an earlier listener left a reading behind. With a null angle the
  posture comes from the display features. On the cover screen there is no fold in the window,
  so a one-off read there answers `unknown`. Under `FoldDivisionScope` or
  `FoldableProvider` the stream is open, the angle is live and the cover screen reads `closed`.
- **Size classes are computed.** Android has no iOS size classes. The values come from the
  window size and the breakpoints above.
- **`debugDumpNativeApi()` returns Android data on Android.** The map holds the sensor state and
  the display features. It has none of the iOS selectors the base package lists.

## Supported Flutter versions

Flutter 3.24 and later (Dart 3.5 and later), the same floor as the `foldable` package.

The CI workflow analyzes and tests the package on Flutter 3.24, 3.27, 3.32, 3.38, the latest
stable release and beta. A second job builds an Android app that depends on the plugin on
Flutter 3.24, 3.38 and the latest stable release.

`android/build.gradle` is written to build with each Android toolchain those versions create: the
Android Gradle plugin 7.3 through 9 and Kotlin 1.7 through 2.3. The Android library has a
`minSdk` of 21.

The app in `example/` uses the Android project of the Flutter 3.44 template, so the example
itself needs Flutter 3.44 or later.

## Contributing

Bug reports and pull requests are welcome at
[github.com/kuyazee/foldable_ext](https://github.com/kuyazee/foldable_ext). Readings from a real
foldable are the most useful thing to send: open an
[issue](https://github.com/kuyazee/foldable_ext/issues) with the device, the Android version and
what the example app shows under **Live values**.

Before you open a pull request, run the same checks as CI:

```sh
flutter pub get
flutter analyze
flutter test
(cd example && flutter pub get && flutter test)
```

The Kotlin unit tests run from the example's Android project, after one debug build:

```sh
cd example
flutter build apk --debug
cd android
./gradlew :foldable_ext:testDebugUnitTest
```

Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credit

This package builds on the [`foldable`](https://pub.dev/packages/foldable) package, which does
the work on iOS and defines the API. `foldable_ext` keeps that API unchanged and exports it.

## Licence

Apache-2.0, copyright kuyazee. See [LICENSE](LICENSE).
