import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks two relevance fixes the fresh self-audit surfaced:
//  1. the ~10-option backfill must NOT pad a search with flats >15% over the
//     stated budget (a ₪3300 flat for "עד 2800").
//  2. an explicit "על הים" search must NOT backfill clearly-inland flats.

Future<String> _r(String p) => File(p).readAsString();

RentalProperty f(String id, int price, double rooms, String city, double lat, double lon,
        {List<String> ft = const []}) =>
    RentalProperty(id: id, price: price, rooms: rooms, sizeM2: (rooms * 26).round(), floor: '3', totalFloors: '20',
        city: city, neighborhood: '', street: 'הרצל', streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
        transactionType: PropertyTransactionType.rent, entryDate: '', condition: 'טוב', ownerName: 'x',
        agencyListing: false, features: ft,
        media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
        marketSignals: const PropertyMarketSignals(views: 130, likes: 20, saves: 6),
        verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)));

void main() {
  setUpAll(() async { TestWidgetsFlutterBinding.ensureInitialized(); await GovData.instance.init(reader: _r); });

  test('backfill never pads a search with flats >15% over the stated budget', () {
    final cat = [
      f('cheap', 2600, 2, 'באר שבע', 31.262, 34.799),
      f('over18', 3300, 3, 'באר שבע', 31.25, 34.79),   // 18% over 2800 → must NOT show
      f('over40', 3900, 3, 'באר שבע', 31.24, 34.78),   // 39% over → must NOT show
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat, query: SmartSearch.parse('דירה בבאר שבע עד 2800'),
      profile: null, limit: 8, seed: 7);
    expect(recs, isNotEmpty);
    for (final s in recs) {
      expect(s.property.price <= 2800 * 1.15, true,
          reason: '${s.property.id} ₪${s.property.price} padded a "עד 2800" search');
    }
  });

  test('"על הים" never backfills a clearly-inland flat', () {
    final cat = [
      f('ta-beach', 11000, 3, 'תל אביב', 32.081, 34.767),   // ~beachfront
      f('ta-inland', 9000, 3, 'תל אביב', 32.07, 34.80),      // a few km in
      f('rg-inland', 7000, 3, 'רמת גן', 32.083, 34.83),      // clearly inland
      f('jlm', 6000, 3, 'ירושלים', 31.772, 35.213),          // far inland
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat, query: SmartSearch.parse('דירה על הים בתל אביב עד 12000'),
      profile: null, limit: 8, seed: 7);
    expect(recs, isNotEmpty);
    expect(recs.first.property.id, 'ta-beach', reason: 'beachfront should lead');
    for (final s in recs) {
      final km = IsraelGeoIndex.coastKm(s.property.lat, s.property.lon);
      expect(km != null && km <= 5.5, true,
          reason: '${s.property.id} is ${km?.toStringAsFixed(1)}km inland — not "על הים"');
    }
  });

  test('a slightly-over near-match (≤15%) may still show, flagged as a concern', () {
    final cat = [
      f('inb', 6000, 3, 'רמת גן', 32.08, 34.81),
      f('over12', 6700, 4, 'רמת גן', 32.083, 34.814), // 12% over 6000 → allowed
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat, query: SmartSearch.parse('דירה ברמת גן עד 6000'),
      profile: null, limit: 8, seed: 7);
    final over = recs.where((s) => s.property.id == 'over12');
    if (over.isNotEmpty) {
      // if shown, it must carry an over-budget concern (honest, not hidden)
      final concerns = over.first.scorecard!.concerns.join(' ');
      expect(concerns.contains('תקציב'), true,
          reason: 'a ≤15%-over flat must be flagged as over-budget');
    }
    for (final s in recs) {
      expect(s.property.price <= 6000 * 1.15, true);
    }
  });
}
