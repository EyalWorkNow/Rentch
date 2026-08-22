import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/nearby_jobs_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the "עבודה באיזור" card on the property detail screen: it renders
// the title + search bar + board buttons, pre-fills from the seeker's
// occupation, autocompletes Hebrew job titles, and hides without a city.
void main() {
  Widget host(Widget child) => MaterialApp(
        locale: const Locale('he'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('renders title, hint with city and search bar', (tester) async {
    await tester.pumpWidget(host(const NearbyJobsCard(
        city: 'תל אביב', lat: 32.0853, lon: 34.7818)));
    await tester.pumpAndSettle();

    expect(find.text('עבודה באיזור'), findsOneWidget);
    expect(find.textContaining('תל אביב'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // The old external-board buttons are gone — results render in-app.
    expect(find.text('AllJobs'), findsNothing);
    expect(find.text('LinkedIn'), findsNothing);
    // Widget tests block real HTTP → the pre-search fails soft into the
    // empty state rather than crashing or hanging.
    expect(find.textContaining('לא נמצאו משרות'), findsOneWidget);
  });

  testWidgets('seeker occupation pre-fills the search bar', (tester) async {
    await tester.pumpWidget(host(const NearbyJobsCard(
        city: 'חיפה', lat: 32.79, lon: 34.99, occupation: 'hightech')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'מפתח תוכנה');
  });

  testWidgets('typing shows matching autocomplete suggestions',
      (tester) async {
    await tester.pumpWidget(host(const NearbyJobsCard(
        city: 'תל אביב', lat: 32.0853, lon: 34.7818)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'מהנדס');
    await tester.pumpAndSettle();
    // Several engineering flavours contain the substring.
    expect(find.text('מהנדס תוכנה'), findsOneWidget);
    expect(find.text('מהנדס אזרחי'), findsOneWidget);
    // Selecting one puts it in the field.
    await tester.tap(find.text('מהנדס אזרחי'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'מהנדס אזרחי');
  });

  testWidgets('hides entirely when the listing has no city', (tester) async {
    await tester.pumpWidget(
        host(const NearbyJobsCard(city: '', lat: 0, lon: 0)));
    await tester.pumpAndSettle();
    expect(find.text('עבודה באיזור'), findsNothing);
  });
}
