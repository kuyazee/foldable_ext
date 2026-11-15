import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';
import 'package:foldable_ext_example/main.dart';

/// A half opened fold down the middle of the 800 x 600 test window.
const Rect _division = Rect.fromLTWH(380, 0, 40, 600);

FoldableData _data({required HingeStatus status, required bool active}) {
  return FoldableData(
    capabilities: const FoldableCapabilities(
      supportLevel: FoldableSupportLevel.available,
      isFoldable: true,
      hingeApiPresent: true,
      regionApiPresent: true,
      angleUnitVerified: true,
      strategy: 'test',
    ),
    status: status,
    angleDegrees: status == HingeStatus.partiallyOpen ? 95 : 180,
    regions: <ReservedRegion>[
      ReservedRegion(
        kind: ReservedRegionKind.division,
        bounds: _division,
        isActive: active,
      ),
    ],
    displayFeatures: const <DisplayFeature>[],
  );
}

final FoldableData _halfOpen = _data(
  status: HingeStatus.partiallyOpen,
  active: true,
);
final FoldableData _flat = _data(status: HingeStatus.fullyOpen, active: false);

Future<void> _pump(WidgetTester tester, FoldableData data) async {
  await tester.pumpWidget(
    FoldDivisionExampleApp(debugData: Stream<FoldableData>.value(data)),
  );
  // One frame for the stream event, one for the buttons to measure themselves.
  await tester.pump();
  await tester.pump();
}

RenderFoldDivisionOverlay _overlay(WidgetTester tester) =>
    tester.renderObject<RenderFoldDivisionOverlay>(
      find.byType(FoldDivisionOverlay),
    );

void main() {
  setUp(() {
    FoldDivision.config.value = const FoldDivisionConfig(enabled: true);
  });

  tearDown(() {
    FoldDivision.config.value = const FoldDivisionConfig();
  });

  testWidgets('shows the live values from the base API', (tester) async {
    await _pump(tester, _halfOpen);

    await tester.scrollUntilVisible(find.text('Strategy'), 200);

    expect(find.text('partiallyOpen'), findsOneWidget);
    expect(find.text('95.0 degrees'), findsOneWidget);
    expect(find.text('380,0 40x600, active'), findsOneWidget);
    // The division grown by the default 12 logical pixels on both sides.
    expect(find.text('368,0 64x600'), findsOneWidget);
    expect(find.text('available'), findsOneWidget);
  });

  testWidgets('marks the button that sits on the division', (tester) async {
    await _pump(tester, _halfOpen);

    // Row A B C spreads over the width, so B lands on the centre line.
    expect(find.text('B in zone'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('marks no button while the device lies flat', (tester) async {
    await _pump(tester, _flat);

    expect(find.textContaining('in zone'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('the overlay switch shows and hides the band', (tester) async {
    await _pump(tester, _halfOpen);

    expect(_overlay(tester).bands, hasLength(1));
    expect(_overlay(tester).bands.single.division, _division);

    await tester.tap(find.byKey(const ValueKey<String>('overlay')));
    await tester.pump();

    expect(_overlay(tester).bands, isEmpty);
  });

  testWidgets('the division mode switch changes the config', (tester) async {
    await _pump(tester, _halfOpen);
    expect(FoldDivision.config.value.enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('division-mode')));
    await tester.pump();

    expect(FoldDivision.config.value.enabled, isFalse);
  });

  testWidgets('the window size switch changes the config', (tester) async {
    await _pump(tester, _halfOpen);
    expect(FoldDivision.config.value.matchWindowSize, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('match-window-size')));
    await tester.pump();

    expect(FoldDivision.config.value.matchWindowSize, isFalse);
  });

  testWidgets('shows the window MediaQuery describes', (tester) async {
    await _pump(tester, _halfOpen);

    await tester.scrollUntilVisible(find.text('Safe area'), 200);

    // A stream of test data is not emulated: the real 800 x 600 test window.
    expect(find.text('none'), findsNWidgets(3));
    expect(find.text('800 x 600'), findsOneWidget);
    expect(find.text('l 0, t 0, r 0, b 0'), findsOneWidget);
  });

  testWidgets('the activation control changes the config', (tester) async {
    await _pump(tester, _halfOpen);
    expect(
      FoldDivision.config.value.activation,
      DivisionActivation.followPosture,
    );

    await tester.tap(find.text('Always'));
    await tester.pump();

    expect(FoldDivision.config.value.activation, DivisionActivation.always);
  });

  testWidgets('runs without the plugin on a host with no fold', (tester) async {
    await tester.pumpWidget(const FoldDivisionExampleApp());
    await tester.pump();

    expect(find.text('Division mode'), findsWidgets);
    expect(find.textContaining('in zone'), findsNothing);
  });
}
