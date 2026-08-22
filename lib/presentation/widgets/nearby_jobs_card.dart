import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/services/jobs_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// "עבודה באיזור" on the property detail screen — LIVE job openings near the
/// LISTING's city, fetched from the Jooble aggregator (which merges the
/// Israeli boards into one refreshing index — see [JobsService]). Free-text
/// search bar with autocomplete over common Hebrew job titles; the seeker's
/// own occupation pre-fills and pre-searches. Tapping an opening shows it on
/// its source board.
class NearbyJobsCard extends StatefulWidget {
  const NearbyJobsCard({
    super.key,
    required this.city,
    required this.lat,
    required this.lon,
    this.occupation,
  });

  final String city;
  final double lat;
  final double lon;

  /// The seeker's occupation vocabulary key ('hightech' | 'healthcare' | …),
  /// from [TenantProfile.occupation]. Null → the search bar starts empty.
  final String? occupation;

  @override
  State<NearbyJobsCard> createState() => _NearbyJobsCardState();
}

/// Common Israeli job-search terms for the autocomplete — role titles grouped
/// by field. Static and offline (the LIVE data is the search results, not the
/// suggestions); matching is substring-based so "מהנדס" surfaces every
/// engineering flavour and "מנהל" every management role.
const List<String> kJobSuggestions = [
  // הייטק ופיתוח
  'מפתח תוכנה', 'מפתחת תוכנה', 'מפתח Full Stack', 'מפתח Frontend',
  'מפתח Backend', 'מפתח מובייל', 'מפתח iOS', 'מפתח Android', 'מפתח Python',
  'מפתח Java', 'מפתח .NET', 'מפתח C++', 'מפתח React', 'מפתח Node.js',
  'מהנדס תוכנה', 'ארכיטקט תוכנה', 'ראש צוות פיתוח', 'בודק תוכנה QA',
  'אוטומציה QA', 'מהנדס DevOps', 'מהנדס SRE', 'מנהל מוצר', 'מנהל פרויקטים',
  'מעצב UX/UI', 'מעצב גרפי', 'מעצב מוצר', 'אנליסט נתונים', 'מדען נתונים',
  'מהנדס נתונים', 'מהנדס בינה מלאכותית', 'מומחה אבטחת מידע', 'סייבר',
  'תמיכה טכנית', 'מנהל רשת', 'מנהל מערכות מידע', 'Help Desk', 'IT',
  'מנהל אתר', 'בונה אתרים', 'מנתח מערכות',
  // הנדסה ותכנון
  'מהנדס אזרחי', 'מהנדס בניין', 'מהנדס מכונות', 'מהנדס חשמל',
  'מהנדס אלקטרוניקה', 'מהנדס תעשייה וניהול', 'מהנדס כימיה', 'מהנדס איכות',
  'מהנדס ביצוע', 'מנהל עבודה בבניין', 'הנדסאי בניין', 'הנדסאי אדריכלות',
  'הנדסאי חשמל', 'הנדסאי מכונות', 'אדריכל', 'שרטט', 'מודד', 'מפקח בנייה',
  // בריאות וטיפול
  'אח מוסמך', 'אחות מוסמכת', 'רופא', 'רופא שיניים', 'סייעת שיניים',
  'שיננית', 'רוקח', 'עוזר רוקח', 'פיזיותרפיסט', 'מרפא בעיסוק',
  'קלינאי תקשורת', 'פסיכולוג', 'עובד סוציאלי', 'דיאטן', 'אופטומטריסט',
  'טכנאי רנטגן', 'פרמדיק', 'חובש', 'מטפל בקשישים', 'מטפלת בקשישים',
  'כוח עזר', 'מזכירה רפואית', 'וטרינר', 'מטפל ברפואה משלימה', 'קוסמטיקאית',
  'ספר', 'מעצב שיער', 'מניקוריסטית',
  // חינוך והדרכה
  'מורה', 'מורה למתמטיקה', 'מורה לאנגלית', 'מחנך', 'גננת', 'סייעת גן',
  'סייעת בית ספר', 'מדריך נוער', 'מדריך חוגים', 'מרצה', 'מתרגל',
  'מורה פרטי', 'מאמן כושר', 'מדריך שחייה', 'מטפלת', 'בייביסיטר', 'אומנת',
  // משרד, אדמיניסטרציה ומשאבי אנוש
  'מזכירה', 'מזכיר', 'פקיד', 'פקידת קבלה', 'מנהל משרד', 'מנהלת משרד',
  'עוזר אישי', 'עוזרת אישית', 'רכז אדמיניסטרטיבי', 'מנהל אדמיניסטרטיבי',
  'קלדנית', 'מזין נתונים', 'רכז גיוס', 'מגייסת', 'משאבי אנוש',
  'מנהל משאבי אנוש', 'רכז הדרכה', 'מנהל רווחה',
  // כספים, ביטוח ומשפט
  'רואה חשבון', 'מנהל חשבונות', 'מנהלת חשבונות', 'הנהלת חשבונות',
  'חשב שכר', 'חשבת שכר', 'כלכלן', 'אנליסט פיננסי', 'יועץ השקעות',
  'יועץ משכנתאות', 'בנקאי', 'פקיד בנק', 'סוכן ביטוח', 'חתם ביטוח',
  'רפרנט ביטוח', 'עורך דין', 'מתמחה במשפטים', 'פרליגל', 'נוטריון',
  // מכירות, שיווק ושירות לקוחות
  'איש מכירות', 'אשת מכירות', 'נציג מכירות', 'נציג מכירות שטח',
  'נציג שירות לקוחות', 'נציג טלפוני', 'טלמיטינג', 'מוקדן', 'מנהל מכירות',
  'מנהל תיקי לקוחות', 'מנהל שיווק', 'מנהל דיגיטל', 'מנהל סושיאל',
  'מנהל קמפיינים', 'קופירייטר', 'עורך תוכן', 'כתב תוכן', 'מנהל קהילה',
  'יחסי ציבור', 'מנהל אירועים', 'מפיק אירועים',
  // מסחר וקמעונאות
  'קופאי', 'קופאית', 'סדרן סחורה', 'מוכר', 'מוכרת', 'מנהל חנות',
  'סגן מנהל חנות', 'מנהל משמרת', 'מנהל סניף', 'זבן', 'מחסנאי',
  // מסעדנות, מלונאות ואירוח
  'טבח', 'טבחית', 'שף', 'סו שף', 'עוזר טבח', 'מלצר', 'מלצרית', 'ברמן',
  'בריסטה', 'אופה', 'קונדיטור', 'מנהל מסעדה', 'אחמ"ש', 'שוטף כלים',
  'עובד מטבח', 'פקיד קבלה במלון', 'חדרנית', 'מארחת',
  // תחבורה, שילוח ולוגיסטיקה
  'נהג', 'נהג ב', 'נהג ג', 'נהג משאית', 'נהג אוטובוס', 'נהג מונית',
  'נהג חלוקה', 'שליח', 'שליח על אופנוע', 'מלגזן', 'מנהל לוגיסטיקה',
  'רכז שינוע', 'עובד מחסן', 'מנהל מחסן', 'סבל', 'מוביל',
  // מקצועות כפיים, תעשייה ובנייה
  'חשמלאי', 'חשמלאי רכב', 'אינסטלטור', 'שרברב', 'מסגר', 'רתך', 'נגר',
  'זגג', 'צבע', 'שפכטל', 'טייח', 'רצף', 'גבס', 'איטום', 'טכנאי מזגנים',
  'טכנאי קירור', 'טכנאי שירות', 'מכונאי רכב', 'פחח רכב', 'מפעיל מכונה',
  'מפעיל CNC', 'עובד ייצור', 'עובד בניין', 'איש אחזקה', 'מנהל אחזקה',
  'גנן', 'מדביר', 'מתקין מטבחים', 'מתקין דלתות', 'מתקין סולארי',
  // אבטחה, ניקיון ושירותים
  'מאבטח', 'קב"ט', 'שומר', 'סייר ביטחון', 'עובד ניקיון', 'מנקה',
  'אב בית', 'שוער', 'עובד תחזוקה',
  // חקלאות
  'עובד חקלאות', 'קטיף', 'מגדל',
  // נדל"ן
  'מתווך נדל"ן', 'סוכן נדל"ן', 'מנהל נכסים', 'שמאי מקרקעין', 'מאכלס',
  // כללי
  'משרה חלקית', 'משרה מלאה', 'עבודה מהבית', 'עבודה היברידית',
  'עבודה במשמרות', 'משמרות לילה', 'עבודה לסטודנטים', 'עבודה לבני נוער',
  'עבודה ללא ניסיון', 'עבודה זמנית', 'פרילנס',
];

