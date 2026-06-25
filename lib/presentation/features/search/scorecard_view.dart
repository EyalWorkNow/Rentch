// ════════════════════════════════════════════════════════════════════════════
// SCORECARD VIEW — "למה זו?" transparency panel for one recommended property.
// ════════════════════════════════════════════════════════════════════════════
//
// Renders the FULL, honest, data-grounded reasoning behind a single match:
//   • the fit% + tier + confidence header,
//   • the top weighted dimensions as labeled bars (width ∝ contributionPct),
//     each citing its raw `stat` when present,
//   • persona reasons as ✓ chips (why it fits the user specifically),
//   • honest concerns (subtle),
//   • and the LLM's natural-language "by the numbers" sentence (llmReason).
//
// Collapsible by default to keep the chat card compact. Pure presentation over a
// frozen [Scorecard]; degrades gracefully when stats/reasons/llmReason are absent.
// Matches the Hebrew RTL styling + AppColors conventions of the אתי chat.
// ════════════════════════════════════════════════════════════════════════════

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

class ScorecardView extends StatefulWidget {
  const ScorecardView({super.key, required this.card, this.initiallyExpanded = false});

  final Scorecard card;
  final bool initiallyExpanded;

  @override
  State<ScorecardView> createState() => _ScorecardViewState();
}

class _ScorecardViewState extends State<ScorecardView> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(c),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _body(c),
            ),
          ),
        ],
      ),
    );
  }

  // ── collapsible header: "למה זו?" + fit% pill ──────────────────────────────
  Widget _header(Scorecard c) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Icon(IconsaxPlusBold.chart_2, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('למה זו?',
              style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          const SizedBox(width: 8),
          _fitPill(c),
          const Spacer(),
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            child: Icon(Icons.keyboard_arrow_down,
                size: 20, color: AppColors.textSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _fitPill(Scorecard c) {
    final color = _fitColor(c.fitPct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text('${c.fitPct}% התאמה',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  // ── expanded body ──────────────────────────────────────────────────────────
  Widget _body(Scorecard c) {
    final dims = [...c.dimensions]
      ..sort((a, b) {
        final w = b.weightPct.compareTo(a.weightPct);
        return w != 0 ? w : b.contributionPct.compareTo(a.contributionPct);
      });
    final top = dims.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // tier + confidence
        Row(children: [
          if (c.tier.isNotEmpty) _tierChip(c.tier),
          if (c.tier.isNotEmpty) const SizedBox(width: 8),
          if (c.confidence > 0) _confidenceLabel(c.confidence),
        ]),
        if (c.explanation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(c.explanation,
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
        ],
        // dimension bars — each shows how strong THIS apartment is on that axis
        // (its satisfaction 0–100%), so the overall fit reads as their blend.
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('כמה הדירה חזקה בכל פרמטר:',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final d in top) ...[
            _dimensionBar(d),
            const SizedBox(height: 10),
          ],
        ],
        // persona reasons (✓ chips)
        if (c.personaReasons.isNotEmpty) ...[
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final r in c.personaReasons) _personaChip(r)],
          ),
        ],
        // concerns (subtle)
        if (c.concerns.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final con in c.concerns) _concernRow(con),
        ],
        // LLM natural-language reason
        if ((c.llmReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _llmReason(c.llmReason!.trim()),
        ],
      ],
    );
  }

  Widget _tierChip(String tier) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(tier,
            style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
                fontSize: 11)),
      );

  Widget _confidenceLabel(double confidence) {
    final pct = (confidence.clamp(0.0, 1.0) * 100).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(IconsaxPlusLinear.shield_tick,
          size: 13, color: AppColors.textSecondary),
      const SizedBox(width: 4),
      Text('ביטחון $pct%',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _dimensionBar(ScorecardDimension d) {
    final frac = d.contributionPct.clamp(0.0, 1.0);
    final color = d.positive ? AppColors.primary : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(d.label,
              style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
          const Spacer(),
          Text('${(frac * 100).round()}%',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LayoutBuilder(builder: (context, cons) {
            return Stack(children: [
              Container(height: 7, width: cons.maxWidth, color: AppColors.divider),
              Container(
                height: 7,
                width: cons.maxWidth * frac,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.65)]),
                ),
              ),
            ]);
          }),
        ),
        if ((d.stat ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(d.stat!.trim(),
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.3)),
        ],
      ],
    );
  }

  Widget _personaChip(String reason) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(99),
          border:
              Border.all(color: AppColors.success.withValues(alpha: 0.30)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, size: 14, color: AppColors.success),
          const SizedBox(width: 4),
          Flexible(
            child: Text(reason,
                style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 11)),
          ),
        ]),
      );

  Widget _concernRow(String concern) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(IconsaxPlusLinear.info_circle,
              size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(concern,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35)),
          ),
        ]),
      );

  Widget _llmReason(String reason) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(IconsaxPlusBold.magicpen, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(reason,
                style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Color _fitColor(int fitPct) {
    if (fitPct >= 80) return AppColors.success;
    if (fitPct >= 60) return AppColors.primary;
    return AppColors.warning;
  }
}
