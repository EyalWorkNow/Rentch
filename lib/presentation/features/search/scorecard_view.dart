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
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/widgets/nearby_places_card.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

class ScorecardView extends StatefulWidget {
  const ScorecardView({
    super.key,
    required this.card,
    this.initiallyExpanded = false,
    this.lat,
    this.lon,
    this.city,
    this.nearbyProfile,
  });

  final Scorecard card;
  final bool initiallyExpanded;

  // When lat/lon + a [nearbyProfile] are supplied (the chat "why this" preview),
  // a RELEVANT-ONLY nearby-places dropdown is appended at the very bottom.
  final double? lat;
  final double? lon;
  final String? city;
  final NearbyProfile? nearbyProfile;

  @override
  State<ScorecardView> createState() => _ScorecardViewState();
}

class _ScorecardViewState extends State<ScorecardView> {
  late bool _open = widget.initiallyExpanded;
  bool _sourcesOpen = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.slate50,
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
          Text(AppLocalizations.of(context)!.scorecardViewBd0267a3,
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
      child: Text(
          AppLocalizations.of(context)!.scorecardView161967a5(c.fitPct),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  // ── expanded body ──────────────────────────────────────────────────────────
  Widget _body(Scorecard c) {
    // c.dimensions is already ordered stated-first (the axes the user actually
    // searched by), so show the top of that order — not a generic re-sort.
    final top = c.dimensions.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // tier + confidence
        Row(children: [
          if (c.tier.isNotEmpty) _tierChip(c.tier),
          if (c.tier.isNotEmpty) const SizedBox(width: 8),
          if (c.confidence > 0) Flexible(child: _confidenceLabel(c.confidence)),
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
          Text(AppLocalizations.of(context)!.scorecardView2c98190f,
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
        // Named geo "why here" tags (X מ׳ from park/school/station/…) — a WRAP of
        // iconsax tags, shown inside "למה זו" above the data sources.
        if (c.highlights.any(isGeoTag)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in c.highlights.where(isGeoTag)) _GeoTag(t),
            ],
          ),
        ],
        // SEPARATE "מקורות הנתונים" dropdown — its own expand/collapse, shown
        // only when at least one dimension carries a real figure + source.
        if (_sourcedDimensions(c).isNotEmpty) ...[
          const SizedBox(height: 12),
          _sourcesSection(c),
        ],
        // At the VERY BOTTOM — a nearby-places dropdown with ONLY the sections
        // relevant to this seeker's search (a family sees schools/gans/clinics/…,
        // a young-area seeker sees supermarkets/dining/parks). Hidden when there's
        // no coords/profile or nothing relevant.
        if (widget.nearbyProfile != null &&
            widget.lat != null &&
            widget.lon != null) ...[
          const SizedBox(height: 4),
          NearbyPlacesCard(
            lat: widget.lat!,
            lon: widget.lon!,
            city: widget.city ?? '',
            profile: widget.nearbyProfile!,
            relevantOnly: true,
            carousel: true, // preview → tag carousel, top 3 + "צפה בכולם"
            maxChips: 3,
          ),
        ],
      ],
    );
  }

  // Dimensions that carry both a concrete figure and an attributable source.
  List<ScorecardDimension> _sourcedDimensions(Scorecard c) => [
        for (final d in c.dimensions)
          if ((d.stat ?? '').trim().isNotEmpty &&
              (d.source ?? '').trim().isNotEmpty)
            d,
      ];

  // ── collapsible "מקורות הנתונים" dropdown — distinct from "למה זו?" ─────────
  Widget _sourcesSection(Scorecard c) {
    final sourced = _sourcedDimensions(c);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _sourcesOpen = !_sourcesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Icon(IconsaxPlusLinear.document_text,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 7),
                Text(AppLocalizations.of(context)!.scorecardView5d1b29db,
                    style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('${sourced.length}',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _sourcesOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 19, color: AppColors.textSecondary),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _sourcesOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.scorecardViewE2d283c3,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          height: 1.3)),
                  const SizedBox(height: 8),
                  for (final d in sourced) ...[
                    _sourceRow(d),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(ScorecardDimension d) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(IconsaxPlusLinear.tick_circle,
                size: 13, color: AppColors.primary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d.label} — ${d.stat!.trim()}',
                    style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(
                    AppLocalizations.of(context)!
                        .scorecardViewBf4062b1(d.source!.trim()),
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      );

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
      Flexible(
        child: Text(AppLocalizations.of(context)!.scorecardViewA33028e6(pct),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
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

// Geo "why here" tags are emoji-prefixed by the engine; map the emoji → an iconsax
// icon and strip it from the label so each tag reads clearly.
const Map<String, IconData> _geoIcon = {
  '🏫': IconsaxPlusLinear.buildings_2,
  '🌳': IconsaxPlusLinear.tree,
  '🚉': IconsaxPlusLinear.bus,
  '🏖️': IconsaxPlusLinear.sun_1,
  '🎓': IconsaxPlusLinear.teacher,
  '🍸': IconsaxPlusLinear.coffee,
  '🏥': IconsaxPlusLinear.hospital,
  '🛒': IconsaxPlusLinear.shopping_cart,
  '🧸': IconsaxPlusLinear.teacher,
};

/// True if [t] is a named geo proximity tag (park/school/station/sea/uni/nightlife).
bool isGeoTag(String t) => _geoIcon.keys.any(t.startsWith);

class _GeoTag extends StatelessWidget {
  _GeoTag(this.raw);
  final String raw;

  @override
  Widget build(BuildContext context) {
    var icon = IconsaxPlusLinear.location;
    var label = raw;
    for (final e in _geoIcon.entries) {
      if (raw.startsWith(e.key)) {
        icon = e.value;
        label = raw.substring(e.key.length).trim();
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.navy)),
      ]),
    );
  }
}
