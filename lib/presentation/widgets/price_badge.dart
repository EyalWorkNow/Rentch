// A small, defensive "price vs. area median" badge for a property listing.
//
// The backend enrichment Lambda attaches a `priceBadge` object to the listing:
//   { "medianPpm": 28500, "deltaPct": -12, "badge": "great_deal" }
//   medianPpm  – median price per m² for comparable units in the area (₪/m²)
//   deltaPct   – this listing's price-per-m² vs. that median (signed %)
//   badge      – one of: great_deal | fair | above_market | insufficient_data
//
// This widget reads ALL of that defensively: the map may be absent, partial, or
// carry unexpected types (it lands before the model knows about it). When the
// data is missing, malformed, or `insufficient_data`, the badge renders nothing
// (SizedBox.shrink) so the detail screen degrades cleanly with no enrichment.

import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// A colored chip summarising how a listing's price compares to the area median.
///
/// [enrichment] is the raw (untyped) listing enrichment map — typically
/// `priceBadge` read from the backend response. Pass the whole listing
/// enrichment map OR the `priceBadge` sub-map; both are tolerated.
class PriceBadge extends StatelessWidget {
  const PriceBadge({super.key, required this.enrichment});

  /// Raw enrichment map; may be null/partial/absent. Never assumed well-formed.
  final Map<String, dynamic>? enrichment;

  /// Pulls the `priceBadge` sub-map whether [enrichment] already IS that
  /// sub-map or is the listing-level enrichment map that contains it.
  static Map<String, dynamic>? _badgeMap(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final nested = raw['priceBadge'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    // Already looks like a priceBadge map (carries its own keys).
    if (raw.containsKey('badge') ||
        raw.containsKey('deltaPct') ||
        raw.containsKey('medianPpm')) {
      return raw;
    }
    return null;
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final map = _badgeMap(enrichment);
    if (map == null) return const SizedBox.shrink();

    final badge = (map['badge'] as Object?)?.toString().trim().toLowerCase();
    // No usable verdict, or explicitly not enough comps → render nothing.
    if (badge == null || badge.isEmpty || badge == 'insufficient_data') {
      return const SizedBox.shrink();
    }

    final medianPpm = _toDouble(map['medianPpm']);
    final deltaPct = _toDouble(map['deltaPct']);

    final style = _styleFor(badge);

    // Build the right-side comparison line defensively: only include parts we
    // actually have. Median alone, delta alone, or both — all read naturally.
    final parts = <String>[];
    if (medianPpm != null && medianPpm > 0) {
      parts.add('₪${_formatInt(medianPpm.round())}/מ״ר');
    }
    if (deltaPct != null && deltaPct.abs() >= 1) {
      final pct = deltaPct.abs().round();
      parts.add(deltaPct < 0 ? '−$pct% מתחת לחציון האזור'
          : '+$pct% מעל חציון האזור');
    } else if (deltaPct != null) {
      parts.add('סביב חציון האזור');
    }
    final detail = parts.join(' · ');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.fg.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 18, color: style.fg),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: style.fg,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: style.fg.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeStyle _styleFor(String badge) {
    switch (badge) {
      case 'great_deal':
        return const _BadgeStyle(
          label: 'מחיר מצוין לאזור',
          fg: Color(0xFF15803D),
          bg: Color(0xFFE9F8EF),
          icon: IconsaxPlusLinear.trend_down,
        );
      case 'above_market':
        return const _BadgeStyle(
          label: 'מעל מחיר השוק',
          fg: Color(0xFFC2410C),
          bg: Color(0xFFFDF1E7),
          icon: IconsaxPlusLinear.trend_up,
        );
      case 'fair':
      default:
        // "fair" (and any unknown-but-present verdict) → neutral, calm blue.
        return const _BadgeStyle(
          label: 'מחיר הוגן לאזור',
          fg: Color(0xFF1D4ED8),
          bg: Color(0xFFEAF0FE),
          icon: IconsaxPlusLinear.tick_circle,
        );
    }
  }

  static String _formatInt(int value) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (value < 0 ? '-' : '') + buf.toString();
  }
}

class _BadgeStyle {
  const _BadgeStyle({
    required this.label,
    required this.fg,
    required this.bg,
    required this.icon,
  });
  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;
}
