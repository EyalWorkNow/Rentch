import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/legal_consent_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:geocoding/geocoding.dart';

/// Builds a complete, valid [RentalProperty] from the structured draft Erik (the
/// assistant) collected during a conversation — mirroring exactly what the
/// add-property form produces (geocoding, legal consent, price history, sane
/// defaults). This lets Erik actually publish a listing for an older landlord
/// instead of making them fill a form. Photos can be added later from
/// "הדירות שלי".
Future<RentalProperty> buildPropertyFromErikDraft(
  Map<String, dynamic> draft, {
  required String ownerName,
  List<String> photoUrls = const [],
}) async {
  String str(Object? v) => v == null ? '' : v.toString().trim();
  int? toInt(Object? v) {
    if (v is num) return v.toInt();
    final cleaned = str(v).replaceAll(RegExp(r'[^0-9]'), '');
    return cleaned.isEmpty ? null : int.tryParse(cleaned);
  }

  double? toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(str(v));
  }

  final city = InputSanitizer.sanitizeAddress(str(draft['city']));
  final street = InputSanitizer.sanitizeAddress(str(draft['street']));
  final streetNumber = toInt(draft['streetNumber']) ?? -1;
  final price = InputSanitizer.clampPrice(toInt(draft['price']) ?? 0);
  final rooms = InputSanitizer.clampRooms(toDouble(draft['rooms']) ?? 3);
  final size = InputSanitizer.clampSize(toInt(draft['sizeM2']) ?? 0);

  // Geocode the address; fall back to Tel Aviv centre so the map marker is valid.
  double lat = 32.0853;
  double lon = 34.7818;
  try {
    final parts = <String>[
      if (street.isNotEmpty) street,
      if (streetNumber > 0) '$streetNumber',
      if (city.isNotEmpty) city,
      'ישראל',
    ];
    if (parts.length > 1) {
      // Cap geocoding so a slow/blocked lookup can never hang the publish flow
      // (geocoding has no built-in timeout). On timeout we keep the TLV fallback.
      final locations = await locationFromAddress(parts.join(', '))
          .timeout(const Duration(seconds: 8));
      if (locations.isNotEmpty) {
        lat = locations.first.latitude;
        lon = locations.first.longitude;
      }
    }
  } catch (_) {}

  const transactionType = PropertyTransactionType.rent;
  final priceHistory = price > 0
      ? [
          PropertyPricePoint(
            date: DateTime.now().toUtc(),
            price: price,
            transactionType: transactionType,
          ),
        ]
      : const <PropertyPricePoint>[];

  // The landlord verbally confirmed the details with Erik before publishing.
  final legal = LegalConsentService.instance.grantConsent(source: 'erik_assistant');

  return RentalProperty(
    id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
    sourceUrl: '',
    price: price,
    rooms: rooms,
    sizeM2: size,
    floor: InputSanitizer.sanitizeText(str(draft['floor']), maxLength: 10),
    totalFloors:
        InputSanitizer.sanitizeText(str(draft['totalFloors']), maxLength: 10),
    city: city,
    neighborhood: InputSanitizer.sanitizeAddress(str(draft['neighborhood'])),
    street: street,
    streetNumber: streetNumber,
    lat: lat,
    lon: lon,
    propertyType:
        str(draft['propertyType']).isEmpty ? 'דירה' : str(draft['propertyType']),
    entryDate: InputSanitizer.sanitizeText(str(draft['entryDate']), maxLength: 20),
    condition: str(draft['condition']).isEmpty ? 'תקין' : str(draft['condition']),
    ownerName: ownerName.trim().isEmpty ? 'בעל הדירה' : ownerName.trim(),
    agencyListing: false,
    features: const <String>[],
    media: photoUrls
        .where((u) => u.trim().isNotEmpty)
        .map((u) => PropertyMedia(url: u.trim(), type: PropertyMediaType.image))
        .toList(),
    transactionType: transactionType,
    legal: legal,
    priceHistory: priceHistory,
    verification: const PropertyVerification(),
    createdAt: DateTime.now(),
  );
}
