import 'package:dating_app/data/models/rental_models.dart';

/// A tenant's saved apartment search.
///
/// In Israel good apartments rent within days, so a tenant who knows what they
/// want should be able to "save the search" and be told the moment a *new*
/// matching listing appears — instead of refreshing the feed all day.
///
/// This model is deliberately small and honest: it stores only the few criteria
/// we can cheaply check against a [RentalProperty] on the device (city, price,
/// rooms, rent/sale, a handful of must-have tags). [matches] is a plain boolean
/// predicate — no scoring, no surprises — so an older, stressed user always gets
/// a result they can reason about.
class SavedSearch {
  SavedSearch({
    required this.id,
    required this.name,
    this.city,
    this.minBudget,
    this.maxBudget,
    this.minRooms,
    this.maxRooms,
    this.transactionType,
    List<String>? requiredTags,
    this.alertsOn = true,
    DateTime? createdAt,
  })  : requiredTags = List.unmodifiable(requiredTags ?? const <String>[]),
        createdAt = createdAt ?? DateTime.now();

  /// Stable local id (used as the SharedPreferences map key + notification dedupe).
  final String id;

  /// What the tenant calls this search, e.g. "3 חדרים בתל אביב".
  final String name;

  /// Desired city. Null/empty means "anywhere".
  final String? city;

  /// Inclusive budget bounds, in the same units as [RentalProperty.price].
  final int? minBudget;
  final int? maxBudget;

  /// Inclusive room-count bounds.
  final double? minRooms;
  final double? maxRooms;

  /// `'rent'` or `'sale'` (matching [PropertyTransactionType.name]); null = any.
  final String? transactionType;

  /// Must-have tags/features — a listing must contain *all* of them to match.
  /// Compared case-insensitively against the property's feature labels/text.
  final List<String> requiredTags;

  /// Whether this search should fire local "new listing" alerts.
  final bool alertsOn;

  final DateTime createdAt;

  SavedSearch copyWith({
    String? name,
    String? city,
    int? minBudget,
    int? maxBudget,
    double? minRooms,
    double? maxRooms,
    String? transactionType,
    List<String>? requiredTags,
    bool? alertsOn,
  }) {
    return SavedSearch(
      id: id,
      name: name ?? this.name,
      city: city ?? this.city,
      minBudget: minBudget ?? this.minBudget,
      maxBudget: maxBudget ?? this.maxBudget,
      minRooms: minRooms ?? this.minRooms,
      maxRooms: maxRooms ?? this.maxRooms,
      transactionType: transactionType ?? this.transactionType,
      requiredTags: requiredTags ?? this.requiredTags,
      alertsOn: alertsOn ?? this.alertsOn,
      createdAt: createdAt,
    );
  }

  /// True if [property] satisfies every criterion that was actually set. Unset
  /// criteria (null/empty) never exclude — so an empty search matches everything.
  bool matches(RentalProperty property) {
    final wantedCity = city?.trim();
    if (wantedCity != null && wantedCity.isNotEmpty) {
      if (property.city.trim().toLowerCase() != wantedCity.toLowerCase()) {
        return false;
      }
    }

    if (minBudget != null && property.price < minBudget!) return false;
    if (maxBudget != null && property.price > maxBudget!) return false;

    if (minRooms != null && property.rooms < minRooms!) return false;
    if (maxRooms != null && property.rooms > maxRooms!) return false;

    final wantedType = transactionType?.trim();
    if (wantedType != null && wantedType.isNotEmpty) {
      if (property.transactionType.name != wantedType) return false;
    }

    if (requiredTags.isNotEmpty) {
      final haystack = property.searchableText; // already lower-cased
      for (final tag in requiredTags) {
        final needle = tag.trim().toLowerCase();
        if (needle.isEmpty) continue;
        if (!haystack.contains(needle)) return false;
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (city != null) 'city': city,
        if (minBudget != null) 'minBudget': minBudget,
        if (maxBudget != null) 'maxBudget': maxBudget,
        if (minRooms != null) 'minRooms': minRooms,
        if (maxRooms != null) 'maxRooms': maxRooms,
        if (transactionType != null) 'transactionType': transactionType,
        'requiredTags': requiredTags,
        'alertsOn': alertsOn,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? v) => v == null ? null : (v as num).toDouble();
    int? toInt(Object? v) => v == null ? null : (v as num).toInt();

    return SavedSearch(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      minBudget: toInt(json['minBudget']),
      maxBudget: toInt(json['maxBudget']),
      minRooms: toDouble(json['minRooms']),
      maxRooms: toDouble(json['maxRooms']),
      transactionType: json['transactionType']?.toString(),
      requiredTags: (json['requiredTags'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      alertsOn: json['alertsOn'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}
