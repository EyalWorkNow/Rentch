import 'dart:math' as math;
import 'package:dating_app/data/models/rental_models.dart';

// Advanced multi-dimensional matching engine for the apartment search assistant.
// Uses user preference vectors, contextual signals, and behavioral factors to
// rank properties with high precision and explainability.

class UserIntentVector {
  UserIntentVector({
    required this.locationDesirability, // 0..1: how much user cares about location
    required this.priceElasticity, // 0..1: willingness to spend above stated max
    required this.sizePreference, // -1..1: smaller=-1 (studio), larger=1 (spacious)
    required this.luxuryTolerance, // 0..1: amenity/feature appetite
    required this.timePreference, // -1..1: immediate=-1 (asap), flexible=1 (no rush)
    required this.neighborhoodVibe, // -1..1: quiet/residential=-1, central/vibrant=1
    required this.travelWeight, // 0..1: how much transit proximity matters
    required this.verificationWeight, // 0..1: trust in listing verification
    required this.budgetFlexibility, // 0..1: how much above max is "ok"
  });

  final double locationDesirability;
  final double priceElasticity;
  final double sizePreference;
  final double luxuryTolerance;
  final double timePreference;
  final double neighborhoodVibe;
  final double travelWeight;
  final double verificationWeight;
  final double budgetFlexibility;

  // Euclidean magnitude — signals how strongly user preferences are defined
  double get magnitude => math.sqrt(
      locationDesirability * locationDesirability +
      priceElasticity * priceElasticity +
      sizePreference * sizePreference +
      luxuryTolerance * luxuryTolerance);

  @override
  String toString() =>
      'Intent(loc:${locationDesirability.toStringAsFixed(2)}, '
      'price:${priceElasticity.toStringAsFixed(2)}, '
      'size:${sizePreference.toStringAsFixed(2)}, '
      'luxury:${luxuryTolerance.toStringAsFixed(2)}, '
      'vibe:${neighborhoodVibe.toStringAsFixed(2)})';
}

class PropertyVector {
  PropertyVector({
    required this.property,
    required this.locationScore, // 0..1: how "central" or well-situated
    required this.valueScore, // 0..1: price-to-quality ratio
    required this.sizeNormalized, // -1..1: normalized room count relative to market
    required this.amenityRichness, // 0..1: how feature-rich (0=bare, 1=all features)
    required this.trendingScore, // 0..1: recent engagement (views/saves/contacts)
    required this.freshnessScore, // 0..1: 1=brand new, 0=old listing
    required this.vibeFit, // -1..1: quiet neighborhood=-1, vibrant=1
    required this.distanceToTransit, // kilometers to nearest station
    required this.verifiedScore, // 0..1: trust signal (verified, photos, reviews)
  });

  final RentalProperty property;
  final double locationScore;
  final double valueScore;
  final double sizeNormalized;
  final double amenityRichness;
  final double trendingScore;
  final double freshnessScore;
  final double vibeFit;
  final double distanceToTransit;
  final double verifiedScore;

  // L2 norm of the property feature vector
  double get magnitude => math.sqrt(
      locationScore * locationScore +
      valueScore * valueScore +
      sizeNormalized * sizeNormalized +
      amenityRichness * amenityRichness +
      trendingScore * trendingScore);
}

class MatchScore {
  MatchScore({
    required this.property,
    required this.totalScore,
    required this.dimensionalScores,
    required this.explanation,
    required this.fitPct,
  });

  final RentalProperty property;
  final double totalScore; // 0..100
  final Map<String, double> dimensionalScores; // component breakdown
  final String explanation; // why this match works
  final int fitPct; // user-facing "89% fit"
}

