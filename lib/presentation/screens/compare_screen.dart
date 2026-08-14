import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/finance/monthly_cost.dart';
import 'package:dating_app/core/utils/helpers/property_label_helper.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/core/finance/price_realism.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Side-by-side comparison of the tenant's saved (or searched-in) listings.
///
/// Built from the apartment-seeker's point of view, around the things that
/// actually make choosing hard:
///   1. the rent is NOT the real cost (arnona + vaad hide ~₪600–1,000/mo),
///   2. you can't tell if a price is fair without a market anchor,
///   3. trade-offs are hard to hold in your head ("cheaper but smaller, no
///      parking, 4th floor no elevator…"),
///   4. "which do I actually pick?" — decision paralysis.
/// So the primary surface is decisions, not a spec dump: a bottom-line pick, the
/// TRUE monthly cost, and plain-language trade-offs. The full spec table is
/// demoted to a collapsible section for the detail-oriented.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  /// Max columns compared at once (mobile-portrait ceiling).
  static const int maxColumns = 3;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  /// Ordered ids of the listings currently compared (<= maxColumns).
  final List<String> _columns = <String>[];

  /// Listings pulled in via search (not in the saved list).
  final List<RentalProperty> _searchAdded = <RentalProperty>[];

  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context.watch in build() re-fires this when saved listings finish loading,
    // so seeding survives async persistence.
    if (_seeded) return;
    final pool = _pool(context.read<DatingProvider>());
    if (pool.length < 2) return;
    _columns
      ..clear()
      ..addAll(pool.take(CompareScreen.maxColumns).map((p) => p.id));
    _seeded = true;
  }

  List<RentalProperty> _pool(DatingProvider p) => <RentalProperty>[
        ...p.savedProperties,
        ..._searchAdded
            .where((a) => !p.savedProperties.any((s) => s.id == a.id)),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<DatingProvider>();
    final pool = _pool(provider);

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(l10n.compareScreen724ef1bb),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: l10n.compareScreenBbabc52c,
              icon: const Icon(IconsaxPlusLinear.search_normal_1),
              onPressed: () => _openSearch(provider),
            ),
          ],
        ),
        body: _body(context, provider, pool),
      ),
    );
  }

  Widget _body(
      BuildContext context, DatingProvider provider, List<RentalProperty> pool) {
    final l10n = AppLocalizations.of(context)!;
    if (pool.length < 2) return _EmptyState(savedCount: pool.length);

    final columns = _resolveColumns(pool);
    final showPicker = pool.length > CompareScreen.maxColumns;

    return Column(
      children: [
        if (showPicker)
          _ColumnDropdown(pool: pool, selected: _columns, onToggle: _toggle),
        if (columns.length < 2)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.compareScreen61e90252,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: _CompareBody(
              analysis: _Analysis(columns, provider),
            ),
          ),
      ],
    );
  }

  List<RentalProperty> _resolveColumns(List<RentalProperty> pool) {
    final byId = {for (final p in pool) p.id: p};
    return [
      for (final id in _columns)
        if (byId[id] != null) byId[id]!
    ];
  }

  void _toggle(String id) {
    setState(() {
      if (_columns.contains(id)) {
        _columns.remove(id);
      } else if (_columns.length < CompareScreen.maxColumns) {
        _columns.add(id);
      }
    });
  }

  Future<void> _openSearch(DatingProvider provider) async {
    final picked = await showModalBottomSheet<RentalProperty>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComparePickerSheet(properties: provider.allProperties),
    );
    if (picked == null) return;
    setState(() {
      if (!_searchAdded.any((p) => p.id == picked.id) &&
          !provider.savedProperties.any((p) => p.id == picked.id)) {
        _searchAdded.add(picked);
      }
      _columns.remove(picked.id);
      if (_columns.length >= CompareScreen.maxColumns) _columns.removeAt(0);
      _columns.add(picked.id);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Analysis — everything the seeker-facing widgets need, computed once.
// ═══════════════════════════════════════════════════════════════════════════

class _Analysis {
  _Analysis(this.props, this.provider)
      : costs = [for (final p in props) _trueCost(p)],
        below = [for (final p in props) belowMarket(p)],
        matches = [for (final p in props) provider.displayMatchScore(p)] {
    valueIdx = bestValueIndex(below);
    cheapestTotalIdx = _minIdx([for (final p in props) _totalMonthly(p)]);
    cheapestRentIdx =
        _minIdx([for (final p in props) p.price > 0 ? p.price : null]);
    matchIdx = _maxIdx(matches.map((m) => m?.toDouble()).toList());
    allRent = props
        .every((p) => p.transactionType == PropertyTransactionType.rent);
  }

  final List<RentalProperty> props;
  final DatingProvider provider;
  final List<MonthlyCostEstimate?> costs;
  final List<double?> below; // fraction below local market (null = no anchor)
  final List<int?> matches;

  late final int valueIdx; // best value vs market (or -1)
  late final int matchIdx; // best personal match (or -1)
  late final int cheapestTotalIdx; // cheapest TRUE monthly cost (or -1)
  late final int cheapestRentIdx; // cheapest headline rent (or -1)
  late final bool allRent;

  /// The recommended pick: value if we could anchor it, else cheapest true cost.
  int get pickIdx => valueIdx >= 0 ? valueIdx : cheapestTotalIdx;

  static int _minIdx(List<num?> v) {
    var idx = -1;
    num best = double.infinity;
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x != null && x < best) {
        best = x;
        idx = i;
      }
    }
    return idx;
  }

  static int _maxIdx(List<double?> v) {
    if (v.whereType<double>().length < 2) return -1;
    var idx = -1;
    var best = double.negativeInfinity;
    for (var i = 0; i < v.length; i++) {
      final x = v[i];
      if (x != null && x > best) {
        best = x;
        idx = i;
      }
    }
    return idx;
  }
}

