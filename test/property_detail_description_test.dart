// Regression test for the "description silently dropped" fix: the website's
// Ezra publisher flow has always sent a free-text description, but
// RentalProperty had no field for it at all — never modeled, never shown
// anywhere in the app. This verifies the fixed round trip: fromJson parses
// it, and PropertyDetailScreen renders it when present, and omits the
// section entirely when absent (no empty header shown for older listings).

import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('RentalProperty.fromJson parses description', () {
    final json = _baseJson()..['description'] = 'דירה מקסימה עם נוף לים.';
    final property = RentalProperty.fromJson(json);
    expect(property.description, 'דירה מקסימה עם נוף לים.');
  });

  test('RentalProperty.fromJson defaults description to empty when absent',
      () {
    final property = RentalProperty.fromJson(_baseJson());
    expect(property.description, '');
  });

  testWidgets('property detail screen shows the description when present',
      (tester) async {
    final property = _property(
      id: 'with-desc',
      description: 'דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.',
    );
    await _pumpDetail(tester, property);

    // Classic's below-the-fold content (specs, enrichment, description,
    // features, owner, reviews, map) renders in a lazy SliverList — off-
    // screen sections aren't built until scrolled into view, so scroll the
    // description into view first (same as the broker-template case below).
    await tester.scrollUntilVisible(
      find.text('דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.'),
        findsOneWidget);
    await _settle(tester);
  });

  testWidgets(
      'property detail screen omits the description section when empty',
      (tester) async {
    final property = _property(id: 'no-desc', description: '');
    await _pumpDetail(tester, property);

    // No description text means no description SECTION HEADER either —
    // otherwise an older listing with no description would show an empty
    // "תיאור" block with nothing under it.
    expect(find.text('תיאור'), findsNothing);
    await _settle(tester);
  });

  // A property with a custom design (hasCustomDesign: true — set whenever a
  // landlord/broker picks a non-classic template) routes to a completely
  // different widget tree (_BrokerPropertyDetailTemplate → _ParitySections),
  // not _ClassicTemplate. The two trees have separate description code —
  // covering only one leaves the other unverified.
  testWidgets(
      'broker/custom-design template also shows the description when present',
      (tester) async {
    final property = _property(
      id: 'with-desc-broker',
      description: 'דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.',
      designTemplate: 'galleryEditorial',
    );
    await _pumpDetail(tester, property);

    // This template renders its below-the-fold sections (including the
    // description) in a lazy SliverList — unlike the Classic template above,
    // off-screen sections aren't built until scrolled into view, so a plain
    // find.text() (no scroll) would find nothing even though the section IS
    // there. Scroll the sliver into view first, matching what a real user
    // would have to do.
    await tester.scrollUntilVisible(
      find.text('דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('דירה מקסימה עם נוף לים, קרובה לתחבורה ציבורית.'),
        findsOneWidget);
    await _settle(tester);
  });
}

Future<void> _pumpDetail(WidgetTester tester, RentalProperty property) async {
  final provider = DatingProvider(
    rentalDataService: _NoopRentalDataService(),
    localStorageService: _MemoryLocalStorageService(),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<DatingProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('he'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PropertyDetailScreen(property: property),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

// Leaving the screen schedules a debounced analytics/persist write (see
// WriteDebouncer) — replace the widget tree to trigger dispose, then let the
// debounce settle, or the test framework fails on a "timer still pending
// after dispose" check that has nothing to do with what a test verifies.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // 11s > the 10s WriteDebouncer window (fake time — instant in practice).
  await tester.pump(const Duration(seconds: 11));
}

RentalProperty _property({
  required String id,
  required String description,
  String designTemplate = '',
}) {
  return RentalProperty(
    id: id,
    url: 'https://example.com/$id',
    price: 5400,
    rooms: 3,
    sizeM2: 78,
    floor: '2',
    totalFloors: '7',
    city: 'נתניה',
    neighborhood: 'מרכז',
    street: 'הרצל',
    streetNumber: 12,
    lat: 32.32,
    lon: 34.85,
    propertyType: 'דירה',
    entryDate: 'גמיש',
    condition: 'טוב',
    ownerName: 'בעל הדירה',
    agencyListing: false,
    description: description,
    designTemplate: designTemplate,
    features: const [],
    // Empty on purpose — a real image URL triggers a real (failing, in a
    // test sandbox with no network) image load whose fallback widget
    // overflows this screen's fixed layout, unrelated to what this test
    // actually checks (the description section).
    media: const [],
  );
}

Map<String, dynamic> _baseJson() => {
      'id': 'json-prop',
      'price': 5000,
      'rooms': 3,
      'sizeM2': 70,
      'city': 'תל אביב',
      'street': 'רוטשילד',
    };

class _NoopRentalDataService extends RentalDataService {
  @override
  Future<PropertyPage> loadFirstPage({String areaId = 'all_israel'}) async =>
      const PropertyPage(items: [], hasMore: false);
}

class _MemoryLocalStorageService extends LocalStorageService {
  Map<String, dynamic>? state;

  @override
  Future<Map<String, dynamic>?> loadAppState() async => state;

  @override
  Future<void> saveAppState(Map<String, dynamic> state,
      {bool syncRemote = true}) async {
    this.state = Map<String, dynamic>.from(state);
  }

  @override
  Future<void> syncRemoteAppState(Map<String, dynamic> state) async {
    this.state = Map<String, dynamic>.from(state);
  }

  @override
  Future<void> clearAppState() async {
    state = null;
  }
}
