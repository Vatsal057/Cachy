import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/ui/core/theme.dart';

void main() {
  testWidgets('motionEnabled follows MediaQuery.disableAnimations', (tester) async {
    late bool enabled;
    late Duration gated;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        enabled = context.motionEnabled;
        gated = context.gated(Motion.medium);
        return const SizedBox();
      }),
    ));
    expect(enabled, isFalse);
    expect(gated, Duration.zero);
  });

  testWidgets('motion on by default', (tester) async {
    late bool enabled;
    late Duration gated;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(),
      child: Builder(builder: (context) {
        enabled = context.motionEnabled;
        gated = context.gated(Motion.medium);
        return const SizedBox();
      }),
    ));
    expect(enabled, isTrue);
    expect(gated, Motion.medium);
  });
}
