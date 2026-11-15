# foldable_ext example

One screen for trying `foldable_ext` on an Android foldable or a foldable emulator profile.

## Run it

From this folder:

```sh
flutter run
```

On an emulator, open **Extended controls**, then **Virtual sensors**, and move the hinge angle
slider or pick a posture. The [package README](../README.md#the-android-emulator) has the
emulator setup.

## What is on the screen

- **Division mode** switches between the real hinge bounds and the iPhone Duo style division.
- **Division is active** picks between following the posture and staying active on a flat device.
- **Overlay** draws the division and its keep-clear margins over the app.
- The lettered buttons span the width of the screen. A button turns red while it overlaps the
  keep-clear zone.
- **Live values** lists what the `foldable` API reports: posture, hinge angle, regions, size
  classes and capabilities.

All of the code is in [`lib/main.dart`](lib/main.dart).

## Flutter version

The Android project here uses the Gradle toolchain of the Flutter 3.44 template, so the example
app builds with Flutter 3.44 or later. The package itself supports Flutter 3.24 and later.
