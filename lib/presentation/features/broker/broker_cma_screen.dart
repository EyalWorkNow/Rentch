import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_search_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// ניתוח שוק ותמחור — a Comparative Market Analysis (CMA).
///
/// The broker picks one of their own listings (the "subject"), and the screen
/// pulls comparable listings from the live market (same/near city, rooms ±1,
/// same transaction type) and derives a suggested price range from the comps'
/// median and 25–75th percentiles. This is the number a broker shows a seller
/// to justify the asking price. Read-only over the provider; no mutations.
class BrokerCmaScreen extends StatefulWidget {
  const BrokerCmaScreen({super.key});

  @override
  State<BrokerCmaScreen> createState() => _BrokerCmaScreenState();
}

/// Pure summary of comparable prices, computed from a sorted price list.
class CmaPriceRange {
  const CmaPriceRange({
    required this.count,
    required this.p25,
    required this.median,
    required this.p75,
  });

  final int count;
  final double p25;
  final double median;
  final double p75;
}

/// Linear-interpolated percentile [q] (0..1) of [values]. Pure + total: returns
/// 0 for an empty list. Values need NOT be pre-sorted.
double cmaPercentile(List<num> values, double q) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  if (sorted.length == 1) return sorted.first.toDouble();
  final clampedQ = q.clamp(0.0, 1.0);
  final pos = clampedQ * (sorted.length - 1);
  final lo = pos.floor();
  final hi = pos.ceil();
  final frac = pos - lo;
  return sorted[lo] * (1 - frac) + sorted[hi] * frac;
}

/// Builds the 25/50/75 percentile band for [prices]. Pure; null if empty.
CmaPriceRange? cmaRange(List<num> prices) {
  if (prices.isEmpty) return null;
  final range = CmaPriceRange(
    count: prices.length,
    p25: cmaPercentile(prices, 0.25),
    median: cmaPercentile(prices, 0.50),
    p75: cmaPercentile(prices, 0.75),
  );
  // Self-check: percentiles must be monotonic and within the data's bounds.
  assert(() {
    final minV = prices.reduce((a, b) => a < b ? a : b).toDouble();
    final maxV = prices.reduce((a, b) => a > b ? a : b).toDouble();
    final ok = range.p25 <= range.median + 1e-6 &&
        range.median <= range.p75 + 1e-6 &&
        range.p25 >= minV - 1e-6 &&
        range.p75 <= maxV + 1e-6;
    if (!ok) {
      throw StateError('cmaRange invariant broken: $prices -> '
          '${range.p25}/${range.median}/${range.p75}');
    }
    return true;
  }());
  return range;
}

class _BrokerCmaScreenState extends State<BrokerCmaScreen> {
  final PropertySearchRepository _searchRepo = PropertySearchRepository();

  String? _subjectId;

  // Comps fetched from the market for the selected subject's city. Null until a
  // subject is chosen; the in-memory ≤150 feed catalog is NOT a real comp pool,
  // so we query the backend for the city and filter that.
  List<RentalProperty>? _cityMarket; // raw city listings from the backend
  bool _loadingComps = false;
  String? _loadedForSubjectId; // guards against refetching the same subject

  Future<void> _loadCompsFor(RentalProperty subject) async {
    if (_loadedForSubjectId == subject.id && _cityMarket != null) return;
    setState(() {
      _loadingComps = true;
      _loadedForSubjectId = subject.id;
      _cityMarket = null;
    });
    List<RentalProperty> market = const [];
    try {
      if (_searchRepo.isConfigured && subject.city.trim().isNotEmpty) {
        market = await _searchRepo.search(
          PropertySearchCriteria(city: subject.city.trim()),
          limit: 200,
        );
      }
    } catch (_) {
      market = const [];
    }
    if (!mounted || _loadedForSubjectId != subject.id) return;
    // Fall back to the in-memory catalog if the city query returned nothing
    // (offline / unconfigured), so we never regress below the old behavior.
    if (market.isEmpty) {
      market = context.read<DatingProvider>().allProperties;
    }
    setState(() {
      _cityMarket = market;
      _loadingComps = false;
    });
  }

  /// Comps = market listings genuinely comparable to the subject: same
  /// transaction type, same city, rooms within ±1, SAME property type (a villa
  /// must not comp an apartment) and SIMILAR size (within ±35%) so ₪/m²
  /// percentiles aren't skewed by a 40m² vs 200m² pairing. Type/size filters
  /// apply only when both values are known (never drop a comp for missing data).
  List<RentalProperty> _comparablesFor(
    RentalProperty subject,
    List<RentalProperty> market,
  ) {
    final city = subject.city.trim().toLowerCase();
    final subjType = subject.propertyType.trim().toLowerCase();
    final subjSize = subject.sizeM2;
    return market.where((p) {
      if (p.id == subject.id) return false;
      if (p.price <= 0) return false;
      if (p.transactionType != subject.transactionType) return false;
      if (p.city.trim().toLowerCase() != city) return false;
      if ((p.rooms - subject.rooms).abs() > 1.0) return false;
      final pType = p.propertyType.trim().toLowerCase();
      if (subjType.isNotEmpty && pType.isNotEmpty && pType != subjType) {
        return false;
      }
      if (subjSize > 0 && p.sizeM2 > 0) {
        final ratio = p.sizeM2 / subjSize;
        if (ratio < 0.65 || ratio > 1.35) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final mine = provider.myProperties;
    RentalProperty? subject;
    for (final p in mine) {
      if (p.id == _subjectId) {
        subject = p;
        break;
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('ניתוח שוק ותמחור'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        body: mine.isEmpty
            ? _emptyState('אין לך נכסים פעילים לניתוח עדיין.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _picker(mine, subject),
                  const SizedBox(height: 16),
                  if (subject != null) _subjectSection(subject),
                ],
              ),
      ),
    );
  }

  Widget _picker(List<RentalProperty> mine, RentalProperty? subject) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: subject?.id,
          hint: const Text('בחר נכס לניתוח',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          items: [
            for (final p in mine)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                  '${p.address} · ${p.roomsLabel} חד׳',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() => _subjectId = id),
        ),
      ),
    );
  }