class AdvancedMatcher {
  // Derive a user intent vector from the search query and behavioral cues.
  static UserIntentVector buildUserIntent({
    required bool statedCityPreference,
    required bool budgetStated,
    required bool roomsRangeStated,
    required double? minPrice,
    required double? maxPrice,
    required bool amenityDemanding,
    required int amenitiesCount,
    required bool nearTrainRequired,
    required bool cheapPreference,
    required bool urgentTone,
    required bool flexibleTone,
  }) {
    // location: if city + neighborhood stated → high; if vague → low
    final locationDesirability = statedCityPreference ? 0.85 : 0.4;

    // price elasticity: if "cheap" or budget stated as range → inelastic (0.3);
    // if open-ended → elastic (0.7)
    final priceElasticity = cheapPreference
        ? 0.2
        : (minPrice != null && maxPrice != null
            ? 0.4
            : 0.65); // room to negotiate if not stated

    // size: if rooms stated → user-aware of size needs; if not → neutral
    final sizePreference = roomsRangeStated ? 0.0 : -0.1; // slight small bias if unclear

    // luxury: more amenities demanded → higher tolerance for upscale
    final luxuryTolerance = amenitiesCount > 3 ? 0.75 : 0.45;

    // time: urgent ("מיד", "חייב עכשיו") → -1; flexible ("יש לי זמן") → +0.7
    final timePreference = urgentTone ? -0.8 : (flexibleTone ? 0.6 : 0.0);

    // transit: if explicitly requested → matters a lot; else soft
    final travelWeight = nearTrainRequired ? 0.8 : 0.3;

    // verification: if user is cautious (many amenities, specific neighborhood) → trust matters
    final verificationWeight =
        statedCityPreference && amenityDemanding ? 0.7 : 0.4;

    // budget flexibility: if cheapPreference or max is tight → low; else moderate
    final budgetFlexibility = cheapPreference ? 0.15 : 0.4;

    // neighborhood vibe: placeholder (could infer from amenities + time preference)
    final neighborhoodVibe = timePreference > 0 ? 0.5 : -0.2; // flexible users like vibrancy

    return UserIntentVector(
      locationDesirability: locationDesirability,
      priceElasticity: priceElasticity,
      sizePreference: sizePreference,
      luxuryTolerance: luxuryTolerance,
      timePreference: timePreference,
      neighborhoodVibe: neighborhoodVibe,
      travelWeight: travelWeight,
      verificationWeight: verificationWeight,
      budgetFlexibility: budgetFlexibility,
    );
  }

  // Build a multi-dimensional vector for a property based on real data.
  static PropertyVector buildPropertyVector(
    RentalProperty prop, {
    required double minRoomMarket,
    required double maxRoomMarket,
    required double medianPriceMarket,
    required int totalProperties,
  }) {
    // location score: central areas (תל אביב, חיפה מרכז) → 0.9; periphery → 0.4
    final locationScore = _locationScore(prop.city, prop.neighborhood);

    // value score: price relative to market + room count
    final valueScore = _valueScore(prop.price, prop.rooms, medianPriceMarket);

    // size normalized: -1 (tiny studio) to +1 (spacious 5+ rooms)
    final sizeNormalized =
        _normalizeRooms(prop.rooms, minRoomMarket, maxRoomMarket);

    // amenity richness: count enabled features / all possible
    final enabledFeatures = [
      'feat_renovated',
      'feat_pets',
      'feat_parking',
      'feat_balcony',
      'feat_elevator',
      'feat_furnished',
      'feat_mamad',
      'feat_garden',
      'feat_air',
      'feat_gym'
    ]
        .where((k) => prop.featureFlags.isEnabled(k))
        .length;
    final amenityRichness =
        enabledFeatures / 10; // 0..1 scale (10 = all features)

    // trending: logarithmic scale of engagement
    final signals = prop.marketSignals;
    final engagement =
        signals.views + signals.likes * 3 + signals.saves * 4 + signals.contactRequests * 6;
    final trendingScore = engagement > 0
        ? (math.log(1 + engagement) / math.log(1 + 200))
            .clamp(0.0, 1.0) // 200 = "trending" threshold
        : 0.0;

    // freshness: 1.0 if <3 days, 0.5 if ~15 days, 0.1 if >45 days
    final ageInDays =
        DateTime.now().difference(prop.createdAt ?? DateTime.now()).inDays;
    final freshnessScore =
        (1 - (ageInDays / 45).clamp(0.0, 1.0)) * 0.8; // decay over 45 days

    // vibe: quiet/residential (outer neighborhoods) vs central (vibrant)
    final vibeFit = _vibeScore(prop.neighborhood, prop.city);

    // transit: distance in km to nearest station (handled separately in scoring)
    final distanceToTransit = nearestStationKm(prop.lat, prop.lon) ?? 5.0;

    // verified: if verified + has images + is active
    final verifiedScore =
        (prop.isVerifiedListing ? 0.6 : 0.2) + (prop.imageUrl.isNotEmpty ? 0.3 : 0.0);

    return PropertyVector(
      property: prop,
      locationScore: locationScore,
      valueScore: valueScore,
      sizeNormalized: sizeNormalized,
      amenityRichness: amenityRichness,
      trendingScore: trendingScore,
      freshnessScore: freshnessScore,
      vibeFit: vibeFit,
      distanceToTransit: distanceToTransit,
      verifiedScore: verifiedScore,
    );
  }