/// True monthly cost for a rental (rent + arnona + vaad); null for sales/missing.
MonthlyCostEstimate? _trueCost(RentalProperty p) =>
    p.transactionType == PropertyTransactionType.rent
        ? MonthlyCost.estimate(rent: p.price, sizeM2: p.sizeM2, city: p.city)
        : null;

/// The number to rank cost by: true monthly total for rentals, else the price.
num? _totalMonthly(RentalProperty p) {
  final c = _trueCost(p);
  if (c != null) return c.total;
  return p.price > 0 ? p.price : null;
}

/// How far a listing sits below its own local market price, as a fraction
/// (0.12 = 12% under). Null when there's no market prior or the price is a
/// sanity outlier (bait) — those can't be a genuine "best value".
double? belowMarket(RentalProperty p) {
  final v = PriceRealism.check(p);
  if (v.flag != PriceFlag.ok) return null;
  return 1 - v.ratio;
}

// ═══════════════════════════════════════════════════════════════════════════
// Pure ranking helpers (unit-tested in test/compare_logic_test.dart).
// ═══════════════════════════════════════════════════════════════════════════

/// Best value = the listing furthest below its own local market price.
/// Returns -1 unless ≥2 columns are comparable, so the pick is real rather than
/// an arbitrary in-group score.
int bestValueIndex(List<double?> belowMarket) {
  if (belowMarket.whereType<double>().length < 2) return -1;
  var best = -1;
  var bestVal = double.negativeInfinity;
  for (var i = 0; i < belowMarket.length; i++) {
    final v = belowMarket[i];
    if (v != null && v > bestVal) {
      bestVal = v;
      best = i;
    }
  }
  return best;
}

