import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:proxysmith/main.dart';
import 'package:proxysmith/models/app_settings.dart';
import 'package:proxysmith/models/config_source.dart';

void main() {
  testWidgets('main screen renders and meets Android tap-target guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const ProxySmithApp(initialSettings: AppSettings.defaults),
    );
    await tester.pumpAndSettle();

    expect(find.text('ProxySmith'), findsOneWidget);
    expect(find.text('Run pipeline'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('custom subscription URL shows an inline validation error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProxySmithApp(initialSettings: AppSettings.defaults),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<ConfigSource>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom URL').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run pipeline'));
    await tester.pump();

    expect(find.text('Enter a valid HTTP or HTTPS URL'), findsOneWidget);
  });

  testWidgets('options menu exposes the privacy policy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProxySmithApp(initialSettings: AppSettings.defaults),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
  });
}
