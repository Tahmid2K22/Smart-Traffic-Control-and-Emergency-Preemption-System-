import 'package:e_ambulance/main.dart';
import 'package:e_ambulance/pages/ambulance_booking_screen.dart';
import 'package:e_ambulance/pages/home_page.dart';
import 'package:e_ambulance/pages/login_page.dart';
import 'package:e_ambulance/pages/nearby_places_page.dart';
import 'package:e_ambulance/pages/notifications_page.dart';
import 'package:e_ambulance/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> openGuestHome(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DashboardPage(isGuest: true)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guests see the home page without initializing Firebase', (
    tester,
  ) async {
    await openGuestHome(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Hello, Guest!'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('booking opens login and cancellation returns to guest home', (
    tester,
  ) async {
    await openGuestHome(tester);
    await tester.ensureVisible(find.text('Ambulance'));
    await tester.tap(find.text('Ambulance'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AmbulanceBookingScreen), findsNothing);

    await tester.ensureVisible(find.text('Continue browsing'));
    await tester.tap(find.text('Continue browsing'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('Hello, Guest!'), findsOneWidget);
  });

  for (final service in ['Pharmacy', 'Hospitals']) {
    testWidgets('$service access requires login for guests', (tester) async {
      await openGuestHome(tester);
      await tester.ensureVisible(find.text(service));
      await tester.tap(find.text(service));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(NearbyPlacesPage), findsNothing);
    });
  }

  for (final icon in [Icons.receipt_long_rounded, Icons.person_rounded]) {
    testWidgets('protected tab $icon requires login', (tester) async {
      await openGuestHome(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is GButton && widget.icon == icon,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(ProfilePage), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Hello, Guest!'), findsOneWidget);
    });
  }

  testWidgets('guest notifications open login, not account data', (
    tester,
  ) async {
    await openGuestHome(tester);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(NotificationsPage), findsNothing);
  });
}
