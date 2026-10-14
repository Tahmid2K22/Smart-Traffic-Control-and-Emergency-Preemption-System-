import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e_ambulance/pages/login_page.dart';

void main() {
  testWidgets('Login entry points render', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Register a Hospital'), findsOneWidget);
  });
}
