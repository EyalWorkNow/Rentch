/// A broker's exclusivity mandate (בלעדיות) over a property.
///
/// In Israel an exclusivity agreement is time-boxed (typically a few months).
/// If it lapses the broker loses the exclusive right to market the property —
/// and the commission with it. So the single most valuable thing this model
/// supports is answering "which mandates are about to expire?" before it's too
/// late. Everything here is local, broker-private bookkeeping (SharedPreferences
/// JSON), no backend.
class BrokerExclusivity {
  BrokerExclusivity({
    required this.id,
    required this.propertyTitle,
    required this.ownerName,
    required this.ownerPhone,
    required this.startDate,
    required this.endDate,
    this.commissionPct = 0,
    this.notes = '',
  });

  /// Stable local id (SharedPreferences list key + edit/delete target).
  final String id;
  final String propertyTitle;
  final String ownerName;
  final String ownerPhone;
  final DateTime startDate;
  final DateTime endDate;

  /// Agreed commission percentage (e.g. 2 means 2%). 0 = unspecified.
  final double commissionPct;
  final String notes;

  /// Whole days from [now] until the mandate ends. Negative = already expired.
  /// Compared on calendar dates (not wall-clock) so "expires today" reads 0.
  int daysUntilEnd([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    return _dateOnly(endDate).difference(today).inDays;
  }

  bool isExpired([DateTime? now]) => daysUntilEnd(now) < 0;

  /// Expiring soon = ends within the next [withinDays] days (default 14) and is
  /// not already expired. This is the renewal-reminder trigger.
  bool isExpiringSoon([DateTime? now, int withinDays = 14]) {
    final days = daysUntilEnd(now);
    return days >= 0 && days <= withinDays;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  BrokerExclusivity copyWith({
    String? propertyTitle,
    String? ownerName,
    String? ownerPhone,
    DateTime? startDate,
    DateTime? endDate,
    double? commissionPct,
    String? notes,
  }) {
    return BrokerExclusivity(
      id: id,
      propertyTitle: propertyTitle ?? this.propertyTitle,
      ownerName: ownerName ?? this.ownerName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      commissionPct: commissionPct ?? this.commissionPct,
      notes: notes ?? this.notes,
    );
  }

  static const int schemaVersion = 1;

  Map<String, dynamic> toJson() => {
        '_schemaV': schemaVersion,
        'id': id,
        'propertyTitle': propertyTitle,
        'ownerName': ownerName,
        'ownerPhone': ownerPhone,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'commissionPct': commissionPct,
        'notes': notes,
      };

  factory BrokerExclusivity.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return BrokerExclusivity(
      id: (json['id'] ?? '').toString(),
      propertyTitle: (json['propertyTitle'] ?? '').toString(),
      ownerName: (json['ownerName'] ?? '').toString(),
      ownerPhone: (json['ownerPhone'] ?? '').toString(),
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      commissionPct: (json['commissionPct'] as num?)?.toDouble() ?? 0,
      notes: (json['notes'] ?? '').toString(),
    );
  }
}
