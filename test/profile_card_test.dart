import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/discover/profile_card.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile card clamps media index when property changes',
      (tester) async {
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
    final first = _property(id: 'six-media', mediaCount: 6);
    final second = _property(id: 'four-media', mediaCount: 4);
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([first, second]),
      localStorageService: _MemoryLocalStorageService(),
    );

    try {
      await provider.initialize();
      await _pumpCard(tester, provider, first);

      final cardRect = tester.getRect(find.byType(ProfileCard));
      final nextTap = Offset(
        cardRect.right - 40,
        cardRect.top + cardRect.height * 0.25,
      );

      for (var i = 0; i < 5; i++) {
        await tester.tapAt(nextTap);
        await tester.pump(const Duration(milliseconds: 260));
      }

      // ProfileCard renders one stable-keyed SafeMedia and swaps its `media`
      // provider on navigation (gapless) — verify the shown image via that.
      expect(
        tester.widget<SafeMedia>(find.byType(SafeMedia)).media?.url,
        'https://example.com/six-media-5.jpg',
      );

      await _pumpCard(tester, provider, second);

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<SafeMedia>(find.byType(SafeMedia)).media?.url,
        'https://example.com/four-media-0.jpg',
      );
    } finally {
      debugNetworkImageHttpClientProvider = null;
      provider.dispose();
    }
  });

  testWidgets('profile card uses physical right side as next image in rtl',
      (tester) async {
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
    final property = _property(id: 'rtl-media', mediaCount: 3);
    final provider = DatingProvider(
      rentalDataService: _FakeRentalDataService([property]),
      localStorageService: _MemoryLocalStorageService(),
    );

    try {
      await provider.initialize();
      await _pumpCard(
        tester,
        provider,
        property,
        textDirection: TextDirection.rtl,
      );

      final cardRect = tester.getRect(find.byType(ProfileCard));
      await tester.tapAt(
        Offset(
          cardRect.right - 40,
          cardRect.top + cardRect.height * 0.25,
        ),
      );
      await tester.pump(const Duration(milliseconds: 260));

      // Physical-right tap in RTL advances to the next image (index 1).
      expect(
        tester.widget<SafeMedia>(find.byType(SafeMedia)).media?.url,
        'https://example.com/rtl-media-1.jpg',
      );
      await tester.pump(const Duration(milliseconds: 900));
    } finally {
      debugNetworkImageHttpClientProvider = null;
      provider.dispose();
    }
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  DatingProvider provider,
  RentalProperty property, {
  TextDirection textDirection = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DatingProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 640,
            child: Directionality(
              textDirection: textDirection,
              child: ProfileCard(property: property),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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

RentalProperty _property({
  required String id,
  required int mediaCount,
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
    entryDate: '2026-06-15',
    condition: 'משופץ',
    ownerName: 'בעלים',
    agencyListing: false,
    features: const ['מעלית', 'חניה'],
    media: [
      for (var i = 0; i < mediaCount; i++)
        PropertyMedia(
          url: 'https://example.com/$id-$i.jpg',
          type: PropertyMediaType.image,
        ),
    ],
  );
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