/// Column indices holding the best value for a numeric row. Uses an epsilon so
/// float ties all light up; empty when every column is equal or none numeric.
Set<int> numericWinners(List<double?> vals, {required bool minIsBest}) {
  double? bestVal;
  for (final v in vals) {
    if (v == null) continue;
    if (bestVal == null || (minIsBest ? v < bestVal : v > bestVal)) bestVal = v;
  }
  if (bestVal == null) return const {};
  if (vals.whereType<double>().toSet().length < 2) return const {};
  final out = <int>{};
  for (var i = 0; i < vals.length; i++) {
    final v = vals[i];
    if (v != null && (v - bestVal).abs() < 0.5) out.add(i);
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// Seeker-facing body.
// ═══════════════════════════════════════════════════════════════════════════

class _CompareBody extends StatelessWidget {
  const _CompareBody({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderStrip(analysis: analysis),
          const SizedBox(height: 14),
          _BottomLineCard(analysis: analysis),
          const SizedBox(height: 14),
          if (analysis.allRent) ...[
            _TrueCostCard(analysis: analysis),
            const SizedBox(height: 14),
          ],
          _TradeOffCard(analysis: analysis),
          const SizedBox(height: 14),
          _DetailsSection(analysis: analysis),
        ],
      ),
    );
  }
}

// ── header: which flats, with photos ────────────────────────────────────────

class _HeaderStrip extends StatelessWidget {
  _HeaderStrip({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final props = analysis.props;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < props.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == props.length - 1 ? 0 : 8),
              child: _headerCard(context, props[i], i == analysis.pickIdx),
            ),
          ),
      ],
    );
  }

  Widget _headerCard(BuildContext context, RentalProperty p, bool isPick) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 88,
              width: double.infinity,
              child: SafeMedia(
                media: p.primaryMedia,
                fallback: Container(color: AppColors.borderLight),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _where(p),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: isPick ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
          Text(
            p.priceLabel,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── the bottom line: which to pick, and why (honest) ────────────────────────

class _BottomLineCard extends StatelessWidget {
  _BottomLineCard({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = analysis;
    if (a.pickIdx < 0) {
      // Not enough data to recommend — say so, don't fake it.
      return _plain(
        l10n.compareScreen27eebc10,
        l10n.compareScreen4ec49abd,
      );
    }
    final pick = a.props[a.pickIdx];
    final lines = <String>[];

    // 1) value vs market (the "am I overpaying?" answer)
    lines.add(_valueLine(context, pick));
    // 2) the real cost (the "rent isn't the real cost" answer), rentals only
    final cost = a.costs[a.pickIdx];
    if (cost != null) {
      lines.add(l10n.compareScreenFcb21fe2(_thousands(cost.total)) +
          l10n.compareScreen46bf1369);
    }
    // 3) one honest caveat
    final caveat = _caveat(context, a, a.pickIdx);
    if (caveat != null) lines.add(l10n.compareScreenA8bb36b3(caveat));

    final matchNote = (a.matchIdx >= 0 && a.matchIdx != a.pickIdx)
        ? l10n.compareScreenC25ab447(_where(a.props[a.matchIdx])) +
            l10n.compareScreen332e33ea(a.matches[a.matchIdx]!)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(l10n.compareScreen2f883e47,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          Text('${_where(pick)} · ${pick.priceLabel}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(IconsaxPlusBold.tick_circle,
                    size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(l,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.3))),
              ]),
            ),
          if (matchNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(IconsaxPlusBold.heart, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(matchNote,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.3))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  String _valueLine(BuildContext context, RentalProperty w) {
    final l10n = AppLocalizations.of(context)!;
    final bm = belowMarket(w);
    final city = w.city.trim();
    final where = city.isEmpty ? '' : l10n.compareScreen08920749(city);
    if (bm == null) return l10n.compareScreen651fe4ea;
    final pct = (bm * 100).round();
    if (pct >= 2) return l10n.compareScreenE97266c1(pct, where);
    if (pct <= -2) return l10n.compareScreen2514977c;
    return l10n.compareScreenE036fa5f(where);
  }

  Widget _plain(String title, String body) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
        ]),
      );

  /// The single biggest thing the pick gives up to any other option.
  String? _caveat(BuildContext context, _Analysis a, int idx) {
    final l10n = AppLocalizations.of(context)!;
    final pick = a.props[idx];
    final others = [
      for (var i = 0; i < a.props.length; i++)
        if (i != idx) a.props[i]
    ];
    // Bigger flat exists?
    if (others.any((o) => o.sizeM2 > pick.sizeM2 + 4)) {
      return l10n.compareScreen41c2e13a;
    }
    // A premium feature the pick lacks but another has.
    final featureLabels = _featureLabels(context);
    for (final f in _premiumFeatures) {
      if (!pick.featureFlags.isEnabled(f) &&
          others.any((o) => o.featureFlags.isEnabled(f))) {
        return l10n.compareScreen7cb99b30(featureLabels[f]!);
      }
    }
    // A cheaper true cost exists?
    final myCost = _totalMonthly(pick);
    if (myCost != null &&
        others.any((o) {
          final c = _totalMonthly(o);
          return c != null && c < myCost - 100;
        })) {
      return l10n.compareScreenD948b41f;
    }
    return null;
  }
}

