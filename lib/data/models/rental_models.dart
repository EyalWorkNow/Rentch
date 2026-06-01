import 'package:latlong2/latlong.dart';

enum SearchSortOption {
  bestMatch,
  priceLowToHigh,
  priceHighToLow,
  newestEntry,
  biggestFirst,
}

enum ListingSourceFilter {
  any,
  privateOnly,
  agencyOnly,
}

enum MoveInFilter {
  any,
  immediate,
  within30Days,
  within90Days,
}

enum PropertyTransactionType { rent, sale }

enum TransactionTypeFilter { any, rent, sale }

enum PropertyMediaType { image, video }

class PropertyMedia {
  const PropertyMedia({
    required this.url,
    required this.type,
  });

  final String url;
  final PropertyMediaType type;

  bool get isImage => type == PropertyMediaType.image;
  bool get isVideo => type == PropertyMediaType.video;

  factory PropertyMedia.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String?;
    final url = json['url'] as String? ?? '';
    return PropertyMedia(
      url: url,
      type: rawType == 'video'
          ? PropertyMediaType.video
          : rawType == 'image'
              ? PropertyMediaType.image
              : _inferMediaType(url),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type.name,
    };
  }
}

class RentalProperty {
  const RentalProperty({
    required this.id,
    required this.url,
    required this.price,
    required this.rooms,
    required this.sizeM2,
    required this.floor,
    required this.totalFloors,
    required this.city,
    required this.neighborhood,
    required this.street,
    required this.streetNumber,
    required this.lat,
    required this.lon,
    required this.propertyType,
    required this.entryDate,
    required this.condition,
    required this.ownerName,
    required this.agencyListing,
    required this.features,
    required this.media,
    this.transactionType = PropertyTransactionType.rent,
  });

  final String id;
  final String url;
  final int price;
  final double rooms;
  final int sizeM2;
  final String floor;
  final String totalFloors;
  final String city;
  final String neighborhood;
  final String street;
  final int streetNumber;
  final double lat;
  final double lon;
  final String propertyType;
  final String entryDate;
  final String condition;
  final String ownerName;
  final bool agencyListing;
  final List<String> features;
  final List<PropertyMedia> media;
  final PropertyTransactionType transactionType;

  PropertyMedia? get primaryMedia => media.isEmpty ? null : media.first;
  List<String> get mediaUrls => media.map((item) => item.url).toList();
  List<String> get imageUrls =>
      media.where((item) => item.isImage).map((item) => item.url).toList();
  List<String> get videoUrls =>
      media.where((item) => item.isVideo).map((item) => item.url).toList();
  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;
  LatLng get point => LatLng(lat, lon);
  int? get floorNumber => int.tryParse(floor);
  DateTime? get entryDateValue => DateTime.tryParse(entryDate);
  int? get pricePerSquareMeter => sizeM2 > 0 ? (price / sizeM2).round() : null;
  String get searchableText => [
        city,
        neighborhood,
        street,
        ownerName,
        propertyType,
        condition,
        transactionType == PropertyTransactionType.sale ? 'מכירה' : 'השכרה',
        ...features,
      ].join(' ').toLowerCase();

  String get address {
    final streetPart = streetNumber > 0 ? '$street $streetNumber' : street;
    return [
      if (streetPart.trim().isNotEmpty) streetPart.trim(),
      if (neighborhood.trim().isNotEmpty) neighborhood.trim(),
      city,
    ].join(', ');
  }

  String get priceLabel => '₪${_formatNumber(price)}';
  String get priceSuffixLabel =>
      transactionType == PropertyTransactionType.sale ? 'למכירה' : 'לחודש';
  String get transactionLabel =>
      transactionType == PropertyTransactionType.sale ? 'מכירה' : 'השכרה';
  String get roomsLabel =>
      rooms % 1 == 0 ? rooms.toInt().toString() : rooms.toString();

