/// An in-app notification as returned by `GET /notifications`.
///
/// The backend sends newest-first; `data` is a free-form payload used for deep
/// linking (e.g. `{propertyId: ...}` or `{matchId: ...}`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String type; // 'match' | 'message' | 'like' | 'tour' | 'review' | ...
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      data: switch (json['data']) {
        final Map<String, dynamic> m => m,
        final Map m => Map<String, dynamic>.from(m),
        _ => const <String, dynamic>{},
      },
      read: json['read'] == true,
      createdAt: _parseCreatedAt(json['createdAt']),
    );
  }

  // Backend sends createdAt as an epoch-ms Number; tolerate ISO strings too.
  static DateTime _parseCreatedAt(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal();
    }
    final s = (raw ?? '').toString();
    final ms = int.tryParse(s);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
  }

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        read: read ?? this.read,
        createdAt: createdAt,
      );

  /// Convenience accessor for the property id used by property-centric types.
  String? get propertyId {
    final v = data['propertyId'] ?? data['property_id'];
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}
