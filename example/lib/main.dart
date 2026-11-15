import 'dart:ui' show DisplayFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:foldable_ext/foldable_ext.dart';

void main() {
  runApp(const FoldDivisionExampleApp());
}

/// One screen that shows what the `foldable` API reports and lets you change
/// division mode and device emulation while the app runs.
class FoldDivisionExampleApp extends StatefulWidget {
  const FoldDivisionExampleApp({super.key, this.debugData});

  /// Drives the screen from a stream in place of the platform. For tests.
  final Stream<FoldableData>? debugData;

  @override
  State<FoldDivisionExampleApp> createState() => _FoldDivisionExampleAppState();
}

class _FoldDivisionExampleAppState extends State<FoldDivisionExampleApp> {
  bool _showOverlay = true;

  @override
  Widget build(BuildContext context) {
    // The scope sits above MaterialApp, where a FoldableProvider would go.
    return FoldDivisionScope(
      showOverlay: _showOverlay,
      debugData: widget.debugData,
      child: MaterialApp(
        title: 'foldable_ext example',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF3B6EA8),
          useMaterial3: true,
        ),
        home: HomePage(
          showOverlay: _showOverlay,
          onShowOverlayChanged: (bool value) {
            setState(() => _showOverlay = value);
          },
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.showOverlay,
    required this.onShowOverlayChanged,
  });

  final bool showOverlay;
  final ValueChanged<bool> onShowOverlayChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // The probe buttons measure themselves again whenever the list scrolls.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      // The list scrolls under a bar that blurs it. The bar is flush with
      // the top of the window, so its blur reaches the window edge: under an
      // emulated window that edge is inside the screen.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('foldable_ext'),
        backgroundColor: colors.surface.withValues(alpha: 0.6),
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      body: ListView(
        controller: _scroll,
        // The list starts below the bar and scrolls under it.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
          bottom: 8,
        ),
        children: <Widget>[
          const _SectionTitle('Division mode'),
          _Controls(
            showOverlay: widget.showOverlay,
            onShowOverlayChanged: widget.onShowOverlayChanged,
          ),
          const _SectionTitle('Buttons across the middle'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'A button turns red while it overlaps the keep-clear zone. '
              'In tabletop posture, scroll a row onto the fold.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _ProbeRow(scroll: _scroll, labels: const <String>['A', 'B', 'C']),
          _ProbeRow(
            scroll: _scroll,
            labels: const <String>['D', 'E', 'F', 'G'],
          ),
          const _SectionTitle('Live values'),
          const _LiveValues(),
          const _SectionTitle('More buttons'),
          _ProbeRow(
            scroll: _scroll,
            labels: const <String>['H', 'I', 'J', 'K', 'L'],
          ),
          _ProbeRow(scroll: _scroll, labels: const <String>['M', 'N']),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// The division mode switch, the window size switch, the activation control
/// and the overlay switch.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.showOverlay,
    required this.onShowOverlayChanged,
  });

  final bool showOverlay;
  final ValueChanged<bool> onShowOverlayChanged;

  @override
  Widget build(BuildContext context) {
    final FoldDivisionConfig config = FoldDivision.configOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          key: const ValueKey<String>('division-mode'),
          title: const Text('Division mode'),
          subtitle: const Text(
            'Render as an iPhone Duo on an Android foldable',
          ),
          value: config.enabled,
          onChanged: (bool value) {
            FoldDivision.config.value = config.copyWith(enabled: value);
          },
        ),
        SwitchListTile(
          key: const ValueKey<String>('match-window-size'),
          title: const Text('Match window size'),
          subtitle: const Text(
            'On: the iPhone Duo window, scaled to fit. '
            'Off: the real window with the iPhone Duo safe area',
          ),
          value: config.matchWindowSize,
          onChanged: config.enabled
              ? (bool value) {
                  FoldDivision.config.value = config.copyWith(
                    matchWindowSize: value,
                  );
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Division is active'),
              const SizedBox(height: 8),
              SegmentedButton<DivisionActivation>(
                segments: const <ButtonSegment<DivisionActivation>>[
                  ButtonSegment<DivisionActivation>(
                    value: DivisionActivation.followPosture,
                    label: Text('With the posture'),
                  ),
                  ButtonSegment<DivisionActivation>(
                    value: DivisionActivation.always,
                    label: Text('Always'),
                  ),
                ],
                selected: <DivisionActivation>{config.activation},
                onSelectionChanged: (Set<DivisionActivation> selection) {
                  FoldDivision.config.value = config.copyWith(
                    activation: selection.first,
                  );
                },
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const ValueKey<String>('overlay'),
          title: const Text('Overlay'),
          subtitle: const Text(
            'Draw the division, its margins, the occlusions and the safe area',
          ),
          value: showOverlay,
          onChanged: onShowOverlayChanged,
        ),
      ],
    );
  }
}

/// What the base `foldable` API, `MediaQuery` and the emulation report.
class _LiveValues extends StatelessWidget {
  const _LiveValues();

