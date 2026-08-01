/// A window of time a landlord (or agent) marked as FREE for apartment
/// viewings. Tenants pick an [open] slot from the chat; picking it flips it to
/// [booked] and records who took it.
///
/// Local-first (SharedPreferences JSON), matching [BrokerViewing] and the rest
/// of the app's on-device stores. Phase-3 will two-way sync these with Google
/// Calendar; the model already carries everything that sync needs.
enum SlotStatus { open, booked }

extension SlotStatusLabel on SlotStatus {
  String get hebrew => this == SlotStatus.booked ? 'נתפס' : 'פנוי';
}

class AvailabilitySlot {
  const AvailabilitySlot({
    required this.id,
    required this.start,
    this.durationMinutes = 30,
    this.propertyId = '',
    this.note = '',
    this.tag = '',
    this.status = SlotStatus.open,
    this.bookedByName = '',
    this.bookedByPhone = '',
  });

  final String id;
  final DateTime start;

  /// Slot length in minutes (default 30) → drives [end] and clash detection.
  final int durationMinutes;

  /// Optional listing the slot is for ('' = any / general availability).
  final String propertyId;
  final String note;

  /// Optional short colored label the landlord attaches (e.g. 'דחוף',
  /// 'בלעדי', 'טלפוני'). '' = untagged. Colors are resolved in the UI.
  final String tag;
  final SlotStatus status;
  final String bookedByName;
  final String bookedByPhone;

  DateTime get end => start.add(Duration(minutes: durationMinutes));
  bool get isOpen => status == SlotStatus.open;
  bool get isUpcoming => start.isAfter(DateTime.now());

  /// Two slots overlap iff each starts before the other ends. Used to stop the
  /// landlord double-booking the same window. Windows tagged to DIFFERENT
  /// apartments are separate offerings and may share a time — only same-property
  /// (or untagged) windows clash.
  bool clashesWith(AvailabilitySlot other) {
    if (other.id == id) return false;
    if (propertyId.isNotEmpty &&
        other.propertyId.isNotEmpty &&
        propertyId != other.propertyId) {
      return false;
    }
    return start.isBefore(other.end) && other.start.isBefore(end);
  }

  AvailabilitySlot copyWith({
    DateTime? start,
    int? durationMinutes,
    String? propertyId,
    String? note,
    String? tag,
    SlotStatus? status,
    String? bookedByName,
    String? bookedByPhone,
  }) =>
      AvailabilitySlot(
        id: id,
        start: start ?? this.start,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        propertyId: propertyId ?? this.propertyId,
        note: note ?? this.note,
        tag: tag ?? this.tag,
        status: status ?? this.status,
        bookedByName: bookedByName ?? this.bookedByName,
        bookedByPhone: bookedByPhone ?? this.bookedByPhone,
      );

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      AvailabilitySlot(
        id: json['id']?.toString() ?? '',
        start: DateTime.tryParse(json['start']?.toString() ?? '') ??
            DateTime.now(),
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
        propertyId: json['propertyId']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
        tag: json['tag']?.toString() ?? '',
        status: json['status']?.toString() == 'booked'
            ? SlotStatus.booked
            : SlotStatus.open,
        bookedByName: json['bookedByName']?.toString() ?? '',
        bookedByPhone: json['bookedByPhone']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'durationMinutes': durationMinutes,
        if (propertyId.isNotEmpty) 'propertyId': propertyId,
        if (note.isNotEmpty) 'note': note,
        if (tag.isNotEmpty) 'tag': tag,
        'status': status == SlotStatus.booked ? 'booked' : 'open',
        if (bookedByName.isNotEmpty) 'bookedByName': bookedByName,
        if (bookedByPhone.isNotEmpty) 'bookedByPhone': bookedByPhone,
      };
}
