// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kelivo/utils/restart_widget.dart';
import 'package:kelivo/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RestartWidget(child: MyApp()));

    // Verify that the app builds without crashing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
