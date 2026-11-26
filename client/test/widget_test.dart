import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:siteledger/main.dart';

void main() {
  testWidgets('starts with demo sign-in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LedgerScreen()));
    expect(find.text('Demo sign-in'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    final field = find.byType(EditableText);
    expect(
      tester.widget<EditableText>(field).controller.text,
      'local-demo-only',
    );
    await tester.enterText(field, 'another-password');
    expect(
      tester.widget<EditableText>(field).controller.text,
      'another-password',
    );
  });
}
