import 'package:e_ambulance/pages/home_page.dart';
import 'package:e_ambulance/pages/nearby_places_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('home offers a real 15 km scan without seeded hospital cards', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isLocationServiceEnabled') return false;
      throw PlatformException(code: 'UNEXPECTED_LOCATION_CALL');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    // No Firebase init, so browsing must not seed or query sample data.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage(isGuest: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nearby Hospitals'), findsOneWidget);
    expect(find.textContaining('Khulna Medical College'), findsNothing);
    expect(find.textContaining('Dhaka Medical College'), findsNothing);
    expect(find.textContaining('beds'), findsNothing);
    final scan = find.text('Scan hospitals within 15 km');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.byType(NearbyPlacesPage), findsOneWidget);
    expect(find.text('Scan unsuccessful'), findsOneWidget);
    expect(
      find.textContaining('Location services are disabled'),
      findsOneWidget,
    );
    expect(find.textContaining('No hospitals found'), findsNothing);
  });
}
