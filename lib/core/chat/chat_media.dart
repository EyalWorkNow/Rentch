/// Encodes chat media (image / voice note) inside a [ChatMessage]'s `text`
/// field, so images and voice notes ride the existing text-only message
/// transport + persistence with no model/backend change. Mirrors the
/// `[[SLOT_...]]` marker convention already used for scheduling messages.
///
/// Wire format (the marker is followed by the media URL):
///   image → `[[MEDIA:image]]<url>`
///   audio → `[[MEDIA:audio:<durationMs>]]<url>`
library;

enum ChatMediaKind { image, audio }

class ChatMedia {
  const ChatMedia({required this.kind, required this.url, this.durationMs});

  final ChatMediaKind kind;
  final String url;
  final int? durationMs; // voice notes only

  Duration? get duration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;
}

class ChatMediaCodec {
  static const String _open = '[[MEDIA:';
  static const String _close = ']]';

  static String encodeImage(String url) => '$_open image$_close$url';

  static String encodeAudio(String url, int durationMs) =>
      '$_open audio:$durationMs$_close$url';

  /// Returns the decoded media, or null when [text] is a plain message.
  static ChatMedia? parse(String text) {
    if (!text.startsWith(_open)) return null;
    final closeIdx = text.indexOf(_close);
    if (closeIdx < 0) return null;
    final header = text.substring(_open.length, closeIdx).trim(); // e.g. "audio:1234"
    final url = text.substring(closeIdx + _close.length).trim();
    if (url.isEmpty) return null;
    final parts = header.split(':');
    switch (parts.first) {
      case 'image':
        return ChatMedia(kind: ChatMediaKind.image, url: url);
      case 'audio':
        final ms = parts.length > 1 ? int.tryParse(parts[1]) : null;
        return ChatMedia(
            kind: ChatMediaKind.audio, url: url, durationMs: ms);
      default:
        return null;
    }
  }

  static bool isMedia(String text) => text.startsWith(_open);
}
