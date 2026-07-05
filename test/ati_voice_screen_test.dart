import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/presentation/features/search/ati_voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake speech service: captures the STT callback so the test can simulate the
/// user speaking, and records what אתי "spoke" — no real mic/TTS.
class FakeAssistant extends AssistantService {
  void Function(String text, bool isFinal)? _onResult;
  int startCount = 0;
  int stopCount = 0;
  final spoken = <String>[];

  void Function(String status)? _onStatus;

  @override
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
    void Function(String status)? onStatus,
  }) async {
    startCount++;
    _onResult = onResult;
    _onStatus = onStatus;
  }

  /// Simulate the recogniser stopping on its own (pauseFor / done).
  void status(String s) => _onStatus?.call(s);

  @override
  Future<void> stopListening() async => stopCount++;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}

  /// Simulate the user's mic producing a (partial or final) transcript.
  void say(String text, {bool isFinal = true}) => _onResult?.call(text, isFinal);
}

void main() {
  Widget host(FakeAssistant svc,
          Future<({String reply, bool showResults, List<ScoredProperty> results})>
              Function(String) onUtterance) =>
      MaterialApp(home: AtiVoiceScreen(service: svc, onUtterance: onUtterance));

  testWidgets('a full turn: utterance → reply spoken → mic re-opens (no freeze)',
      (tester) async {
    final svc = FakeAssistant();
    final asked = <String>[];
    Future<({String reply, bool showResults, List<ScoredProperty> results})> onU(
        String t) async {
      asked.add(t);
      return (reply: 'רוצה שאראה לך אותן עכשיו?', showResults: false, results: const <ScoredProperty>[]);
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump(); // postFrame → startListening
    expect(svc.startCount, 1, reason: 'starts listening hands-free on open');

    svc.say('שלוש חדרים בתל אביב עד 8000', isFinal: true);
    await tester.pump(); // enter _handle → thinking
    await tester.pump(const Duration(milliseconds: 50)); // await onUtterance
    expect(asked.single, 'שלוש חדרים בתל אביב עד 8000');
    expect(svc.spoken.single, contains('רוצה שאראה'),
        reason: 'אתי speaks the consent question');

    // finally-block: 700ms settle then re-open the mic — proves it never freezes.
    await tester.pump(const Duration(milliseconds: 800));
    expect(svc.startCount, 2, reason: 're-opens the mic for the next turn');
  });

  testWidgets('does NOT cut the user off: a mid-sentence pause under 3.5s waits',
      (tester) async {
    final svc = FakeAssistant();
    var calls = 0;
    Future<({String reply, bool showResults, List<ScoredProperty> results})> onU(
        String t) async {
      calls++;
      return (reply: 'ok', showResults: false, results: const <ScoredProperty>[]);
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();

    // Partial words, then a THINKING pause (not final) — must not submit yet.
    svc.say('אני מחפש', isFinal: false);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(calls, 0, reason: 'a 1.5s pause is NOT the end of the turn');

    // The user resumes — the timer resets on the new word.
    svc.say('אני מחפש שלושה חדרים', isFinal: false);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(calls, 0, reason: 'still mid-thought after the reset');

    // Now a genuine long silence (>3.5s) — the backup VAD ends the turn.
    await tester.pump(const Duration(milliseconds: 3600));
    expect(calls, 1, reason: 'only a true 3.5s silence ends the turn');
    expect(svc.stopCount, greaterThan(0));
  });

  testWidgets('recogniser stops on its own (no final) → turn finalises, not stuck',
      (tester) async {
    final svc = FakeAssistant();
    final asked = <String>[];
    Future<({String reply, bool showResults, List<ScoredProperty> results})> onU(
        String t) async {
      asked.add(t);
      return (reply: 'ok', showResults: false, results: const <ScoredProperty>[]);
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();

    // A partial arrives but NO final ever comes (the iOS bug that got users stuck).
    svc.say('דירה בעין עירון', isFinal: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(asked, isEmpty);

    // The recogniser stops itself → 'notListening'. Must finalise the turn.
    svc.status('notListening');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(asked.single, 'דירה בעין עירון',
        reason: 'status stop must finalise — never sit on "listening"');
    await tester.pump(const Duration(milliseconds: 800)); // drain the resume timer
  });

  testWidgets('a GPT error never freezes the loop (mic re-opens)', (tester) async {
    final svc = FakeAssistant();
    Future<({String reply, bool showResults, List<ScoredProperty> results})> onU(
        String t) async {
      throw Exception('network down');
    }

    await tester.pumpWidget(host(svc, onU));
    await tester.pump();
    expect(svc.startCount, 1);

    svc.say('תל אביב', isFinal: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    // try/finally must have re-opened the mic despite the thrown error.
    expect(svc.startCount, 2, reason: 'error path still resumes listening');
  });
}
