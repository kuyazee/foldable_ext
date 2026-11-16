## 0.2.1

- Shorter README that covers install, usage, settings and known gaps.
- Releases publish to pub.dev from GitHub Actions when a version tag is pushed.

## 0.2.0

Device emulation: with division mode on, an app under `FoldDivisionScope` on an Android foldable
renders as it does on an iPhone Duo.

- `EmulatedDevice` and `EmulatedDeviceState`, a device profile with one set of metrics per
  window: size, safe area, fold axis and centre, occlusions. `EmulatedDevice.iphoneDuo` is built
  in. Several of its numbers are unverified against hardware, and every number is a field.
- `FoldDivisionConfig.device` (default `EmulatedDevice.iphoneDuo`) and
  `FoldDivisionConfig.matchWindowSize` (default true). `copyWith` takes `clearDevice`.
- `FoldDivisionScope` lays its child out at the window size of the device, scaled to fit the
  real safe area over black, with hit testing through the scale. `MediaQuery` under it reports
  the emulated size, safe area, pixel ratio, keyboard inset and display features. With
  `matchWindowSize` off the window keeps its real size and takes the emulated safe area.
- `DuoMediaQuery`, `FoldDivision.divisionOf`, `marginsOf`, `keepClearRectOf` and the overlay
  work in the coordinates of the emulated window. The division sits on the fold of the profile
  and the occlusions of the profile are `occlusion` regions.
- `FoldDivision.isEmulatingDevice`, `emulatedDeviceOf`, `emulationOf` and `windowRectOf`.
- `selectEmulatedWindow`, `emulateDeviceData`, `placeEmulatedWindow`, `emulatedViewInsets` and
  `mergeSafeArea`, the pure functions behind the scope.
- `FoldDivisionOverlay` draws the occlusions and the safe area edges of the emulated device,
  with `occlusionColor` and `safeAreaColor`.
- The example app has a switch for `matchWindowSize`, shows the emulated window and blurs the
  list under its top bar.

Changed:

- With the default config, a `FoldDivisionScope` on an Android foldable in a debug build now
  emulates the iPhone Duo window. Set `device` to null (`copyWith(clearDevice: true)`) for the
  0.1.0 behaviour: the real window with the division on the hinge.

- The hinge angle decides the posture whenever the sensor has given one. The state Android
  attaches to the fold is used only with no angle. In 0.1.0 that state came first.

Fixed:

- The emulated window is composited into a buffer of its own size, so a `BackdropFilter` at its
  edge no longer blurs the black around the window into the app.
- An open device whose fold Android does not list (a foldable emulator at 180 degrees) is
  rendered as the inner display, and a fold listed as flat at 90 degrees reads `partiallyOpen`.

- Display feature bounds are read as logical pixels, which is what the engine reports. They
  were divided by the device pixel ratio a second time, which put the division at a fraction of
  the real fold position on a device.

## 0.1.0

First release.

- Android implementation of the `foldable` platform interface. `Foldable`, `FoldableProvider`,
  `DuoMediaQuery` and `FoldAwareBuilder` report the fold of an Android foldable.
- Division mode: `FoldDivision.config` turns the Android hinge into an iPhone Duo style division,
  40 logical pixels across by default, with a choice between following the posture and staying
  active on a flat device.
- `FoldDivisionScope`, a `FoldableProvider` with division mode and the overlay wired in.
- `FoldDivisionOverlay`, a debug overlay that draws the division rect and its keep-clear margins.
- `FoldDivision.divisionOf`, `marginsOf` and `keepClearRectOf` for reading the division and its
  margins from a `BuildContext`.
- Android plugin that reads the hinge angle from `Sensor.TYPE_HINGE_ANGLE` (API 30 and later),
  with no dependencies.
- Exports everything in `package:foldable/foldable.dart`.
- Supports Flutter 3.24 and later.

Not yet checked on a real foldable or on an emulator foldable profile.
