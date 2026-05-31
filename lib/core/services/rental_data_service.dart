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
      // All Israel — covers all 21 cities in the dataset
      SearchArea(
        id: 'all_israel',
        name: 'כל הארץ',
        center: LatLng(32.07, 34.87),
        polygon: [
          LatLng(31.65, 34.50),
          LatLng(31.65, 35.30),
          LatLng(32.50, 35.30),
          LatLng(32.50, 34.50),
        ],
      ),
      // Tel Aviv Center — organic polygon following the city's coastal/central shape
      SearchArea(
        id: 'central_tel_aviv',
        name: 'תל אביב מרכז',
        center: LatLng(32.075, 34.785),
        polygon: [
          LatLng(32.048, 34.752),
          LatLng(32.063, 34.747),
          LatLng(32.085, 34.749),
          LatLng(32.106, 34.754),
          LatLng(32.120, 34.763),
          LatLng(32.128, 34.780),
          LatLng(32.125, 34.810),
          LatLng(32.118, 34.830),
          LatLng(32.100, 34.838),
          LatLng(32.075, 34.836),
          LatLng(32.055, 34.831),
          LatLng(32.043, 34.816),
          LatLng(32.040, 34.795),
          LatLng(32.044, 34.771),
        ],
      ),
      // Gush Dan — wider metro area following regional boundaries
      SearchArea(
        id: 'gush_dan',
        name: 'גוש דן',
        center: LatLng(32.065, 34.805),
        polygon: [
          LatLng(31.994, 34.745),
          LatLng(32.018, 34.737),
          LatLng(32.048, 34.735),
          LatLng(32.085, 34.738),
          LatLng(32.120, 34.743),
          LatLng(32.140, 34.758),
          LatLng(32.148, 34.786),
          LatLng(32.145, 34.820),
          LatLng(32.138, 34.855),
          LatLng(32.118, 34.872),
          LatLng(32.080, 34.876),
          LatLng(32.040, 34.872),
          LatLng(32.005, 34.860),
          LatLng(31.990, 34.838),
          LatLng(31.988, 34.805),
          LatLng(31.990, 34.773),
        ],
      ),
      // HaSharon & North — Herzliya, Ra'anana, Kfar Saba, Netanya
      SearchArea(
        id: 'hasharon',
        name: 'השרון',
        center: LatLng(32.220, 34.870),
        polygon: [
          LatLng(32.118, 34.775),
          LatLng(32.140, 34.758),
          LatLng(32.165, 34.757),
          LatLng(32.200, 34.780),
          LatLng(32.250, 34.805),
          LatLng(32.340, 34.840),
          LatLng(32.360, 34.870),
          LatLng(32.350, 34.920),
          LatLng(32.310, 34.940),
          LatLng(32.260, 34.930),
          LatLng(32.210, 34.920),
          LatLng(32.170, 34.910),
          LatLng(32.140, 34.890),
          LatLng(32.120, 34.860),
          LatLng(32.115, 34.820),
        ],
      ),
      // South & Foothills — Rishon, Rehovot, Nes Ziona, Yavne, Gadera, Lod, Ramla, Modi'in
      SearchArea(
        id: 'south_center',
        name: 'מרכז-דרום',
        center: LatLng(31.90, 34.90),
        polygon: [
          LatLng(31.75, 34.70),
          LatLng(31.75, 35.10),
          LatLng(32.00, 35.10),
          LatLng(32.00, 34.70),
        ],
      ),
    ];
  }
}