// ── the true monthly cost reveal (rentals) ──────────────────────────────────

class _TrueCostCard extends StatelessWidget {
  _TrueCostCard({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = analysis;
    final maxTotal = a.costs
        .whereType<MonthlyCostEstimate>()
        .fold<int>(0, (m, c) => c.total > m ? c.total : m);

    // The teaching moment: the flat with the lowest RENT isn't always the
    // cheapest to actually live in once arnona + vaad are counted.
    final revealsGap = a.cheapestRentIdx >= 0 &&
        a.cheapestTotalIdx >= 0 &&
        a.cheapestRentIdx != a.cheapestTotalIdx;

    return _Section(
      icon: IconsaxPlusBold.wallet_3,
      title: l10n.compareScreen5b4d6e83,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.compareScreen3b9ffcf8,
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < a.props.length; i++)
            _costRow(context, a.props[i], a.costs[i], maxTotal,
                isCheapest: i == a.cheapestTotalIdx),
          if (revealsGap) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(IconsaxPlusBold.info_circle,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.compareScreen35beed96(
                            _where(a.props[a.cheapestRentIdx])) +
                        l10n.compareScreenFc7a9430(
                            _where(a.props[a.cheapestTotalIdx])) +
                        l10n.compareScreen5706cd1b,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _costRow(
      BuildContext context, RentalProperty p, MonthlyCostEstimate? c, int maxTotal,
      {required bool isCheapest}) {
    final l10n = AppLocalizations.of(context)!;
    final total = c?.total ?? p.price;
    final frac = maxTotal > 0 ? (total / maxTotal).clamp(0.08, 1.0) : 1.0;
    final rentFrac = c != null && c.total > 0 ? c.rent / c.total : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                _where(p),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (isCheapest)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l10n.compareScreenCbde97ef,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success)),
              ),
            Text('₪${_thousands(total)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: isCheapest
                        ? AppColors.success
                        : AppColors.textPrimary)),
          ]),
          const SizedBox(height: 5),
          // Stacked bar: rent portion vs the arnona+vaad add-on.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: frac,
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  Expanded(
                    flex: (rentFrac * 100).round().clamp(1, 100),
                    child: Container(color: AppColors.primary),
                  ),
                  if (c != null)
                    Expanded(
                      flex: ((1 - rentFrac) * 100).round().clamp(1, 100),
                      child: Container(
                          color: AppColors.primary.withValues(alpha: 0.35)),
                    ),
                ]),
              ),
            ),
          ),
          if (c != null) ...[
            const SizedBox(height: 3),
            Text(
              l10n.compareScreenCc3022d2(_thousands(c.rent), _thousands(c.arnona)) +
                  l10n.compareScreenAab6709f(_thousands(c.vaad)),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── trade-offs: what you give up, in plain Hebrew ───────────────────────────

class _TradeOffCard extends StatelessWidget {
  const _TradeOffCard({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = analysis;
    final pickIdx = a.pickIdx >= 0 ? a.pickIdx : 0;
    final pick = a.props[pickIdx];

    return _Section(
      icon: IconsaxPlusBold.arrow_swap_horizontal,
      title: l10n.compareScreenE1000003,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.compareScreenB05c14b6(_where(pick)),
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < a.props.length; i++)
            if (i != pickIdx) _versusBlock(context, a, i, pickIdx),
        ],
      ),
    );
  }

  Widget _versusBlock(BuildContext context, _Analysis a, int i, int pickIdx) {
    final l10n = AppLocalizations.of(context)!;
    final o = a.props[i];
    final v = _versus(context, a, i, pickIdx);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_where(o),
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (v.better.isEmpty && v.worse.isEmpty)
          Text(l10n.compareScreen87ede2ed,
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
        else ...[
          for (final b in v.better) _line(true, b),
          for (final w in v.worse) _line(false, w),
        ],
      ]),
    );
  }

  Widget _line(bool good, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            good ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.minus_cirlce,
            size: 15,
            color: good ? AppColors.success : AppColors.textDisabled,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: good ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
        ]),
      );

  /// What option [i] is better/worse at vs the pick — the head-to-head a seeker
  /// would otherwise have to work out in their head.
  ({List<String> better, List<String> worse}) _versus(
      BuildContext context, _Analysis a, int i, int pickIdx) {
    final l10n = AppLocalizations.of(context)!;
    final o = a.props[i];
    final pick = a.props[pickIdx];
    final better = <String>[];
    final worse = <String>[];

    // cost (true monthly when we have it)
    final co = _totalMonthly(o);
    final cp = _totalMonthly(pick);
    if (co != null && cp != null && (co - cp).abs() >= 100) {
      final d = _thousands((co - cp).abs().round());
      (co < cp ? better : worse).add(co < cp
          ? l10n.compareScreenD46b7e4d(d)
          : l10n.compareScreenF17583c1(d));
    }
    // space
    if (o.sizeM2 > 0 && pick.sizeM2 > 0 && (o.sizeM2 - pick.sizeM2).abs() >= 4) {
      final d = (o.sizeM2 - pick.sizeM2).abs();
      (o.sizeM2 > pick.sizeM2 ? better : worse).add(o.sizeM2 > pick.sizeM2
          ? l10n.compareScreenF1897440(d)
          : l10n.compareScreenE791ef57(d));
    }
    // rooms
    if (o.rooms > 0 && pick.rooms > 0 && (o.rooms - pick.rooms).abs() >= 0.5) {
      (o.rooms > pick.rooms ? better : worse).add(o.rooms > pick.rooms
          ? l10n.compareScreen5d0daead(o.roomsLabel)
          : l10n.compareScreenE9e5b9ac(o.roomsLabel));
    }
    // features
    final featureLabels = _featureLabels(context);
    for (final f in _premiumFeatures) {
      final oHas = o.featureFlags.isEnabled(f);
      final pHas = pick.featureFlags.isEnabled(f);
      if (oHas && !pHas) better.add(l10n.compareScreenAe9d2da6(featureLabels[f]!));
      if (!oHas && pHas) worse.add(l10n.compareScreenC88245ca(featureLabels[f]!));
    }
    // market value
    final bo = belowMarket(o);
    final bp = belowMarket(pick);
    if (bo != null && bp != null && (bo - bp).abs() >= 0.03) {
      final pct = ((bo - bp).abs() * 100).round();
      (bo > bp ? better : worse).add(bo > bp
          ? l10n.compareScreen56d02b30(pct)
          : l10n.compareScreen3bce9322(pct));
    }
    // personal match
    final mo = a.matches[i];
    final mp = a.matches[pickIdx];
    if (mo != null && mp != null && (mo - mp).abs() >= 5) {
      (mo > mp ? better : worse).add(mo > mp
          ? l10n.compareScreen7f897f38(mo)
          : l10n.compareScreen95af2d2f(mo));
    }

    return (better: better.take(4).toList(), worse: worse.take(4).toList());
  }
}