  // Cosine similarity + weighted distance metric between user intent and property.
  static MatchScore scoreMatch(
    UserIntentVector intent,
    PropertyVector propVec, {
    required bool meetsHardConstraints, // city/budget/rooms
    required bool hasRequestedAmenities,
    required bool transitProximity,
  }) {
    final map = <String, double>{};

    // hard constraints gate: if not met, score is capped at 60
    double baseMultiplier = meetsHardConstraints ? 1.0 : 0.6;

    // 1. location alignment
    double locationScore = 0;
    if (intent.locationDesirability > 0.7) {
      // user cares about location
      locationScore = propVec.locationScore * 0.85;
    } else if (intent.locationDesirability < 0.5) {
      // user vague about location
      locationScore = 0.5; // neutral
    }
    map['location'] = locationScore;

    // 2. price-value fit: cosine of (intent.priceElasticity, propVec.valueScore)
    final priceVectorUser = intent.priceElasticity;
    final priceVectorProp = propVec.valueScore;
    final priceDot = priceVectorUser * priceVectorProp;
    double priceScore = (priceDot + 1) / 2; // normalize to 0..1
    if (!meetsHardConstraints) priceScore *= 0.5; // penalize if over budget
    map['price'] = priceScore;

    // 3. size fit: how well property.rooms matches intent.sizePreference
    final sizeDot = intent.sizePreference * propVec.sizeNormalized;
    double sizeScore = (sizeDot + 1) / 2; // -1..1 → 0..1
    map['size'] = sizeScore;

    // 4. amenity fit: if user demanding + property rich → high; if user casual → neutral
    double amenityScore = 0;
    if (intent.luxuryTolerance > 0.6 && propVec.amenityRichness > 0.5) {
      amenityScore = 0.85;
    } else if (hasRequestedAmenities) {
      amenityScore = 0.75;
    } else {
      amenityScore = 0.4; // soft boost
    }
    map['amenities'] = amenityScore;

    // 5. trending + freshness: if user flexible on time → favor trending/fresh
    double trendScore = 0;
    if (intent.timePreference > 0.5) {
      // flexible user — trending properties signal quality
      trendScore = (propVec.trendingScore + propVec.freshnessScore) / 2;
    } else if (intent.timePreference < -0.5) {
      // urgent user — fresh matters more than trending
      trendScore = propVec.freshnessScore * 0.9;
    } else {
      trendScore = propVec.freshnessScore * 0.5; // mild bonus for fresh
    }
    map['trending_fresh'] = trendScore;

    // 6. neighborhood vibe fit
    double vibeScore = (intent.neighborhoodVibe * propVec.vibeFit + 1) / 2;
    map['neighborhood_vibe'] = vibeScore;

    // 7. transit: if user cares + property near → high; else neutral
    double transitScore = 0;
    if (intent.travelWeight > 0.6) {
      if (transitProximity && propVec.distanceToTransit < 1.5) {
        transitScore = 0.95;
      } else if (propVec.distanceToTransit < 3) {
        transitScore = 0.7;
      } else {
        transitScore = 0.3;
      }
    } else {
      transitScore = 0.5; // soft
    }
    map['transit'] = transitScore;

    // 8. verification trust
    double verifyScore = (intent.verificationWeight * propVec.verifiedScore +
            (1 - intent.verificationWeight) * 0.5)
        .clamp(0.0, 1.0);
    map['verification'] = verifyScore;

    // weighted average: weights reflect user intent strength
    double totalScore = 0;
    double weightSum = 0;
    final weights = <String, double>{
      'location': intent.locationDesirability,
      'price': 1.0,
      'size': (intent.sizePreference.abs() + 0.5),
      'amenities': intent.luxuryTolerance,
      'trending_fresh': 0.6,
      'neighborhood_vibe': (intent.neighborhoodVibe.abs() + 0.3),
      'transit': intent.travelWeight,
      'verification': intent.verificationWeight,
    };

    weights.forEach((k, w) {
      if (map.containsKey(k)) {
        totalScore += (map[k] ?? 0) * w;
        weightSum += w;
      }
    });

    final normalizedScore = weightSum > 0 ? totalScore / weightSum : 0.5;
    final finalScore =
        (normalizedScore * baseMultiplier * 100).clamp(0.0, 100.0);
    final fitPct = finalScore.round();

    // explanation: why this property ranked
    final reasons = <String>[];
    if (map['price']! > 0.75) reasons.add('excellent price-to-value');
    if (map['size']! > 0.8) reasons.add('perfect size');
    if (map['amenities']! > 0.8) reasons.add('feature-rich');
    if (map['trending_fresh']! > 0.75) reasons.add('popular & recent');
    if (map['transit']! > 0.8) reasons.add('great transit access');
    if (map['verification']! > 0.8) reasons.add('verified & trusted');

    final explanation = reasons.isNotEmpty
        ? reasons.join(', ')
        : 'solid match across dimensions';

    return MatchScore(
      property: propVec.property,
      totalScore: finalScore,
      dimensionalScores: map,
      explanation: explanation,
      fitPct: fitPct,
    );
  }