  @override
  Widget build(BuildContext context) {
    final FoldableData data = DuoMediaQuery.of(context);
    final FoldableCapabilities caps = data.capabilities;
    final double? angle = data.angleDegrees;
    final Rect? keepClear = FoldDivision.keepClearRectOf(context);
    final DeviceEmulation? emulation = FoldDivision.emulationOf(context);
    final MediaQueryData media = MediaQuery.of(context);

    return Column(
      children: <Widget>[
        _ValueRow('Emulated device', emulation?.device.name ?? 'none'),
        _ValueRow('Emulated window', emulation?.kind.name ?? 'none'),
        _ValueRow(
          'Scale',
          emulation == null ? 'none' : emulation.scale.toStringAsFixed(3),
        ),
        _ValueRow(
          'Window size',
          '${media.size.width.toStringAsFixed(0)} x '
              '${media.size.height.toStringAsFixed(0)}',
        ),
        _ValueRow('Safe area', _insets(media.viewPadding)),
        _ValueRow('Posture', data.status.name),
        _ValueRow(
          'Hinge angle',
          angle == null ? 'none' : '${angle.toStringAsFixed(1)} degrees',
        ),
        _ValueRow('Width size class', data.horizontalSizeClass.name),
        _ValueRow('Height size class', data.verticalSizeClass.name),
        _ValueRow('Regions', '${data.regions.length}'),
        for (final ReservedRegion region in data.regions)
          _ValueRow(
            '  ${region.kind.name}',
            '${_rect(region.bounds)}, '
                '${region.isActive ? 'active' : 'inactive'}',
          ),
        _ValueRow(
          'Keep-clear rect',
          keepClear == null ? 'none' : _rect(keepClear),
        ),
        _ValueRow(
          'MediaQuery display features',
          '${MediaQuery.displayFeaturesOf(context).length}',
        ),
        _ValueRow(
          'Engine display features',
          _features(View.of(context).displayFeatures),
        ),
        _ValueRow('Emulating', FoldDivision.isEmulating ? 'yes' : 'no'),
        _ValueRow('Support level', caps.supportLevel.name),
        _ValueRow('Foldable', caps.isFoldable ? 'yes' : 'no'),
        _ValueRow('Hinge API', caps.hingeApiPresent ? 'yes' : 'no'),
        _ValueRow('Region API', caps.regionApiPresent ? 'yes' : 'no'),
        _ValueRow('Angle unit checked', caps.angleUnitVerified ? 'yes' : 'no'),
        _ValueRow('Strategy', caps.strategy),
      ],
    );
  }

  /// The list the engine reports, before the scope rewrites it. It can
  /// disagree with the hinge angle, which is why it is on screen.
  static String _features(List<DisplayFeature> features) {
    if (features.isEmpty) return 'none';
    return features
        .map(
          (DisplayFeature feature) => '${feature.type.name} '
              '${feature.state.name} ${_rect(feature.bounds)}',
        )
        .join('\n');
  }

  static String _insets(EdgeInsets insets) =>
      'l ${insets.left.toStringAsFixed(0)}, t ${insets.top.toStringAsFixed(0)}, '
      'r ${insets.right.toStringAsFixed(0)}, '
      'b ${insets.bottom.toStringAsFixed(0)}';

  static String _rect(Rect rect) =>
      '${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)} '
      '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}';
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              key: ValueKey<String>('value-$label'),
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of buttons spread over the full width, so some of them land on a
/// division that runs down the middle.
class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.scroll, required this.labels});

  final ScrollController scroll;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (final String label in labels)
            ProbeButton(label: label, scroll: scroll),
        ],
      ),
    );
  }
}

/// A button that checks its own place on screen against the keep-clear rect.
class ProbeButton extends StatefulWidget {
  const ProbeButton({super.key, required this.label, required this.scroll});

  final String label;
  final ScrollController scroll;

  @override
  State<ProbeButton> createState() => ProbeButtonState();
}

class ProbeButtonState extends State<ProbeButton> {
  Rect? _keepClear;

  /// Whether the button overlaps the keep-clear rect of a division in force.
  bool inZone = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_measure);
  }

  @override
  void didUpdateWidget(ProbeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_measure);
      widget.scroll.addListener(_measure);
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_measure);
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    // Region bounds are in the coordinates of the window MediaQuery
    // describes, which is the emulated one while a device is emulated.
    // `windowRectOf` answers in the same coordinates. `localToGlobal` would
    // answer in those of the real view.
    final Rect? bounds = FoldDivision.windowRectOf(context);
    if (bounds == null) return;
    final Rect? keepClear = _keepClear;
    final bool next = keepClear != null && keepClear.overlaps(bounds);
    if (next != inZone) {
      setState(() => inZone = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    _keepClear = FoldDivision.keepClearRectOf(context);
    // The window size is a dependency too: a resize moves the button.
    MediaQuery.sizeOf(context);
    // The button has no position until layout is done.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    final ColorScheme colors = Theme.of(context).colorScheme;
    return FilledButton(
      style: inZone
          ? FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            )
          : null,
      onPressed: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                inZone
                    ? 'Button ${widget.label} is in the keep-clear zone'
                    : 'Button ${widget.label} is clear of the division',
              ),
            ),
          );
      },
      child: Text(inZone ? '${widget.label} in zone' : widget.label),
    );
  }
}
