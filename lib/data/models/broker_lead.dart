/// A single sales lead a broker (מתווך) is working on.
///
/// Brokers in Israel juggle dozens of interested clients across phone, WhatsApp,
/// Yad2 and walk-ins; the ones that slip are the ones nobody followed up on. This
/// model is the minimal "card" that moves through a pipeline of [LeadStage]s, ties
/// to one of the broker's own listings, and carries an optional [nextFollowUp] so
/// the screen can surface anything overdue. Local-only (SharedPreferences JSON),
/// matching the app's existing saved-search store — no backend.
enum LeadStage {
  newLead,
  contacted,
  viewing,
  negotiation,
  closedWon,
  closedLost,
}

extension LeadStageLabel on LeadStage {
  /// Hebrew section header for the pipeline board.
  String get hebrew {
    switch (this) {
      case LeadStage.newLead:
        return 'ליד חדש';
      case LeadStage.contacted:
        return 'יצרתי קשר';
      case LeadStage.viewing:
        return 'בתיאום צפייה';
      case LeadStage.negotiation:
        return 'במשא ומתן';
      case LeadStage.closedWon:
        return 'נסגר בהצלחה';
      case LeadStage.closedLost:
        return 'נסגר ללא עסקה';
    }
  }

  bool get isClosed =>
      this == LeadStage.closedWon || this == LeadStage.closedLost;
}

class BrokerLead {
  BrokerLead({
    required this.id,
    required this.clientName,
    this.phone = '',
    this.propertyId = '',
    this.propertyTitle = '',
    this.stage = LeadStage.newLead,
    this.source = '',
    this.nextFollowUp,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String clientName;
  final String phone;

  /// The broker listing this lead is interested in (may be empty if general).
  final String propertyId;
  final String propertyTitle;

  final LeadStage stage;

  /// Free-form origin tag, e.g. yad2 / whatsapp / call / walkin.
  final String source;

  /// When the broker should next chase this lead. Null = nothing scheduled.
  final DateTime? nextFollowUp;
  final String notes;
  final DateTime createdAt;

  /// A follow-up that should already have happened (and the lead is still open).
  bool isOverdue(DateTime now) {
    final due = nextFollowUp;
    if (due == null || stage.isClosed) return false;
    return due.isBefore(now);
  }

  BrokerLead copyWith({
    String? clientName,
    String? phone,
    String? propertyId,
    String? propertyTitle,
    LeadStage? stage,
    String? source,
    DateTime? nextFollowUp,
    bool clearFollowUp = false,
    String? notes,
  }) {
    return BrokerLead(
      id: id,
      clientName: clientName ?? this.clientName,
      phone: phone ?? this.phone,
      propertyId: propertyId ?? this.propertyId,
      propertyTitle: propertyTitle ?? this.propertyTitle,
      stage: stage ?? this.stage,
      source: source ?? this.source,
      nextFollowUp: clearFollowUp ? null : (nextFollowUp ?? this.nextFollowUp),
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  factory BrokerLead.fromJson(Map<String, dynamic> json) {
    return BrokerLead(
      id: json['id']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      stage: _parseStage(json['stage']),
      source: json['source']?.toString() ?? '',
      nextFollowUp: _parseDate(json['nextFollowUp']),
      notes: json['notes']?.toString() ?? '',
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
    );
  }

  static const int schemaVersion = 1;

  Map<String, dynamic> toJson() {
    return {
      '_schemaV': schemaVersion,
      'id': id,
      'clientName': clientName,
      'phone': phone,
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'stage': stage.name,
      'source': source,
      'nextFollowUp': nextFollowUp?.toIso8601String(),
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static LeadStage _parseStage(Object? raw) {
    final name = raw?.toString();
    return LeadStage.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LeadStage.newLead,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
