import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/insights/area_intelligence.dart';
import 'package:dating_app/core/insights/target_personas.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// "אינטליגנציית אזור" — enter an address, get every gov-data layer at that spot
/// and see which target tenant/buyer persona it serves best (and why). The
/// supply-side mirror of the tenant search engine (see AreaIntelligence).
class AreaIntelScreen extends StatefulWidget {
  const AreaIntelScreen({super.key});
  @override
  State<AreaIntelScreen> createState() => _AreaIntelScreenState();
}

class _AreaIntelScreenState extends State<AreaIntelScreen> {
  final _addr = TextEditingController();
  bool _loading = false;
  String? _error;
  AreaProfile? _profile;
  List<PersonaFit> _fits = const [];
  String _selectedPersona = 'young_couples';

  Future<void> _analyze() async {
    final q = _addr.text.trim();
    if (q.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locs = await locationFromAddress(q);
      if (locs.isEmpty) throw 'no-geo';
      final loc = locs.first;
      final profile = AreaIntelligence.profileAt(loc.latitude, loc.longitude);
      final fits = AreaIntelligence.suitablePersonas(profile.pfv);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _fits = fits;
        _selectedPersona = fits.first.persona.key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'לא הצלחתי לאתר את הכתובת. נסה לכתוב עיר + רחוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: AppColors.primary,
          elevation: 0,
          centerTitle: true,
          title: const Text('אינטליגנציית אזור',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _intro(),
              const SizedBox(height: 12),
              _addressRow(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(color: AppColors.error, fontSize: 13.5)),
              ],
              if (_profile != null) ...[
                const SizedBox(height: 18),
                _personaPicker(),
                const SizedBox(height: 12),
                _selectedFitCard(),
                const SizedBox(height: 18),
                _sectionTitle('כל שכבות הנתונים במקום'),
                const SizedBox(height: 10),
                _layersCard(_profile!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          Icon(IconsaxPlusLinear.map_1, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'הזן כתובת לבדיקת השקעה — ואקבל את כל הנתונים והשכבות של האזור, '
              'ולמי הוא הכי מתאים. ככה תדע בדיוק איזה קהל לחפש ומה חוזק המקום.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  Widget _addressRow() => Row(children: [
        Expanded(
          child: TextField(
            controller: _addr,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _analyze(),
            decoration: InputDecoration(
              hintText: 'כתובת: עיר + רחוב (למשל: תל אביב, דיזנגוף 100)',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(IconsaxPlusLinear.location, color: AppColors.primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.borderLight)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.borderLight)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _analyze,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('נתח',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ]);

  Widget _personaPicker() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in _fits) ...[
            _personaChip(f),
            const SizedBox(width: 8),
          ],
        ]),
      );

  Widget _personaChip(PersonaFit f) {
    final on = f.persona.key == _selectedPersona;
    return GestureDetector(
      onTap: () => setState(() => _selectedPersona = f.persona.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? AppColors.primary : AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${f.persona.emoji} ${f.persona.label}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.navy)),
          const SizedBox(width: 6),
          Text('${f.pct}%',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: on ? Colors.white70 : AppColors.primary)),
        ]),
      ),
    );
  }

  Widget _selectedFitCard() {
    final f = _fits.firstWhere((x) => x.persona.key == _selectedPersona,
        orElse: () => _fits.first);
    final color = f.pct >= 75
        ? AppColors.success
        : (f.pct >= 55 ? AppColors.primary : AppColors.warning);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${f.persona.emoji} ${f.persona.label}',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${f.pct}% התאמה',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
        const SizedBox(height: 12),
        if (f.reasons.isEmpty)
          Text('האזור פחות מתאים לקהל הזה.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5))
        else ...[
          Text('למה זה עובד לקהל הזה:',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in f.reasons)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999)),
                child: Text('✓ ${r.label}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _layersCard(AreaProfile p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        if (p.sesCluster > 0)
          _clusterRow('אשכול סוציו-אקונומי (בלוק)', p.sesCluster),
        _bar('בטיחות', p.safety),
        _bar('מרכזיות', p.centrality),
        _bar('תחבורה ציבורית', p.transit),
        _bar('מוסדות חינוך', p.schools),
        _bar('שירותי בריאות', p.health),
        _bar('חיי לילה ובילוי', p.nightlife),
        _bar('קרבה לתעסוקה', p.employment),
        _bar('פארקים וירוק', p.parkAccess),
        _bar('פוטנציאל השבחה', p.futureValue),
        const Divider(height: 22),
        _demographics(p),
      ]),
    );
  }

  Widget _clusterRow(String label, int cluster) {
    final color = cluster >= 7
        ? AppColors.success
        : (cluster >= 4 ? AppColors.primary : AppColors.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999)),
          child: Text('$cluster מתוך 10',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900, color: color)),
        ),
      ]),
    );
  }

  Widget _bar(String label, double v) {
    final pct = (v.clamp(0.0, 1.0) * 100).round();
    final color = pct >= 66
        ? AppColors.success
        : (pct >= 40 ? AppColors.primary : AppColors.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary))),
          Text('$pct%',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: v.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppColors.borderLight,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  Widget _demographics(AreaProfile p) => Row(children: [
        _demoStat('👶 ילדים (0-19)', p.childShare),
        _demoStat('🧑 עובדים (20-64)', p.youngShare),
        _demoStat('🌿 65+', p.seniorShare),
      ]);

  Widget _demoStat(String label, double share) => Expanded(
        child: Column(children: [
          Text('${(share.clamp(0.0, 1.0) * 100).round()}%',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary)),
        ]),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary));
}