  // ── helper scoring functions ──────────────────────────────────────────────

  static double _locationScore(String city, String neighborhood) {
    const Map<String, double> cityWeights = {
      'תל אביב': 0.95,
      'ירושלים': 0.85,
      'חיפה': 0.8,
      'רמת גן': 0.9,
      'גבעתיים': 0.88,
      'הרצליה': 0.75,
    };
    const Map<String, double> neighborhoodWeights = {
      'נווה צדק': 0.95,
      'פלורנטין': 0.93,
      'רוטשילד': 0.92,
      'כרם התימנים': 0.9,
      'רמת אביב': 0.85,
      'הקריה': 0.8,
    };

    double score = cityWeights[city] ?? 0.5;
    if (neighborhood.isNotEmpty) {
      final neighScore = neighborhoodWeights[neighborhood];
      if (neighScore != null) {
        score = (score + neighScore) / 2; // blend city + neighborhood
      }
    }
    return score.clamp(0.0, 1.0);
  }

  static double _valueScore(int price, double rooms, double medianPrice) {
    if (price <= 0 || rooms <= 0) return 0.4;
    final pricePerRoom = price / rooms;
    final marketPricePerRoom = medianPrice / 3;
    // if price/room is 20% below market → 0.9 (great deal)
    // if price/room is at market → 0.5
    // if price/room is 50% above market → 0.1
    final ratio = pricePerRoom / marketPricePerRoom;
    return (1 - (ratio - 1).clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  static double _normalizeRooms(double rooms, double min, double max) {
    if (max <= min) return 0.0;
    return ((rooms - min) / (max - min)) * 2 - 1; // -1..1
  }

  // Public reuse hook for the production linear scorer (vibe_fit feature).
  static double neighborhoodVibrancy(String neighborhood, String city) =>
      _vibeScore(neighborhood, city);

  static double _vibeScore(String neighborhood, String city) {
    const vibrancy = {
      'נווה צדק': 0.9,
      'פלורנטין': 0.95,
      'רוטשילד': 0.85,
      'כרם התימנים': 0.8,
      'תל אביב': 0.7,
    };
    const quiet = {
      'רמת אביב': -0.7,
      'גבעתיים': -0.75,
      'בני ברק': -0.6,
    };
    if (quiet.containsKey(neighborhood)) return quiet[neighborhood]!;
    if (vibrancy.containsKey(neighborhood)) return vibrancy[neighborhood]!;
    return city == 'תל אביב' ? 0.5 : -0.2;
  }

  static double? nearestStationKm(double lat, double lon) {
    if (lat == 0 || lon == 0) return null;
    double? best;
    for (final st in _trainStations) {
      final d = _haversineKm(lat, lon, st.$2, st.$3);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLa = _rad(la2 - la1);
    final dLo = _rad(lo2 - lo1);
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(_rad(la1)) *
            math.cos(_rad(la2)) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  static const List<(String, double, double)> _trainStations = [
    ('תל אביב סבידור מרכז', 32.0833, 34.7991),
    ('תל אביב השלום', 32.0734, 34.7920),
    ('תל אביב ההגנה', 32.0540, 34.7940),
    ('תל אביב אוניברסיטה', 32.1140, 34.8040),
    ('הרצליה', 32.1660, 34.8340),
    ('נתניה', 32.3180, 34.8570),
    ('רעננה מערב', 32.1820, 34.8510),
    ('כפר סבא נורדאו', 32.1670, 34.9160),
    ('פתח תקווה קריית אריה', 32.1030, 34.8570),
    ('בני ברק', 32.0930, 34.8340),
    ('ראשון לציון הראשונים', 31.9620, 34.8060),
    ('רחובות', 31.9170, 34.7970),
    ('לוד', 31.9480, 34.8720),
    ('רמלה', 31.9280, 34.8640),
    ('מודיעין מרכז', 31.9010, 35.0070),
    ('בית שמש', 31.7470, 34.9880),
    ('ירושלים יצחק נבון', 31.7870, 35.2030),
    ('אשדוד עד הלום', 31.7700, 34.6610),
    ('אשקלון', 31.6520, 34.5780),
    ('באר שבע מרכז', 31.2430, 34.7980),
    ('חיפה חוף הכרמל', 32.7940, 34.9570),
    ('חיפה בת גלים', 32.8310, 34.9890),
    ('חיפה מרכז השמונה', 32.8210, 35.0000),
  ];
}
