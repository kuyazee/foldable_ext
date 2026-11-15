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
