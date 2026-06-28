import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/core/search/engine/search_narrative.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/recommendation_explainer.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/features/search/scorecard_view.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// "נועה" — a warm, conversational search assistant. She lets the user explain
// themselves in their own words, reflects back what she understood, asks a
// gentle follow-up to build a fuller persona, and only then surfaces real
// listings (ranked over the loaded catalogue) inline in the chat — using the
// exact property-card design from the Messages page. Persona signal is captured
// to the dataset only after explicit consent.
class SearchChatScreen extends StatefulWidget {
  const SearchChatScreen({super.key});

  @override
  State<SearchChatScreen> createState() => _SearchChatScreenState();
}

const _botName = 'אתי';

class _ChatMsg {
  _ChatMsg({
    required this.role,
    this.text = '',
    this.scored = const [],
    this.chips = const [],
    this.isConsent = false,
  });
  final String role; // 'user' | 'assistant'
  String text; // mutable: the "how I chose" bubble is upgraded once the LLM returns
  List<ScoredProperty> scored; // mutable: scorecards get llmReason merged in async
  final List<String> chips;
  final bool isConsent;
  bool expanded = false; // "show more" toggle for result lists
}

class _SearchChatScreenState extends State<SearchChatScreen> {
  static const _consentPrefKey = 'dataset_persona_consent_v1';

  final _service = AssistantService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMsg> _messages = [];
  final List<String> _personaSnippets = [];
  final Map<String, String> _persona = {}; // household / vibe / timing ...
  SearchQuery _query = SearchQuery();

  int _userTurns = 0;
  bool _searched = false;
  bool _busy = false;
  String _lastReply = ''; // last assistant text, for the voice visualizer to speak
  bool? _consent;
  bool _consentAsked = false;
  Map<String, dynamic>? _pendingPersona;

  static const _starterChips = [
    '3 חדרים בתל אביב עד 7000, עם מרפסת',
    'ליד הרכבת, משופצת, לזוג עם כלב',
    'דירה בחיפה עם חניה ומעלית',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(_greetingMsg());
    _loadConsent();
  }

  _ChatMsg _greetingMsg() => _ChatMsg(
        role: 'assistant',
        text:
            'היי! אני $_botName 👋 כיף להכיר.\nאני כאן כדי לעזור לך למצוא בית שבאמת '
            'מתאים לך — בלי לחץ ובקצב שלך. ספר לי קצת עליך ועל מה שאתה מחפש, '
            'במילים שלך, ואני אדאג לשאר. 🙂',
        chips: _starterChips,
      );

  void _resetConversation() {
    setState(() {
      _messages.clear();
      _personaSnippets.clear();
      _persona.clear();
      _query = SearchQuery();
      _userTurns = 0;
      _searched = false;
      _messages.add(_greetingMsg());
    });
    _scrollToEnd();
  }

