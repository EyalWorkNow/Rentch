import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/main.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
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

      expect(find.text('גלה דירות'), findsOneWidget);
      expect(find.text('התאמות'), findsOneWidget);
      expect(find.text('פרופיל'), findsOneWidget);
      expect(find.textContaining('לחודש'), findsWidgets);

      await tester.tap(find.byTooltip('דלג על דירה'));
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('אהבתי דירה'));
      await _pumpFrames(tester);

      await tester.tap(find.text('התאמות'));
      await _pumpFrames(tester);

      expect(find.textContaining('התאמות'), findsWidgets);
      expect(find.text('שיחה פתוחה'), findsOneWidget);

      await tester.tap(find.text('פרופיל'));
      await _pumpFrames(tester);

      expect(find.text('נועה לוי'), findsOneWidget);
      await tester.tap(find.text('עריכה'));
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

        expect(find.text('פעולות מהירות'), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, 'מועמדים'),
        );
        await _pumpFrames(tester);

        expect(find.text('סוויפים'), findsOneWidget);
        expect(find.text('דשבורד'), findsOneWidget);
        expect(find.text('הדירות שלי'), findsOneWidget);

        _invokeInkWellTap(
          tester,
          find.widgetWithText(InkWell, 'דשבורד'),
        );
        await _pumpFrames(tester);
        expect(find.text('פעולות מהירות'), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, "מאצ'ים"),
        );
        await _pumpFrames(tester);

        expect(find.text('דשבורד'), findsOneWidget);
        expect(find.text('הדירות שלי'), findsWidgets);

        _invokeInkWellTap(
          tester,
          find.widgetWithText(InkWell, 'דשבורד'),
        );
        await _pumpFrames(tester);
        expect(find.text('פעולות מהירות'), findsOneWidget);

        _invokeGestureTap(
          tester,
          find.widgetWithText(GestureDetector, 'הנכסים'),
        );
        await _pumpFrames(tester);

        expect(find.text('דשבורד'), findsOneWidget);
        expect(find.text('הדירות שלי'), findsWidgets);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        provider.dispose();
      }
    },
  );

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
      ),
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
    expect(decoded.model3d?.viewerUrl, 'https://example.com/tour/scene-1');
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(const RentchApp());
  for (var attempt = 0; attempt < 25; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await _pumpFrames(tester);
    final context = tester.element(find.byType(MaterialApp));
    final provider = Provider.of<DatingProvider>(context, listen: false);
    if (!provider.isLoading) {
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
  final widget = tester.widget<GestureDetector>(finder.first);
  widget.onTap?.call();
}

void _invokeInkWellTap(WidgetTester tester, Finder finder) {
  final widget = tester.widget<InkWell>(finder.first);
  widget.onTap?.call();
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
  required String street,
  required String city,
}) {
  return RentalProperty(
    id: id,
    url: 'https://example.com/$id',
    price: 7200,
    rooms: 3,
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
    agencyListing: false,
    features: const ['מעלית', 'מרפסת'],
    media: const [
      PropertyMedia(
        url: 'https://example.com/property.jpg',
        type: PropertyMediaType.image,
      ),
    ],
  );
}
