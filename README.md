# foldable_ext

Test iPhone Duo layouts on an Android foldable.

[![pub package](https://img.shields.io/pub/v/foldable_ext.svg)](https://pub.dev/packages/foldable_ext)
[![CI](https://github.com/kuyazee/foldable_ext/actions/workflows/ci.yml/badge.svg)](https://github.com/kuyazee/foldable_ext/actions/workflows/ci.yml)
[![Licence: Apache-2.0](https://img.shields.io/badge/licence-Apache--2.0-blue)](LICENSE)

The [`foldable`](https://pub.dev/packages/foldable) package gives Flutter the iPhone Duo's fold,
but only on iOS. This package adds Android support for the same API, so a Galaxy Z Fold or a
foldable emulator reports its fold the way an iPhone Duo would.

Here's [a quick demo on Threads](https://www.threads.com/share/BAbmPtq9Ul).

In debug builds it also:

- draws your app at iPhone Duo size, with the Duo's safe area and fold
- reports the fold as a 40 px division, the width `foldable` measured on the Duo simulator
- paints the division red and the keep-clear margins amber, so you can see what's in the way

This won't make your app Duo-ready by itself. It shows you how the app looks at Duo size and
where the fold lands. You'll still need to tweak a few layouts here and there before it really
looks at home on an iPhone Duo.

## Install

```sh
flutter pub add foldable_ext
```

You don't need any permissions or Gradle changes. The package re-exports `foldable`, so one
import covers both.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:foldable_ext/foldable_ext.dart';

void main() {
  runApp(
    FoldDivisionScope(
      child: MaterialApp(
        home: Scaffold(
          body: FoldAwareBuilder(
            builder: (context, constraints, fold) => Center(
              child: Text('posture: ${fold.status.name}'),
            ),
          ),
        ),
      ),
    ),
  );
}
```

Run it in debug mode on a foldable and half open the hinge. You should see red and amber bands
over the fold.

## Reading the fold

```dart
final HingeStatus status = DuoMediaQuery.statusOf(context);
final double? angle = DuoMediaQuery.angleOf(context);
final Rect? keepClear = FoldDivision.keepClearRectOf(context);
```

On an Android phone that doesn't fold, `Foldable.changes` and `Foldable.hingeAngleStream` never
close. Check `Foldable.isFoldable` before you wait on them.

## Settings

Change `FoldDivision.config` whenever you like. Everything listening picks up the new value.

```dart
FoldDivision.config.value = FoldDivision.config.value.copyWith(
  activation: DivisionActivation.always,
);
```

| Field | Default | What it does |
|---|---|---|
| `enabled` | `kDebugMode` | Turns division mode and device emulation on or off |
| `divisionExtent` | `40` | Division width in logical pixels |
| `margins` | 12 on each side facing the panes | Space to keep clear next to the division |
| `activation` | `followPosture` | `followPosture` shows the division only while half open. `always` shows it whenever the fold is on screen |
| `device` | `EmulatedDevice.iphoneDuo` | The device to imitate. `copyWith(clearDevice: true)` turns this off |
| `matchWindowSize` | `true` | Shrinks the app to the device's window size. When false, the app keeps the real size and only gets the device's safe area |

`FoldDivisionScope` also takes `showOverlay`, which defaults to `kDebugMode`.

## Fixing the device numbers

Some of the iPhone Duo numbers are guesses. Only the inner screen size and the 40 px division
come from simulator readings. Every number is a field, so you can override it:

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

## Coordinates under emulation

Under the scope, `MediaQuery` and the `FoldDivision` helpers use the emulated window's
coordinates. `RenderBox.localToGlobal` and pointer positions still use the real screen. When you
compare a widget against `keepClearRectOf`, get its bounds from
`FoldDivision.windowRectOf(context)`.

## Sizes outside the scope

`MediaQuery.of` under the scope already gives the emulated window. Code above the scope, or code
that reads the view, still sees the real screen. Swap the call and it gets the emulated window:

| Instead of | Use |
|---|---|
| `MediaQuery.of(context)` | `EmulatedMediaQuery.of(context)` |
| `MediaQuery.sizeOf(context)`, `paddingOf` and the rest | `EmulatedMediaQuery.sizeOf(context)`, `paddingOf` and the rest |
| `MediaQueryData.fromView(View.of(context))` | `EmulatedMediaQuery.windowOf(context)` |
| `MediaQueryData.fromView(view)` | `EmulatedMediaQuery.fromView(view)` |

`windowOf` skips local `MediaQuery` changes, like the one a `Scaffold` body gets, so use it when
you need the window edge. With no device emulated, every call answers the same as the one it
replaces.

## Platforms

- iOS passes straight through to `foldable`. The emulation settings do nothing there because the
  device is already an iPhone Duo.
- Android foldables get everything. The hinge angle needs Android 11 or later.
- On Android phones without a fold, the overlay and helpers draw nothing.
- Other platforms aren't supported.

You need Flutter 3.24 or later. The Android `minSdk` is 21.

## Known gaps

- The 12 px margin is a guess. `foldable` doesn't pass iOS's real margins to Dart, so
  `config.margins` is used everywhere.
- The first frame shows the real screen. Emulation starts once the first platform update arrives.

## Contributing

Issues and pull requests are welcome. If you have a real foldable, readings help the most: tell
me the device, the Android version and what the example app shows.

Run the checks before you open a pull request:

```sh
flutter pub get && flutter analyze && flutter test
(cd example && flutter pub get && flutter test)
```

## Licence

Apache-2.0, copyright kuyazee. Built on [`foldable`](https://pub.dev/packages/foldable).
