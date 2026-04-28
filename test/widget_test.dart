// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trideta_v2/main.dart';

void main() {
  testWidgets('App boots up smoke test', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const MyApp());

    // 🚨 The old counter app test logic (expecting '0' and tapping '+') has been removed
    // because Trideta is a full app now, not a counter!

    // Instead, we just do a basic "Smoke Test" to ensure the MaterialApp builds successfully.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
