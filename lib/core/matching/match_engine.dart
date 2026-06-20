import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/data/models/profile_tags.dart';

/// Tunable weights + thresholds for the matching engine. Externalised so the
/// model can be retuned (or A/B-tested) without touching the logic.
class MatchWeights {
  const MatchWeights({
    this.propertyFitWeight = 0.62,
    this.tenantFitWeight = 0.38,
    this.dealBreakerPenalty = 28,
    this.sharedTagBonus = 4,
    this.budgetHeadroomBonus = 10,
  });

  /// How much the tenant→property fit counts in the blended mutual score.
  final double propertyFitWeight;

  /// How much the landlord→tenant fit counts in the blended mutual score.
  final double tenantFitWeight;

  /// Points removed from the mutual score per unmet deal-breaker.
  final double dealBreakerPenalty;

  /// Landlord-side points per shared preference key with the tenant.
  final double sharedTagBonus;

  /// Landlord-side points when the tenant comfortably affords the rent.
  final double budgetHeadroomBonus;

  static const MatchWeights standard = MatchWeights();
}

/// What the tenant is looking for.
class TenantSignals {
  const TenantSignals({
    required this.budgetMax,
    required this.desiredRooms,
    this.tags = const [],
    this.dealBreakers = const [],
    this.searchCity = '',
  });

  final int budgetMax;
  final double desiredRooms;
  final List<String> tags;
  final List<String> dealBreakers;
  final String searchCity;
}

/// What the landlord offers + requires of a tenant.
class LandlordSignals {
  const LandlordSignals({
    this.tags = const [],
    this.dealBreakers = const [],
    this.known = true,
  });

  final List<String> tags;
  final List<String> dealBreakers;

  /// False when we don't have the landlord's profile yet (one-sided match).
  final bool known;

  static const LandlordSignals unknown =
      LandlordSignals(known: false);
}

/// The property under consideration.
class PropertySignals {
  const PropertySignals({
    required this.price,
    required this.rooms,
    required this.sizeM2,
    required this.city,
    this.features = const [],
    this.verified = false,
    this.hasReadyTour = false,
    this.photoCount = 0,
  });

  final int price;
  final double rooms;
  final int sizeM2;
  final String city;
  final List<String> features;
  final bool verified;
  final bool hasReadyTour;
  final int photoCount;
}

/// Human labels for the cross-side preference keys, so reasons read naturally.
const Map<String, String> _matchKeyLabels = {
  'no_smoking': 'ללא עישון',
  'pets_allowed': 'מתאים לחיות מחמד',
  'pets': 'חיות מחמד',
  'couples': 'מתאים לזוגות',
  'family': 'מתאים למשפחות',
  'roommates': 'מתאים לשותפים',
  'students': 'מתאים לסטודנטים',
  'parking': 'חניה',
  'furnished': 'מרוהטת',
  'elevator': 'מעלית',
  'balcony': 'מרפסת',
  'shelter': 'ממ"ד',
  'ac': 'מיזוג אוויר',
  'accessible': 'נגישות',
  'long_term': 'שכירות ארוכת טווח',
  'short_term': 'טווח קצר',
  'immediate': 'כניסה מיידית',
  'quiet': 'שקט',
  'income_proof': 'אישור הכנסה',
  'guarantors': 'ערבים',
};

String _keyLabel(String key) => _matchKeyLabels[key] ?? key;

/// The two-sided rental matching engine. Pure + dependency-free, so it can be
/// exhaustively unit-tested. Given the (proven, tuned) tenant→property fit score
/// plus both sides' signals, it computes the landlord→tenant fit, applies hard
/// deal-breaker gates, blends a final mutual score, and emits the human reasons
/// behind it.
class MatchEngine {
  const MatchEngine({this.weights = MatchWeights.standard});

  final MatchWeights weights;

