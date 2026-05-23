import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

      expect(find.text('דירת החלומות'), findsOneWidget);
      expect(find.text('דירות'), findsOneWidget);
      expect(find.text('בעלי דירה'), findsOneWidget);
      expect(find.text('התאמות'), findsOneWidget);
      expect(find.text('פרופיל'), findsOneWidget);
      expect(find.textContaining('לחודש'), findsWidgets);

      await tester.tap(find.byTooltip('דלג על דירה'));
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('אהבתי דירה'));
      await _pumpFrames(tester);

      await tester.tap(find.text('בעלי דירה'));
      await _pumpFrames(tester);

      expect(find.text('נועה לוי'), findsOneWidget);
      await tester.tap(find.byTooltip('אישור שוכר'));
      await _pumpFrames(tester);

      await tester.tap(find.text('התאמות'));
      await _pumpFrames(tester);

      expect(find.text('התאמות (1)'), findsOneWidget);
      expect(find.text('צ׳אט פתוח'), findsOneWidget);

      await tester.tap(find.text('פרופיל'));
      await _pumpFrames(tester);

      expect(find.text('נועה לוי'), findsOneWidget);
      await tester.ensureVisible(find.text('עריכת פרופיל').first);
      await tester.tap(find.text('עריכת פרופיל').first);
      await _pumpFrames(tester);

      await tester.enterText(find.byType(TextFormField).first, 'דניאל');
      await tester.tap(find.text('שמירה'));
      await _pumpFrames(tester);

      expect(find.text('דניאל'), findsOneWidget);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
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
