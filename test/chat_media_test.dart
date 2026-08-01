import 'package:dating_app/core/chat/chat_media.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('image round-trip', () {
    final enc = ChatMediaCodec.encodeImage('https://x/y.jpg');
    final m = ChatMediaCodec.parse(enc)!;
    expect(m.kind, ChatMediaKind.image);
    expect(m.url, 'https://x/y.jpg');
  });
  test('audio round-trip with duration', () {
    final enc = ChatMediaCodec.encodeAudio('https://x/v.m4a', 4200);
    final m = ChatMediaCodec.parse(enc)!;
    expect(m.kind, ChatMediaKind.audio);
    expect(m.url, 'https://x/v.m4a');
    expect(m.durationMs, 4200);
  });
  test('plain text is not media', () {
    expect(ChatMediaCodec.parse('שלום מה קורה'), isNull);
    expect(ChatMediaCodec.isMedia('שלום'), isFalse);
  });
  test('malformed marker returns null (no crash)', () {
    expect(ChatMediaCodec.parse('[[MEDIA:image]]'), isNull); // no url
    expect(ChatMediaCodec.parse('[[MEDIA:bogus]]http://x'), isNull);
  });
}