// ── full spec table (collapsed by default) ──────────────────────────────────

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(l10n.compareScreenE33e9eb9,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          leading: const Icon(IconsaxPlusLinear.document_text,
              color: AppColors.textSecondary),
          childrenPadding: EdgeInsets.zero,
          children: [_CompareTable(analysis: analysis)],
        ),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.analysis});
  final _Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = analysis.provider;
    final properties = analysis.props;
    final rows = <_CompareRow>[
      _CompareRow.number(l10n.compareScreenCc097285,
          (p) => p.price > 0 ? p.price.toDouble() : null, (p) => p.priceLabel,
          best: _Best.min),
      _CompareRow.number(l10n.compareScreen1e7862a6, _perM2, _perM2Label,
          best: _Best.min),
      _CompareRow.text(l10n.compareScreenB50b3974, (p) => p.roomsLabel),
      _CompareRow.number(l10n.compareScreen16f6bd25,
          (p) => p.sizeM2 > 0 ? p.sizeM2.toDouble() : null,
          (p) => p.sizeM2 > 0 ? l10n.compareScreenD8b6113c(p.sizeM2) : '—',
          best: _Best.max),
      _CompareRow.text(l10n.compareScreen047e630b, (p) => _floorLabel(p, l10n)),
      _CompareRow.flag(l10n.compareScreen8d058056, l10n.compareScreen4175f994,
          l10n.compareScreen21a2d9d6, (p) => p.featureFlags.isEnabled('elevator')),
      _CompareRow.flag(l10n.compareScreenA9655ab3, l10n.compareScreen4175f994,
          l10n.compareScreen21a2d9d6, (p) => p.featureFlags.isEnabled('parking')),
      _CompareRow.flag(l10n.compareScreen86425fcf, l10n.compareScreen4175f994,
          l10n.compareScreen21a2d9d6, (p) => p.featureFlags.isEnabled('balcony')),
      _CompareRow.flag(l10n.compareScreenE1cca9ff, l10n.compareScreen4175f994,
          l10n.compareScreen21a2d9d6, (p) => p.featureFlags.isEnabled('mamad')),
      _CompareRow.text(l10n.compareScreenFcf022d8,
          (p) => p.condition.trim().isEmpty
              ? '—'
              : conditionLabel(p.condition.trim(), l10n)),
      _CompareRow.number(
        l10n.compareScreen206ee003,
        (p) => provider.displayMatchScore(p)?.toDouble(),
        (p) {
          final s = provider.displayMatchScore(p);
          return s == null ? '—' : '$s%';
        },
        best: _Best.max,
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          _DataRow(row: rows[i], properties: properties, shaded: i.isEven),
      ],
    );
  }
}

