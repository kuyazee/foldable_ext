import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

import 'support.dart';

/// The iPhone Duo inner display, open like a book.
const Size kInnerSize = Size(951, 669);
const EdgeInsets kInnerSafeArea = EdgeInsets.only(right: 84);

Size get realSize => testView.physicalSize / testView.devicePixelRatio;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// What a widget reads through [EmulatedMediaQuery].
class Read {
  MediaQueryData? media;
  MediaQueryData? window;
  Size? size;
  EdgeInsets? padding;
  EdgeInsets? viewPadding;
  double? pixelRatio;
  Orientation? orientation;
}

Widget reader(Read read) => Builder(
      builder: (BuildContext context) {
        read
          ..media = EmulatedMediaQuery.of(context)
          ..window = EmulatedMediaQuery.windowOf(context)
          ..size = EmulatedMediaQuery.sizeOf(context)
          ..padding = EmulatedMediaQuery.paddingOf(context)
          ..viewPadding = EmulatedMediaQuery.viewPaddingOf(context)
          ..pixelRatio = EmulatedMediaQuery.devicePixelRatioOf(context)
          ..orientation = EmulatedMediaQuery.orientationOf(context);
        return const SizedBox.expand();
      },
    );

void main() {
  late FakeHingePlugin plugin;
  late FoldDivisionAndroid platform;

  setUp(() {
    FoldDivision.config.value = const FoldDivisionConfig(enabled: true);
    plugin = FakeHingePlugin(angle: 95)..install();
    platform = FoldDivisionAndroid();
  });

  tearDown(() async {
    await platform.debugReset();
    plugin.uninstall();
    FoldDivision.config.value = const FoldDivisionConfig();
  });

  Future<void> pumpScope(WidgetTester tester, Widget child) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FoldDivisionScope(
        platform: platform,
        showOverlay: false,
        child: MaterialApp(home: child),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('under the scope the lookups match MediaQuery', (
    WidgetTester tester,
  ) async {
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
    final Read read = Read();
    late MediaQueryData media;
    await pumpScope(
      tester,
      Builder(
        builder: (BuildContext context) {
          media = MediaQuery.of(context);
          return reader(read);
        },
      ),
    );

    expect(media.size, kInnerSize);
    expect(read.media, media);
    expect(read.window!.size, kInnerSize);
    expect(read.size, kInnerSize);
    expect(read.padding, kInnerSafeArea);
    expect(read.viewPadding, kInnerSafeArea);
    expect(read.pixelRatio, media.devicePixelRatio);
    expect(read.orientation, Orientation.landscape);

    await unmount(tester);
  });

  testWidgets('a local MediaQuery change applies, windowOf skips it', (
    WidgetTester tester,
  ) async {
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
    final Read read = Read();
    await pumpScope(
      tester,
      Builder(
        builder: (BuildContext context) => MediaQuery.removePadding(
          context: context,
          removeRight: true,
          child: reader(read),
        ),
      ),
    );

    expect(read.padding, EdgeInsets.zero);
    expect(read.window!.padding, kInnerSafeArea);
    expect(read.window!.viewPadding, kInnerSafeArea);
    expect(read.window!.size, kInnerSize);

    await unmount(tester);
  });

  testWidgets('fromView answers for the emulated window, then the real one', (
    WidgetTester tester,
  ) async {
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
    await pumpScope(tester, const SizedBox.expand());

    final MediaQueryData emulated = EmulatedMediaQuery.fromView(testView);
    expect(emulated.size, kInnerSize);
    expect(emulated.padding, kInnerSafeArea);

    await unmount(tester);
    expect(EmulatedMediaQuery.fromView(testView).size, realSize);
  });

  testWidgets('above the scope the lookups answer for the emulated window', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.view.reset);
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
    final Read read = Read();
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          rebuild = setState;
          return Stack(
            textDirection: TextDirection.ltr,
            children: <Widget>[
              reader(read),
              FoldDivisionScope(
                platform: platform,
                showOverlay: false,
                child: const SizedBox.expand(),
              ),
            ],
          );
        },
      ),
    );
    await settle(tester);
    rebuild(() {});
    await tester.pump();

    expect(read.media!.size, kInnerSize);
    expect(read.window!.size, kInnerSize);
    expect(read.size, kInnerSize);
    expect(read.padding, kInnerSafeArea);

    await unmount(tester);
  });

  testWidgets('with no device emulated the lookups answer the real window', (
    WidgetTester tester,
  ) async {
    FoldDivision.config.value = const FoldDivisionConfig(enabled: false);
    showInnerDisplay(DisplayFeatureState.postureHalfOpened);
    final Read read = Read();
    late MediaQueryData media;
    await pumpScope(
      tester,
      Builder(
        builder: (BuildContext context) {
          media = MediaQuery.of(context);
          return reader(read);
        },
      ),
    );

    expect(read.media, media);
    expect(read.size, realSize);
    expect(read.window!.size, realSize);
    expect(EmulatedMediaQuery.fromView(testView).size, realSize);

    await unmount(tester);
  });
}