  String _money(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  // ── editable active-criteria bar ──────────────────────────────────────────
  Widget _criteriaBar() {
    if (_query.isEmpty) return const SizedBox.shrink();
    final items = <Widget>[];
    if (_query.neighborhood != null) {
      items.add(_removableChip('📍 ${_query.neighborhood}',
          () => _drop(neighborhood: true)));
    }
    if (_query.city != null) {
      items.add(_removableChip('📍 ${_query.city}', () => _drop(city: true)));
    }
    if (_query.propertyType != null) {
      items.add(_removableChip('🏠 ${_query.propertyType}',
          () => _drop(propertyType: true)));
    }
    if (_query.minRooms != null || _query.maxRooms != null) {
      items.add(
          _removableChip('🛏️ ${_roomsChipLabel()} חד׳', () => _drop(rooms: true)));
    }
    if (_query.minPrice != null || _query.maxPrice != null) {
      items.add(
          _removableChip('💰 ${_priceChipLabel()}', () => _drop(price: true)));
    }
    if (_query.nearTrain) {
      items.add(_removableChip('🚉 ליד הרכבת', () => _drop(train: true)));
    }
    if (_query.cheapPreference) {
      items.add(_removableChip('🏷️ הכי משתלם', () => _drop(cheap: true)));
    }
    for (final a in _query.amenities) {
      items.add(_removableChip(SmartSearch.amenityTag(a), () => _drop(amenity: a)));
    }
    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text('הסינון שלך:',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          for (final w in items)
            Padding(padding: const EdgeInsets.only(left: 6), child: w),
        ]),
      ),
    );
  }

  Widget _removableChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        GestureDetector(
            onTap: onRemove,
            child:
                Icon(Icons.close, size: 15, color: AppColors.primaryDark)),
      ]),
    );
  }

  String _roomsChipLabel() {
    String f(double r) => r % 1 == 0 ? r.toInt().toString() : r.toString();
    final lo = _query.minRooms, hi = _query.maxRooms;
    if (lo != null && hi != null) return lo == hi ? f(lo) : '${f(lo)}-${f(hi)}';
    if (lo != null) return '${f(lo)}+';
    return 'עד ${f(hi!)}';
  }

  String _priceChipLabel() {
    final lo = _query.minPrice, hi = _query.maxPrice;
    if (lo != null && hi != null) return '₪${_money(lo)}–${_money(hi)}';
    if (hi != null) return 'עד ₪${_money(hi)}';
    return 'מ-₪${_money(lo!)}';
  }

  void _drop(
      {bool city = false,
      bool neighborhood = false,
      bool rooms = false,
      bool price = false,
      bool propertyType = false,
      bool train = false,
      bool cheap = false,
      String? amenity}) {
    setState(() {
      _query = SearchQuery(
        city: city ? null : _query.city,
        neighborhood: neighborhood ? null : _query.neighborhood,
        minPrice: price ? null : _query.minPrice,
        maxPrice: price ? null : _query.maxPrice,
        minRooms: rooms ? null : _query.minRooms,
        maxRooms: rooms ? null : _query.maxRooms,
        propertyType: propertyType ? null : _query.propertyType,
        amenities: {..._query.amenities}..removeWhere((k) => k == amenity),
        nearTrain: train ? false : _query.nearTrain,
        cheapPreference: cheap ? false : _query.cheapPreference,
        rawText: _query.rawText,
      );
    });
    _rerunSearch();
  }

  void _rerunSearch() {
    if (!_searched) return;
    if (_query.isEmpty) {
      setState(() => _messages.add(_ChatMsg(
          role: 'assistant',
          text: 'ניקיתי את הסינון 🙂 ספר לי מה לחפש עכשיו.')));
      _scrollToEnd();
      return;
    }
    final provider = context.read<DatingProvider>();
    // Commute-aware: routes through the provider so the tenant's stored work
    // coords add the "מרחק מהעבודה" dimension to each scorecard automatically.
    final results = provider.recommendForTenant(provider.allProperties, _query,
        limit: 10);
    setState(() {
      _messages.add(_ChatMsg(
        role: 'assistant',
        text: results.isEmpty
            ? 'אחרי העדכון לא נשארו התאמות. אפשר להוסיף משהו אחר?'
            : 'עדכנתי לפי השינוי 👇',
        scored: results,
        chips: results.isEmpty ? const [] : _refineChips(),
      ));
    });
    _scrollToEnd();
  }

  Widget _resultList(_ChatMsg m) {
    final total = m.scored.length;
    final show = m.expanded ? total : (total > 3 ? 3 : total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < show; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _AssistantPropertyCard(
            scored: m.scored[i],
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    PropertyDetailScreen(property: m.scored[i].property))),
          ),
        ),
      if (!m.expanded && total > 3)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onTap: () => setState(() => m.expanded = true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('הצג עוד ${total - 3} דירות',
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down,
                    size: 18, color: AppColors.primaryDark),
              ]),
            ),
          ),
        ),
    ]);
  }

  Future<void> _loadConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_consentPrefKey)) {
        _consent = prefs.getBool(_consentPrefKey);
        _consentAsked = true;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Opens the full-screen voice conversation (big, clear visualizer). Speaking
  // and listening happen there; results flow into the chat behind it.
  Future<void> _openVoice() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _VoiceVisualizer(
        service: _service,
        onUtterance: _processVoiceUtterance,
      ),
    ));
    _scrollToEnd();
  }

  // Runs a spoken sentence through the same pipeline as typed input and returns
  // אתי's reply text (for the visualizer to read aloud).
  Future<String> _processVoiceUtterance(String transcript) async {
    await _send(transcript);
    return _lastReply.isEmpty
        ? 'ספר לי עוד קצת על מה שאתה מחפש'
        : _lastReply;
  }

  // ── conversation ──────────────────────────────────────────────────────────

  // Explicit "show me now" intent only — must NOT match the common word
  // "מחפש" (which contains "חפש"), so נועה still asks her refining question first.
  bool _wantsResultsNow(String t) => RegExp(
        r'תראה לי|תראי לי|הצג|בוא נראה|בואי נראה|תמצא לי|תמצאי לי|show me',
      ).hasMatch(t);

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    final provider = context.read<DatingProvider>();

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _personaSnippets.add(text);
      _userTurns++;
      _input.clear();
      _busy = true;
    });
    _scrollToEnd();

    // Criteria understanding: server Gemini (/assistant/extract) + on-device parser.
    Map<String, dynamic> llm = const {};
    try {
      final r = await _service.extractPropertyFields(text, currentFields: {});
      llm = r.fields;
    } catch (_) {}
    _query = _merge(_query, SmartSearch.parse(text, llm: llm));

    // Warm conversational reply from server נועה (Gemini, tenant_search mode).
    final sr = await _serverReply();
    final shouldSearch = !_query.isEmpty &&
        (_searched || _wantsResultsNow(text) || _userTurns >= 2);

    List<ScoredProperty> results = const [];
    bool anyExact = false;
    if (shouldSearch) {
      // Pass the tenant persona so it DRIVES the scores + populates each
      // scorecard's personaReasons (tag / deal-breaker matches). Routed through
      // the provider so the tenant's work coords add the commute dimension too.
      results = provider.recommendForTenant(provider.allProperties, _query,
          limit: 10);
      anyExact = results.any((r) => r.exact);
    }

    if (!mounted) return;
    _lastReply = sr.$1;
    _ChatMsg? howChoseMsg;
    _ChatMsg? resultsMsg;
    setState(() {
      _messages.add(_ChatMsg(role: 'assistant', text: sr.$1, chips: sr.$2));
      if (shouldSearch) {
        if (results.isEmpty) {
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'עוד לא צף לי משהו מדויק — ננסה אזור אחר או תקציב גמיש יותר?',
          ));
        } else {
          // Explain what the engine actually analysed/filtered/ranked before
          // showing the cards — turns the multi-dimensional math into a warm,
          // one-paragraph "here's what I checked and why these fit".
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: SearchNarrative.summarize(
                _query, provider.allProperties.length, results),
          ));
          // Transparency header: "how I chose these". Starts with a scorecard-
          // built fallback, then gets upgraded to the LLM's warm version below.
          howChoseMsg = _ChatMsg(
            role: 'assistant',
            text: _howIChoseFallback(results),
          );
          _messages.add(howChoseMsg!);
          resultsMsg = _ChatMsg(
            role: 'assistant',
            text: anyExact
                ? 'מצאתי ${results.length} דירות שמתאימות לך 🎯'
                : 'אלה הכי קרובות למה שחיפשת 👇',
            scored: results,
            chips: _refineChips(),
          );
          _messages.add(resultsMsg!);
        }
        _searched = true;
      }
      _busy = false;
    });
    _scrollToEnd();

    // Fetch the LLM's number-grounded explanations WITHOUT blocking the cards:
    // they're already on screen; this fills llmReason + the "how I chose" bubble
    // when (and if) it returns within a short timeout. Degrades to engine reasons.
    if (shouldSearch && results.isNotEmpty && resultsMsg != null) {
      _fetchExplanations(
        results: results,
        persona: _personaLabels(provider),
        howChoseMsg: howChoseMsg!,
        resultsMsg: resultsMsg!,
      );
    }

    if (shouldSearch && results.isNotEmpty) _maybeCapturePersona(results.length);
  }

  // Persona labels driving the ranking + sent to the explainer.
  List<String> _personaLabels(DatingProvider provider) {
    final p = provider.tenantProfile;
    if (p == null) return const [];
    return [...p.importantDetails, ...p.dealBreakers]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // Calls the (frozen) RecommendationExplainer over the engine's scorecards and
  // merges the result back in: per-property llmReason + the persona-level
  // "how I chose these" paragraph. Never blocks the UI; null result = no-op.
  Future<void> _fetchExplanations({
    required List<ScoredProperty> results,
    required List<String> persona,
    required _ChatMsg howChoseMsg,
    required _ChatMsg resultsMsg,
  }) async {
    // Index-align properties + cards (only entries that actually carry a card).
    final props = <RentalProperty>[];
    final cards = <Scorecard>[];
    final order = <ScoredProperty>[];
    for (final r in results) {
      final c = r.scorecard;
      if (c == null) continue;
      props.add(r.property);
      cards.add(c);
      order.add(r);
    }
    if (cards.isEmpty) return;

    RecommendationExplanation? exp;
    try {
      exp = await RecommendationExplainer.explain(
        properties: props,
        cards: cards,
        persona: persona,
        querySummary: _query.describe(),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      exp = null; // timeout / failure → keep the engine's own reasons
    }
    if (exp == null || !mounted) return;

    // Merge: rebuild each ScoredProperty with its scorecard.withLlmReason(...).
    final merged = <ScoredProperty>[];
    for (final r in results) {
      final c = r.scorecard;
      final reason = c == null ? null : exp.perProperty[r.property.id];
      merged.add(reason == null || reason.trim().isEmpty
          ? r
          : ScoredProperty(r.property, r.score, r.tags, r.trainKm, r.exact,
              c!.withLlmReason(reason)));
    }

    setState(() {
      resultsMsg.scored = merged;
      if (exp!.howIChose.trim().isNotEmpty) {
        howChoseMsg.text = exp.howIChose.trim();
      }
    });
  }

  // Engine-only fallback "how I chose these", built from the top scorecards when
  // the LLM is unavailable — still cites real data so the header stays honest.
  String _howIChoseFallback(List<ScoredProperty> results) {
    final cards = results
        .map((r) => r.scorecard)
        .whereType<Scorecard>()
        .toList();
    if (cards.isEmpty) {
      return 'דירגתי כל דירה לפי ציון רב-ממדי — תמורה למחיר, מיקום, '
          'קרבה לתחבורה ובטיחות — והצפתי את ההתאמות הטובות ביותר.';
    }
    // Which dimensions weighed most across the top picks?
    final weight = <String, double>{};
    final labels = <String, String>{};
    for (final c in cards.take(4)) {
      for (final d in c.dimensions) {
        weight[d.key] = (weight[d.key] ?? 0) + d.weightPct;
        labels[d.key] = d.label;
      }
    }
    final topDims = (weight.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => labels[e.key] ?? e.key)
        .toList();
    final best = cards.first;
    final sb = StringBuffer('כך בחרתי: שקללתי בעיקר ');
    sb.write(topDims.isEmpty ? 'תמורה למחיר ומיקום' : _joinHe(topDims));
    sb.write(' על בסיס נתוני אמת. ');
    if (best.personaReasons.isNotEmpty) {
      sb.write('התאמתי גם להעדפות שלך — ${best.personaReasons.first}. ');
    }
    sb.write('בראש הרשימה ${best.fitPct}% התאמה');
    if (best.tier.isNotEmpty) sb.write(' (${best.tier})');
    sb.write('. הקש "למה זו?" על כל דירה לפירוט המלא.');
    return sb.toString();
  }

  // Hebrew-friendly list join: "א, ב ו-ג".
  String _joinHe(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    final head = items.sublist(0, items.length - 1).join(', ');
    return '$head ו${items.last}';
  }

  // Warm conversational reply from server נועה (Gemini, tenant_search mode);
  // returns (replyText, quick-reply suggestions). Falls back to local copy if
  // the server is unavailable (the on-device search still works regardless).
  Future<(String, List<String>)> _serverReply() async {
    try {
      final history = _messages
          .where((m) => !m.isConsent && m.text.isNotEmpty && m.scored.isEmpty)
          .map((m) => AssistantTurn(role: m.role, text: m.text))
          .toList();
      final reply = await _service.chat(history, mode: 'tenant_search');
      final t = reply.reply.trim();
      if (t.isNotEmpty) return (t, reply.suggestions);
    } catch (_) {}
    return (_warmFallback(), const <String>[]);
  }

  int _warmIdx = 0;
  String _warmFallback() {
    const lines = [
      'כיף, נשמע שיש לך כיוון 🙌 ספר לי עוד קצת — אזור, תקציב, כמה חדרים?',
      'הבנתי אותך. מה הכי חשוב לך בדירה או בשכונה?',
      'אהבתי. רוצה שאראה לך כבר כמה אפשרויות, או שנחדד עוד קצת?',
    ];
    return lines[(_warmIdx++) % lines.length];
  }

  List<String> _refineChips() {
    final chips = <String>[];
    if (_query.maxPrice != null) {
      chips.add('עד ₪${(_query.maxPrice! * 0.85).round()}');
    }
    if (_query.minRooms != null) chips.add('${(_query.minRooms! + 1).toInt()} חדרים');
    if (!_query.amenities.contains('feat_parking')) chips.add('עם חניה');
    if (!_query.nearTrain) chips.add('קרוב לרכבת');
    if (!_query.amenities.contains('feat_elevator')) chips.add('עם מעלית');
    return chips.take(4).toList();
  }

  SearchQuery _merge(SearchQuery a, SearchQuery b) => SearchQuery(
        city: b.city ?? a.city,
        neighborhood: b.neighborhood ?? a.neighborhood,
        minPrice: b.minPrice ?? a.minPrice,
        maxPrice: b.maxPrice ?? a.maxPrice,
        minRooms: b.minRooms ?? a.minRooms,
        maxRooms: b.maxRooms ?? a.maxRooms,
        propertyType: b.propertyType ?? a.propertyType,
        amenities: {...a.amenities, ...b.amenities},
        nearTrain: a.nearTrain || b.nearTrain,
        cheapPreference: a.cheapPreference || b.cheapPreference,
        rawText: '${a.rawText} ${b.rawText}'.trim(),
      );

  // ── persona capture (consent-gated) ───────────────────────────────────────

  void _maybeCapturePersona(int resultCount) {
    final persona = <String, dynamic>{
      'source': 'ai_chat',
      'criteria': {
        'city': _query.city,
        'maxPrice': _query.maxPrice,
        'minRooms': _query.minRooms,
        'nearTrain': _query.nearTrain,
        'amenities': _query.amenities.toList(),
      },
      'persona': _persona,
      'persona_text': _personaSnippets.join(' • '),
      'result_count': resultCount,
    };

    if (_consent == true) {
      AppEvents.instance.log(UserEventType.searchPerformed, metadata: persona);
      return;
    }
    if (_consent == false || _consentAsked) return;

    _consentAsked = true;
    _pendingPersona = persona;
    setState(() {
      _messages.add(_ChatMsg(
        role: 'assistant',
        isConsent: true,
        text:
            'רוצה שאזכור את ההעדפות שלך כדי לדייק לך עוד יותר בפעם הבאה? '
            'הכל מאובטח, ותמיד אפשר לבטל. 💙',
      ));
    });
    _scrollToEnd();
  }

  Future<void> _resolveConsent(bool granted) async {
    setState(() {
      _consent = granted;
      _messages.removeWhere((m) => m.isConsent);
      _messages.add(_ChatMsg(
        role: 'assistant',
        text: granted
            ? 'מעולה, תודה! מבטיחה לשמור על זה 🙌'
            : 'אין בעיה בכלל, נמשיך ככה. 🙂',
      ));
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentPrefKey, granted);
    } catch (_) {}
    if (granted) {
      AppEvents.instance.log(UserEventType.consentGranted,
          metadata: {'scope': 'persona_dataset', 'source': 'search_chat'});
      if (_pendingPersona != null) {
        AppEvents.instance
            .log(UserEventType.searchPerformed, metadata: _pendingPersona);
        _pendingPersona = null;
      }
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8FB),
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0.5,
          titleSpacing: 0,
          title: Row(children: [
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child:
                  Icon(IconsaxPlusBold.magicpen, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_botName · העוזרת החכמה',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Row(children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Color(0xFF27AE60), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('כאן בשבילך',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ]),
              ],
            ),
          ]),
          actions: [
            IconButton(
              tooltip: 'שיחה חדשה',
              icon: Icon(Icons.refresh,
                  color: AppColors.textSecondary, size: 24),
              onPressed: _resetConversation,
            ),
          ],
        ),
        body: Column(children: [
          _criteriaBar(),
          Expanded(
            // Tap anywhere on the conversation to dismiss the keyboard.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView.builder(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) return const _Typing();
                  final isLast = i == _messages.length - 1;
                  final bubble = _bubble(_messages[i]);
                  return isLast ? _FadeSlideIn(child: bubble) : bubble;
                },
              ),
            ),
          ),
          _inputBar(),
        ]),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (m.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(14),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: isUser
                    ? null
                    : [
                        BoxShadow(
                            color: AppColors.navy.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
              ),
              child: Text(m.text,
                  style: TextStyle(
                      color: isUser
                          ? AppColors.textOnPrimary
                          : AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.45)),
            ),
          if (m.scored.isNotEmpty) _resultList(m),
          if (m.chips.isNotEmpty) _chipsRow(m.chips),
          if (m.isConsent) _consentButtons(),
        ],
      ),
    );
  }

  Widget _chipsRow(List<String> chips) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips
            .map((c) => GestureDetector(
                  onTap: _busy ? null : () => _send(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight2,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35)),
                    ),
                    child: Text(c,
                        style: TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _consentButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        ElevatedButton(
          onPressed: () => _resolveConsent(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('כן, בשמחה'),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: () => _resolveConsent(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: BorderSide(color: AppColors.borderLight),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('לא עכשיו'),
        ),
      ]),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      // Floating, rounded, detached ≥13px from every edge.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 6, 13, 13),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Send — on the right (first child in RTL).
              GestureDetector(
                onTap: () => _send(_input.text),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  child: Icon(IconsaxPlusLinear.send_1,
                      color: AppColors.textOnPrimary, size: 20),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 130),
                  // WhatsApp-style: grows with content, wraps lines.
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'ספר לי במילים שלך...',
                      isCollapsed: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Voice-conversation button → opens the big, clear visualizer.
              GestureDetector(
                onTap: _openVoice,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq,
                      color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Property card — mirrors the Messages-page (_MatchCard) design ─────────────
class _AssistantPropertyCard extends StatelessWidget {
  const _AssistantPropertyCard({required this.scored, required this.onTap});
  final ScoredProperty scored;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = scored.property;
    final width = MediaQuery.of(context).size.width * 0.82;
    final saved = context.watch<DatingProvider>().isSaved(p.id);
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.97,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1),
          boxShadow: [
            BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: AspectRatio(
                aspectRatio: 1.84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(fit: StackFit.expand, children: [
                    SafeMedia(
                      // prefer a video for the hero so the user can play it
                      // straight from the assistant preview (tap to play),
                      // without opening the 3D-tour flow.
                      media: p.media.any((m) => m.isVideo)
                          ? p.media.firstWhere((m) => m.isVideo)
                          : p.primaryMedia,
                      fallback: Container(
                        color: AppColors.primaryLight2,
                        child: Icon(IconsaxPlusLinear.building,
                            color: AppColors.primary, size: 48),
                      ),
                      fit: BoxFit.cover,
                      videoMode: SafeVideoDisplayMode.playback,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Text(p.propertyType,
                            style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                    ),
                    if (p.isVerifiedListing)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified,
                                size: 13, color: AppColors.success),
                            const SizedBox(width: 3),
                            const Text('מאומת',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy)),
                          ]),
                        ),
                      ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Row(children: [
                        _circleAction(
                          icon: saved ? Icons.favorite : Icons.favorite_border,
                          color: saved ? AppColors.coral : AppColors.navy,
                          onTap: () =>
                              context.read<DatingProvider>().toggleSave(p.id),
                        ),
                        const SizedBox(width: 8),
                        _circleAction(
                          icon: Icons.ios_share,
                          color: AppColors.navy,
                          onTap: () => showPropertyShareSheet(context, p),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.street.isNotEmpty
                                  ? '${p.street} ${p.streetNumber}'
                                  : p.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.neighborhood.isNotEmpty
                                  ? '${p.city}, ${p.neighborhood}'
                                  : p.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(p.priceLabel,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _InfoChip(
                          icon: IconsaxPlusLinear.home,
                          label: '${p.roomsLabel} חדרים'),
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: '${p.sizeM2} מ״ר'),
                      for (final t in scored.tags) ...[
                        const SizedBox(width: 8),
                        _InfoChip(label: t),
                      ],
                    ]),
                  ),
                  // Expandable transparency panel — the data-grounded "why this
                  // one" breakdown (dimensions + stats + persona + LLM reason).
                  if (scored.scorecard != null)
                    ScorecardView(card: scored.scorecard!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({this.icon, required this.label});
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AppColors.navy),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.navy)),
      ]),
    );
  }
}

