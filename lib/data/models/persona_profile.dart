import 'dart:convert';
import 'dart:math' as math;

/// Per-user "persona" the assistant accumulates over time (declared + inferred
/// preferences) to personalise search and, with consent, to build a per-user
/// dataset. This is the DECLARED/INFERRED counterpart to the behavioural
/// `UserSignals` aggregate — keep behavioural signals there, stated ones here.
///
/// Accuracy is baked into the data model, not bolted on:
/// - every fact carries a **confidence**, its **source**, an **evidence** count
///   and a timestamp;
/// - **recency decay** fades stale facts (half-life ~180d) so old prefs can't
///   dominate forever;
/// - **conflict resolution**: a stronger source (declared > behavioural >
///   inferred) or a higher decayed-confidence wins; otherwise the incumbent is
///   kept but eroded;
/// - **dedup**: the same value from the same source in a short window doesn't
///   inflate confidence;
/// - **validation** rejects implausible values before they're stored;
/// - **version** increments on every change → last-writer-wins on sync, so a
///   slow remote write can never clobber a newer local profile.
enum PersonaSource { inferred, behavioral, declared }

extension PersonaSourceX on PersonaSource {
  /// Base confidence a fresh observation from this source starts at.
  double get baseConfidence => switch (this) {
        PersonaSource.declared => 0.92,
        PersonaSource.behavioral => 0.65,
        PersonaSource.inferred => 0.55,
      };

  /// Ordering for conflict resolution (declared beats inferred).
  int get strength => index;
}

class PersonaFact {
  const PersonaFact({
    required this.value,
    required this.confidence,
    required this.source,
    required this.evidence,
    required this.updatedAt,
  });

  final Object value; // String | num | bool | List
  final double confidence; // 0..1 at [updatedAt]
  final PersonaSource source;
  final int evidence; // supporting observations
  final DateTime updatedAt;

  /// Confidence after time-decay to [now] (half-life 180 days).
  double confidenceAt(DateTime now) {
    final days = now.difference(updatedAt).inMilliseconds / 86400000.0;
    if (days <= 0) return confidence;
    return confidence * math.pow(0.5, days / 180).toDouble();
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'confidence': confidence,
        'source': source.name,
        'evidence': evidence,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static PersonaFact fromJson(Map<String, dynamic> j) => PersonaFact(
        value: j['value'] as Object,
        confidence: (j['confidence'] as num).toDouble(),
        source: PersonaSource.values.firstWhere(
          (s) => s.name == j['source'],
          orElse: () => PersonaSource.inferred,
        ),
        evidence: (j['evidence'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class PersonaProfile {
  const PersonaProfile({
    this.version = 0,
    this.facts = const {},
    required this.updatedAt,
  });

  final int version;
  final Map<String, PersonaFact> facts;
  final DateTime updatedAt;

  factory PersonaProfile.empty() =>
      PersonaProfile(updatedAt: DateTime.fromMillisecondsSinceEpoch(0));

  /// Dedup window: identical value+source seen within this doesn't add evidence.
  static const Duration _dedupWindow = Duration(seconds: 90);

  /// Fold ONE observation in, applying every accuracy rule. Pure: pass [now].
  PersonaProfile observe(
    String key,
    Object? value,
    PersonaSource source, {
    required DateTime now,
    double weight = 1.0,
  }) {
    if (!_isValid(key, value)) return this; // validation gate
    final v = value!;
    final base = (source.baseConfidence * weight).clamp(0.0, 1.0);
    final existing = facts[key];

    late final PersonaFact next;
    if (existing == null) {
      next = PersonaFact(
          value: v,
          confidence: base,
          source: source,
          evidence: 1,
          updatedAt: now);
    } else if (_sameValue(existing.value, v)) {
      // Reinforce — but dedup near-duplicate spam from the same source.
      final isDup = existing.source == source &&
          now.difference(existing.updatedAt).abs() < _dedupWindow;
      final decayed = existing.confidenceAt(now);
      final conf =
          isDup ? existing.confidence : (decayed + (1 - decayed) * 0.35);
      next = PersonaFact(
        value: existing.value,
        confidence: conf.clamp(0.0, 1.0),
        source: source.strength >= existing.source.strength
            ? source
            : existing.source,
        evidence: existing.evidence + (isDup ? 0 : 1),
        updatedAt: now,
      );
    } else {
      // Conflict: stronger source, or higher decayed confidence, wins.
      final decayed = existing.confidenceAt(now);
      if (source.strength > existing.source.strength || base > decayed) {
        next = PersonaFact(
            value: v,
            confidence: base,
            source: source,
            evidence: 1,
            updatedAt: now);
      } else {
        // Keep incumbent but erode it — a real conflict lowers certainty.
        next = PersonaFact(
          value: existing.value,
          confidence: (decayed * 0.85).clamp(0.0, 1.0),
          source: existing.source,
          evidence: existing.evidence,
          updatedAt: now,
        );
      }
    }

    return PersonaProfile(
      version: version + 1,
      facts: {...facts, key: next},
      updatedAt: now,
    );
  }

  /// Best-known value for [key], or null if its (decayed) confidence is below
  /// [minConfidence]. Callers use this to personalise without trusting noise.
  Object? value(String key,
      {double minConfidence = 0.5, DateTime? now}) {
    final f = facts[key];
    if (f == null) return null;
    final conf = now == null ? f.confidence : f.confidenceAt(now);
    return conf >= minConfidence ? f.value : null;
  }

  double confidence(String key, {DateTime? now}) {
    final f = facts[key];
    if (f == null) return 0;
    return now == null ? f.confidence : f.confidenceAt(now);
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'updatedAt': updatedAt.toIso8601String(),
        'facts': facts.map((k, v) => MapEntry(k, v.toJson())),
      };

  static PersonaProfile fromJson(Map<String, dynamic> j) {
    final raw = (j['facts'] as Map?) ?? const {};
    return PersonaProfile(
      version: (j['version'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      facts: raw.map(
        (k, v) => MapEntry(
            k as String, PersonaFact.fromJson(Map<String, dynamic>.from(v))),
      ),
    );
  }

  /// Flattened snapshot for the consent-gated dataset event (value + confidence
  /// so downstream targeting can weight by certainty, never guess).
  Map<String, dynamic> toEventMetadata(DateTime now) => {
        'version': version,
        'facts': {
          for (final e in facts.entries)
            e.key: {
              'value': e.value.value,
              'confidence':
                  double.parse(e.value.confidenceAt(now).toStringAsFixed(3)),
              'source': e.value.source.name,
              'evidence': e.value.evidence,
            },
        },
      };

  // ── Validation ──────────────────────────────────────────────────────────
  static bool _isValid(String key, Object? value) {
    if (value == null) return false;
    switch (key) {
      case 'religiosity':
        return const {'secular', 'traditional', 'religious', 'haredi'}
            .contains(value);
      case 'maxBudget':
      case 'minBudget':
        return value is num && value >= 1000 && value <= 200000;
      case 'minRooms':
      case 'maxRooms':
        return value is num && value >= 0.5 && value <= 12;
      case 'city':
        return value is String && value.trim().isNotEmpty;
      case 'baby':
        return value is bool;
      case 'amenities':
        return value is List && value.isNotEmpty;
      default:
        return true;
    }
  }

  static bool _sameValue(Object a, Object b) {
    if (a is List || b is List) return jsonEncode(a) == jsonEncode(b);
    return a == b;
  }
}
