// A compact "neighborhood score" card for a property listing.
//
// The backend enrichment Lambda attaches a `neighborhoodScore` object:
//   {
//     "score": 84,                       // 0..100 headline
//     "sub": { "safety": 88, "walkability": 82, "schools": 79,
//              "transit": 71, "green": 64 }
//   }
//
// This widget reads everything defensively (the map may be absent, partial, or
// carry odd types — it lands before the model knows about it). It shows the
// 0–100 headline plus the TOP 2–3 contributing sub-scores as chips, e.g.
// "בטיחות 88 · הליכתיות 82 · בתי״ס 79". If the data is missing or has no usable
// sub-scores, it renders nothing (SizedBox.shrink) so the screen degrades cleanly.

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

class NeighborhoodScoreCard extends StatelessWidget {
  const NeighborhoodScoreCard({super.key, required this.enrichment});

  /// Raw enrichment map; may be null/partial/absent. Never assumed well-formed.
  final Map<String, dynamic>? enrichment;

  /// Hebrew labels for the known sub-scores, in canonical display order.
  static const Map<String, String> _subLabels = {
    'safety': 'בטיחות',
    'walkability': 'הליכתיות',
    'schools': 'בתי״ס',
    'transit': 'תחבורה',
    'green': 'ירוק',
  };

  static Map<String, dynamic>? _scoreMap(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final nested = raw['neighborhoodScore'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    if (raw.containsKey('score') || raw.containsKey('sub')) return raw;
    return null;
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final map = _scoreMap(enrichment);
    if (map == null) return const SizedBox.shrink();

    final headline = _toDouble(map['score']);

    // Collect usable sub-scores (0..100), preserving a sensible label order,
    // then keep the top 3 by value for the chips.
    final subRaw = map['sub'];
    final subs = <MapEntry<String, int>>[];
    if (subRaw is Map) {
      for (final key in _subLabels.keys) {
        final v = _toDouble(subRaw[key]);
        if (v != null && v > 0) subs.add(MapEntry(key, v.round().clamp(0, 100)));
      }
      // Tolerate unknown sub-keys the backend may add later.
      for (final entry in subRaw.entries) {
        final k = entry.key.toString();
        if (_subLabels.containsKey(k)) continue;
        final v = _toDouble(entry.value);
        if (v != null && v > 0) subs.add(MapEntry(k, v.round().clamp(0, 100)));
      }
    }

    final hasHeadline = headline != null && headline > 0;
    if (!hasHeadline && subs.isEmpty) return const SizedBox.shrink();

    final topSubs = [...subs]..sort((a, b) => b.value.compareTo(a.value));
    final chips = topSubs.take(3).toList();
    final headlineInt = hasHeadline ? headline.round().clamp(0, 100) : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.slate200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(IconsaxPlusLinear.location,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'ציון השכונה',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                if (headlineInt != null) _HeadlineBadge(score: headlineInt),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chips)
                    _SubScoreChip(
                      label: _subLabels[c.key] ?? c.key,
                      value: c.value,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeadlineBadge extends StatelessWidget {
  const _HeadlineBadge({required this.score});
  final int score;

  Color get _color {
    if (score >= 80) return AppColors.scoreStrong; // strong
    if (score >= 60) return AppColors.scoreGood; // good
    if (score >= 40) return AppColors.scoreMixed; // mixed
    return AppColors.slate400; // low
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$score',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _color,
              height: 1,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '/100',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubScoreChip extends StatelessWidget {
  const _SubScoreChip({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.slate700,
        ),
      ),
    );
  }
}
