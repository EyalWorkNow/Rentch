import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/search/ati_voice_screen.dart';
import 'package:dating_app/presentation/widgets/liquid_glass_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake push-to-talk service: records nothing real, returns a canned Whisper
/// transcript, and captures what אתי "spoke".
class FakeAssistant extends AssistantService {
  String nextTranscript = 'דירה בתל אביב';
  bool micOk = true;
  int recordCount = 0;
  final spoken = <String>[];

  @override
  Future<bool> startRecording({void Function(double level)? onLevel}) async {
    recordCount++;
    lastRecordError = micOk ? null : 'permission';
    return micOk;
  }

  @override
  Future<String> stopRecordingAndTranscribe({String language = 'he'}) async =>
      nextTranscript;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}
}

void main() {
  Widget host(FakeAssistant svc,
          Future<VoiceTurn> Function(String) onUtterance) =>
      MaterialApp(
        locale: const Locale('he'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AtiVoiceScreen(service: svc, onUtterance: onUtterance),
      );

  // Hold the orb, then release — the push-to-talk gesture.
  Future<void> holdAndRelease(WidgetTester tester) async {
    final orb = find.byType(LiquidGlassOrb).first;
    final g = await tester.startGesture(tester.getCenter(orb));
    await tester.pump(); // onPointerDown → startRecording
    await tester.pump(const Duration(milliseconds: 50));
    await g.up(); // onPointerUp → stopAndSend → transcribe → respond
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('hold-to-record → Whisper transcript → onUtterance → אתי speaks',
      (tester) async {
    final svc = FakeAssistant()..nextTranscript = 'דירה בתל אביב עד 8000';
    final asked = <String>[];
    Future<VoiceTurn> onU(
        String t) async {
      asked.add(t);
      return VoiceTurn(reply: 'הנה מה שמצאתי', showResults: false, results: const <ScoredProperty>[]);
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();
    // Nothing auto-starts — push-to-talk.
    expect(svc.recordCount, 0);

    await holdAndRelease(tester);

    expect(svc.recordCount, 1, reason: 'press starts recording');
    expect(asked.single, 'דירה בתל אביב עד 8000',
        reason: 'the Whisper transcript is sent on release');
    expect(svc.spoken.single, contains('הנה'), reason: 'אתי speaks the reply');
  });

  testWidgets('empty transcript → gentle retry, no crash', (tester) async {
    final svc = FakeAssistant()..nextTranscript = '   ';
    var calls = 0;
    Future<VoiceTurn> onU(
        String t) async {
      calls++;
      return VoiceTurn(reply: 'x', showResults: false, results: const <ScoredProperty>[]);
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();
    await holdAndRelease(tester);

    expect(calls, 0, reason: 'nothing said → do not call the model');
    expect(find.textContaining('לא שמעתי'), findsOneWidget);
  });

  testWidgets('mic permission denied → clear message', (tester) async {
    final svc = FakeAssistant()..micOk = false;
    Future<VoiceTurn> onU(
        String t) async => VoiceTurn(reply: 'x', showResults: false, results: const <ScoredProperty>[]);

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();
    final orb = find.byType(LiquidGlassOrb).first;
    final g = await tester.startGesture(tester.getCenter(orb));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pump();

    expect(find.textContaining('הרשאת מיקרופון'), findsOneWidget);
  });

  testWidgets('needLocation → animated share-location button → onShareLocation',
      (tester) async {
    final svc = FakeAssistant()..nextTranscript = 'דירה באזור שלי';
    var shared = 0;
    Future<VoiceTurn> onU(String t) async =>
        const VoiceTurn(reply: 'אפשר לשתף מיקום?', needLocation: true);
    Future<VoiceTurn> onShare() async {
      shared++;
      return const VoiceTurn(reply: 'מצאתי!');
    }

    await tester.pumpWidget(MaterialApp(
        locale: const Locale('he'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AtiVoiceScreen(
            service: svc, onUtterance: onU, onShareLocation: onShare)));
    await tester.pump();
    await holdAndRelease(tester);

    // The animated button appears (no silent GPS grab).
    expect(find.text('שיתוף המיקום שלי'), findsOneWidget);
    expect(shared, 0);

    await tester.tap(find.text('שיתוף המיקום שלי'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(shared, 1, reason: 'tapping the button captures location + searches');
  });
}