  Widget _subjectSection(RentalProperty subject) {
    // Kick off the city-market fetch for this subject (once) after the frame.
    if (_loadedForSubjectId != subject.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCompsFor(subject));
    }
    if (_loadingComps || _cityMarket == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final comps = _comparablesFor(subject, _cityMarket!);
    return _analysis(subject, comps);
  }

  Widget _analysis(RentalProperty subject, List<RentalProperty> comps) {
    final range = cmaRange(comps.map((p) => p.price).toList());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subjectCard(subject, range),
        const SizedBox(height: 20),
        Text(
          'נכסים להשוואה (${comps.length})',
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'אותה עיר · עד חדר הפרש · אותו סוג עסקה',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (comps.isEmpty)
          _emptyInline('לא נמצאו נכסים דומים בשוק להשוואה.')
        else
          for (final c in comps) _compRow(c, subject),
      ],
    );
  }

  Widget _subjectCard(RentalProperty subject, CmaPriceRange? range) {
    final price = subject.price;
    String position = '';
    Color positionColor = AppColors.textSecondary;
    if (range != null && price > 0) {
      if (price < range.p25) {
        position = 'מתחת לטווח המומלץ — אפשר אולי להעלות מחיר';
        positionColor = AppColors.success;
      } else if (price > range.p75) {
        position = 'מעל הטווח המומלץ — קשה יותר להצדיק מול הקונה';
        positionColor = AppColors.warning;
      } else {
        position = 'בתוך הטווח המומלץ — תמחור תואם שוק';
        positionColor = AppColors.primaryDark;
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(subject.address,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            '${subject.roomsLabel} חד׳ · ${subject.sizeM2} מ״ר · ${subject.transactionLabel}',
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text('המחיר הנוכחי: ${subject.priceLabel}',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          _cbsAnchor(subject),
          if (range == null)
            Text(
              subject.priceBadge?.hasData == true
                  ? 'מעט נכסים דומים בשוק — ההערכה מבוססת על מדד CBS לאזור.'
                  : 'אין מספיק נתוני שוק לחישוב טווח מומלץ.',
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textSecondary),
            )
          else ...[
            const Text('טווח מחיר מומלץ (25–75 אחוזון)',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(
              '${_money(range.p25)} – ${_money(range.p75)}',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark),
            ),
            const SizedBox(height: 4),
            Text('חציון השוק: ${_money(range.median)}',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: positionColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(position,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: positionColor)),
            ),
          ],
        ],
      ),
    );
  }

  // Real CBS/nadlan market anchor (₪/m² median for the area + implied fair
  // price + above/below-market badge). Renders nothing when unavailable.
  Widget _cbsAnchor(RentalProperty subject) {
    final badge = subject.priceBadge;
    if (badge == null || !badge.hasData) return const SizedBox.shrink();
    final ppm = badge.medianPpm!;
    final fair = subject.sizeM2 > 0 ? ppm * subject.sizeM2 : 0;
    final delta = badge.deltaPct;
    Color c = AppColors.primaryDark;
    if (delta != null) {
      if (delta > 5) {
        c = AppColors.warning; // priced above market
      } else if (delta < -5) {
        c = AppColors.success; // priced below market
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מדד שוק (CBS · נדל"ן)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('${_money(ppm.toDouble())} למ״ר · חציון האזור',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          if (fair > 0) ...[
            const SizedBox(height: 2),
            Text('מחיר הוגן משוער לנכס: ${_money(fair.toDouble())}',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
          if (badge.badge != null && badge.badge!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                delta != null
                    ? '${badge.badge} (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)}%)'
                    : badge.badge!,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: c),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compRow(RentalProperty comp, RentalProperty subject) {
    final perM2 = comp.pricePerSquareMeter;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comp.address,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${comp.roomsLabel} חד׳ · ${comp.sizeM2} מ״ר'
                  '${perM2 != null ? ' · ${_money(perM2.toDouble())}/מ״ר' : ''}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(comp.priceLabel,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _emptyState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, color: AppColors.textSecondary)),
        ),
      );

  Widget _emptyInline(String message) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message,
            style:
                const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
      );
}

/// ₪ with thousands separators, no decimals.
String _money(double value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '₪${rounded < 0 ? '-' : ''}$buf';
}
