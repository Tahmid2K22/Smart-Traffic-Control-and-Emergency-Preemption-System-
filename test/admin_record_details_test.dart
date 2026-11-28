import 'package:e_ambulance/widgets/admin_record_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expands profile fields but never exposes tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminRecordDetails(
            title: 'View all user information',
            data: {
              'email': 'user@example.com',
              'assigned_intersection_id': 'intersection-1',
              'fcmTokens': {'secret-token': 'private'},
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('View all user information'));
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Assigned Intersection Id'), findsOneWidget);
    expect(find.text('intersection-1'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
  });
}
