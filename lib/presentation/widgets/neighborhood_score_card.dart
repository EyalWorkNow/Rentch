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
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

class NeighborhoodScoreCard extends StatelessWidget {
  NeighborhoodScoreCard({super.key, required this.enrichment});

  /// Raw enrichment map; may be null/partial/absent. Never assumed well-formed.
  final Map<String, dynamic>? enrichment;

  /// Labels for the known sub-scores, in canonical display order. Localized —
  /// keyed by the SAME server-side keys the enrichment map uses.
  static Map<String, String> _subLabels(AppLocalizations l10n) => {
        'safety': l10n.neighborhoodScoreCardE642cece,
        'walkability': l10n.neighborhoodScoreCard0fff92d0,
        'schools': l10n.neighborhoodScoreCard5a567748,
        'kindergarten': l10n.neighborhoodScoreCard00a5eaf2,
        'transit': l10n.neighborhoodScoreCard8cf2e63d,
        'green': l10n.neighborhoodScoreCard08d4f99e,
        'quiet': l10n.neighborhoodScoreCard40d07087,
      };

  /// Each sub-score → its honest data source, so the breakdown can show WHERE the
  /// figure came from. Reuses the shared GovSources registry where a matching
  /// gov dimension exists.
  static GovSource? _sourceFor(String key) {
    switch (key) {
      case 'safety':
        return GovSources.forDimension('safety');
      case 'schools':
        return GovSources.forDimension('schools');
      case 'transit':
        return GovSources.forDimension('transit');
      case 'walkability':
        return GovSources.forDimension('convenience');
      case 'green':
        return const GovSource(
          agency: 'OpenStreetMap / data.gov.il',
          dataset: 'פארקים ושטחים ירוקים',
        );
      default:
        return null;
    }
  }

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
    final l10n = AppLocalizations.of(context)!;
    final subLabels = _subLabels(l10n);
    final map = _scoreMap(enrichment);
    if (map == null) return const SizedBox.shrink();

    final headline = _toDouble(map['score']);

    // Collect usable sub-scores (0..100), preserving a sensible label order,
    // then keep the top 3 by value for the chips.
    final subRaw = map['sub'];
    final subs = <MapEntry<String, int>>[];
    if (subRaw is Map) {
      for (final key in subLabels.keys) {
        final v = _toDouble(subRaw[key]);
        if (v != null && v > 0) subs.add(MapEntry(key, v.round().clamp(0, 100)));
      }
      // Tolerate unknown sub-keys the backend may add later.
      for (final entry in subRaw.entries) {
        final k = entry.key.toString();
        if (subLabels.containsKey(k)) continue;
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
      textDirection: Directionality.of(context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showBreakdown(context, headlineInt, topSubs, subLabels),
          borderRadius: BorderRadius.circular(20),
          child: Ink(
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
                    Text(
                      l10n.neighborhoodScoreCard2de2ff3f,
                      style: const TextStyle(
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
                          label: subLabels[c.key] ?? c.key,
                          value: c.value,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(IconsaxPlusLinear.info_circle,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      l10n.neighborhoodScoreCard542929e1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.keyboard_arrow_left_rounded,
                        size: 18, color: AppColors.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBreakdown(BuildContext context, int? headline,
      List<MapEntry<String, int>> subs, Map<String, String> labels) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NeighborhoodBreakdownSheet(
        headline: headline,
        subs: subs,
        labels: labels,
        sourceFor: _sourceFor,
      ),
    );
  }
}

/// The tap-through breakdown: every sub-score as a labeled bar + the honest data
/// source behind it, so "ציון השכונה" is transparent instead of a mystery number.
class _NeighborhoodBreakdownSheet extends StatelessWidget {
  const _NeighborhoodBreakdownSheet({
    required this.headline,
    required this.subs,
    required this.labels,
    required this.sourceFor,
  });

  final int? headline;
  final List<MapEntry<String, int>> subs;
  final Map<String, String> labels;
  final GovSource? Function(String key) sourceFor;

  Color _barColor(int v) {
    if (v >= 80) return AppColors.scoreStrong;
    if (v >= 60) return AppColors.scoreGood;
    if (v >= 40) return AppColors.scoreMixed;
    return AppColors.slate400;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Sources actually cited (deduped by label) for the footer.
    final sources = <String>[];
    for (final s in subs) {
      final src = sourceFor(s.key)?.label;
      if (src != null && !sources.contains(src)) sources.add(src);
    }

    return Directionality(
      textDirection: Directionality.of(context),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate200,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(IconsaxPlusLinear.location,
                        size: 22, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(l10n.neighborhoodScoreCard2de2ff3f,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    if (headline != null) _HeadlineBadge(score: headline!),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.neighborhoodScoreCard63eefa9b,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (subs.isEmpty)
                  Text(l10n.neighborhoodScoreCard4c69a81b,
                      style: TextStyle(color: AppColors.textSecondary))
                else
                  for (final s in subs) ...[
                    _BreakdownRow(
                      label: labels[s.key] ?? s.key,
                      value: s.value,
                      color: _barColor(s.value),
                      source: sourceFor(s.key)?.dataset,
                    ),
                    const SizedBox(height: 14),
                  ],
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Divider(color: AppColors.divider, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(IconsaxPlusLinear.document_text,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(l10n.neighborhoodScoreCard5d1b29db,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final src in sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $src',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.4)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.color,
    this.source,
  });

  final String label;
  final int value;
  final Color color;
  final String? source;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$value',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value / 100.0,
            minHeight: 7,
            backgroundColor: AppColors.slate100,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        if (source != null) ...[
          const SizedBox(height: 5),
          Text(source!,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
        ],
      ],
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
