import 'package:latlong2/latlong.dart';

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
    required this.imageUrls,
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
  final List<String> imageUrls;

  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;
  LatLng get point => LatLng(lat, lon);

  String get address {
    final streetPart = streetNumber > 0 ? '$street $streetNumber' : street;
    return [
      if (streetPart.trim().isNotEmpty) streetPart.trim(),
      if (neighborhood.trim().isNotEmpty) neighborhood.trim(),
      city,
    ].join(', ');
  }

  String get priceLabel => '₪${_formatNumber(price)}';
  String get roomsLabel =>
      rooms % 1 == 0 ? rooms.toInt().toString() : rooms.toString();

  factory RentalProperty.fromJson(Map<String, dynamic> json) {
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
      imageUrls:
          List<String>.from(json['imageUrls'] as List<dynamic>? ?? const []),
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
      'imageUrls': imageUrls,
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

class SearchFilters {
  const SearchFilters({
    required this.maxBudget,
    required this.minRooms,
    required this.areaId,
    required this.requiredFeatures,
  });

  final int maxBudget;
  final double minRooms;
  final String areaId;
  final Set<String> requiredFeatures;

  SearchFilters copyWith({
    int? maxBudget,
    double? minRooms,
    String? areaId,
    Set<String>? requiredFeatures,
  }) {
    return SearchFilters(
      maxBudget: maxBudget ?? this.maxBudget,
      minRooms: minRooms ?? this.minRooms,
      areaId: areaId ?? this.areaId,
      requiredFeatures: requiredFeatures ?? this.requiredFeatures,
    );
  }

  factory SearchFilters.fromJson(Map<String, dynamic> json) {
    return SearchFilters(
      maxBudget: json['maxBudget'] as int? ?? 9000,
      minRooms: (json['minRooms'] as num? ?? 2).toDouble(),
      areaId: json['areaId'] as String? ?? 'central_tel_aviv',
      requiredFeatures: Set<String>.from(
        json['requiredFeatures'] as List<dynamic>? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxBudget': maxBudget,
      'minRooms': minRooms,
      'areaId': areaId,
      'requiredFeatures': requiredFeatures.toList(),
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
