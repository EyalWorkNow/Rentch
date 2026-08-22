import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/core/matching/ranked_lead.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:dating_app/data/repositories/property_repository.dart';
import 'package:dating_app/data/repositories/review_repository.dart';
import 'package:dating_app/data/repositories/user_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/assistant/erik_chat_screen.dart';
import 'package:dating_app/presentation/screens/explore_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('UNIFY — swipe deck is now stat-area aware: high-SES block outranks a '
      'low-SES block in the SAME city', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
    try {
      // Two identical Tel Aviv flats, differing ONLY by block: central TLV (CBS
      // SES ~9) vs Shapira (SES ~2). The deck's legacy _locationScore is a binary
      // in-city check blind to this; the gov-data neighbourhood nudge fixes it.
      final central = _property(id: 'central', lat: 32.0700, lon: 34.7750);
      final shapira = _property(id: 'shapira', lat: 32.0545, lon: 34.7790);
      final provider = DatingProvider(
        rentalDataService: _FakeRentalDataService([
          central,
          shapira,
          _property(id: 'm1', price: 5900),
          _property(id: 'm2', price: 6100),
        ]),
        localStorageService: _MemoryLocalStorageService(),
      );
      await provider.initialize();
      await provider.updateFilters(const SearchFilters(
        query: '',
        minBudget: 600,
        maxBudget: 8000,
        minRooms: 0,
        maxRooms: 10,
        areaId: 'all_israel',
        requiredFeatures: {'parking'},
        preferredFeatures: <String>{},
        minSizeM2: 0,
        maxSizeM2: 200,
        propertyTypes: <String>{},
        preferredPropertyTypes: <String>{},
        conditions: <String>{},
        preferredConditions: <String>{},
        listingSource: ListingSourceFilter.any,
        minFloor: 0,
        moveInFilter: MoveInFilter.any,
        sortBy: SearchSortOption.bestMatch,
        includeUnknownPriceListings: false,
        customAreaPolygon: <LatLng>[],
        city: 'Tel Aviv',
        transactionType: TransactionTypeFilter.rent,
      ));
      expect(provider.matchScore(central),
          greaterThan(provider.matchScore(shapira)),
          reason: 'block-level CBS SES must reach the swipe deck score');
      // CRUSH: pathological coords with gov data loaded must stay bounded (the
      // neighbourhood delta must never crash or push the score out of range).
      final bad = provider.matchScore(
          _property(id: 'bad', lat: double.nan, lon: double.infinity));
      expect(bad, inInclusiveRange(0, 100));
      provider.dispose();
    } finally {
      // Restore the no-gov state so the other (gov-less) deck tests are unaffected.
      GovData.instance.resetForTest();
    }
  });

  test('best match ranks soft near-misses by value, fit, and confidence',
      () async {
    final excellent = _property(
      id: 'excellent-near-budget',
      price: 6250,
      rooms: 3,
      sizeM2: 78,
      street: 'Market',
      streetNumber: 12,
      features: const ['parking', 'balcony', 'elevator'],
      mediaCount: 4,
      ownerName: 'Owner',
      url: 'https://example.com/excellent',
      entryDate: '2026-06-10',
    );
    final cheapButWeak = _property(
      id: 'cheap-but-weak',
      price: 5600,
      rooms: 3,
      sizeM2: 63,
      street: '',
      streetNumber: -1,
      features: const ['parking'],
      mediaCount: 0,
      ownerName: '',
      entryDate: '2026-06-12',
    );
    final missingDealBreaker = _property(
      id: 'missing-deal-breaker',
      price: 5200,
      rooms: 3,
      sizeM2: 70,
      features: const ['balcony', 'elevator'],
      mediaCount: 3,
      entryDate: '2026-06-08',
    );

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        excellent,
        cheapButWeak,
        missingDealBreaker,
        _property(id: 'market-1', price: 5900, sizeM2: 72),
        _property(id: 'market-2', price: 6100, sizeM2: 76),
        _property(id: 'market-3', price: 6400, sizeM2: 80),
        _property(id: 'market-4', price: 6600, sizeM2: 82),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const filters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 6000,
      minRooms: 3,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: {'parking'},
      preferredFeatures: {'balcony', 'elevator'},
      minSizeM2: 60,
      maxSizeM2: 90,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.within30Days,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: 'Tel Aviv',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(filters);

    final rankedIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(rankedIds, contains(excellent.id));
    expect(rankedIds, isNot(contains(missingDealBreaker.id)));
    expect(
      rankedIds.indexOf(excellent.id),
      lessThan(rankedIds.indexOf(cheapButWeak.id)),
    );
    expect(
      provider.matchScore(excellent),
      greaterThan(provider.matchScore(cheapButWeak)),
    );
    expect(provider.matchScore(missingDealBreaker), 0);

    await provider.updateFilters(
      filters.copyWith(sortBy: SearchSortOption.priceLowToHigh),
    );

    expect(
      provider.filteredProperties.map((p) => p.id),
      isNot(contains(excellent.id)),
    );

    provider.dispose();
  });

  test('strictMaxBudget hard-caps the deck; soft budget tolerates near-misses',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _property(id: 'in-budget', price: 3900, sizeM2: 70),
        _property(id: 'over-budget', price: 4700, sizeM2: 72),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    const base = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 4000,
      minRooms: 0,
      maxRooms: 10,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 200,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
    );

    // Soft (slider) budget: best-match tolerates a ₪4,700 near-miss.
    await provider.updateFilters(base);
    expect(provider.filteredProperties.map((p) => p.id),
        contains('over-budget'));

    // Strict (typed "עד 4000"): the ₪4,700 flat must NOT appear.
    await provider.updateFilters(base.copyWith(strictMaxBudget: true));
    final ids = provider.filteredProperties.map((p) => p.id).toList();
    expect(ids, contains('in-budget'));
    expect(ids, isNot(contains('over-budget')));

    provider.dispose();
  });

  test('listings without a real price stay hidden until explicitly included',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _property(id: 'priced', price: 6200, sizeM2: 78),
        _property(id: 'missing-price', price: 0, sizeM2: 78),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const filters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 7000,
      minRooms: 0,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 120,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(filters);
    expect(
      provider.filteredProperties.map((p) => p.id),
      isNot(contains('missing-price')),
    );

    await provider.updateFilters(
      filters.copyWith(includeUnknownPriceListings: true),
    );
    expect(
      provider.filteredProperties.map((p) => p.id),
      contains('missing-price'),
    );

    provider.dispose();
  });

  test('verified camera-video listings receive a higher algorithm score',
      () async {
    final base = _property(
      id: 'camera-base',
      price: 12000,
      rooms: 1,
      sizeM2: 25,
      street: '',
      streetNumber: -1,
      features: const [],
      mediaCount: 0,
      ownerName: '',
      url: '',
      entryDate: '2027-12-15',
    );
    final verified = _property(
      id: 'camera-verified',
      price: 12000,
      rooms: 1,
      sizeM2: 25,
      street: '',
      streetNumber: -1,
      features: const [],
      mediaCount: 0,
      ownerName: '',
      url: '',
      entryDate: '2027-12-15',
      verification: PropertyVerification.cameraVideo(
        videoUrl: 'https://example.com/verification.mp4',
        capturedAt: DateTime.utc(2026, 6, 4, 8),
      ),
    );
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([base, verified]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    expect(verified.isVerifiedListing, isTrue);
    expect(
        provider.matchScore(verified), greaterThan(provider.matchScore(base)));

    provider.dispose();
  });

  test('listing source and move-in support preferred and required states',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _property(
          id: 'private-fast',
          agencyListing: false,
          entryDate: '2026-06-12',
          price: 6200,
        ),
        _property(
          id: 'agency-fast',
          agencyListing: true,
          entryDate: '2026-06-11',
          price: 6200,
        ),
        _property(
          id: 'private-slow',
          agencyListing: false,
          // Relative date: a fixed '2026-09-20' silently crossed INTO the
          // within-30-days window as real time advanced, flipping the test.
          entryDate: DateTime.now()
              .add(const Duration(days: 90))
              .toIso8601String()
              .substring(0, 10),
          price: 6200,
        ),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    await provider.initialize();

    const preferredFilters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 7000,
      minRooms: 0,
      maxRooms: 4,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 120,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      preferredListingSources: {ListingSourceFilter.privateOnly},
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      preferredMoveInFilters: {MoveInFilter.within30Days},
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.rent,
    );

    await provider.updateFilters(preferredFilters);
    final preferredIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(preferredIds, contains('agency-fast'));
    expect(
      preferredIds.indexOf('private-fast'),
      lessThan(preferredIds.indexOf('agency-fast')),
    );

    await provider.updateFilters(
      preferredFilters.copyWith(
        requiredListingSources: {ListingSourceFilter.privateOnly},
        preferredListingSources: const <ListingSourceFilter>{},
        requiredMoveInFilters: {MoveInFilter.within30Days},
        preferredMoveInFilters: const <MoveInFilter>{},
      ),
    );

    final requiredIds = provider.filteredProperties.map((p) => p.id).toList();
    expect(requiredIds, contains('private-fast'));
    expect(requiredIds, isNot(contains('agency-fast')));
    expect(requiredIds, isNot(contains('private-slow')));

    provider.dispose();
  });

  test('landlord sees only owned local properties and leads', () async {
    final ownLead = _property(id: 'own-lead', ownerUserId: 'owner-1');
    final ownVisible = _property(id: 'own-visible', ownerUserId: 'owner-1');
    final guestDemo = _property(
      id: 'demo-prop-1',
      ownerUserId: 'guest_landlord',
      ownerName: 'Guest Demo',
    );
    final storage = _MemoryLocalStorageService()
      ..state = {
        'schema': 'rental_match_v2',
        'tenantProfile': const TenantProfile(
          id: 'owner-1',
          name: 'Owner One',
          bio: '',
          photoUrls: <String>[],
          budgetMax: 6000,
          desiredRooms: 3,
          moveInWindow: 'within 30 days',
          importantDetails: <String>[],
        ).toJson(),
        'filters': const <String, dynamic>{},
        'likedPropertyIds': [ownLead.id, guestDemo.id],
        'passedPropertyIds': const <String>[],
        'ownerAcceptedPropertyIds': const <String>[],
        'ownerRejectedPropertyIds': const <String>[],
        'matches': [
          RentalMatch(
            id: 'guest-match',
            propertyId: guestDemo.id,
            createdAt: DateTime.utc(2026, 6, 8),
            messages: const [],
            contractSent: false,
            ownerSigned: false,
            tenantSigned: false,
          ).toJson(),
        ],
        'tenantReviews': const <Map<String, dynamic>>[],
        'propertyReviews': const <String, dynamic>{},
        'customProperties': [
          ownLead.toJson(),
          ownVisible.toJson(),
          guestDemo.toJson(),
        ],
        'userRole': 'landlord',
        'isGuestMode': false,
        'hasActiveSession': true,
        'roleExplicitlyChosen': true,
        'savedPropertyIds': const <String>[],
        'blockedOwnerNames': const <String>[],
        'reportedPropertyIds': const <String>[],
        'propertySignalOverrides': const <String, dynamic>{},
        'lastSeenMatchCount': 0,
      };
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: storage,
    );

    await provider.initialize();

    expect(provider.myProperties.map((p) => p.id), [ownLead.id, ownVisible.id]);
    expect(provider.ownerLeads.map((p) => p.id), [ownLead.id]);
    expect(provider.matches.map((m) => m.id), isNot(contains('guest-match')));
    expect(
      provider.filteredProperties.map((p) => p.id),
      contains(ownVisible.id),
    );
    expect(
      provider.filteredProperties.map((p) => p.id),
      isNot(contains(guestDemo.id)),
    );

    provider.dispose();
  });

  // Regression: the candidates deck card (_FactGrid) used a Row with
  // CrossAxisAlignment.stretch inside a vertical scroll view, which forced an
  // infinite height and blanked the whole deck at runtime (analyze/unit tests
  // passed — only layout throws). Rendering the real ExploreScreen here fails if
  // that (or any layout crash) comes back.
  testWidgets('candidates deck renders a lead card without a layout crash',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ownLead = _property(id: 'own-lead', ownerUserId: 'owner-1');
    final storage = _MemoryLocalStorageService()
      ..state = {
        'schema': 'rental_match_v2',
        'tenantProfile': const TenantProfile(
          id: 'owner-1',
          name: 'Owner One',
          bio: '',
          photoUrls: <String>[],
          budgetMax: 6000,
          desiredRooms: 3,
          moveInWindow: 'within 30 days',
          importantDetails: <String>[],
        ).toJson(),
        'likedPropertyIds': [ownLead.id],
        'customProperties': [ownLead.toJson()],
        'userRole': 'landlord',
        'hasActiveSession': true,
        'roleExplicitlyChosen': true,
      };
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: storage,
    );
    await provider.initialize();
    expect(provider.ownerLeads, isNotEmpty,
        reason: 'precondition: the landlord has a candidate lead');

    await tester.pumpWidget(
      ChangeNotifierProvider<DatingProvider>.value(
        value: provider,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ExploreScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the deck must lay out without an infinite-height crash');
    expect(find.byType(CardSwiper), findsOneWidget,
        reason: 'the candidate card deck must render');

    // Unmount, then advance the clock past any pending fail-soft delayed
    // timers (throttled refreshes) so the binding's no-pending-timers teardown
    // check is satisfied.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    provider.dispose();
  });

  // Phase-0: the landlord lead ranking must PREFER the server's two-sided score
  // (/match/leads) for the exact representative liker, and fall back to the local
  // heuristic when the server doesn't cover that tenant.
  test('leadFitScore prefers the server ranked-lead score, keyed by tenant',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final owned = _property(id: 'p1', ownerUserId: 'owner-1');
    final storage = _MemoryLocalStorageService()
      ..state = {
        'schema': 'rental_match_v2',
        'tenantProfile': const TenantProfile(
          id: 'owner-1',
          name: 'Owner',
          bio: '',
          photoUrls: <String>[],
          budgetMax: 6000,
          desiredRooms: 3,
          moveInWindow: 'flexible',
          importantDetails: <String>[],
        ).toJson(),
        'customProperties': [owned.toJson()],
        'userRole': 'landlord',
        'hasActiveSession': true,
        'roleExplicitlyChosen': true,
      };
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: storage,
    );
    await provider.initialize();

    // A real cross-user like from tenant 't-9' → the deck's representative liker.
    provider.debugSetIncomingLikes({
      'p1': const [
        PropertyLike(
            propertyId: 'p1',
            tenantId: 't-9',
            tenantName: 'דן',
            budgetMax: 8000),
      ],
    });
    expect(provider.ownerLeads.map((p) => p.id), contains('p1'),
        reason: 'precondition: the liked property is a lead');
    final localScore = provider.leadFitScore(owned);

    // Server score for the SAME tenant → must win.
    provider.debugApplyRankedLeads(const [
      RankedLead(
          tenantId: 't-9',
          tenantName: 'דן',
          propertyId: 'p1',
          propertyTitle: '',
          score: 88,
          excluded: false,
          reasons: ['בעל הדירה מחפש בדיוק שוכר כמוך'],
          conflicts: []),
    ]);
    expect(provider.leadFitScore(owned), 88.0,
        reason: 'the server two-sided score must be preferred');
    expect(provider.rankedLeadReasonFor(owned),
        'בעל הדירה מחפש בדיוק שוכר כמוך');

    // Server score for a DIFFERENT tenant → key mismatch → fall back to local.
    provider.debugApplyRankedLeads(const [
      RankedLead(
          tenantId: 'someone-else',
          tenantName: 'x',
          propertyId: 'p1',
          propertyTitle: '',
          score: 5,
          excluded: true,
          reasons: [],
          conflicts: []),
    ]);
    expect(provider.leadFitScore(owned), localScore,
        reason: 'a non-matching tenant key must not override the local score');
    expect(provider.rankedLeadReasonFor(owned), isNull);

    provider.dispose();
  });

  // Phase-0: when several tenants like the same property, the deck must surface
  // the BEST-fitting one — by server score when present, else budget fit — not
  // an arbitrary first, and expose how many others are interested.
  test('bestLikerFor picks the strongest candidate; counts the rest', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final owned = _property(id: 'p1', ownerUserId: 'owner-1', price: 6000);
    final storage = _MemoryLocalStorageService()
      ..state = {
        'schema': 'rental_match_v2',
        'tenantProfile': const TenantProfile(
          id: 'owner-1',
          name: 'Owner',
          bio: '',
          photoUrls: <String>[],
          budgetMax: 6000,
          desiredRooms: 3,
          moveInWindow: 'flexible',
          importantDetails: <String>[],
        ).toJson(),
        'customProperties': [owned.toJson()],
        'userRole': 'landlord',
        'hasActiveSession': true,
        'roleExplicitlyChosen': true,
      };
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: storage,
    );
    await provider.initialize();

    // Two interested tenants: t-low can barely afford, t-high has headroom.
    provider.debugSetIncomingLikes({
      'p1': const [
        PropertyLike(
            propertyId: 'p1', tenantId: 't-low', tenantName: 'א', budgetMax: 4000),
        PropertyLike(
            propertyId: 'p1', tenantId: 't-high', tenantName: 'ב', budgetMax: 9000),
      ],
    });
    expect(provider.additionalInterestedCount('p1'), 1);
    // No server data → local budget fit → the affording tenant wins.
    expect(provider.bestLikerFor(owned)?.tenantId, 't-high');

    // Server says t-low is actually the best fit (tags/deal-breakers) → it wins.
    provider.debugApplyRankedLeads(const [
      RankedLead(
          tenantId: 't-low',
          tenantName: 'א',
          propertyId: 'p1',
          propertyTitle: '',
          score: 95,
          excluded: false,
          reasons: [],
          conflicts: []),
      RankedLead(
          tenantId: 't-high',
          tenantName: 'ב',
          propertyId: 'p1',
          propertyTitle: '',
          score: 40,
          excluded: false,
          reasons: [],
          conflicts: []),
    ]);
    expect(provider.bestLikerFor(owned)?.tenantId, 't-low',
        reason: 'server two-sided score should override the local proxy');
    expect(provider.leadFitScore(owned), 95.0);

    provider.dispose();
  });

  // Erik's new chat surface must lay out (dark canvas, bubbles, starter chips,
  // input bar) without a crash and show the welcome + starters at rest.
  testWidgets('Erik chat screen renders the welcome + starter chips',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = _MemoryLocalStorageService()
      ..state = {
        'schema': 'rental_match_v2',
        'userRole': 'landlord',
        'hasActiveSession': true,
        'roleExplicitlyChosen': true,
      };
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: storage,
    );
    await provider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider<DatingProvider>.value(
        value: provider,
        child: const MaterialApp(
          locale: Locale('he'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ErikChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the chat surface must lay out without a crash');
    expect(find.text('עזרא · העוזר האישי'), findsOneWidget,
        reason: 'the identity header must render');
    expect(find.text('אני רוצה לפרסם דירה חדשה'), findsOneWidget,
        reason: 'starter chips must render on the welcome state');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    provider.dispose();
  });

  test('landlord-added property is owned locally and remains discoverable',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(const []),
      localStorageService: _MemoryLocalStorageService(),
      // addLandlordProperty now awaits the remote write and rolls back the
      // optimistic local add on a genuine failure (see PropertyRepository.
      // isRealFailure) — without this fake, the real PropertyRepository would
      // attempt an actual network call in the test environment and fail.
      propertyRepository: _FakePropertyRepository(),
    );

    await provider.initialize();
    await provider.setUserRole('landlord');
    await provider.addLandlordProperty(_property(id: 'new-upload'));

    final ownProperty = provider.myProperties.single;
    expect(ownProperty.id, 'new-upload');
    expect(ownProperty.ownerUserId, 'tenant-test');
    expect(
      provider.filteredProperties.map((p) => p.id),
      contains('new-upload'),
    );
    expect(
      provider.previewFilteredProperties(provider.filters).map((p) => p.id),
      contains('new-upload'),
    );

    provider.dispose();
  });


  test('matching algorithm factors in tag compatibility and completeness bonuses', () async {
    final property = _property(
      id: 'prop-tag-compat',
      ownerUserId: 'landlord-test-id',
      price: 6000,
    );

    final userRepository = _FakeUserRepository();
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([property]),
      localStorageService: _MemoryLocalStorageService(),
      userRepository: userRepository,
    );

    await provider.initialize();

    const filters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 2000000000,
      minRooms: 4.0,
      maxRooms: 10.0,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: {'balcony'},
      minSizeM2: 0,
      maxSizeM2: 1000000,
      propertyTypes: <String>{},
      preferredPropertyTypes: {'Duplex'},
      conditions: <String>{},
      preferredConditions: {'New'},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: [],
      city: '',
      transactionType: TransactionTypeFilter.rent,
    );
    await provider.updateFilters(filters);

    // 1. Initially, no tenant profile and no cached landlord profile -> tag compatibility score = 0
    final baseScore = provider.matchScore(property);

    // 2. Set tenant profile with tags
    const tenantProfile = TenantProfile(
      id: 'tenant-test-id',
      name: 'Tenant Name',
      bio: 'Bio text',
      photoUrls: [],
      budgetMax: 7000,
      desiredRooms: 3.0,
      moveInWindow: 'גמיש',
      // Catalog tenant tags resolving to matchKeys: pets_allowed, no_smoking, parking
      importantDetails: ['מתאים לחיות מחמד', 'לא מעשן/ת', 'חייב/ת חניה'], // 3 tags
    );
    await provider.updateTenantProfile(tenantProfile);

    // Landlord profile in repository
    const landlordProfile = TenantProfile(
      id: 'landlord-test-id',
      name: 'Landlord Name',
      bio: 'Landlord bio',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: '',
      // Catalog landlord tags resolving to the same matchKeys: pets_allowed, no_smoking, parking
      importantDetails: ['מאפשר בעלי חיים', 'מעדיף שוכרים לא מעשנים', 'יש חניה'], // 3 tags
    );
    userRepository.profiles['landlord-test-id'] = landlordProfile;

    // Trigger loading of landlord profile into cache.
    expect(provider.getCachedProfile('landlord-test-id'), isNull);
    
    // Wait for the async repository fetch to complete and trigger listeners
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Now, the landlord profile is cached
    expect(provider.getCachedProfile('landlord-test-id'), equals(landlordProfile));

    // Calculate score again. Tenant & landlord tags share 3 matchKeys:
    //   - pets_allowed (מתאים לחיות מחמד ↔ מאפשר בעלי חיים) -> +5
    //   - no_smoking   (לא מעשן/ת ↔ מעדיף שוכרים לא מעשנים) -> +5
    //   - parking      (חייב/ת חניה ↔ יש חניה)              -> +5
    // Completeness bonus (both profiles have 3+ tags) -> +5
    // Total compatibility bonus = 5 + 5 + 5 + 5 = 20 points. With the unified
    // engine core, adding the profile ALSO lifts the base relevance a little
    // (the profile's budget/persona reweight the ranker), so the gap is the 20-pt
    // tag bonus plus a small profile-driven relevance lift — not exactly 20.
    final scoreWithTags = provider.matchScore(property);
    expect(scoreWithTags - baseScore, inInclusiveRange(20, 30),
        reason: 'the ~20-pt tag/completeness bonus must be applied (plus a small '
            'profile-relevance lift)');

    provider.dispose();
  });

  test(
      'persona: a CRITICAL deal-breaker miss scores far below a hit, and an '
      'IMPORTANT match boosts the score', () async {
    // Two listings identical except for their features. No landlord profile is
    // cached for either, so the tenant's own persona is scored against the
    // property's own attributes.
    final withParking = _property(
      id: 'with-parking',
      features: const ['parking', 'elevator'],
    );
    final withoutParking = _property(
      id: 'without-parking',
      features: const ['elevator'], // fails the CRITICAL parking deal-breaker
    );
    final withElevator = _property(
      id: 'with-elevator',
      features: const ['parking', 'elevator'],
    );
    final withoutElevator = _property(
      id: 'without-elevator',
      features: const ['parking'], // meets CRITICAL, misses IMPORTANT elevator
    );

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService(
        [withParking, withoutParking, withElevator, withoutElevator],
      ),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    // חייב/ת חניה → parking (CRITICAL); מעלית → elevator (IMPORTANT).
    const profile = TenantProfile(
      id: 'tenant-persona',
      name: 'Persona',
      bio: '',
      photoUrls: [],
      budgetMax: 7000,
      desiredRooms: 3,
      moveInWindow: 'גמיש',
      importantDetails: ['חייב/ת חניה', 'מעלית'],
      dealBreakers: ['חייב/ת חניה'], // parking is non-negotiable
    );
    await provider.updateTenantProfile(profile);

    final critHit = provider.matchScore(withParking);
    final critMiss = provider.matchScore(withoutParking);

    // A property that FAILS the critical deal-breaker scores clearly lower than
    // one that meets it — by a wide, gating margin.
    expect(critMiss, lessThan(critHit));
    expect(critHit - critMiss, greaterThanOrEqualTo(30),
        reason: 'an unmet CRITICAL must heavily sink the match %');

    // An IMPORTANT match (elevator) raises the score above an otherwise-equal
    // property that lacks it.
    final impHit = provider.matchScore(withElevator);
    final impMiss = provider.matchScore(withoutElevator);
    expect(impHit, greaterThan(impMiss),
        reason: 'an IMPORTANT match must boost the score');

    provider.dispose();
  });

  test('displayed % does not saturate: it moves with how many IMPORTANT '
      'details the property satisfies', () async {
    // Identical listings except for their features. With the old un-compressed
    // base every one of these clamped to 100 and the IMPORTANT boost was eaten
    // by the ceiling, so the badge was a meaningless "100% for everything".
    final both = _property(id: 'both', features: const ['parking', 'elevator']);
    final one = _property(id: 'one', features: const ['parking']);
    final none = _property(id: 'none', features: const []);

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([both, one, none]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    const profile = TenantProfile(
      id: 'tenant-imp',
      name: 'Persona',
      bio: '',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: 'גמיש',
      // חייב/ת חניה → parking, מעלית → elevator, both IMPORTANT (not critical).
      importantDetails: ['חייב/ת חניה', 'מעלית'],
    );
    await provider.updateTenantProfile(profile);

    final sBoth = provider.matchScore(both);
    final sOne = provider.matchScore(one);
    final sNone = provider.matchScore(none);

    // Strictly monotonic in the number of satisfied IMPORTANT details.
    expect(sBoth, greaterThan(sOne));
    expect(sOne, greaterThan(sNone));
    // And the score genuinely varies — it is NOT pinned at 100 for everything.
    expect(sNone, lessThan(100));
    expect(sBoth - sNone, greaterThanOrEqualTo(10),
        reason: 'the IMPORTANT boost must be visible, not absorbed by a clamp');

    provider.dispose();
  });

  test('profile budget is honoured even with no active filters: an '
      'over-budget property scores below an in-budget one', () async {
    final inBudget = _property(id: 'in-budget', price: 3800);
    final overBudget = _property(id: 'over-budget', price: 6000);

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([inBudget, overBudget]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    // No filters touched — only the PROFILE states a max budget.
    expect(provider.activeFilterCount, 0);
    const profile = TenantProfile(
      id: 'tenant-budget',
      name: 'Budgeter',
      bio: '',
      photoUrls: [],
      budgetMax: 4000,
      desiredRooms: 0,
      moveInWindow: 'גמיש',
      importantDetails: [],
    );
    await provider.updateTenantProfile(profile);

    // hasMatchPersona is true (profile budget set) so the badge shows…
    expect(provider.displayMatchScore(inBudget), isNotNull);
    // …and it honestly reflects the profile budget rather than ignoring it.
    expect(
      provider.matchScore(overBudget),
      lessThan(provider.matchScore(inBudget)),
      reason: 'a 50%-over-budget listing must not match the profile budget',
    );

    provider.dispose();
  });

  test('profile rooms are honoured with no active filters: too-few-rooms '
      'scores below a rooms match', () async {
    final enoughRooms = _property(id: 'enough', rooms: 4);
    final tooFewRooms = _property(id: 'too-few', rooms: 2);

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([enoughRooms, tooFewRooms]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    expect(provider.activeFilterCount, 0);
    const profile = TenantProfile(
      id: 'tenant-rooms',
      name: 'Roomer',
      bio: '',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 4,
      moveInWindow: 'גמיש',
      importantDetails: [],
    );
    await provider.updateTenantProfile(profile);

    expect(
      provider.matchScore(tooFewRooms),
      lessThan(provider.matchScore(enoughRooms)),
      reason: 'a 2-room listing must not fully match a 4-room desire',
    );

    provider.dispose();
  });

  test('an explicit filter always overrides the profile preference', () async {
    final mid = _property(id: 'mid', price: 6000);

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([mid]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    // Profile says max 4000 → with no filters, the 6000 listing is penalised.
    const profile = TenantProfile(
      id: 'tenant-override',
      name: 'Override',
      bio: '',
      photoUrls: [],
      budgetMax: 4000,
      desiredRooms: 0,
      moveInWindow: 'גמיש',
      importantDetails: [],
    );
    await provider.updateTenantProfile(profile);
    final penalised = provider.matchScore(mid);

    // The user explicitly widens the budget filter to 8000 → the listing is now
    // comfortably in budget and the explicit filter wins over the stale profile.
    await provider.updateFilters(
      provider.filters.copyWith(maxBudget: 8000, minBudget: 600),
    );
    final widened = provider.matchScore(mid);

    expect(widened, greaterThan(penalised),
        reason: 'an explicit filter must override the profile preference');

    provider.dispose();
  });

  test('a CRITICAL miss can never look like a strong match (< 80)', () async {
    // Two over-budget, wrong-room, missing-feature listings to stress the gate.
    final compliant = _property(
      id: 'compliant',
      price: 5000,
      rooms: 3,
      features: const ['parking', 'elevator'],
    );
    final violating = _property(
      id: 'violating',
      price: 5000,
      rooms: 3,
      features: const ['elevator'], // fails CRITICAL parking
    );

    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([compliant, violating]),
      localStorageService: _MemoryLocalStorageService(),
    );
    await provider.initialize();

    const profile = TenantProfile(
      id: 'tenant-crit',
      name: 'Critical',
      bio: '',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: 'גמיש',
      importantDetails: ['חייב/ת חניה'],
      dealBreakers: ['חייב/ת חניה'],
    );
    await provider.updateTenantProfile(profile);

    final violatingScore = provider.matchScore(violating);
    expect(violatingScore, lessThan(80),
        reason: 'a property that misses a non-negotiable must never read as a '
            'strong match');
    expect(violatingScore, lessThan(provider.matchScore(compliant) - 30),
        reason: 'the CRITICAL gate must dominate over any base similarity');

    provider.dispose();
  });

  test(
      'learning loop: liking over-budget + tagged + clustered listings raises a '
      'similar property\'s score above cold-start, while a deal-breaker miss '
      'stays low', () async {
    // Training listings: each is ~17% over the stated budget, has parking, and
    // sits in the same geographic cluster — exactly the revealed pattern we want
    // the algorithm to learn (budget tolerance + tag affinity + area affinity).
    List<RentalProperty> trainers() => [
          for (var i = 0; i < 6; i++)
            _property(
              id: 'train-$i',
              price: 7000, // budget is 6000 → ratio ≈ 1.17
              features: const ['parking', 'elevator'],
              lat: 32.10 + i * 0.001,
              lon: 34.80 + i * 0.001,
            ),
        ];

    // The held-out probe: same shape (over-budget + parking + near-cluster) but
    // priced far enough over budget that even after the learned lift there is
    // real headroom below 100 — so the test proves the personalisation does NOT
    // re-saturate the score.
    final probe = _property(
      id: 'probe',
      price: 8000,
      features: const ['parking', 'elevator'],
      lat: 32.101,
      lon: 34.801,
    );

    DatingProvider build() => DatingProvider(
          rentalDataService: _FakeRentalDataService([...trainers(), probe]),
          localStorageService: _MemoryLocalStorageService(),
        );

    const profile = TenantProfile(
      id: 'learner',
      name: 'Learner',
      bio: '',
      photoUrls: [],
      budgetMax: 6000,
      desiredRooms: 0,
      moveInWindow: 'גמיש',
      importantDetails: ['חייב/ת חניה'],
    );

    // ── Cold start: a fresh provider that has never seen a swipe. ──
    final cold = build();
    await cold.initialize();
    await cold.updateTenantProfile(profile);
    final coldScore = cold.matchScore(probe);
    cold.dispose();

    // ── Warm: the same setup, but the user likes every over-budget trainer. ──
    final warm = build();
    await warm.initialize();
    await warm.updateTenantProfile(profile);

    // Swipe-like the trainers off the top of the deck. Each like removes the
    // card, so index 0 always points at the next unliked trainer; the probe is
    // intentionally never swiped so we read a learned-but-unseen property.
    for (var i = 0; i < 6; i++) {
      final deck = warm.filteredProperties;
      final idx = deck.indexWhere((p) => p.id.startsWith('train-'));
      if (idx < 0) break;
      await warm.handlePropertySwipe(idx, null, CardSwiperDirection.right,
          l10n: lookupAppLocalizations(const Locale('he')));
    }

    final warmScore = warm.matchScore(probe);

    // The learned signals must measurably lift the probe above cold start, but
    // stay bounded — the personalisation layer is small by design and must not
    // re-saturate the score to 100.
    expect(warmScore, greaterThan(coldScore),
        reason: 'revealed budget tolerance + tag/area affinity must personalise '
            'the score upward for a property matching demonstrated behaviour');
    expect(warmScore - coldScore, greaterThanOrEqualTo(5),
        reason: 'the learned lift should be measurable, not noise');
    expect(warmScore, lessThan(100),
        reason: 'bounded honest learning must never re-saturate the score');

    // A property that violates the CRITICAL parking deal-breaker stays low even
    // after all that learning — revealed preferences never override a gate.
    final dealBreakerMiss = _property(
      id: 'no-parking',
      price: 8000,
      features: const ['elevator'], // misses parking
      lat: 32.101,
      lon: 34.801,
    );
    final missScore = warm.matchScore(dealBreakerMiss);
    expect(missScore, lessThan(warmScore - 20),
        reason: 'a deal-breaker miss must score far below a learned-good match');

    // The aggregate persisted, so a relaunch keeps the personalisation.
    expect(warm.userSignals.revealedBudgetTolerance, greaterThan(1.0),
        reason: 'liking over-budget listings must raise the revealed tolerance');
    expect(warm.userSignals.tagAffinity['parking'], greaterThan(0.0),
        reason: 'liking parking listings must raise parking affinity');

    warm.dispose();
  });
}

class _FakeUserRepository extends UserRepository {
  final Map<String, TenantProfile> profiles = {};

  @override
  Future<TenantProfile?> getProfile(String userId) async {
    return profiles[userId];
  }
}

class _FakePropertyRepository extends PropertyRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<PropertySaveResult> saveProperty(
    RentalProperty property, {
    required String ownerUserId,
    PropertyRecordStatus status = PropertyRecordStatus.active,
    String? expectedUpdatedAt,
    bool isCreate = false,
  }) async =>
      const PropertySaveResult.ok();

  @override
  Future<bool> deleteProperty(String propertyId) async => true;
}

class _FakeRentalDataService extends RentalDataService {
  _FakeRentalDataService(this.properties);

  final List<RentalProperty> properties;

  @override
  Future<PropertyPage> loadFirstPage({String areaId = 'all_israel'}) async {
    return PropertyPage(items: properties, hasMore: false);
  }

  @override
  TenantProfile createDefaultTenantProfile() {
    return const TenantProfile(
      id: 'tenant-test',
      name: 'Tenant',
      bio: '',
      photoUrls: <String>[],
      budgetMax: 6000,
      desiredRooms: 3,
      moveInWindow: 'within 30 days',
      importantDetails: <String>[],
    );
  }

  @override
  List<AppReview> createTenantReviews() => const [];

  @override
  List<AppReview> createPropertyReviews(RentalProperty property) {
    if (property.id == 'excellent-near-budget') {
      return const [
        AppReview(
          id: 'review-excellent',
          authorName: 'Previous tenant',
          rating: 5,
          text: 'Clear owner, maintained building, easy handover.',
        ),
      ];
    }
    return const [];
  }

  @override
  List<SearchArea> createSearchAreas() {
    return const [
      SearchArea(
        id: 'all_israel',
        name: 'All',
        center: LatLng(32.07, 34.78),
        polygon: [
          LatLng(31.7, 34.4),
          LatLng(31.7, 35.2),
          LatLng(32.4, 35.2),
          LatLng(32.4, 34.4),
        ],
      ),
    ];
  }
}

class _MemoryLocalStorageService extends LocalStorageService {
  Map<String, dynamic>? state;

  @override
  Future<Map<String, dynamic>?> loadAppState() async => state;

  @override
  Future<void> saveAppState(
    Map<String, dynamic> state, {
    bool syncRemote = true,
  }) async {
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

class _FakeReviewRepository extends ReviewRepository {
  final saved = <ReviewRecord>[];

  @override
  Future<bool> saveReview(ReviewRecord review) async {
    saved.add(review);
    return true;
  }

  @override
  Future<List<AppReview>> fetchReviews({
    required ReviewTargetType targetType,
    required String targetId,
    int limit = 50,
  }) async {
    return const [];
  }
}

RentalProperty _property({
  required String id,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 75,
  String street = 'Main',
  int streetNumber = 1,
  List<String> features = const ['parking'],
  int mediaCount = 2,
  String ownerName = 'Owner',
  String ownerUserId = '',
  String url = 'https://example.com/listing',
  String entryDate = '2026-06-15',
  bool agencyListing = false,
  PropertyVerification? verification,
  double lat = 32.08,
  double lon = 34.78,
}) {
  return RentalProperty(
    id: id,
    url: url,
    ownerUserId: ownerUserId,
    price: price,
    rooms: rooms,
    sizeM2: sizeM2,
    floor: '3',
    totalFloors: '6',
    city: 'Tel Aviv',
    neighborhood: 'Center',
    street: street,
    streetNumber: streetNumber,
    lat: lat,
    lon: lon,
    propertyType: 'Apartment',
    entryDate: entryDate,
    condition: 'Renovated',
    ownerName: ownerName,
    agencyListing: agencyListing,
    features: features,
    media: [
      for (var i = 0; i < mediaCount; i++)
        PropertyMedia(
          url: 'https://example.com/$id-$i.jpg',
          type: PropertyMediaType.image,
        ),
    ],
    verification: verification,
  );
}
