/// Per-property monthly rent ledger for landlords.
///
/// A landlord has no other way to track who paid rent. [RentLedger] is a simple
/// list of monthly [RentEntry] rows (one per calendar month), each carrying the
/// expected amount and whether it has been paid. It is intentionally tiny and
/// JSON-round-trippable so it can be persisted with the app's existing local
/// storage (SharedPreferences) without any new backend.
library;

/// One month's rent expectation + payment status.
class RentEntry {
  const RentEntry({
    required this.year,
    required this.month,
    required this.amount,
    this.paid = false,
    this.paidAt,
    this.note,
  });

  /// Calendar year, e.g. 2026.
  final int year;

  /// Calendar month, 1-12.
  final int month;

  /// Expected rent for this month, in ₪.
  final int amount;

  /// Whether this month has been collected.
  final bool paid;

  /// When [paid] was last set to true. Cleared when toggled back to unpaid.
  final DateTime? paidAt;

  /// Optional free-text note (e.g. "שילם במזומן").
  final String? note;

  /// First day of this entry's month.
  DateTime get monthStart => DateTime(year, month);

  /// `year * 12 + month` — a stable, comparable key for ordering/dedup.
  int get sortKey => year * 12 + month;

  /// True when this month is in the past (its month has fully ended) relative to
  /// [now] and the rent has NOT been paid.
  bool isOverdue([DateTime? now]) {
    if (paid) return false;
    final ref = now ?? DateTime.now();
    // The month is overdue once we are past its final calendar moment, i.e. once
    // the *next* month has started.
    final nextMonthStart = DateTime(year, month + 1);
    return !ref.isBefore(nextMonthStart);
  }

  /// True when [now] falls inside this entry's calendar month.
  bool isCurrent([DateTime? now]) {
    final ref = now ?? DateTime.now();
    return ref.year == year && ref.month == month;
  }

  RentEntry copyWith({
    int? year,
    int? month,
    int? amount,
    bool? paid,
    DateTime? paidAt,
    bool clearPaidAt = false,
    String? note,
    bool clearNote = false,
  }) {
    return RentEntry(
      year: year ?? this.year,
      month: month ?? this.month,
      amount: amount ?? this.amount,
      paid: paid ?? this.paid,
      paidAt: clearPaidAt ? null : (paidAt ?? this.paidAt),
      note: clearNote ? null : (note ?? this.note),
    );
  }

  /// Returns a copy with [paid] flipped. When flipping to paid, stamps [paidAt]
  /// (defaulting to [at] or now); when flipping to unpaid, clears it.
  RentEntry toggledPaid({DateTime? at}) {
    if (paid) {
      return copyWith(paid: false, clearPaidAt: true);
    }
    return copyWith(paid: true, paidAt: at ?? DateTime.now());
  }

  Map<String, dynamic> toJson() => {
        'year': year,
        'month': month,
        'amount': amount,
        'paid': paid,
        if (paidAt != null) 'paidAt': paidAt!.toIso8601String(),
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory RentEntry.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final rawPaidAt = json['paidAt'];
    return RentEntry(
      year: asInt(json['year']),
      month: asInt(json['month'], 1),
      amount: asInt(json['amount']),
      paid: json['paid'] == true,
      paidAt: rawPaidAt is String ? DateTime.tryParse(rawPaidAt) : null,
      note: (json['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['note'] as String,
    );
  }
}

/// A property's full rent ledger: its id plus an ordered list of monthly entries.
class RentLedger {
  RentLedger({
    required this.propertyId,
    List<RentEntry>? entries,
  }) : entries = List<RentEntry>.of(entries ?? const <RentEntry>[]) {
    _sort();
  }

  final String propertyId;

  /// Monthly entries, kept sorted oldest → newest.
  final List<RentEntry> entries;

  void _sort() => entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// Generates [count] consecutive monthly entries starting at [start]'s month,
  /// each expecting [monthlyAmount]. Existing entries for the same month are
  /// preserved (their paid status is kept); only missing months are added.
  /// Returns a NEW ledger.
  RentLedger generateMonths({
    required DateTime start,
    required int count,
    required int monthlyAmount,
  }) {
    final byKey = {for (final e in entries) e.sortKey: e};
    for (var i = 0; i < count; i++) {
      final d = DateTime(start.year, start.month + i);
      final key = d.year * 12 + d.month;
      byKey.putIfAbsent(
        key,
        () => RentEntry(year: d.year, month: d.month, amount: monthlyAmount),
      );
    }
    return RentLedger(propertyId: propertyId, entries: byKey.values.toList());
  }

  /// The entry for [now]'s month, if it exists.
  RentEntry? currentEntry([DateTime? now]) {
    final ref = now ?? DateTime.now();
    for (final e in entries) {
      if (e.year == ref.year && e.month == ref.month) return e;
    }
    return null;
  }

  /// All unpaid months that are in the past relative to [now].
  List<RentEntry> overdueEntries([DateTime? now]) =>
      entries.where((e) => e.isOverdue(now)).toList();

  /// Amount collected during [now]'s month (0 if unpaid / missing).
  int collectedThisMonth([DateTime? now]) {
    final c = currentEntry(now);
    return (c != null && c.paid) ? c.amount : 0;
  }

  /// Total owed: sum of all overdue (past + unpaid) amounts.
  int outstandingDebt([DateTime? now]) =>
      overdueEntries(now).fold(0, (sum, e) => sum + e.amount);

  /// Replaces the entry matching [updated]'s month, or appends it.
  RentLedger upsert(RentEntry updated) {
    final next = entries
        .where((e) => e.sortKey != updated.sortKey)
        .toList()
      ..add(updated);
    return RentLedger(propertyId: propertyId, entries: next);
  }

  /// Toggles the paid status of the entry at [index] in the sorted list.
  RentLedger togglePaidAt(int index, {DateTime? at}) {
    if (index < 0 || index >= entries.length) return this;
    final updated = entries[index].toggledPaid(at: at);
    return upsert(updated);
  }

  Map<String, dynamic> toJson() => {
        'propertyId': propertyId,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory RentLedger.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final parsed = <RentEntry>[];
    if (rawEntries is List) {
      for (final e in rawEntries) {
        if (e is Map) {
          parsed.add(RentEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return RentLedger(
      propertyId: json['propertyId']?.toString() ?? '',
      entries: parsed,
    );
  }
}
