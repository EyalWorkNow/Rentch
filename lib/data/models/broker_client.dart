/// A broker's (מתווך) client — a buyer/renter they're actively sourcing
/// listings for.
///
/// Brokers juggle many clients in their head, on WhatsApp, and on sticky notes.
/// This is the small, honest record that turns that chaos into a list the app
/// can match against the broker's own listings. It's deliberately flat and
/// device-local (SharedPreferences JSON, like [SavedSearch]) — a broker has tens
/// of clients, not thousands, and never needs a backend for their private book.
class BrokerClient {
  BrokerClient({
    required this.id,
    required this.name,
    this.phone = '',
    this.transactionType = 'rent',
    this.budgetMin,
    this.budgetMax,
    List<String>? areas,
    this.minRooms,
    List<String>? mustHaves,
    this.notes = '',
    DateTime? createdAt,
  })  : areas = List.unmodifiable(areas ?? const <String>[]),
        mustHaves = List.unmodifiable(mustHaves ?? const <String>[]),
        createdAt = createdAt ?? DateTime.now();

  /// Stable local id (SharedPreferences key + seen-match dedupe).
  final String id;

  /// Client's name, e.g. "משפחת כהן".
  final String name;

  /// Phone for a one-tap call/WhatsApp. Free text; may be empty.
  final String phone;

  /// `'rent'` or `'sale'` — matches [PropertyTransactionType.name].
  final String transactionType;

  /// Inclusive budget bounds, same units as [RentalProperty.price]. Null = open.
  final int? budgetMin;
  final int? budgetMax;

  /// Cities/neighborhoods the client will consider. Empty = anywhere.
  final List<String> areas;

  /// Minimum rooms the client needs. Null = no minimum.
  final double? minRooms;

  /// Must-have feature tags (e.g. "מעלית", "חניה"). A listing must contain all.
  final List<String> mustHaves;

  /// Free-text notes the broker keeps on this client.
  final String notes;

  final DateTime createdAt;

  bool get isSale => transactionType == 'sale';

  BrokerClient copyWith({
    String? name,
    String? phone,
    String? transactionType,
    int? budgetMin,
    int? budgetMax,
    List<String>? areas,
    double? minRooms,
    List<String>? mustHaves,
    String? notes,
  }) {
    return BrokerClient(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      transactionType: transactionType ?? this.transactionType,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      areas: areas ?? this.areas,
      minRooms: minRooms ?? this.minRooms,
      mustHaves: mustHaves ?? this.mustHaves,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'transactionType': transactionType,
        if (budgetMin != null) 'budgetMin': budgetMin,
        if (budgetMax != null) 'budgetMax': budgetMax,
        'areas': areas,
        if (minRooms != null) 'minRooms': minRooms,
        'mustHaves': mustHaves,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BrokerClient.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? v) => v == null ? null : (v as num).toDouble();
    int? toInt(Object? v) => v == null ? null : (v as num).toInt();
    List<String> toStrList(Object? v) => (v as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        const <String>[];

    return BrokerClient(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      transactionType: (json['transactionType'] ?? 'rent').toString(),
      budgetMin: toInt(json['budgetMin']),
      budgetMax: toInt(json['budgetMax']),
      areas: toStrList(json['areas']),
      minRooms: toDouble(json['minRooms']),
      mustHaves: toStrList(json['mustHaves']),
      notes: (json['notes'] ?? '').toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}
