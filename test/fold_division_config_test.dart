import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable_ext/foldable_ext.dart';

void main() {
  test('defaults', () {
    const FoldDivisionConfig config = FoldDivisionConfig();
    // Tests run in debug mode, where kDebugMode is true.
    expect(config.enabled, isTrue);
    expect(config.divisionExtent, 40);
    expect(config.margins, const EdgeInsets.symmetric(horizontal: 12));
    expect(config.activation, DivisionActivation.followPosture);
  });

  test('copyWith replaces only the given fields', () {
    const FoldDivisionConfig config = FoldDivisionConfig(enabled: true);
    final FoldDivisionConfig next = config.copyWith(
      divisionExtent: 24,
      activation: DivisionActivation.always,
    );
    expect(next.enabled, isTrue);
    expect(next.divisionExtent, 24);
    expect(next.margins, config.margins);
    expect(next.activation, DivisionActivation.always);
    expect(config.copyWith(), config);
  });

  test('equality and hashCode follow the fields', () {
    const FoldDivisionConfig a = FoldDivisionConfig(enabled: true);
    const FoldDivisionConfig b = FoldDivisionConfig(enabled: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(a.copyWith(enabled: false)));
    expect(a, isNot(a.copyWith(divisionExtent: 41)));
    expect(a, isNot(a.copyWith(margins: EdgeInsets.zero)));
    expect(a, isNot(a.copyWith(activation: DivisionActivation.always)));
  });

  test('margins stay as written for an upright division', () {
    const FoldDivisionConfig config = FoldDivisionConfig(
      margins: EdgeInsets.fromLTRB(10, 1, 14, 2),
    );
    const Rect division = Rect.fromLTWH(316.5, 0, 40, 841);
    expect(config.marginsFor(division), config.margins);
    expect(
      config.keepClearRect(division),
      const Rect.fromLTRB(306.5, -1, 370.5, 843),
    );
  });

  test('margins are transposed for a division lying flat', () {
    const FoldDivisionConfig config = FoldDivisionConfig(
      margins: EdgeInsets.fromLTRB(10, 1, 14, 2),
    );
    const Rect division = Rect.fromLTWH(0, 400.5, 673, 40);
    expect(
      config.marginsFor(division),
      const EdgeInsets.fromLTRB(1, 10, 2, 14),
    );
    expect(
      config.keepClearRect(division),
      const Rect.fromLTRB(-1, 390.5, 675, 454.5),
    );
  });

  test('FoldDivision.enable and disable flip the shared config', () {
    final FoldDivisionConfig before = FoldDivision.config.value;
    addTearDown(() => FoldDivision.config.value = before);

    FoldDivision.disable();
    expect(FoldDivision.config.value.enabled, isFalse);
    expect(FoldDivision.isEmulating, isFalse);
    FoldDivision.enable();
    expect(FoldDivision.config.value.enabled, isTrue);
    // The default platform is the iOS channel one, so nothing is emulated.
    expect(FoldDivision.isEmulating, isFalse);
  });
}