  factory RentalProperty.fromJson(Map<String, dynamic> json) {
    final mediaJson = json['media'] as List<dynamic>? ?? const [];
    final legacyImageUrls =
        List<String>.from(json['imageUrls'] as List<dynamic>? ?? const []);
    final legacyVideoUrls =
        List<String>.from(json['videoUrls'] as List<dynamic>? ?? const []);
    final media = mediaJson.isNotEmpty
        ? mediaJson
            .map((item) =>
                PropertyMedia.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList()
        : [
            ...legacyImageUrls.map(
              (url) => PropertyMedia(
                url: url,
                type: PropertyMediaType.image,
              ),
            ),
            ...legacyVideoUrls.map(
              (url) => PropertyMedia(
                url: url,
                type: PropertyMediaType.video,
              ),
            ),
          ];

    return RentalProperty(
      id: json['id'] as String,
      url: json['url'] as String,
      price: json['price'] as int,
      rooms: (json['rooms'] as num).toDouble(),
      sizeM2: json['sizeM2'] as int,
      floor: json['floor'] as String? ?? '',
      totalFloors: json['totalFloors'] as String? ?? '',
      city: json['city'] as String,
      neighborhood: json['neighborhood'] as String? ?? '',
      street: json['street'] as String? ?? '',
      streetNumber: json['streetNumber'] as int? ?? -1,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      propertyType: json['propertyType'] as String,
      entryDate: json['entryDate'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? 'בעל הנכס',
      agencyListing: json['agencyListing'] as bool? ?? false,
      features:
          List<String>.from(json['features'] as List<dynamic>? ?? const []),
      media: media,
      transactionType: _parseTransactionType(json['transactionType']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'price': price,
      'rooms': rooms,
      'sizeM2': sizeM2,
      'floor': floor,
      'totalFloors': totalFloors,
      'city': city,
      'neighborhood': neighborhood,
      'street': street,
      'streetNumber': streetNumber,
      'lat': lat,
      'lon': lon,
      'propertyType': propertyType,
      'entryDate': entryDate,
      'condition': condition,
      'ownerName': ownerName,
      'agencyListing': agencyListing,
      'features': features,
      'media': media.map((item) => item.toJson()).toList(),
      'imageUrls': imageUrls,
      'videoUrls': videoUrls,
      'transactionType': transactionType.name,
    };
  }
}

class TenantProfile {
  const TenantProfile({
    required this.id,
    required this.name,
    required this.bio,
    required this.photoUrls,
    required this.budgetMax,
    required this.desiredRooms,
    required this.moveInWindow,
    required this.importantDetails,
  });

  final String id;
  final String name;
  final String bio;
  final List<String> photoUrls;
  final int budgetMax;
  final double desiredRooms;
  final String moveInWindow;
  final List<String> importantDetails;

  String get photoUrl => photoUrls.isEmpty ? '' : photoUrls.first;

  TenantProfile copyWith({
    String? name,
    String? bio,
    List<String>? photoUrls,
    int? budgetMax,
    double? desiredRooms,
    String? moveInWindow,
    List<String>? importantDetails,
  }) {
    return TenantProfile(
      id: id,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      photoUrls: photoUrls ?? this.photoUrls,
      budgetMax: budgetMax ?? this.budgetMax,
      desiredRooms: desiredRooms ?? this.desiredRooms,
      moveInWindow: moveInWindow ?? this.moveInWindow,
      importantDetails: importantDetails ?? this.importantDetails,
    );
  }

  factory TenantProfile.fromJson(Map<String, dynamic> json) {
    return TenantProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      bio: json['bio'] as String,
      photoUrls:
          List<String>.from(json['photoUrls'] as List<dynamic>? ?? const []),
      budgetMax: json['budgetMax'] as int,
      desiredRooms: (json['desiredRooms'] as num).toDouble(),
      moveInWindow: json['moveInWindow'] as String,
      importantDetails: List<String>.from(
        json['importantDetails'] as List<dynamic>? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'bio': bio,
      'photoUrls': photoUrls,
      'budgetMax': budgetMax,
      'desiredRooms': desiredRooms,
      'moveInWindow': moveInWindow,
      'importantDetails': importantDetails,
    };
  }
}

class SearchArea {
  const SearchArea({
    required this.id,
    required this.name,
    required this.center,
    required this.polygon,
  });

  final String id;
  final String name;
  final LatLng center;
  final List<LatLng> polygon;

  bool contains(LatLng point) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi + 0.0) + xi);
      if (intersects) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// Feature tag priority in filters.
/// [none] = unselected, [preferred] = nice-to-have (blue), [dealBreaker] = must-have (red).
enum FeatureTagState { none, preferred, dealBreaker }

class SearchFilters {
  const SearchFilters({
    required this.query,
    required this.maxBudget,
    required this.minRooms,
    required this.areaId,
    required this.requiredFeatures,
    required this.preferredFeatures,
    required this.minSizeM2,
    required this.maxSizeM2,
    required this.propertyTypes,
    required this.conditions,
    required this.listingSource,
    required this.minFloor,
    required this.moveInFilter,
    required this.sortBy,
    this.city = '',
    this.transactionType = TransactionTypeFilter.any,
  });

  final String query;
  final int maxBudget;
  final double minRooms;
  final String areaId;
  /// Red tags — deal breakers. Properties missing any of these are excluded entirely.
  final Set<String> requiredFeatures;
  /// Blue tags — nice-to-have preferences. Boost score proportionally.
  final Set<String> preferredFeatures;
  final int minSizeM2;
  final int maxSizeM2;
  final Set<String> propertyTypes;
  final Set<String> conditions;
  final ListingSourceFilter listingSource;
  final int minFloor;
  final MoveInFilter moveInFilter;
  final SearchSortOption sortBy;
  final String city;
  final TransactionTypeFilter transactionType;

  bool get hasQuery => query.trim().isNotEmpty;

  /// Returns the [FeatureTagState] for a given feature tag.
  FeatureTagState featureState(String feature) {
    if (requiredFeatures.contains(feature)) return FeatureTagState.dealBreaker;
    if (preferredFeatures.contains(feature)) return FeatureTagState.preferred;
    return FeatureTagState.none;
  }

  /// Cycles tag through: none → preferred → dealBreaker → none.
  SearchFilters cycleFeature(String feature) {
    final state = featureState(feature);
    final newPreferred = {...preferredFeatures};
    final newRequired = {...requiredFeatures};
    switch (state) {
      case FeatureTagState.none:
        newPreferred.add(feature);
      case FeatureTagState.preferred:
        newPreferred.remove(feature);
        newRequired.add(feature);
      case FeatureTagState.dealBreaker:
        newRequired.remove(feature);
    }
    return copyWith(preferredFeatures: newPreferred, requiredFeatures: newRequired);
  }

  SearchFilters copyWith({
    String? query,
    int? maxBudget,
    double? minRooms,
    String? areaId,
    Set<String>? requiredFeatures,
    Set<String>? preferredFeatures,
    int? minSizeM2,
    int? maxSizeM2,
    Set<String>? propertyTypes,
    Set<String>? conditions,
    ListingSourceFilter? listingSource,
    int? minFloor,
    MoveInFilter? moveInFilter,
    SearchSortOption? sortBy,
    String? city,
    TransactionTypeFilter? transactionType,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      maxBudget: maxBudget ?? this.maxBudget,
      minRooms: minRooms ?? this.minRooms,
      areaId: areaId ?? this.areaId,
      requiredFeatures: requiredFeatures ?? this.requiredFeatures,
      preferredFeatures: preferredFeatures ?? this.preferredFeatures,
      minSizeM2: minSizeM2 ?? this.minSizeM2,
      maxSizeM2: maxSizeM2 ?? this.maxSizeM2,
      propertyTypes: propertyTypes ?? this.propertyTypes,
      conditions: conditions ?? this.conditions,
      listingSource: listingSource ?? this.listingSource,
      minFloor: minFloor ?? this.minFloor,
      moveInFilter: moveInFilter ?? this.moveInFilter,
      sortBy: sortBy ?? this.sortBy,
      city: city ?? this.city,
      transactionType: transactionType ?? this.transactionType,
    );
  }

  factory SearchFilters.fromJson(Map<String, dynamic> json) {
    return SearchFilters(
      query: json['query'] as String? ?? '',
      maxBudget: json['maxBudget'] as int? ?? 2000000000,
      minRooms: (json['minRooms'] as num? ?? 0).toDouble(),
      areaId: json['areaId'] as String? ?? 'all_israel',
      requiredFeatures: Set<String>.from(
        json['requiredFeatures'] as List<dynamic>? ?? const [],
      ),
      preferredFeatures: Set<String>.from(
        json['preferredFeatures'] as List<dynamic>? ?? const [],
      ),
      minSizeM2: json['minSizeM2'] as int? ?? 0,
      maxSizeM2: json['maxSizeM2'] as int? ?? 1000000,
      propertyTypes: Set<String>.from(
        json['propertyTypes'] as List<dynamic>? ?? const [],
      ),
      conditions: Set<String>.from(
        json['conditions'] as List<dynamic>? ?? const [],
      ),
      listingSource: ListingSourceFilter.values.byName(
        json['listingSource'] as String? ?? ListingSourceFilter.any.name,
      ),
      minFloor: json['minFloor'] as int? ?? 0,
      moveInFilter: MoveInFilter.values.byName(
        json['moveInFilter'] as String? ?? MoveInFilter.any.name,
      ),
      sortBy: SearchSortOption.values.byName(
        json['sortBy'] as String? ?? SearchSortOption.bestMatch.name,
      ),
      city: json['city'] as String? ?? '',
      transactionType: TransactionTypeFilter.values.byName(
        json['transactionType'] as String? ?? TransactionTypeFilter.any.name,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      'maxBudget': maxBudget,
      'minRooms': minRooms,
      'areaId': areaId,
      'requiredFeatures': requiredFeatures.toList(),
      'preferredFeatures': preferredFeatures.toList(),
      'minSizeM2': minSizeM2,
      'maxSizeM2': maxSizeM2,
      'propertyTypes': propertyTypes.toList(),
      'conditions': conditions.toList(),
      'listingSource': listingSource.name,
      'minFloor': minFloor,
      'moveInFilter': moveInFilter.name,
      'sortBy': sortBy.name,
      'city': city,
      'transactionType': transactionType.name,
    };
  }
}

class AppReview {
  const AppReview({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.text,
  });

  final String id;
  final String authorName;
  final int rating;
  final String text;

  factory AppReview.fromJson(Map<String, dynamic> json) {
    return AppReview(
      id: json['id'] as String,
      authorName: json['authorName'] as String,
      rating: json['rating'] as int,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorName': authorName,
      'rating': rating,
      'text': text,
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String sender;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      sender: json['sender'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class RentalMatch {
  const RentalMatch({
    required this.id,
    required this.propertyId,
    required this.createdAt,
    required this.messages,
    required this.contractSent,
    required this.ownerSigned,
    required this.tenantSigned,
  });

  final String id;
  final String propertyId;
  final DateTime createdAt;
  final List<ChatMessage> messages;
  final bool contractSent;
  final bool ownerSigned;
  final bool tenantSigned;

  RentalMatch copyWith({
    List<ChatMessage>? messages,
    bool? contractSent,
    bool? ownerSigned,
    bool? tenantSigned,
  }) {
    return RentalMatch(
      id: id,
      propertyId: propertyId,
      createdAt: createdAt,
      messages: messages ?? this.messages,
      contractSent: contractSent ?? this.contractSent,
      ownerSigned: ownerSigned ?? this.ownerSigned,
      tenantSigned: tenantSigned ?? this.tenantSigned,
    );
  }

  factory RentalMatch.fromJson(Map<String, dynamic> json) {
    return RentalMatch(
      id: json['id'] as String,
      propertyId: json['propertyId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .map((item) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      contractSent: json['contractSent'] as bool? ?? false,
      ownerSigned: json['ownerSigned'] as bool? ?? false,
      tenantSigned: json['tenantSigned'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'propertyId': propertyId,
      'createdAt': createdAt.toIso8601String(),
      'messages': messages.map((message) => message.toJson()).toList(),
      'contractSent': contractSent,
      'ownerSigned': ownerSigned,
      'tenantSigned': tenantSigned,
    };
  }
}

String _formatNumber(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

PropertyMediaType _inferMediaType(String url) {
  final normalized = url.split('?').first.toLowerCase();
  if (normalized.endsWith('.mp4') ||
      normalized.endsWith('.mov') ||
      normalized.endsWith('.m4v') ||
      normalized.endsWith('.webm')) {
    return PropertyMediaType.video;
  }
  return PropertyMediaType.image;
}

PropertyTransactionType _parseTransactionType(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'sale' || 'sell' || 'for_sale' => PropertyTransactionType.sale,
    _ => PropertyTransactionType.rent,
  };
}
