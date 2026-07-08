import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/main.dart';
import 'package:dating_app/presentation/screens/compare_screen.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory documentsDirectory;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    documentsDirectory = Directory.systemTemp.createTempSync('rentch_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return documentsDirectory.path;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
  });

  testWidgets('rental matching critical flow works', (
    WidgetTester tester,
  ) async {
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
    try {
      await _pumpApp(tester);

      expect(find.text('המשך כאורח'), findsOneWidget);
      await tester.ensureVisible(find.text('המשך כאורח'));
      await tester.tap(find.text('המשך כאורח'));
      await _pumpFrames(tester);

      expect(find.text('אורח כדייר מחפש דירה'), findsOneWidget);
      await tester.ensureVisible(find.text('אורח כדייר מחפש דירה'));
      await tester.tap(find.text('אורח כדייר מחפש דירה'));
      await _pumpFrames(tester);

      // Only the selected tab shows its label — check the first (selected) tab
      expect(find.text('גלה דירות'), findsOneWidget);
      // Verify we can reach all tabs via key-based nav (nav bar labels hidden when unselected)
      expect(find.byKey(const Key('nav_tab_0')), findsOneWidget);
      expect(find.byKey(const Key('nav_tab_1')), findsOneWidget);
      expect(find.byKey(const Key('nav_tab_2')), findsOneWidget);
      expect(find.textContaining('לחודש'), findsWidgets);

      await tester.tap(find.byTooltip('דלג על דירה'));
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('אהבתי דירה'));
      await _pumpFrames(tester);

      _invokeGestureTap(tester, find.byKey(const Key('nav_tab_1')));
      await _pumpFrames(tester);

      expect(find.textContaining('התאמות'), findsWidgets);
      // MatchesScreen toolbar always shows "N שיחות פעילות" when there are matches
      expect(find.textContaining('שיחות פעילות'), findsAtLeastNWidgets(1));

      _invokeGestureTap(tester, find.byKey(const Key('nav_tab_2')));
      await _pumpFrames(tester);

      expect(find.text('נועה לוי'), findsOneWidget);
      _invokeGestureTap(tester, find.byKey(const Key('profile_edit_button')));
      await _pumpFrames(tester);

      await tester.enterText(find.byType(TextField).first, 'דניאל');
      await tester.tap(find.text('שמור'));
      await _pumpFrames(tester);

      expect(find.text('דניאל'), findsOneWidget);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets(
    'landlord quick actions switch tabs without losing bottom navigation',
    (WidgetTester tester) async {
      debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
      final provider = DatingProvider(
        rentalDataService: _FakeRentalDataService([
          _testProperty(
              id: 'landlord-1', street: 'אבן גבירול', city: 'תל אביב'),
          _testProperty(id: 'landlord-2', street: 'סוקולוב', city: 'רמת השרון'),
          _testProperty(id: 'landlord-3', street: 'ויצמן', city: 'כפר סבא'),
          _testProperty(id: 'landlord-4', street: 'ביאליק', city: 'רמת גן'),
        ]),
        localStorageService: _MemoryLocalStorageService(),
      );
      try {
        await provider.initialize();
        await provider.enterGuestMode('landlord');
        await tester.pumpWidget(
          ChangeNotifierProvider<DatingProvider>.value(
            value: provider,
            child: MaterialApp(
              builder: (context, child) {
                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const HomeScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        // Dashboard ListView: _QuickActionsGrid is below the fold — scroll to it
        await tester.scrollUntilVisible(
          find.text('פעולות מהירות'),
          300.0,
        );
        expect(find.byKey(const Key('quick_actions_header')), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, 'מועמדים'),
        );
        await _pumpFrames(tester);

        expect(find.text('סוויפים'), findsOneWidget);
        expect(find.byKey(const Key('nav_tab_0')), findsOneWidget);
        expect(find.byKey(const Key('nav_tab_3')), findsOneWidget);

        _invokeGestureTap(tester, find.byKey(const Key('nav_tab_0')));
        await _pumpFrames(tester);
        // IndexedStack preserves ListView scroll — quick actions still in view
        expect(find.byKey(const Key('quick_actions_header')), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, "מאצ'ים"),
        );
        await _pumpFrames(tester);

        expect(find.byKey(const Key('nav_tab_0')), findsOneWidget);
        expect(find.byKey(const Key('nav_tab_3')), findsWidgets);

        _invokeGestureTap(tester, find.byKey(const Key('nav_tab_0')));
        await _pumpFrames(tester);
        // IndexedStack preserves ListView scroll — quick actions still in view
        expect(find.byKey(const Key('quick_actions_header')), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, 'הנכסים'),
        );
        await _pumpFrames(tester);

        expect(find.byKey(const Key('nav_tab_0')), findsOneWidget);
        expect(find.text('הדירות שלי'), findsWidgets);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        provider.dispose();
      }
    },
  );

  testWidgets(
    'landlord properties filter sheet applies a filter and closes',
    (WidgetTester tester) async {
      debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
      final provider = DatingProvider(
        rentalDataService: _FakeRentalDataService([
          _testProperty(id: 'seed-1', street: 'אלנבי', city: 'תל אביב'),
          _testProperty(id: 'seed-2', street: 'ירמיהו', city: 'ירושלים'),
          _testProperty(id: 'seed-3', street: 'ארלוזורוב', city: 'חיפה'),
          _testProperty(id: 'seed-4', street: 'הנשיא', city: 'באר שבע'),
        ]),
        localStorageService: _MemoryLocalStorageService(),
      );

      try {
        await provider.initialize();
        await provider.enterGuestMode('landlord');
        await tester.pumpWidget(
          ChangeNotifierProvider<DatingProvider>.value(
            value: provider,
            child: MaterialApp(
              builder: (context, child) {
                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const LandlordPropertiesScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        expect(find.textContaining('דיזנגוף'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('landlord-properties-filter-button')),
        );
        await _pumpFrames(tester);
        expect(find.text('סינון ומיון נכסים'), findsOneWidget);

        await tester.tap(find.text('עדיפות שיווקית (עד 6K)'));
        await _pumpFrames(tester);

        expect(find.text('סינון ומיון נכסים'), findsNothing);
        expect(find.text('1 מתוך 4 נכסים'), findsOneWidget);
        expect(find.textContaining('מסגר'), findsOneWidget);
        expect(find.textContaining('דיזנגוף'), findsNothing);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        provider.dispose();
      }
    },
  );

  testWidgets('CompareScreen renders a table for saved listings (no blank)',
      (WidgetTester tester) async {
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _testProperty(id: 'c1', street: 'דיזנגוף', city: 'תל אביב', price: 7200),
        _testProperty(id: 'c2', street: 'סוקולוב', city: 'רמת השרון', price: 6100),
        _testProperty(id: 'c3', street: 'ויצמן', city: 'כפר סבא', price: 8300),
        _testProperty(id: 'c4', street: 'ביאליק', city: 'רמת גן', price: 6900),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );
    try {
      await provider.initialize();
      await provider.enterGuestMode('tenant');
      await provider.toggleSave('c1');
      await provider.toggleSave('c2');
      await provider.toggleSave('c3');
      await provider.toggleSave('c4');
      expect(provider.savedProperties.length, 4);

      await tester.pumpWidget(
        ChangeNotifierProvider<DatingProvider>.value(
          value: provider,
          child: const MaterialApp(home: CompareScreen()),
        ),
      );
      await _pumpFrames(tester);

      // The real bug: the screen came up blank. Assert the comparison table is
      // actually there, and no layout/render exception was swallowed.
      expect(tester.takeException(), isNull);
      expect(find.text('מחיר'), findsOneWidget);
      expect(find.text('₪ למ"ר'), findsOneWidget);
      expect(find.text('השוואת דירות'), findsOneWidget);
      // >3 saved → the column dropdown is shown (seeded with the first 3).
      expect(find.text('נבחרו 3/3 דירות'), findsOneWidget);
    } finally {
      debugNetworkImageHttpClientProvider = null;
      provider.dispose();
    }
  });

  test('rental property media preserves image and video entries', () {
    final property = RentalProperty(
      id: 'custom-1',
      sourceUrl: '',
      price: 8500,
      rooms: 3,
      sizeM2: 88,
      floor: '3',
      totalFloors: '6',
      city: 'תל אביב',
      neighborhood: 'הצפון הישן',
      street: 'דיזנגוף',
      streetNumber: 120,
      lat: 32.08,
      lon: 34.77,
      propertyType: 'דירה',
      entryDate: '2026-06-01',
      condition: 'משופץ',
      ownerName: 'נועה',
      agencyListing: false,
      features: ['מרפסת'],
      media: [
        PropertyMedia(
          url: 'https://example.com/cover.jpg',
          type: PropertyMediaType.image,
        ),
        PropertyMedia(
          url: 'https://example.com/tour.mp4',
          type: PropertyMediaType.video,
        ),
      ],
      virtualTour: PropertyVirtualTour(
        id: 'scene-1',
        provider: 'splat3d',
        status: PropertyTourStatus.ready,
        viewerUrl: 'https://example.com/tour/scene-1',
        format: 'sog',
        processingProgress: 100,
      ),
      legal: PropertyLegal(
        thirdPartyTransferAllowed: true,
        commercialSaleAllowed: true,
        aiTrainingAllowed: false,
        consentVersion: 'terms_v4.2',
        consentTimestamp: DateTime.utc(2026, 6, 1, 12, 0),
        consentSource: 'user_upload',
      ),
      priceHistory: [
        PropertyPricePoint(
          date: DateTime.utc(2026, 6, 1),
          price: 8500,
          transactionType: PropertyTransactionType.rent,
        ),
      ],
      marketSignals: const PropertyMarketSignals(
        views: 12,
        likes: 3,
        saves: 2,
        avgTimeIn3dSeconds: 41,
        liveViewers: 2,
        likesToday: 5,
        likesTodayDate: '2026-06-06',
        detailViews: 7,
        gallerySwipes: 11,
        avgDetailStaySeconds: 28,
      ),
      verification: PropertyVerification.cameraVideo(
        videoUrl: 'https://example.com/verification.mp4',
        capturedAt: DateTime.utc(2026, 6, 3, 9, 45),
      ),
      createdAt: DateTime.utc(2026, 6, 3, 9, 30),
    );

    final decoded = RentalProperty.fromJson(property.toJson());

    expect(decoded.media, hasLength(2));
    expect(decoded.imageUrls, ['https://example.com/cover.jpg']);
    expect(decoded.videoUrls, ['https://example.com/tour.mp4']);
    expect(decoded.primaryMedia?.type, PropertyMediaType.image);
    expect(decoded.virtualTour?.status, PropertyTourStatus.ready);
    expect(decoded.hasReadyVirtualTour, isTrue);
    expect(decoded.virtualTour?.viewerUrl, 'https://example.com/tour/scene-1');
    expect(decoded.featureFlags.isEnabled('balcony'), isTrue);
    expect(decoded.legal.thirdPartyTransferAllowed, isTrue);
    expect(decoded.legal.consentVersion, 'terms_v4.2');
    expect(decoded.priceHistory, hasLength(1));
    expect(decoded.marketSignals.views, 12);
    expect(decoded.marketSignals.liveViewers, 2);
    expect(decoded.marketSignals.likesToday, 5);
    expect(decoded.marketSignals.detailViews, 7);
    expect(decoded.marketSignals.gallerySwipes, 11);
    expect(decoded.marketSignals.avgDetailStaySeconds, 28);
    expect(decoded.isVerifiedListing, isTrue);
    expect(decoded.verification.method, PropertyVerification.cameraVideoMethod);
    expect(
        decoded.verification.videoUrl, 'https://example.com/verification.mp4');
    expect(decoded.verification.capturedAt, DateTime.utc(2026, 6, 3, 9, 45));
    expect(decoded.createdAt, DateTime.utc(2026, 6, 3, 9, 30));
    expect(decoded.model3d?.viewerUrl, 'https://example.com/tour/scene-1');
  });

  test('property verification also parses flat backend columns', () {
    final decoded = RentalProperty.fromJson({
      ..._testProperty(id: 'verified-flat').toJson(),
      'verification': null,
      'verifiedListing': true,
      'verificationMethod': PropertyVerification.cameraVideoMethod,
      'verificationVideoUrl': 'https://example.com/flat-verification.mp4',
      'verifiedAt': '2026-06-04T08:00:00.000Z',
    });

    expect(decoded.isVerifiedListing, isTrue);
    expect(
      decoded.verification.videoUrl,
      'https://example.com/flat-verification.mp4',
    );
    expect(decoded.verification.capturedAt, DateTime.utc(2026, 6, 4, 8));
  });

  test('property signals reset daily likes and detect new listings', () {
    final today = DateTime(2026, 6, 6, 11);
    final yesterdaySignals = const PropertyMarketSignals(
      likesToday: 4,
      likesTodayDate: '2026-06-05',
    );

    final normalized = yesterdaySignals.normalizedForToday(today);
    expect(normalized.likesToday, 0);
    expect(normalized.likesTodayDate, '2026-06-06');

    final fresh = _testProperty(
      id: 'fresh',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    );
    final stale = _testProperty(
      id: 'stale',
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
    );

    expect(fresh.isNewListing, isTrue);
    expect(stale.isNewListing, isFalse);
  });

  test('dating provider tracks detail sessions and daily likes locally',
      () async {
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([
        _testProperty(id: 'signals-1'),
      ]),
      localStorageService: _MemoryLocalStorageService(),
    );

    try {
      await provider.initialize();
      provider.beginPropertyDetailView('signals-1');

      var property = provider.propertyById('signals-1')!;
      expect(property.marketSignals.liveViewers, 1);
      expect(property.marketSignals.detailViews, 1);
      expect(property.marketSignals.views, 1);

      provider.recordPropertyGallerySwipe('signals-1', 1);
      property = provider.propertyById('signals-1')!;
      expect(property.marketSignals.gallerySwipes, 1);

      await provider.endPropertyDetailView('signals-1');
      property = provider.propertyById('signals-1')!;
      expect(property.marketSignals.liveViewers, 0);
      expect(
          property.marketSignals.avgDetailStaySeconds, greaterThanOrEqualTo(0));

      await provider.likeProperty('signals-1');
      property = provider.propertyById('signals-1')!;
      expect(property.marketSignals.likes, 1);
      expect(property.marketSignals.likesTodayFor(DateTime.now()), 1);
    } finally {
      provider.dispose();
    }
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(const RentlyApp());
  for (var attempt = 0; attempt < 25; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await _pumpFrames(tester);
    final context = tester.element(find.byType(MaterialApp));
    final provider = Provider.of<DatingProvider>(context, listen: false);
    if (!provider.isLoading) {
      // Advance through OnboardingScreen (added after this test was written)
      while (find.text('הבא').evaluate().isNotEmpty) {
        await tester.tap(find.text('הבא'));
        await _pumpFrames(tester);
      }
      if (find.text('מתחילים').evaluate().isNotEmpty) {
        await tester.tap(find.text('מתחילים'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      return;
    }
  }
  fail('DreamHomeApp did not finish loading rental data');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void _invokeGestureTap(WidgetTester tester, Finder finder) {
  final w = tester.widget(finder.first);
  if (w is ScaleBounce) {
    w.onTap?.call();
  } else {
    (w as GestureDetector).onTap?.call();
  }
}


class _FakeHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  static final List<int> _transparentImage = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlH0pQAAAAASUVORK5CYII=',
  );

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentImage]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
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
      budgetMax: 7000,
      desiredRooms: 3,
      moveInWindow: 'within 30 days',
      importantDetails: <String>[],
    );
  }

  @override
  List<AppReview> createTenantReviews() => const [];

  @override
  List<AppReview> createPropertyReviews(RentalProperty property) => const [];

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

RentalProperty _testProperty({
  required String id,
  String street = 'הרצל',
  String city = 'תל אביב',
  int price = 7200,
  double rooms = 3,
  bool agencyListing = false,
  DateTime? createdAt,
}) {
  return RentalProperty(
    id: id,
    url: 'https://example.com/$id',
    price: price,
    rooms: rooms,
    sizeM2: 82,
    floor: '2',
    totalFloors: '6',
    city: city,
    neighborhood: 'מרכז',
    street: street,
    streetNumber: 12,
    lat: 32.08,
    lon: 34.78,
    propertyType: 'דירה',
    entryDate: '2026-06-15',
    condition: 'משופץ',
    ownerName: 'בעלים',
    agencyListing: agencyListing,
    features: const ['מעלית', 'מרפסת'],
    media: const [
      PropertyMedia(
        url: 'https://example.com/property.jpg',
        type: PropertyMediaType.image,
      ),
    ],
    createdAt: createdAt,
  );
}