// ── small animations ─────────────────────────────────────────────────────────
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            return Row(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 0; i < 3; i++) ...[
                _dot(i),
                if (i < 2) const SizedBox(width: 5),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _dot(int i) {
    final phase = (_c.value + i * 0.2) % 1.0;
    final scale = 0.6 + 0.6 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.7),
            shape: BoxShape.circle),
      ),
    );
  }
}

// ── Voice conversation visualizer ─────────────────────────────────────────────
// Big, calm, high-contrast full-screen voice mode — designed to be obvious for
// older users. One large pulsing orb that reacts to the voice; clear status text;
// tap the orb to talk, אתי listens, thinks, then answers out loud.
enum _VoiceState { idle, listening, thinking, speaking }

class _VoiceVisualizer extends StatefulWidget {
  const _VoiceVisualizer({required this.service, required this.onUtterance});
  final AssistantService service;
  final Future<String> Function(String transcript) onUtterance;

  @override
  State<_VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<_VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  _VoiceState _state = _VoiceState.idle;
  String _transcript = '';
  String _reply = 'שלום! אני אתי 👋\nלחצו על העיגול ופשוט דברו איתי.';
  double _level = 0; // 0..1 smoothed mic level
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat(reverse: true);

  @override
  void dispose() {
    widget.service.stopListening();
    widget.service.stopSpeaking();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _onOrbTap() async {
    if (_state == _VoiceState.listening) {
      await widget.service.stopListening();
      return;
    }
    if (_state == _VoiceState.thinking || _state == _VoiceState.speaking) return;
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _state = _VoiceState.listening;
      _transcript = '';
    });
    try {
      await widget.service.startListening(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() => _transcript = text);
          if (isFinal) _handleUtterance(text);
        },
        onSoundLevelChange: (lvl) {
          if (!mounted) return;
          // speech_to_text level is roughly -2..10; normalise to 0..1.
          final n = ((lvl + 2) / 12).clamp(0.0, 1.0);
          setState(() => _level = _level * 0.6 + n * 0.4);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.idle;
        _reply = 'לא הצלחתי להפעיל את המיקרופון. בדקו שאישרתם הרשאה.';
      });
    }
  }

  Future<void> _handleUtterance(String text) async {
    await widget.service.stopListening();
    if (text.trim().isEmpty) {
      if (mounted) setState(() => _state = _VoiceState.idle);
      return;
    }
    setState(() {
      _state = _VoiceState.thinking;
      _level = 0;
    });
    final reply = await widget.onUtterance(text);
    if (!mounted) return;
    setState(() {
      _reply = reply;
      _state = _VoiceState.speaking;
    });
    try {
      await widget.service.speak(reply);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _state = _VoiceState.idle);
  }

  ({String label, Color color}) get _statusInfo {
    switch (_state) {
      case _VoiceState.listening:
        return (label: 'מקשיבה לך...', color: AppColors.primary);
      case _VoiceState.thinking:
        return (label: 'רגע, חושבת...', color: AppColors.warning);
      case _VoiceState.speaking:
        return (label: 'אתי מדברת', color: AppColors.success);
      case _VoiceState.idle:
        return (label: 'לחצו על העיגול כדי לדבר', color: AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B2138), // calm deep navy
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              const Spacer(),
              // status
              Text(info.label,
                  style: TextStyle(
                      color: info.color,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 36),
              // the orb
              GestureDetector(
                onTap: _onOrbTap,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final base = _state == _VoiceState.listening
                        ? 0.5 + _level * 0.9
                        : (_state == _VoiceState.speaking ? 0.55 : 0.35);
                    final scale = 1.0 + base * (0.10 + 0.10 * _pulse.value);
                    final ring = 150.0 * scale;
                    return SizedBox(
                      width: 300,
                      height: 300,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: ring + 70,
                              height: ring + 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: info.color.withValues(alpha: 0.10),
                              ),
                            ),
                            Container(
                              width: ring,
                              height: ring,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    info.color,
                                    info.color.withValues(alpha: 0.6)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                      color: info.color.withValues(alpha: 0.45),
                                      blurRadius: 40,
                                      spreadRadius: 6),
                                ],
                              ),
                              child: Icon(
                                _state == _VoiceState.speaking
                                    ? Icons.volume_up_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 64,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              // transcript / reply
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  _state == _VoiceState.listening && _transcript.isNotEmpty
                      ? _transcript
                      : _reply,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 19, height: 1.5),
                ),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('סגרו כדי לחזור לצ׳אט ולראות את הדירות',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