// ── shared calc helpers ─────────────────────────────────────────────────────

const _premiumFeatures = ['elevator', 'parking', 'balcony', 'mamad'];

Map<String, String> _featureLabels(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return {
    'elevator': l10n.compareScreen8d058056,
    'parking': l10n.compareScreenA9655ab3,
    'balcony': l10n.compareScreen86425fcf,
    'mamad': l10n.compareScreenE1cca9ff,
  };
}

double? _perM2(RentalProperty p) =>
    (p.sizeM2 <= 0 || p.price <= 0) ? null : p.price / p.sizeM2;

String _perM2Label(RentalProperty p) {
  if (p.sizeM2 <= 0 || p.price <= 0) return '—';
  return '₪${(p.price / p.sizeM2).round()}';
}

String _floorLabel(RentalProperty p, AppLocalizations l10n) {
  final floor = p.floor.trim();
  if (floor.isEmpty) return '—';
  final total = p.totalFloors.trim();
  final label = floorLabel(floor, l10n);
  return total.isEmpty ? label : '$label/$total';
}

String _where(RentalProperty p) {
  final w =
      p.neighborhood.trim().isNotEmpty ? p.neighborhood.trim() : p.city.trim();
  return w.isNotEmpty ? w : p.address;
}

String _thousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ── section shell ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  _Section({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

// ── column picker dropdown ──────────────────────────────────────────────────

class _ColumnDropdown extends StatelessWidget {
  const _ColumnDropdown({
    required this.pool,
    required this.selected,
    required this.onToggle,
  });

  final List<RentalProperty> pool;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final full = selected.length >= CompareScreen.maxColumns;
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: PopupMenuButton<String>(
        onSelected: onToggle,
        constraints: const BoxConstraints(minWidth: 240, maxHeight: 360),
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [
          for (final p in pool)
            CheckedPopupMenuItem<String>(
              value: p.id,
              checked: selected.contains(p.id),
              enabled: selected.contains(p.id) || !full,
              child: Text(_shortLabel(p),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                selected.isEmpty
                    ? l10n.compareScreenEf5ba2c7
                    : l10n.compareScreen0975a98d(
                        selected.length, CompareScreen.maxColumns),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }

  String _shortLabel(RentalProperty p) => '${_where(p)} · ${p.priceLabel}';
}

// ── details-table primitives ────────────────────────────────────────────────

enum _Best { none, min, max }

class _CompareRow {
  const _CompareRow._(
      this.label, this.display, this.numeric, this.flag, this.best);
  final String label;
  final String Function(RentalProperty) display;
  final double? Function(RentalProperty)? numeric;
  final bool Function(RentalProperty)? flag;
  final _Best best;

  factory _CompareRow.text(String l, String Function(RentalProperty) d) =>
      _CompareRow._(l, d, null, null, _Best.none);

  factory _CompareRow.number(
    String l,
    double? Function(RentalProperty) numeric,
    String Function(RentalProperty) display, {
    required _Best best,
  }) =>
      _CompareRow._(l, display, numeric, null, best);

  factory _CompareRow.flag(String l, String yes, String no,
          bool Function(RentalProperty) f) =>
      _CompareRow._(l, (p) => f(p) ? yes : no, null, f, _Best.none);
}

class _DataRow extends StatelessWidget {
  _DataRow({
    required this.row,
    required this.properties,
    required this.shaded,
  });

  final _CompareRow row;
  final List<RentalProperty> properties;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final winners = _winners();
    return Container(
      color: shaded ? AppColors.background : AppColors.surface,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabelCell(row.label),
            for (var i = 0; i < properties.length; i++)
              Expanded(child: _cell(properties[i], winners.contains(i))),
          ],
        ),
      ),
    );
  }

  Set<int> _winners() {
    if (row.numeric == null || row.best == _Best.none) return const {};
    return numericWinners(
      [for (final p in properties) row.numeric!(p)],
      minIsBest: row.best == _Best.min,
    );
  }

  Widget _cell(RentalProperty p, bool isWinner) {
    if (row.flag != null) {
      final on = row.flag!(p);
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Icon(
          on ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.minus_cirlce,
          color: on ? AppColors.success : AppColors.textDisabled,
          size: 22,
        ),
      );
    }
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      color: isWinner ? AppColors.primary.withValues(alpha: 0.10) : null,
      child: Text(
        row.display(p),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
          color: isWinner ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _LabelCell extends StatelessWidget {
  const _LabelCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState({required this.savedCount});
  final int savedCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = savedCount == 0
        ? l10n.compareScreenF419307d
        : l10n.compareScreen8833d8c9;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows_rounded,
                size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, height: 1.4, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable catalog list → returns the tapped property to add to the compare.
class _ComparePickerSheet extends StatefulWidget {
  _ComparePickerSheet({required this.properties});
  final List<RentalProperty> properties;
  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.properties
        : widget.properties.where((p) {
            return p.city.toLowerCase().contains(q) ||
                p.neighborhood.toLowerCase().contains(q) ||
                p.address.toLowerCase().contains(q);
          }).toList();
    return Directionality(
      textDirection: Directionality.of(context),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(l10n.compareScreenAbca0fe8,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: l10n.compareScreenDd5b39ef,
                  prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(l10n.compareScreenEf52c1b3,
                            style: const TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          final where = p.neighborhood.trim().isNotEmpty
                              ? '${p.neighborhood}, ${p.city}'
                              : p.city;
                          return ListTile(
                            leading: Icon(Icons.home_outlined,
                                color: AppColors.primary),
                            title: Text(where,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                l10n.compareScreen0c390fdc(p.priceLabel, p.roomsLabel)),
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
