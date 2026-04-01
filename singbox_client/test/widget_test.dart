import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test without [AppServices.initialize] (path/cookies need full integration).
void main() {
  testWidgets('Riverpod + MaterialApp shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Text('singbox_client')),
        ),
      ),
    );
    expect(find.text('singbox_client'), findsOneWidget);
  });
}
