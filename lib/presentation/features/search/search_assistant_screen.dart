import 'package:provider/provider.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_search_repository.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';

// AI-style apartment search assistant: a rigid 3-turn, zero-free-text
// conversation that builds a [PropertySearchCriteria] and queries real
// listings. Mobile-first, RTL Hebrew, aligned to the app theme.
class SearchAssistantScreen extends StatefulWidget {
  const SearchAssistantScreen({super.key});

  @override
  State<SearchAssistantScreen> createState() => _SearchAssistantScreenState();
}

enum _Step { turn1, turn2, turn3, confirm, loading, results }

class _SearchAssistantScreenState extends State<SearchAssistantScreen> {
  final _repo = PropertySearchRepository();

  _Step _step = _Step.turn1;

  // Turn 1 — location & budget
  String? _city;
  RangeValues _budget = const RangeValues(2500, 8000);

  // Turn 2 — rooms & amenities
  double _minRooms = 2;
  final Set<String> _amenities = {};

  // Turn 3 — vibe
  String? _vibe;

  List<RentalProperty> _results = const [];

  static const _cities = [
    'תל אביב', 'ירושלים', 'רמת גן', 'גבעתיים', 'חיפה', 'נתניה', 'הרצליה', 'באר שבע',
  ];

  // label -> PropertyFeatureSet key
  static const _amenityOptions = <MapEntry<String, String>>[
    MapEntry('חניה', 'feat_parking'),
    MapEntry('מרפסת', 'feat_balcony'),
    MapEntry('מעלית', 'feat_elevator'),
    MapEntry('מרוהט', 'feat_furnished'),
    MapEntry('ממ״ד', 'feat_mamad'),
    MapEntry('משופצת', 'feat_renovated'),
    MapEntry('גינה', 'feat_garden'),
  ];

  static const _vibes = ['שקט', 'תוסס', 'משפחתי', 'סטודנטיאלי'];

  String _money(double v) => '₪${v.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      )}';

  Future<void> _runSearch() async {
    setState(() => _step = _Step.loading);
    final criteria = PropertySearchCriteria(
      city: _city,
      minPrice: _budget.start.round(),
      maxPrice: _budget.end.round(),
      minRooms: _minRooms,
      amenityKeys: _amenities,
      vibe: _vibe,
    );
    final found = await _repo.search(criteria);
    if (!mounted) return;
    // Label outcomes from this surface too: hand the searchId to the provider.
    context.read<DatingProvider>().setLastSearchId(_repo.lastSearchId);
    setState(() {
      _results = found;
      _step = _Step.results;
    });
  }

