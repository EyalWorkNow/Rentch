import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart' show ScoredProperty;
import 'package:flutter/material.dart';

/// Detailed, data-grounded "why I picked this for you" — the personal customization
/// behind a recommendation: the fit %, the personal reasons, each weighted
/// dimension with its real number (price vs area median, distance to transit,
/// safety percentile…), a short narrative, and any honest concerns.
///
/// [dark] switches the palette for the voice screen's dark background.
class WhyDetails extends StatefulWidget {
  WhyDetails({super.key, required this.scored, this.dark = false});
  final ScoredProperty scored;
  final bool dark;

  @override
  State<WhyDetails> createState() => _WhyDetailsState();
}

class _WhyDetailsState extends State<WhyDetails> {
  bool _open = false;

  Color get _ink => widget.dark ? Colors.white : AppColors.textPrimary;
  Color get _sub => widget.dark ? Colors.white70 : AppColors.textSecondary;
  Color get _accent => AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final sc = widget.scored.scorecard;
    // Fallbacks when the full scorecard isn't attached (older paths).
    final tags = widget.scored.tags;
    final fitPct = sc?.fitPct ??
        int.tryParse(RegExp(r'(\d+)').firstMatch(tags.isNotEmpty ? tags.first : '')?.group(1) ?? '') ??
        (widget.scored.score * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Icon(Icons.auto_awesome, size: 16, color: _accent),
              const SizedBox(width: 6),
              Text('למה בחרתי לך את זו? · $fitPct% התאמה',
                  style: TextStyle(
                      color: _accent, fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: _accent),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _body(sc, tags),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ],
    );
  }

  Widget _body(sc, List<String> tags) {
    final children = <Widget>[];

    // Personal reasons (why it fits THIS user).
    final reasons = sc?.personaReasons ??
        (tags.length > 1 ? tags.sublist(1) : const <String>[]);
    for (final r in reasons) {
      children.add(_line(Icons.check_circle_rounded, _accent, r));
    }

    // Weighted dimensions with their real numbers.
    if (sc != null) {
      final dims = List.of(sc.dimensions)
        ..sort((a, b) => b.weightPct.compareTo(a.weightPct));
      for (final d in dims.where((d) => d.positive).take(5)) {
        final pct = (d.contributionPct * 100).round();
        final stat = (d.stat != null && d.stat!.trim().isNotEmpty)
            ? ' · ${d.stat}'
            : '';
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${d.label}$stat',
                    style: TextStyle(color: _ink, fontSize: 12.5, height: 1.3)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      color: _accent, fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: d.contributionPct.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor:
                    (widget.dark ? Colors.white : AppColors.navy).withValues(alpha: 0.10),
                color: _accent,
              ),
            ),
          ]),
        ));
      }
    }

    // Narrative — the "how I chose", grounded in the numbers.
    final narrative = (sc?.llmReason?.trim().isNotEmpty == true)
        ? sc!.llmReason!.trim()
        : (sc?.explanation?.trim().isNotEmpty == true ? sc!.explanation!.trim() : null);
    if (narrative != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(narrative,
            style: TextStyle(color: _sub, fontSize: 12.5, height: 1.45)),
      ));
    }

    // Honest concerns.
    for (final c in (sc?.concerns ?? const <String>[])) {
      children.add(_line(Icons.info_outline_rounded, AppColors.warning, c));
    }

    if (children.isEmpty) {
      children.add(_line(Icons.check_circle_rounded, _accent,
          'מתאימה למה שחיפשת — אזור, תקציב וגודל'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(color: _ink, fontSize: 12.5, height: 1.35)),
          ),
        ]),
      );
}
