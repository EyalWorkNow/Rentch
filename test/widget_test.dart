import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
      expect(find.text('צ׳אט פתוח'), findsOneWidget);

      await tester.tap(find.text('פרופיל'));
      await _pumpFrames(tester);

      expect(find.text('נועה לוי'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await _pumpFrames(tester);
      await tester.ensureVisible(find.text('עריכת פרופיל'));
      await tester.tap(find.text('עריכת פרופיל'));
      await _pumpFrames(tester);

      await tester.enterText(find.byType(TextField).first, 'דניאל');
      await tester.tap(find.text('שמור'));
      await _pumpFrames(tester);

      expect(find.text('דניאל'), findsOneWidget);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  test('rental property media preserves image and video entries', () {
    const property = RentalProperty(
      id: 'custom-1',
      url: '',
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
    );

    final decoded = RentalProperty.fromJson(property.toJson());

    expect(decoded.media, hasLength(2));
    expect(decoded.imageUrls, ['https://example.com/cover.jpg']);
    expect(decoded.videoUrls, ['https://example.com/tour.mp4']);
    expect(decoded.primaryMedia?.type, PropertyMediaType.image);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(const RentchApp());
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
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
