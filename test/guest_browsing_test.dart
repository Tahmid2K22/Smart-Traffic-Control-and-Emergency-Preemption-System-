import 'package:e_ambulance/main.dart';
import 'package:e_ambulance/pages/ambulance_booking_screen.dart';
import 'package:e_ambulance/pages/emergency_services_page.dart';
import 'package:e_ambulance/pages/home_page.dart';
import 'package:e_ambulance/pages/login_page.dart';
import 'package:e_ambulance/pages/nearby_places_page.dart';
import 'package:e_ambulance/pages/notifications_page.dart';
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
    testWidgets('$service is available without login for guests', (
      tester,
    ) async {
      await openGuestHome(tester);
      await tester.ensureVisible(find.text(service));
      await tester.tap(find.text(service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NearbyPlacesPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });
  }

  testWidgets('999 services are available from the dashboard', (tester) async {
    await openGuestHome(tester);
    await tester.ensureVisible(find.text('999 Services'));
    await tester.tap(find.text('999 Services'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EmergencyServicesPage), findsOneWidget);
    expect(find.text('999 Services'), findsWidgets);
  });

  testWidgets('activity and profile tabs are hidden for guests', (
    tester,
  ) async {
    await openGuestHome(tester);
    for (final icon in [Icons.receipt_long_rounded, Icons.person_rounded]) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GButton && widget.icon == icon,
        ),
        findsNothing,
      );
    }
    expect(
      find.byWidgetPredicate(
        (widget) => widget is GButton && widget.icon == Icons.home_rounded,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is GButton && widget.icon == Icons.login_rounded,
      ),
      findsOneWidget,
    );
  });

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
