import 'dart:convert';

import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class RentalDataService {
  static const String assetPath = 'assets/data/proxy_listings.json';

  Future<List<RentalProperty>> loadListings() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;

    return decoded
        .map((item) =>
            RentalProperty.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  TenantProfile createDefaultTenantProfile() {
    return const TenantProfile(
      id: 'tenant-local',
      name: 'נועה לוי',
      bio:
          'מחפשת דירה שקטה ומוארת במרכז, עדיפות לבניין עם מעלית ומרחב עבודה נוח. עובדת בהייטק, שוכרת מסודרת, כניסה גמישה.',
      photoUrls: [
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
      ],
      budgetMax: 9000,
      desiredRooms: 2.5,
      moveInWindow: 'כניסה תוך 60 יום',
      importantDetails: [
        'ערבות בנקאית מוכנה',
        'ללא חיות מחמד',
        'עבודה קבועה',
        'עדיפות לחניה'
      ],
    );
  }

  List<AppReview> createTenantReviews() {
    return const [
      AppReview(
        id: 'tenant-review-1',
        authorName: 'מיכל, בעלת דירה קודמת',
        rating: 5,
        text: 'שוכרת מסודרת, תקשורת ברורה ותשלומים בזמן.',
      ),
      AppReview(
        id: 'tenant-review-2',
        authorName: 'אורן, שותף לשעבר',
        rating: 4,
        text: 'נעימה, שומרת על דירה נקייה ומכבדת שכנים.',
      ),
    ];
  }

  List<AppReview> createPropertyReviews(RentalProperty property) {
    final area =
        property.neighborhood.isEmpty ? property.city : property.neighborhood;
    return [
      AppReview(
        id: '${property.id}-review-1',
        authorName: 'שוכר קודם',
        rating: property.features.contains('מעלית') ? 5 : 4,
        text:
            'הדירה באזור $area, התחזוקה הייתה טובה והתקשורת עם בעל הנכס הייתה זמינה.',
      ),
    ];
  }

  List<SearchArea> createSearchAreas() {
    return const [
      SearchArea(
        id: 'central_tel_aviv',
        name: 'תל אביב מרכז',
        center: LatLng(32.075, 34.785),
        polygon: [
          LatLng(32.045, 34.745),
          LatLng(32.118, 34.750),
          LatLng(32.130, 34.835),
          LatLng(32.055, 34.835),
        ],
      ),
      SearchArea(
        id: 'gush_dan',
        name: 'גוש דן',
        center: LatLng(32.065, 34.805),
        polygon: [
          LatLng(31.990, 34.735),
          LatLng(32.130, 34.735),
          LatLng(32.145, 34.875),
          LatLng(31.990, 34.875),
        ],
      ),
      SearchArea(
        id: 'hasharon',
        name: 'השרון',
        center: LatLng(32.165, 34.835),
        polygon: [
          LatLng(32.120, 34.780),
          LatLng(32.210, 34.780),
          LatLng(32.215, 34.895),
          LatLng(32.125, 34.900),
        ],
      ),
    ];
  }
}
