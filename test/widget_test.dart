import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e_ambulance/pages/login_page.dart';

void main() {
  testWidgets('Login entry points render', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Register a Hospital'), findsOneWidget);
  });

  testWidgets('password visibility can be toggled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    TextField passwordField() =>
        tester.widget<TextField>(find.widgetWithText(TextField, 'Password'));

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
  });
}
