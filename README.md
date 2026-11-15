# foldable_ext

Build and debug iPhone Duo layouts on an Android foldable.

[![Licence: Apache-2.0](https://img.shields.io/badge/licence-Apache--2.0-blue)](LICENSE)
![Platforms: Android and iOS](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)
![Flutter 3.24 and later](https://img.shields.io/badge/Flutter-%E2%89%A5%203.24-02569B)
![Status: 0.2.0, untested on hardware](https://img.shields.io/badge/status-0.2.0%2C%20untested%20on%20hardware-orange)

The [`foldable`](https://pub.dev/packages/foldable) package reports the iPhone Duo fold to
Flutter: the hinge angle, the posture and the reserved regions, including the `.division` rect
down the middle of the inner display. It is iOS only. `foldable_ext` adds an Android
implementation of the same API, so a Samsung Galaxy Z Fold or a foldable emulator profile answers
`Foldable`, `FoldableProvider`, `DuoMediaQuery` and `FoldAwareBuilder` the way an iPhone Duo does.

It adds three things on top:

- **Device emulation.** With division mode on, an app under `FoldDivisionScope` on an Android
  foldable renders as it does on an iPhone Duo: the same logical window size, the same safe area
  and the same fold position.
- **Division mode.** A runtime switch that reports the fold as an iPhone Duo style division:
  40 logical pixels across, centred on the fold.
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

**Status:** version 0.2.0. Not on pub.dev yet. Device emulation has not been run on a real
foldable or a foldable emulator profile. See [Limits](#limits).

## Contents

- [Quick start](#quick-start)
- [Install](#install)
- [Usage](#usage)
  - [Read the fold](#read-the-fold)
  - [Division mode](#division-mode)
  - [Device emulation](#device-emulation)
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
hinge. Debug builds start with division mode and the overlay on, so the app is laid out as on an
iPhone Duo, the red and amber bands appear over its fold and the text follows the posture.

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
gets the fold data of the real window, without the overlay, without the `MediaQuery` rewrite
and without [device emulation](#device-emulation).

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
| `enabled` | `kDebugMode` | On: the fold is reported as a division `divisionExtent` across, and a `FoldDivisionScope` renders its subtree as `device`. Off: the real hinge bounds are reported and no device is emulated. |
| `divisionExtent` | `40` | Width of the division in logical pixels. 40 is what the `foldable` package measured on the iPhone Duo simulator. |
| `margins` | 12 on the two sides that face the panes | Keep-clear room around the division. Written for a fold that runs top to bottom. For a fold that runs left to right the package turns them, so the same two values face the panes. |
| `activation` | `followPosture` | `followPosture`: the division is active while the hinge is partially open, as on iPhone Duo. `always`: active whenever the fold is inside the window, for checking a layout with the Fold lying flat. The posture is then reported as `partiallyOpen` whatever the hinge does, and the hinge angle keeps its real value. |

| `device` | `EmulatedDevice.iphoneDuo` | The device a `FoldDivisionScope` renders its subtree as. Null emulates no device: the window stays real and the division sits on the hinge. Clear it with `copyWith(clearDevice: true)`. See [Device emulation](#device-emulation). |
| `matchWindowSize` | `true` | On: the subtree gets the window size of `device`, scaled to fit. Off: the window keeps its real size and takes the safe area of `device`. |

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
  window `MediaQuery` describes. It is null while no division is in force. Pass
  `includeInactive: true` to get the rect of a division that is not in force too.
- `configOf` returns the current config. Under a `FoldDivisionScope` the caller rebuilds when the
  config changes.

`FoldDivision.isEmulating` is true while division mode is on and the fold data comes from this
package's Android implementation. It is false on iOS. It does not say whether the device folds.

### Device emulation

On an Android foldable, with division mode on, `FoldDivisionScope` renders its subtree as the
device in `FoldDivisionConfig.device`. The default is `EmulatedDevice.iphoneDuo`:

| State | Window | Safe area (`padding` and `viewPadding`) | Fold |
|---|---|---|---|
| Outer display, portrait | 466 x 678 | right 84, bottom 34 | none |
| Outer display, landscape | 678 x 466 | right 84 | none |
| Inner display, landscape (open like a book) | 951 x 669 | right 84 | vertical, centred on x 475.5 |
| Inner display, portrait (tabletop) | 669 x 951 | top 84, bottom 95 | horizontal, centred on y 475.5 |

All values are in logical pixels. The outer display has a system strip on its trailing edge. The
clock and the Wi-Fi indicator sit at the top of the strip, and the outer portrait state lists
them as the occlusion `(385, 0, 84, 120)`.

**Several of these numbers are unverified against hardware.** The 951 x 669 inner window and the
40 point division come from the `foldable` package's simulator readings. The outer window
sizes, the safe areas and the occlusion have not been checked on a device. Every number is a
field, so you can pass a corrected profile:

```dart
FoldDivision.config.value = FoldDivision.config.value.copyWith(
  device: EmulatedDevice.iphoneDuo.copyWith(
    outerPortrait: const EmulatedDeviceState(
      windowSize: Size(466, 678),
      safeArea: EdgeInsets.only(right: 80, bottom: 34),
    ),
  ),
);
```

Which state is used comes from the hinge angle and the real window:

- With a hinge sensor reading, the angle decides the display. 20 degrees or less is the outer
  display, even if Android still lists a fold. Anything above is the inner display, even if
  Android lists no fold, which a foldable emulator does at 180 degrees. The fold axis then comes
  from the fold Android lists, or else from the axis last seen for a window of the same
  orientation, or else from the window shape: wider than tall gives the landscape state.
- With no hinge sensor, or no reading yet, a fold or hinge that crosses the window means the
  inner display and no fold means the outer display.
- A fold that runs top to bottom gives the inner landscape state and one that runs left to
  right gives the inner portrait state. On the outer display a window wider than it is tall
  gives the landscape state, any other window the portrait state.

With `matchWindowSize` on (the default):

- The subtree is laid out in a box of the emulated window size. The box is scaled by one factor
  to fit inside the real window less the Android status and navigation bars, centred, with
  black around it. Touches reach the widgets through the scale.
- `MediaQuery` under the scope describes the emulated window: `size`, the safe area as `padding`
  and `viewPadding`, `devicePixelRatio` multiplied by the scale so physical pixels stay true,
  the keyboard inset converted into emulated coordinates, and zero `systemGestureInsets`. The
  text scale stays as the user set it.
- `MediaQuery.displayFeatures` holds what `bridgeMode` asks for, built from the emulated fold.
  The real fold and the real cutouts are never in it.
- `DuoMediaQuery`, `FoldDivision.divisionOf`, `marginsOf`, `keepClearRectOf` and the overlay
  work in the coordinates of the emulated window. The division is `divisionExtent` thick, sits
  on the fold of the profile and runs the whole window. The occlusions of the profile are
  `occlusion` regions. The size classes come from the emulated window.
- `activation` keeps its meaning: the division is active while the real hinge is partly open,
  or always.

With `matchWindowSize` off the window keeps its real size. The safe area is the larger of the
real one and the emulated one on each side, the division sits on the real hinge and the
occlusions of the profile are not reported.

Read what is in effect from a `BuildContext`:

```dart
final EmulatedDevice? device = FoldDivision.emulatedDeviceOf(context);
final DeviceEmulation? emulation = FoldDivision.emulationOf(context);
final Rect? bounds = FoldDivision.windowRectOf(context);
```

- `emulatedDeviceOf` is not null while the subtree is rendered as a device. Use it to switch on
  the layout rules of the emulated platform, since `Platform.isIOS` stays false.
- `emulationOf` adds the window in use (`kind`, `state`), the `scale`, and whether the window
  size is matched.
- `windowRectOf` returns the bounds of a widget in the coordinates `MediaQuery` and
  `keepClearRectOf` use. `RenderBox.localToGlobal` and global pointer positions are in the
  coordinates of the real view, which differ while a window size is emulated.
- `FoldDivision.isEmulatingDevice` is the static form: division mode is on, a device is set and
  the fold data comes from this package's Android implementation. It does not say whether the
  device folds.

The scope keeps the same widgets above its child in every mode, so a config change, a fold or
an unfold keeps the state of your app. Put the scope where it fills the Flutter view.

### The overlay

`FoldDivisionScope` paints the overlay when `showOverlay` is true. The default is `kDebugMode`.

```dart
FoldDivisionScope(
  showOverlay: showFoldOverlay,
  child: MaterialApp(home: HomePage()),
)
```

The division is drawn in red and the keep-clear margins in amber. While a device is emulated
the overlay also fills the occlusions of the profile in blue and draws a green line along each
inner edge of the emulated safe area. `occlusionColor` and `safeAreaColor` change the two.

The overlay does not take touches. The bands stay on the fold when the overlay sits in a
scrolling list or under a transform. To cover part of the tree only, or to change the colours,
use the widget directly below a scope or a `FoldableProvider`:

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
| Device emulation | no effect, the device is real | yes, under `FoldDivisionScope` | no | no |
| Overlay and `FoldDivision` helpers | yes | yes | draw nothing | draw nothing |
| Margins | from `config.margins` | from `config.margins` | none | none |

### iOS

`foldable_ext` registers nothing on iOS. The `foldable` plugin reports the real iPhone Duo fold
and this package passes it through.

- `enabled`, `divisionExtent`, `activation`, `device` and `matchWindowSize` change nothing.
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

- **Posture.** The hinge angle decides whenever the sensor has given one: 20 degrees or less
  is `closed`, 160 or more is `fullyOpen` and anything between is `partiallyOpen`. The state
  Android attaches to the fold is used only while there is no angle: a half opened fold is
  `partiallyOpen` and a flat one is `fullyOpen`. With no angle and no fold the posture is
  `unknown`. The angle wins because the fold list can lag: a foldable emulator lists the fold
  as flat with the hinge at 90 degrees.
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
  `unknown` are kept. Pass `emulateDisplayFeatures: false` to keep Android's own list. While
  the window size of a device is matched the list always holds the emulated features, since
  Android's bounds are in the coordinates of the real window.

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
- No device is emulated. The window and its safe area stay as Android reports them.
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
change, with switches for division mode, the window size match and the overlay.

## Limits

- **Device emulation is not yet checked on a real Fold.** The Dart side is covered by unit and
  widget tests and the Kotlin side by unit tests with a mocked sensor. Nobody has run device
  emulation on a Galaxy Z Fold or on a foldable emulator profile yet, so treat it as untested
  on hardware.
- **The iPhone Duo profile holds unverified numbers.** See
  [Device emulation](#device-emulation). Pass your own `EmulatedDevice` once you have real
  readings.
- **Emulation needs the scope and a foldable.** A bare `FoldableProvider` and the `Foldable`
  statics report the real window: the division on the real hinge, real cutouts, size classes of
  the real window. A phone with no hinge is not emulated. A foldable with no hinge sensor is
  emulated only while a fold is in the window, so its cover screen stays real.
- **The fold axis can be a guess.** When Android lists no fold and none was seen earlier for
  that window orientation, the inner state comes from the window shape. A Galaxy Z Fold held
  upright is taller than wide with a fold that runs top to bottom, so it would get the inner
  portrait state until Android lists the fold once. The axis seen is kept while the scope
  stays mounted.
- **The first frame is real.** The scope learns that the device folds from the first snapshot
  of the platform. The emulated window appears once that snapshot arrives, after the first
  frame.
- **Only `MediaQuery` readers see the emulated window.** `View.of(context)`,
  `RenderBox.localToGlobal` and global pointer positions stay in the coordinates of the real
  view. The Android system bars keep their own look and sit outside the emulated window.
- **The emulated fold may not sit on the real hinge.** The emulated window is centred in the
  real safe area and has the proportions of the profile, so its fold lands where the profile
  puts it.
- **Margins come from the config on every platform.** UIKit reports keep-clear margins with the
  `.division` region, but the `foldable` package does not send them to Dart. `marginsOf`,
  `keepClearRectOf` and the overlay use `config.margins` on iOS too. The default of 12 logical
  pixels is a guess that nobody has confirmed on iPhone Duo hardware. Set your own value once you
  have a real reading.
- **With no angle the posture needs a fold in the window.** The hinge angle is the first source.
  On a device with no hinge sensor, a split screen window that sits on one side of the fold has
  no display feature and reads `unknown`.
- **A division on the real hinge needs Android to list the fold.** With `device` null or
  `matchWindowSize` off the division takes its place from the listed fold. While Android lists
  none there is no division, whatever the angle.
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