class _NearbyJobsCardState extends State<NearbyJobsCard> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<JobPosting> _jobs = const [];
  bool _loading = false;
  bool _searched = false; // a search completed → empty state is meaningful

  static const _occupationSeed = {
    'hightech': 'מפתח תוכנה',
    'healthcare': 'אח מוסמך',
    'education': 'מורה',
    'finance': 'רואה חשבון',
    'law': 'עורך דין',
    'engineering': 'מהנדס',
    'public': 'עובד מדינה',
    'retail': 'איש מכירות',
    'academia': 'מרצה',
  };

  @override
  void initState() {
    super.initState();
    _query.text = _occupationSeed[widget.occupation] ?? '';
    // Pre-search with the seeker's own field so the card opens already useful.
    if (JobsService.instance.isConfigured && widget.city.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (!JobsService.instance.isConfigured) return;
    _focus.unfocus();
    setState(() => _loading = true);
    final jobs = await JobsService.instance.search(
      keywords: _query.text.trim(),
      city: widget.city,
      lat: widget.lat,
      lon: widget.lon,
    );
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _openJob(JobPosting j) async {
    try {
      await launchUrl(Uri.parse(j.link), mode: LaunchMode.externalApplication);
    } catch (_) {/* launch failed — nothing to do */}
  }

  // Employment density near the listing, from the national govdata job grid —
  // a "will I find work close by?" hint. Hidden when data is absent.
  Widget? _densityBadge(AppLocalizations l10n) {
    if (!GovData.instance.loaded) return null;
    final s = GovData.instance.employmentAccessScore(widget.lat, widget.lon);
    if (s <= 0) return null;
    final label = s > 0.66
        ? l10n.nearbyJobsCardDensityHigh
        : s > 0.33
            ? l10n.nearbyJobsCardDensityMedium
            : l10n.nearbyJobsCardDensityLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _searchBar(AppLocalizations l10n) {
    return RawAutocomplete<String>(
      textEditingController: _query,
      focusNode: _focus,
      optionsBuilder: (v) {
        final t = v.text.trim();
        if (t.isEmpty) return const Iterable<String>.empty();
        return kJobSuggestions.where((s) => s.contains(t)).take(10);
      },
      onSelected: (_) => _search(),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.nearbyJobsCardSearchHint,
            hintStyle: const TextStyle(
                fontSize: 13.5, color: AppColors.textSecondary),
            prefixIcon: IconButton(
              icon: Icon(IconsaxPlusLinear.search_normal_1,
                  size: 18, color: AppColors.primary),
              onPressed: _search,
            ),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () => setState(_query.clear),
                  ),
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    InkWell(
                      onTap: () => onSelected(o),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Expanded(
                            child: Text(o,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Same distance format as the nearby-places card (reuses its l10n keys).
  String _kmLabel(double km) {
    final l10n = AppLocalizations.of(context);
    return km < 1
        ? l10n.nearbyPlacesCardDcabfe76((km * 1000).round())
        : l10n.nearbyPlacesCard0b2db321(km.toStringAsFixed(1));
  }

  Widget _jobRow(JobPosting j) {
    final sub = [
      if (j.company.isNotEmpty) j.company,
      if (j.location.isNotEmpty) j.location,
    ].join(' · ');
    return InkWell(
      onTap: () => _openJob(j),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(j.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (j.km != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_on_rounded, size: 12, color: AppColors.primary),
                const SizedBox(width: 2),
                Text(_kmLabel(j.km!),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ])
            else if (j.salary.isNotEmpty)
              Text(j.salary,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _results(AppLocalizations l10n) {
    if (!JobsService.instance.isConfigured) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(l10n.nearbyJobsCardNoKey,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        ]),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      if (!_searched) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(l10n.nearbyJobsCardEmpty,
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Text(l10n.nearbyJobsCardResults(_jobs.length),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
        const SizedBox(height: 2),
        for (var i = 0; i < _jobs.length && i < 8; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
          _jobRow(_jobs[i]),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.city.trim().isEmpty) return const SizedBox.shrink();
    final badge = _densityBadge(l10n);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(IconsaxPlusLinear.briefcase,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.nearbyJobsCardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy)),
                ),
                if (badge != null) badge,
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.nearbyJobsCardHint(widget.city),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            _searchBar(l10n),
            _results(l10n),
          ],
        ),
      ),
    );
  }
}