  MatchOutcome evaluate({
    required TenantSignals tenant,
    required LandlordSignals landlord,
    required PropertySignals property,
    required int propertyFitScore,
  }) {
    final propertyFit = propertyFitScore.clamp(0, 100);
    final reasons = <MatchReason>[];
    final conflicts = <String>[];

    final tenantKeys = ProfileTagCatalog.matchKeysFor(tenant.tags,
        isLandlord: false);
    final tenantDealKeys = ProfileTagCatalog.matchKeysFor(tenant.dealBreakers,
        isLandlord: false);
    final landlordKeys = ProfileTagCatalog.matchKeysFor(landlord.tags,
        isLandlord: true);
    final landlordDealKeys = ProfileTagCatalog.matchKeysFor(
        landlord.dealBreakers,
        isLandlord: true);

    // ── Property-fit reasons (tenant → property) ──────────────────────────
    _addBudgetReason(reasons, tenant, property);
    _addLocationReason(reasons, tenant, property);
    _addRoomsReason(reasons, tenant, property);
    if (property.verified) {
      reasons.add(const MatchReason(
          kind: MatchReasonKind.quality, label: 'מודעה מאומתת', weight: 1.4));
    }
    if (property.hasReadyTour) {
      reasons.add(const MatchReason(
          kind: MatchReasonKind.quality,
          label: 'סיור תלת-ממדי זמין',
          weight: 1.2));
    }

    // ── Two-sided fit (landlord → tenant) ─────────────────────────────────
    int tenantFit = -1;
    if (landlord.known) {
      tenantFit = _landlordToTenantFit(
        tenant: tenant,
        property: property,
        tenantKeys: tenantKeys,
        landlordKeys: landlordKeys,
        landlordDealKeys: landlordDealKeys,
        reasons: reasons,
      );
    }

    // ── Shared lifestyle preferences (mutual positives) ───────────────────
    final shared = tenantKeys.intersection(landlordKeys);
    for (final key in shared) {
      reasons.add(MatchReason(
        kind: MatchReasonKind.lifestyle,
        label: '${_keyLabel(key)} ✓',
        weight: 1.1,
      ));
    }

    // ── Hard deal-breaker gates (both directions) ─────────────────────────
    var dealBreakerHits = 0;
    if (landlord.known) {
      for (final key in tenantDealKeys) {
        if (!landlordKeys.contains(key)) {
          dealBreakerHits++;
          conflicts.add('הנכס לא עונה על דרישת חובה שלך: ${_keyLabel(key)}');
        }
      }
      for (final key in landlordDealKeys) {
        if (!tenantKeys.contains(key)) {
          dealBreakerHits++;
          conflicts.add('בעל הדירה דורש: ${_keyLabel(key)}');
        }
      }
    }
    for (final c in conflicts) {
      reasons.add(MatchReason(
          kind: MatchReasonKind.dealBreaker, label: c, positive: false,
          weight: 3.0));
    }

    // ── Blend the final mutual score ──────────────────────────────────────
    double blended;
    if (tenantFit < 0) {
      blended = propertyFit.toDouble();
    } else {
      blended = propertyFit * weights.propertyFitWeight +
          tenantFit * weights.tenantFitWeight;
    }
    blended -= dealBreakerHits * weights.dealBreakerPenalty;
    final score = blended.clamp(0, 100).round();

    if (tenantFit >= 70) {
      reasons.add(const MatchReason(
        kind: MatchReasonKind.mutualInterest,
        label: 'בעל הדירה מחפש בדיוק שוכר/ת כמוך',
        weight: 2.2,
      ));
    }

    return MatchOutcome(
      score: score,
      tier: MatchTierX.fromScore(score),
      propertyFitScore: propertyFit,
      tenantFitScore: tenantFit,
      reasons: _dedupe(reasons),
      dealBreakerConflicts: conflicts,
      excluded: dealBreakerHits > 0,
    );
  }

  // ── Landlord → tenant fit ───────────────────────────────────────────────
  int _landlordToTenantFit({
    required TenantSignals tenant,
    required PropertySignals property,
    required Set<String> tenantKeys,
    required Set<String> landlordKeys,
    required Set<String> landlordDealKeys,
    required List<MatchReason> reasons,
  }) {
    // Baseline: an unknown-but-present tenant is a neutral 60.
    double fit = 60;

    // Can the tenant comfortably afford the rent? This is the landlord's
    // single biggest concern.
    if (tenant.budgetMax > 0 && property.price > 0) {
      final ratio = tenant.budgetMax / property.price;
      if (ratio >= 1.15) {
        fit += weights.budgetHeadroomBonus;
        reasons.add(const MatchReason(
          kind: MatchReasonKind.budget,
          label: 'התקציב שלך מכסה בנוחות את שכר הדירה',
          weight: 1.3,
        ));
      } else if (ratio >= 1.0) {
        fit += weights.budgetHeadroomBonus * 0.5;
      } else {
        fit -= 18; // can't afford it from the landlord's view
      }
    }

    // Every landlord requirement (their dealBreaker keys) the tenant satisfies
    // raises the fit; the gate above handles the misses.
    for (final key in landlordDealKeys) {
      if (tenantKeys.contains(key)) fit += 6;
    }
    // Shared, non-required preferences are a softer plus.
    final shared = tenantKeys.intersection(landlordKeys);
    fit += shared.length * weights.sharedTagBonus;

    return fit.clamp(0, 100).round();
  }

  // ── Reason helpers ──────────────────────────────────────────────────────
  void _addBudgetReason(
      List<MatchReason> out, TenantSignals t, PropertySignals p) {
    if (t.budgetMax <= 0 || p.price <= 0) return;
    if (p.price <= t.budgetMax) {
      out.add(const MatchReason(
        kind: MatchReasonKind.budget,
        label: 'מתאים לתקציב שלך',
        weight: 2.0,
      ));
    } else {
      final over = (p.price - t.budgetMax) / t.budgetMax;
      out.add(MatchReason(
        kind: MatchReasonKind.budget,
        label: over > 0.1 ? 'מעל התקציב שלך' : 'מעט מעל התקציב שלך',
        positive: false,
        weight: 2.0,
      ));
    }
  }

  void _addLocationReason(
      List<MatchReason> out, TenantSignals t, PropertySignals p) {
    final city = t.searchCity.trim();
    if (city.isEmpty) return;
    if (p.city.trim() == city) {
      out.add(MatchReason(
        kind: MatchReasonKind.location,
        label: 'ב$city — בדיוק באזור שחיפשת',
        weight: 1.6,
      ));
    }
  }

  void _addRoomsReason(
      List<MatchReason> out, TenantSignals t, PropertySignals p) {
    if (t.desiredRooms <= 0 || p.rooms <= 0) return;
    if ((p.rooms - t.desiredRooms).abs() <= 0.5) {
      out.add(const MatchReason(
        kind: MatchReasonKind.rooms,
        label: 'מספר החדרים מתאים לך',
        weight: 1.2,
      ));
    }
  }

  List<MatchReason> _dedupe(List<MatchReason> reasons) {
    final seen = <String>{};
    final out = <MatchReason>[];
    for (final r in reasons) {
      if (seen.add('${r.kind}|${r.label}')) out.add(r);
    }
    out.sort((a, b) {
      if (a.positive != b.positive) return a.positive ? -1 : 1;
      return b.weight.compareTo(a.weight);
    });
    return out;
  }
}
