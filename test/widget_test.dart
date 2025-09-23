// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_chat/main.dart';

void main() {
  testWidgets('P2P Chat app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const P2PChatApp());

    // Verify that the main screen loads with the app title.
    expect(find.text('💬 P2P Chat'), findsOneWidget);
    expect(find.text('Connect directly with others'), findsOneWidget);

    // Verify that the input field and button are present.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Continue to Chat'), findsOneWidget);
  });
}
