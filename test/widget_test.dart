import 'package:flutter_test/flutter_test.dart';

import 'package:ambulance_dashboard/main.dart';

void main() {
  testWidgets('Dashboard renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AmbulanceApp());

    expect(find.text('Rahim Uddin'), findsOneWidget);
    expect(find.text('Quick Dial 999'), findsOneWidget);
  });
}