  void _reset() {
    setState(() {
      _step = _Step.turn1;
      _city = null;
      _budget = const RangeValues(2500, 8000);
      _minRooms = 2;
      _amenities.clear();
      _vibe = null;
      _results = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.textPrimary),
          title: Text(
            'עוזר חיפוש חכם',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          actions: [
            if (_step != _Step.turn1 && _step != _Step.loading)
              TextButton(
                onPressed: _reset,
                child: Text('התחל מחדש',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.turn1:
        return _turn1();
      case _Step.turn2:
        return _turn2();
      case _Step.turn3:
        return _turn3();
      case _Step.confirm:
        return _confirm();
      case _Step.loading:
        return _loading();
      case _Step.results:
        return _resultsView();
    }
  }

  // ── shared building blocks ───────────────────────────────────────────────

  Widget _progress(int activeIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final on = i <= activeIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 8,
            width: on ? 28 : 8,
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.borderLight,
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }

  Widget _bubble(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(16),
        border: Border(right: BorderSide(color: AppColors.primary, width: 4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(t,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(String text, VoidCallback? onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.borderLight,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Text(text,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  // ── Turn 1 ───────────────────────────────────────────────────────────────

  Widget _turn1() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _progress(0),
        _bubble('בוא נמצא לך דירה מושלמת! איפה אתה מחפש, ומה התקציב החודשי?'),
        _card(children: [
          _label('עיר'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cities
                .map((c) => _chip(c, _city == c,
                    () => setState(() => _city = _city == c ? null : c)))
                .toList(),
          ),
          const SizedBox(height: 20),
          _label('תקציב חודשי'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_money(_budget.start),
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold)),
              Text(_money(_budget.end),
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          RangeSlider(
            values: _budget,
            min: 1000,
            max: 20000,
            divisions: 76,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.borderLight,
            labels: RangeLabels(_money(_budget.start), _money(_budget.end)),
            onChanged: (v) => setState(() => _budget = v),
          ),
          const SizedBox(height: 8),
          _primaryButton('הבא →', _city == null ? null : () {
            setState(() => _step = _Step.turn2);
          }),
        ]),
      ],
    );
  }

  // ── Turn 2 ───────────────────────────────────────────────────────────────

  Widget _turn2() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _progress(1),
        _bubble('כמה מקום אתה צריך, ומה חובה שיהיה?'),
        _card(children: [
          _label('מספר חדרים (מינימום)'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stepperButton(Icons.remove,
                  () => setState(() => _minRooms = (_minRooms - 1).clamp(1, 6))),
              Text(
                _minRooms % 1 == 0
                    ? _minRooms.toInt().toString()
                    : _minRooms.toString(),
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
              _stepperButton(Icons.add,
                  () => setState(() => _minRooms = (_minRooms + 1).clamp(1, 6))),
            ],
          ),
          const SizedBox(height: 20),
          _label('מתקנים שחובה שיהיו'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _amenityOptions.map((e) {
              final on = _amenities.contains(e.value);
              return _chip(e.key, on, () {
                setState(() =>
                    on ? _amenities.remove(e.value) : _amenities.add(e.value));
              });
            }).toList(),
          ),
          const SizedBox(height: 16),
          _primaryButton('הבא →', () => setState(() => _step = _Step.turn3)),
        ]),
      ],
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary, size: 28),
      ),
    );
  }

  // ── Turn 3 ───────────────────────────────────────────────────────────────

  Widget _turn3() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _progress(2),
        _bubble('כמעט סיימנו! איזו אווירת שכונה מתאימה לך?'),
        _card(children: [
          _label('אופי השכונה'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _vibes
                .map((v) => _chip(v, _vibe == v,
                    () => setState(() => _vibe = _vibe == v ? null : v)))
                .toList(),
          ),
          const SizedBox(height: 16),
          _primaryButton('סקירה →', () => setState(() => _step = _Step.confirm)),
        ]),
      ],
    );
  }

  // ── Confirm ──────────────────────────────────────────────────────────────

  Widget _confirm() {
    final rooms = _minRooms % 1 == 0
        ? _minRooms.toInt().toString()
        : _minRooms.toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _progress(3),
        _bubble('מעולה! זה מה שאספתי. מוכן לחפש?'),
        _card(children: [
          _summaryRow('עיר', _city ?? 'הכל'),
          _summaryRow('תקציב', '${_money(_budget.start)} – ${_money(_budget.end)}'),
          _summaryRow('חדרים', '$rooms+'),
          _summaryRow(
              'מתקנים',
              _amenities.isEmpty
                  ? '—'
                  : _amenityOptions
                      .where((e) => _amenities.contains(e.value))
                      .map((e) => e.key)
                      .join(', ')),
          _summaryRow('אווירה', _vibe ?? '—'),
        ]),
        const SizedBox(height: 16),
        _primaryButton('🔍 חפש עכשיו', _runSearch, color: AppColors.success),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _reset,
          child: Text('התחל מחדש',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _summaryRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  // ── Loading ──────────────────────────────────────────────────────────────

  Widget _loading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text('מחפש דירות תואמות...',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── Results ──────────────────────────────────────────────────────────────

  Widget _resultsView() {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off,
                  size: 64, color: AppColors.textDisabled),
              const SizedBox(height: 16),
              Text('לא נמצאו דירות שתואמות',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text('נסה להרחיב את התקציב או להסיר מתקנים',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              _primaryButton('שנה חיפוש', _reset),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('נמצאו ${_results.length} דירות',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              TextButton(
                  onPressed: _reset,
                  child: Text('חיפוש חדש',
                      style: TextStyle(color: AppColors.primary))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: _results.length,
            itemBuilder: (_, i) => _propertyCard(_results[i]),
          ),
        ),
      ],
    );
  }

  Widget _propertyCard(RentalProperty p) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: AppColors.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardImage(p),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${p.priceLabel} ${p.priceSuffixLabel}',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 20)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight2,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text('${p.roomsLabel} חד׳',
                            style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(p.address,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                  if (p.isVerifiedListing) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.verified,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('מאומת',
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardImage(RentalProperty p) {
    final placeholder = Container(
      height: 170,
      color: AppColors.primaryLight2,
      child: Icon(Icons.home_rounded, size: 56, color: AppColors.primary),
    );
    if (p.imageUrl.isEmpty) return placeholder;
    return Image.network(
      p.imageUrl,
      height: 170,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : SizedBox(height: 170, child: Center(
              child: CircularProgressIndicator(color: AppColors.primary))),
    );
  }
}
