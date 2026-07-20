/// A scheduled apartment viewing (צפייה) a broker has booked with a client.
///
/// The two things that burn brokers are no-shows they didn't confirm and two
/// clients booked into the same slot. This model carries the [dateTime] and a
/// [status] so the screen can sort upcoming viewings, mark outcomes, and detect
/// overlapping bookings. Local-only (SharedPreferences JSON), like the rest of
/// the app's on-device stores.
enum ViewingStatus { scheduled, completed, noShow, cancelled }

extension ViewingStatusLabel on ViewingStatus {
  String get hebrew {
    switch (this) {
      case ViewingStatus.scheduled:
        return 'מתוכננת';
      case ViewingStatus.completed:
        return 'התקיימה';
      case ViewingStatus.noShow:
        return 'לא הגיע';
      case ViewingStatus.cancelled:
        return 'בוטלה';
    }
  }

  /// Only a still-on-the-calendar viewing can clash with another.
  bool get blocksTime => this == ViewingStatus.scheduled;
}

class BrokerViewing {
  BrokerViewing({
    required this.id,
    required this.dateTime,
    this.propertyId = '',
    this.propertyTitle = '',
    this.clientName = '',
    this.phone = '',
    this.status = ViewingStatus.scheduled,
    this.notes = '',
    this.durationMinutes = 30,
  });

  final String id;
  final DateTime dateTime;
  final String propertyId;
  final String propertyTitle;
  final String clientName;
  final String phone;
  final ViewingStatus status;
  final String notes;

  /// Assumed slot length, used by clash detection. Default 30 min.
  final int durationMinutes;

  DateTime get end => dateTime.add(Duration(minutes: durationMinutes));

  bool get isUpcoming =>
      status == ViewingStatus.scheduled && dateTime.isAfter(DateTime.now());

  /// Do this viewing and [other] overlap in time? Only meaningful when both are
  /// still scheduled (a cancelled/completed slot frees the calendar). Two slots
  /// overlap iff each starts before the other ends.
  bool clashesWith(BrokerViewing other) {
    if (other.id == id) return false;
    if (!status.blocksTime || !other.status.blocksTime) return false;
    return dateTime.isBefore(other.end) && other.dateTime.isBefore(end);
  }

  BrokerViewing copyWith({
    DateTime? dateTime,
    String? propertyId,
    String? propertyTitle,
    String? clientName,
    String? phone,
    ViewingStatus? status,
    String? notes,
    int? durationMinutes,
  }) {
    return BrokerViewing(
      id: id,
      dateTime: dateTime ?? this.dateTime,
      propertyId: propertyId ?? this.propertyId,
      propertyTitle: propertyTitle ?? this.propertyTitle,
      clientName: clientName ?? this.clientName,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  factory BrokerViewing.fromJson(Map<String, dynamic> json) {
    return BrokerViewing(
      id: json['id']?.toString() ?? '',
      dateTime:
          DateTime.tryParse(json['dateTime']?.toString() ?? '') ??
              DateTime.now(),
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      status: _parseStatus(json['status']),
      notes: json['notes']?.toString() ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
    );
  }

  static const int schemaVersion = 1;

  Map<String, dynamic> toJson() {
    return {
      '_schemaV': schemaVersion,
      'id': id,
      'dateTime': dateTime.toIso8601String(),
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'clientName': clientName,
      'phone': phone,
      'status': status.name,
      'notes': notes,
      'durationMinutes': durationMinutes,
    };
  }

  static ViewingStatus _parseStatus(Object? raw) {
    final name = raw?.toString();
    return ViewingStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ViewingStatus.scheduled,
    );
  }

  /// One-time debug self-check of the overlap rule (called from the screen's
  /// initState behind an `assert`, so it is stripped from release builds).
  static bool debugSelfCheck() {
    final base = DateTime(2026, 1, 1, 10, 0);
    BrokerViewing at(int min, {int dur = 30, ViewingStatus s = ViewingStatus.scheduled}) =>
        BrokerViewing(
          id: 'v$min$dur${s.name}',
          dateTime: base.add(Duration(minutes: min)),
          durationMinutes: dur,
          status: s,
        );
    // 10:00–10:30 and 10:15–10:45 overlap.
    assert(at(0).clashesWith(at(15)));
    // 10:00–10:30 and 10:30–11:00 touch but do not overlap (end == start).
    assert(!at(0).clashesWith(at(30)));
    // Disjoint slots never clash.
    assert(!at(0).clashesWith(at(60)));
    // A cancelled slot frees the calendar even if times overlap.
    assert(!at(0).clashesWith(at(15, s: ViewingStatus.cancelled)));
    // Symmetric.
    assert(at(15).clashesWith(at(0)));
    return true;
  }
}
