import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/core/search/engine/search_narrative.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/lifestyle_knowledge.dart';
import 'package:dating_app/data/models/persona_profile.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/recommendation_explainer.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/repositories/property_search_repository.dart';
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/presentation/features/search/ati_voice_screen.dart';
import 'package:dating_app/presentation/widgets/why_details.dart';
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
    this.locationRequest = false,
  });
  final String role; // 'user' | 'assistant'
  String text; // mutable: the "how I chose" bubble is upgraded once the LLM returns
  List<ScoredProperty> scored; // mutable: scorecards get llmReason merged in async
  final List<String> chips;
  final bool isConsent;
  final bool locationRequest; // אתי asking to share GPS → renders a location button
  bool expanded = false; // "show more" toggle for result lists
}

class _SearchChatScreenState extends State<SearchChatScreen> {
  static const _consentPrefKey = 'dataset_persona_consent_v1';

  final _service = AssistantService();
  final _repo = PropertySearchRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMsg> _messages = [];
  final List<String> _personaSnippets = [];
  final Map<String, String> _persona = {}; // household / vibe / timing ...
  SearchQuery _query = SearchQuery();

  int _userTurns = 0;
  bool _searched = false;
  bool _busy = false;
  bool _lifestyleNoteShown = false; // show the "considered your lifestyle" note once
  bool _lastShowedResults = false; // did the last _send render listing cards
  String _lastReply = ''; // last assistant text, for the voice visualizer to speak
  // Voice-only: אתי asks permission before presenting apartments. True once she's
  // gathered enough and is waiting for the user's "כן" to actually show them.
  bool _voiceAwaitingConsent = false;
  bool _voiceConsented = false; // user already said yes → show results directly
  List<ScoredProperty> _voicePending = const []; // held results to reveal on "כן"
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
    _seedFromPersona();
  }

  /// Personalise for a returning user: pre-fill what we already know with high
  /// confidence (religiosity + query defaults they haven't restated). Anything
  /// they type this session overrides it via [_merge], so this only helps.
  void _seedFromPersona() {
    final p = context.read<DatingProvider>().personaProfile;
    final now = DateTime.now();
    final rel = p.value('religiosity', now: now) as String?;
    if (rel != null) _persona['religiosity'] = rel;
    if (p.value('baby', now: now) == true) _persona['baby'] = 'true';
    _query = _merge(
      _query,
      SearchQuery(
        city: p.value('city', now: now) as String?,
        maxPrice: (p.value('maxBudget', now: now) as num?)?.toInt(),
        minRooms: (p.value('minRooms', now: now) as num?)?.toDouble(),
      ),
    );
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

  Future<void> _rerunSearch() async {
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
    final results =
        _rankByLifestyle(_applyLifestyleFilter(await _cohortRanked(provider, limit: 10)))
            .take(10)
            .toList();
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMsg(
        role: 'assistant',
        text: results.isEmpty
            ? 'אחרי העדכון לא נשארו התאמות. אפשר להוסיף משהו אחר?'
            : 'עדכנתי לפי השינוי 👇',
        scored: results,
        chips: results.isEmpty ? const [] : _refinePromptChips(),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chat = the clean Messages-page card design.
              _AssistantPropertyCard(
                scored: m.scored[i],
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        PropertyDetailScreen(property: m.scored[i].property))),
              ),
              // …with the detailed, personal "why I picked this for you".
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82),
                child: WhyDetails(scored: m.scored[i]),
              ),
            ],
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
    for (final t in _streamTimers) {
      t.cancel();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  final List<Timer> _streamTimers = [];

  // Streaming reveal: flows `full` into `msg.text` word-by-word (a gentle "she's
  // typing/talking" effect) instead of the text popping in all at once.
  void _streamText(_ChatMsg msg, String full) {
    final tokens = full.split(RegExp(r'(?<= )'));
    if (tokens.length <= 1) {
      setState(() => msg.text = full);
      return;
    }
    int shown = 0;
    late final Timer t;
    t = Timer.periodic(const Duration(milliseconds: 38), (_) {
      if (!mounted) {
        t.cancel();
        return;
      }
      shown++;
      setState(() =>
          msg.text = shown >= tokens.length ? full : tokens.take(shown).join());
      _scrollToEnd();
      if (shown >= tokens.length) {
        t.cancel();
        _streamTimers.remove(t);
      }
    });
    _streamTimers.add(t);
  }

  // Opens אתי's voice conversation. Opens the reliable turn-based liquid-glass
  // screen IMMEDIATELY (never block the tap on a network handshake). The realtime
  // streaming session is an in-screen upgrade, tried opportunistically — it must
  // never gate whether the screen appears.
  Future<void> _openVoice() async {
    FocusScope.of(context).unfocus();
    _voiceAwaitingConsent = false; // fresh voice session — no pending confirmation
    _voiceConsented = false;
    _voicePending = const [];
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AtiVoiceScreen(
        service: _service,
        onUtterance: _processVoiceUtterance,
        criteria: _voiceCriteria(),
        resultCount: _lastResultCount,
      ),
    ));
    _scrollToEnd();
  }

  // Runs a `search_listings` tool-call from the live voice agent: builds the query
  // from its args, runs the same cohort search as typed input, drops the cards
  // into the chat, and returns a short spoken summary + the results for אתי.
  // ignore: unused_element  (ready for the realtime in-screen upgrade)
  Future<({List<ScoredProperty> results, String summary})> _handleRealtimeSearch(
      Map<String, dynamic> args) async {
    final provider = context.read<DatingProvider>();
    // Amenities: accept both the legacy `amenities` and the new `features` (feat_*)
    // the tool now emits.
    final amenities = <String>{
      for (final e in ((args['amenities'] as List?) ?? const []))
        'feat_${e.toString().trim()}',
      for (final e in ((args['features'] as List?) ?? const []))
        e.toString().trim().startsWith('feat_')
            ? e.toString().trim()
            : 'feat_${e.toString().trim()}',
    }.where((s) => s.length > 5).toSet();
    // Carry the user's own words into rawText so the intent detectors still fire
    // as a fallback if the model didn't fill `intents` explicitly.
    final rawText = [
      args['city'],
      args['lifestyle'],
      args['notes'],
      args['query'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    // Intent CONTRACT: prefer what the assistant explicitly distilled (args.intents),
    // unioned with the text-derived fallback — a single structured set the engine
    // consumes (see SearchIntent + preference_model).
    final intents = <String>{
      ...SearchIntent.fromText(rawText),
      for (final e in ((args['intents'] as List?) ?? const []))
        e.toString().trim(),
    }..removeWhere((s) => s.isEmpty);
    final txType = switch ((args['transactionType'] as String?)?.toLowerCase()) {
      'sale' => TransactionTypeFilter.sale,
      'rent' => TransactionTypeFilter.rent,
      _ => TransactionTypeFilter.any,
    };
    // THE BRAIN: the importances the assistant assigned → drive the ranking math.
    final llmWeights = <String, double>{};
    final w = args['weights'];
    if (w is Map) {
      w.forEach((k, v) {
        final d = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (d != null) llmWeights[k.toString()] = d.clamp(0.0, 1.0);
      });
    }
    _query = _merge(
      _query,
      SearchQuery(
        city: args['city'] as String?,
        minRooms: (args['minRooms'] as num?)?.toDouble(),
        maxRooms: (args['maxRooms'] as num?)?.toDouble(),
        maxPrice: (args['maxPrice'] as num?)?.toInt(),
        amenities: amenities,
        transactionType: txType,
        rawText: rawText,
        intents: intents,
        weights: llmWeights,
      ),
    );
    final life = (args['lifestyle'] as String?)?.toLowerCase() ?? '';
    final rel = LifestyleKnowledge.detectReligiosity(life);
    if (rel != null) _persona['religiosity'] = rel.name;

    var results = _rankByLifestyle(
            _applyLifestyleFilter(await _cohortRanked(provider, limit: 40)))
        .take(10)
        .toList();
    if (mounted) {
      setState(() {
        _searched = true;
        if (results.isNotEmpty) {
          _messages.add(_ChatMsg(
              role: 'assistant',
              text: 'הנה כמה דירות שמתאימות למה שסיפרת 👇',
              scored: results,
              chips: _refinePromptChips()));
        }
      });
      _scrollToEnd();
    }
    final summary = results.isEmpty
        ? 'לא מצאתי דירה מדויקת, אפשר להרחיב אזור או תקציב?'
        : 'מצאתי ${results.length} דירות שמתאימות, הן מופיעות עכשיו על המסך';
    return (results: results, summary: summary);
  }

  // Understood-criteria chips for the voice screen (mirrors the chat criteria bar).
  List<String> _voiceCriteria() {
    final q = _query;
    final out = <String>[];
    if (q.city != null && q.city!.trim().isNotEmpty) out.add(q.city!.trim());
    if (q.neighborhood != null && q.neighborhood!.trim().isNotEmpty) {
      out.add(q.neighborhood!.trim());
    }
    if (q.minRooms != null) {
      final r = q.minRooms!;
      final label = r == r.roundToDouble() ? r.toInt().toString() : r.toString();
      out.add('$label חדרים');
    }
    if (q.maxPrice != null) {
      final p = q.maxPrice!.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
      out.add('עד $p ₪');
    }
    for (final a in q.amenities) {
      out.add(SmartSearch.amenityTag(a));
    }
    if (q.nearTrain) out.add('🚉 ליד הרכבת');
    return out;
  }

  // Count of listings אתי last surfaced (drives the voice screen's results peek).
  int get _lastResultCount {
    for (final m in _messages.reversed) {
      if (m.scored.isNotEmpty) return m.scored.length;
    }
    return 0;
  }

  // Runs a spoken sentence through the same pipeline as typed input; returns
  // אתי's reply text (for the visualizer to read aloud) + whether listing cards
  // were rendered (so the visualizer can close and reveal them inline).
  Future<({String reply, bool showResults, List<ScoredProperty> results})>
      _processVoiceUtterance(String transcript) async {
    final t = transcript.trim();
    final wantsNow = _wantsResultsNow(t);

    // Waiting for the user's go-ahead to present apartments? DEFAULT TO SHOWING —
    // after "רוצה שאראה לך?", almost any reply ("כן"/"תציג"/"בטח"/"נו"/"בוא") means
    // yes. Only a clear NO or a reply that adds new criteria holds them back. (The
    // old code whitelisted specific words and missed "תציג" → it re-asked forever.)
    if (_voiceAwaitingConsent) {
      _voiceAwaitingConsent = false;
      final holdsBack = _isNegative(t) || _looksLikeCriteria(t);
      if (!holdsBack) {
        _voiceConsented = true;
        final r = _voicePending.isNotEmpty ? _voicePending : _latestScored;
        return (
          reply: r.isEmpty
              ? 'רגע, בוא נחדד עוד קצת ואמצא לך את המתאימות'
              : 'מעולה! הנה מה שמצאתי בשבילך 👇',
          showResults: r.isNotEmpty,
          results: r,
        );
      }
      // A "no" or added criteria → fold it in below (re-search, then re-offer).
    }

    // Voice "באזור שלי / קרוב אליי" → capture GPS ourselves (the spoken request IS
    // the consent; the OS prompt gates the first time) and fold the city in, so we
    // actually search — instead of raising a chat button the voice user can't tap.
    if (_locationRelative.hasMatch(t) && _query.city == null) {
      final city = await _captureGps();
      if (city != null && city.isNotEmpty && mounted) {
        _query = _merge(_query, SearchQuery(city: city));
      } else {
        // GPS / permission unavailable → don't search blindly with no city; ASK.
        return (
          reply: 'לא הצלחתי לזהות איפה את/ה 📍 באיזו עיר לחפש?',
          showResults: false,
          results: const <ScoredProperty>[],
        );
      }
    }

    await _send(transcript, enrich: false); // voice: skip the slow enrich round-trip

    // Voice etiquette: don't dump apartments unasked. The FIRST time אתי has enough
    // to search, she ASKS — unless the user already consented or said "תראה לי".
    if (_lastShowedResults &&
        _latestScored.isNotEmpty &&
        !wantsNow &&
        !_voiceConsented) {
      _voiceAwaitingConsent = true;
      _voicePending = _latestScored; // hold them so "כן" reveals exactly these
      return (
        reply: 'מצאתי כמה אפשרויות שמתאימות למה שתיארת. '
            'רוצה שאראה לך אותן עכשיו, או שנוסיף עוד משהו? 🙂',
        showResults: false,
        results: const <ScoredProperty>[],
      );
    }

    // Explicit "show me" or a refinement AFTER consent → SHOW whatever she found;
    // never suppress (this was the "she said she's showing but didn't" bug).
    if (wantsNow) _voiceConsented = true;
    return (
      reply: _lastReply.isEmpty
          ? 'ספר לי עוד קצת על מה שאתה מחפש'
          : _lastReply,
      showResults: _lastShowedResults,
      results: _lastShowedResults ? _latestScored : const <ScoredProperty>[],
    );
  }

  // Voice affirmatives ("כן / בטח / יאללה…"). NB: Hebrew has no \b word boundary,
  // so single words are matched against a SPACE-PADDED input to avoid false hits
  // inside longer words (לכן / תוכן) while still catching a bare "כן".
  static final _affirmative = RegExp(
      r'\s(?:כן|בטח|בהחלט|יאללה|יאלה|קדימה|סבבה|אוקיי|אוקי|בסדר|נכון|וודאי|בטוח|בבקשה|נו)\s'
      r'|נשמע טוב|למה לא|תראי לי|תראה לי|בוא נראה|בואי נראה|קדימה נראה'
      r'|yes|okay|\bok\b|sure|go ahead',
      caseSensitive: false);
  bool _isAffirmative(String t) => _affirmative.hasMatch(' ${t.trim()} ');

  // A clear "no / not yet / wait" — hold the apartments back.
  static final _negative = RegExp(
      r'\s(?:לא|רגע|חכה|חכי|המתן|עצור)\s|עוד לא|לא עדיין|not yet|\bwait\b',
      caseSensitive: false);
  bool _isNegative(String t) => _negative.hasMatch(' ${t.trim()} ');

  // The reply ADDS search criteria (a number, or a place/feature word) rather than
  // just answering the yes/no — so we refine instead of revealing.
  static final _criteriaCue = RegExp(
      r'חדר|מרפסת|מעלית|ממ"?ד|חני|קומה|זול|יקר|גדול|קטן|מרוה|מרוו|נגיש|כלב|חתול|'
      r'קרוב|ליד|שקט|מרכז|תוסיף|תוסיפי|בנוסף|עוד|גם|באזור|בשכונ|בעיר|למכיר|להשקע|תקציב');
  bool _looksLikeCriteria(String t) =>
      RegExp(r'\d').hasMatch(t) || _criteriaCue.hasMatch(t);

  // The most recent listing cards אתי surfaced — shown inline in the voice screen.
  List<ScoredProperty> get _latestScored {
    for (final m in _messages.reversed) {
      if (m.scored.isNotEmpty) return m.scored;
    }
    return const [];
  }

  // ── conversation ──────────────────────────────────────────────────────────

  // Explicit "show me now" intent only — must NOT match the common word
  // "מחפש" (which contains "חפש"), so נועה still asks her refining question first.
  bool _wantsResultsNow(String t) => RegExp(
        r'תראה לי|תראי לי|הצג|בוא נראה|בואי נראה|תמצא לי|תמצאי לי|show me',
      ).hasMatch(t);

  // Deictic "here" → resolve the device GPS to a city via on-device geocoding
  // (NOT the LLM) and fold it into the query. Fail-soft: no permission / no fix
  // → we simply don't set a location and the normal flow continues.
  // True whenever the user refers to their own location ("פה" / "באזור שלי" /
  // "קרוב אליי" / "my area"…) — the cue to capture GPS instead of asking.
  static final _locationRelative = RegExp(
      r'\bפה\b|\bכאן\b|באזור הזה|באיזור הזה|בסביבה הזו|בסביבה שלי|ליד(?:י| שלי| הבית)?|'
      r'אזור שלי|איזור שלי|באזור שלי|באיזור שלי|האזור שלי|קרוב אלי|קרוב אליי|אצלי|'
      r'near me|around here|\bhere\b|my area|in my area|close to me|nearby');

  // The USER tapped "share my location" on אתי's request → NOW capture the GPS
  // (the OS permission prompt is the approval), set the city, and search. This is
  // the only place that reads location, and only after an explicit user tap.
  Future<void> _shareLocationNow() async {
    setState(() {
      _messages.removeWhere((m) => m.locationRequest);
      _busy = true;
    });
    final city = await _captureGps();
    if (!mounted) return;
    if (city == null) {
      setState(() {
        _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'לא הצלחתי לזהות מיקום כרגע 🙈 אפשר פשוט להגיד לי באיזו עיר לחפש?'));
        _busy = false;
      });
      _scrollToEnd();
      return;
    }
    _query = _merge(_query, SearchQuery(city: city));
    setState(() => _messages.add(_ChatMsg(
        role: 'assistant',
        text: '📍 מצאתי אותך — את/ה ב$city. מחפשת שם עכשיו את מה שהכי מתאים 👇')));
    final provider = context.read<DatingProvider>();
    var results = _rankByLifestyle(
            _applyLifestyleFilter(await _cohortRanked(provider, limit: 40)))
        .take(10)
        .toList();
    if (!mounted) return;
    setState(() {
      _searched = true;
      _busy = false;
      if (results.isEmpty) {
        _messages.add(_ChatMsg(
            role: 'assistant',
            text:
                'לא צפו כרגע התאמות מדויקות באזור שלך — נרחיב תקציב או אזור?'));
      } else {
        _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'הנה מה שהכי מתאים לך באזור שלך 👇',
            scored: results,
            chips: _refinePromptChips()));
      }
    });
    _scrollToEnd();
  }

  // Raw GPS capture → resolved city name (null if unavailable / denied). The OS
  // permission dialog IS the user's approval.
  Future<String?> _captureGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      // PRIMARY: resolve the city from the on-device CBS locality index. This is
      // reliable and IDENTICAL on iOS/Android — unlike the platform reverse-
      // geocoder (`placemarkFromCoordinates`), whose Android Geocoder needs Google
      // Play Services + network and frequently returns nothing (why "my area"
      // silently failed on Android).
      final loc = GovData.instance.nearestLocality(pos.latitude, pos.longitude);
      if (loc != null && loc.name.trim().isNotEmpty) return loc.name.trim();
      // FALLBACK: platform reverse-geocoding (dependable on iOS).
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude)
                .timeout(const Duration(seconds: 5));
        for (final m in marks) {
          final c = (m.locality?.trim().isNotEmpty == true)
              ? m.locality!.trim()
              : (m.subLocality?.trim().isNotEmpty == true)
                  ? m.subLocality!.trim()
                  : m.subAdministrativeArea?.trim();
          if (c != null && c.isNotEmpty) return c;
        }
      } catch (_) {/* geocoder flaky on Android → GovData already tried */}
      return null;
    } catch (_) {
      return null; // location unavailable → fall back to asking
    }
  }

  // Calls the Etti extraction engine and folds its plan into _query. The
  // deterministic _query is passed as the fallback so explicit numbers survive.
  Future<void> _ettiEnrich(String text) async {
    try {
      final resp = await AwsApiClient.instance
          .post('/assistant/extract', {'query': text}).timeout(
        const Duration(seconds: 4),
      );
      final plan = EttiPlan.fromJson(resp);
      if (!plan.isEmpty) _query = plan.toQuery(fallback: _query);
    } catch (_) {
      // graceful — the on-device SmartSearch query already stands
    }
  }

  // [enrich] runs the extra backend LLM extraction. Voice passes false — the
  // on-device SmartSearch (city via CBS data + budget/rooms/features + the
  // transaction & required-feature inference rules) is enough, and dropping the
  // second network round-trip makes אתי answer MUCH faster (she was too slow).
  Future<void> _send(String raw, {bool enrich = true}) async {
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

    // If the user referred to their own area ("אזור שלי" / "פה"), אתי will RAISE a
    // location request instead of a warm reply (see below).
    final maybeLoc = _locationRelative.hasMatch(text);

    // Deterministic base: SmartSearch parses explicit fields instantly on-device
    // (city / budget / rooms / features) — the fallback Etti folds over.
    _query = _merge(_query, SmartSearch.parse(text));

    // Fold lifestyle signals from the whole conversation into the query (e.g.
    // "דתי לאומי" / "תינוק" → an elevator matters). See _applyLifestyle.
    _applyLifestyle(text);

    // ETTI (the LLM brain): read between the lines → hard_constraints + weighted
    // soft preferences, folded over the deterministic parse. Skipped in voice for
    // speed (the on-device parse already covers city/budget/rooms/features/intent).
    if (enrich) await _ettiEnrich(text);

    // Location needed but unknown → אתי RAISES a GPS request (a button). The user
    // approves, then the app captures the location and searches. אתי never grabs
    // GPS silently herself.
    if (maybeLoc && _query.city == null) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMsg(
          role: 'assistant',
          text: 'כדי למצוא לך דירות באזור שלך, אני רק צריכה לזהות איפה את/ה 📍\nלשתף את המיקום?',
          locationRequest: true,
        ));
        _busy = false;
      });
      _scrollToEnd();
      return;
    }

    final shouldSearch = !_query.isEmpty &&
        (_searched || _wantsResultsNow(text) || _userTurns >= 2);

    // SPEED: run the warm reply (GPT) and the cohort search IN PARALLEL — the user
    // waits for the slower of the two, not their sum.
    final replyFuture = _serverReply();
    final searchFuture =
        shouldSearch ? _cohortRanked(provider, limit: 40) : null;

    final sr = await replyFuture;
    List<ScoredProperty> results = const [];
    bool anyExact = false;
    if (searchFuture != null) {
      // Drop lifestyle-incompatible listings (high floor w/o elevator), top 10.
      results = _rankByLifestyle(_applyLifestyleFilter(await searchFuture))
          .take(10)
          .toList();
      anyExact = results.any((r) => r.exact);
    }

    // Auto-widen: nothing matched → progressively relax (budget → drop
    // amenities/rooms → drop city) so אתי shows the closest options, not "אין".
    String? widenNote;
    if (shouldSearch && results.isEmpty) {
      for (final step in _wideningLadder(_query)) {
        final r = _rankByLifestyle(_applyLifestyleFilter(
                await _cohortRanked(provider, limit: 40, query: step.q)))
            .take(10)
            .toList();
        if (r.isNotEmpty) {
          results = r;
          widenNote = step.note;
          break;
        }
      }
    }

    if (!mounted) return;
    _lastReply = sr.$1;
    _ChatMsg? howChoseMsg;
    _ChatMsg? resultsMsg;
    final lifestyleNote = _lifestyleNoteShown ? null : _lifestyleNote();
    final clarify = shouldSearch ? null : _clarifyingPrompt();
    // Streaming reveal: add the reply with empty text, then flow the words in.
    final replyMsg = sr.$1.isNotEmpty
        ? _ChatMsg(role: 'assistant', text: '', chips: sr.$2)
        : null;
    setState(() {
      // When GPS located the user, the "📍 מצאתי אותך" message is the reply — no
      // empty/contradictory bubble.
      if (replyMsg != null) _messages.add(replyMsg);
      if (shouldSearch) {
        if (results.isEmpty) {
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'עוד לא צף לי משהו מדויק — ננסה אזור אחר או תקציב גמיש יותר?',
          ));
        } else {
          if (widenNote != null) {
            _messages.add(_ChatMsg(role: 'assistant', text: '$widenNote 👇'));
          }
          // Let the user know a lifestyle constraint shaped the results.
          if (lifestyleNote != null) {
            _lifestyleNoteShown = true;
            _messages.add(_ChatMsg(role: 'assistant', text: lifestyleNote));
          }
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
            chips: _refinePromptChips(),
          );
          _messages.add(resultsMsg!);
        }
        _searched = true;
      } else if (clarify != null && !sr.$1.contains('?')) {
        // Not enough to search yet → Etty proactively asks the single most
        // useful missing detail (with quick-reply chips) instead of stalling.
        _messages.add(_ChatMsg(
            role: 'assistant', text: clarify.$1, chips: clarify.$2));
      }
      _busy = false;
    });
    if (replyMsg != null) _streamText(replyMsg, sr.$1);
    _scrollToEnd();

    // Fetch the LLM's number-grounded explanations WITHOUT blocking the cards:
    // they're already on screen; this fills llmReason + the "how I chose" bubble
    // when (and if) it returns within a short timeout. Degrades to engine reasons.
    _lastShowedResults = shouldSearch && results.isNotEmpty;
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
    // NATURAL LANGUAGE FIRST: אתי always speaks via the model (warm, natural,
    // multilingual). The local template is ONLY a graceful fallback if the model
    // is unreachable — never the primary voice. (Token savings come from the
    // server's prompt-caching + short outputs, NOT from replacing her language.)
    try {
      final history = _messages
          .where((m) => !m.isConsent && m.text.isNotEmpty && m.scored.isEmpty)
          .map((m) => AssistantTurn(role: m.role, text: m.text))
          .toList();
      final reply = await _service.chat(history, mode: 'tenant_search');
      final t = reply.reply.trim();
      if (t.isNotEmpty) return (t, reply.suggestions);
    } catch (_) {}
    return (_localReply() ?? _warmFallback(), const <String>[]);
  }

  static final _hebrew = RegExp(r'[֐-׿]');
  int _openerIdx = 0;

  // Warm, persona-aware reply built with NO LLM call. Returns null when the input
  // is non-Hebrew or too vague — those go to GPT (correct language / real nuance).
  String? _localReply() {
    final lastUser = _messages.lastWhere((m) => m.role == 'user',
        orElse: () => _ChatMsg(role: 'user'));
    final text = lastUser.text;
    if (text.isEmpty || !_hebrew.hasMatch(text)) return null; // → GPT (language)

    final q = _query;
    final hasCriteria = q.city != null ||
        q.maxPrice != null ||
        q.minRooms != null ||
        q.amenities.isNotEmpty ||
        q.nearTrain;
    if (!hasCriteria) return null; // greeting / ambiguous → GPT

    final parts = <String>[];
    if (q.minRooms != null) {
      final r = q.minRooms!;
      parts.add('${r == r.roundToDouble() ? r.toInt() : r} חדרים');
    }
    if (q.city != null && q.city!.trim().isNotEmpty) parts.add('ב${q.city!.trim()}');
    if (q.maxPrice != null) {
      final p = q.maxPrice!.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
      parts.add('עד $p ₪');
    }
    final summary = parts.join(' ');

    const openers = ['הבנתי 😊', 'מעולה, קלטתי', 'אחלה, הבנתי', 'סבבה, הבנתי'];
    final opener = openers[(_openerIdx++) % openers.length];

    // Enough to search (city + budget or rooms) → reflect + go straight to results.
    final enough = q.city != null && (q.maxPrice != null || q.minRooms != null);
    if (enough || _searched || _userTurns >= 2) {
      return summary.isEmpty
          ? '$opener. בודקת מה הכי מתאים לך 👇'
          : '$opener — $summary. בודקת מה הכי מתאים לך 👇';
    }
    // Otherwise ask ONE persona-appropriate follow-up (still no LLM).
    final follow = _cohortFollowup();
    return summary.isEmpty ? '$opener. $follow' : '$opener — $summary. $follow';
  }

  // A warm follow-up question tuned to the detected persona — a fixed, reused
  // library (no tokens).
  String _cohortFollowup() {
    final s = SmartSearch.cohortSignals(_conversationText);
    if (s['household'] == 'family' || _persona['baby'] == 'true') {
      return 'מה הכי חשוב לכם — קרבה לגנים ובתי ספר, ממ״ד, או שקט?';
    }
    if (s['lifeStage'] == 'student' || s['household'] == 'student') {
      return 'מעדיפ/ה דירת שותפים או משהו לבד? וכמה קריטית הקרבה לאוניברסיטה?';
    }
    if (s['isInvestor'] == 'true') {
      return 'זו השקעה לשכירות או לקנייה? ומה הכי חשוב לך בתשואה?';
    }
    if (s['lifeStage'] == 'senior' || s['accessibilityNeed'] == 'true') {
      return 'חשוב מעלית וקומה נמוכה? וקרבה לשירותי בריאות?';
    }
    if (s['wfh'] == 'true') return 'צריך חדר עבודה נפרד ושקט? ואינטרנט מהיר?';
    if (_persona['religiosity'] != null || s['isReligious'] == 'true') {
      return 'חשוב לכם קרבה לבית כנסת ולמוסדות שמתאימים לכם?';
    }
    return 'מה עוד חשוב לך — אווירת שכונה, קומה, או משהו ספציפי בדירה?';
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

  // Concrete refinement suggestions — shown only AFTER the user opts to refine.
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

  // Gentle refine prompt shown WITH the results (instead of dumping the options)
  // so אתי isn't naggy — she just offers to refine, and only asks the next
  // question if the user says yes.
  static const _kRefineYes = '✨ כן, בוא נדייק';
  static const _kRefineNo = 'זה מצוין, תודה';
  List<String> _refinePromptChips() =>
      _refineChips().isEmpty ? const [] : const [_kRefineYes, _kRefineNo];

  // Routes a quick-reply chip: the refine prompt is handled locally (no LLM),
  // everything else goes through the normal turn.
  void _onChipTap(String c) {
    if (_busy) return;
    if (c == _kRefineYes) {
      setState(() => _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'מעולה 😊 מה נדייק כדי לצמצם למה שהכי מתאים לך?',
            chips: _refineChips(),
          )));
      _scrollToEnd();
      return;
    }
    if (c == _kRefineNo) {
      setState(() => _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'מקסים! 🙏 אם תרצה לחדד עוד משהו בהמשך — אני כאן.',
          )));
      _scrollToEnd();
      return;
    }
    _send(c);
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
        transactionType: b.transactionType != TransactionTypeFilter.any
            ? b.transactionType
            : a.transactionType,
        rawText: '${a.rawText} ${b.rawText}'.trim(),
        intents: {...a.intents, ...b.intents},
        weights: {...a.weights, ...b.weights}, // latest turn's importances win
        requiredFeatures: {...a.requiredFeatures, ...b.requiredFeatures},
      );

  // ── Lifestyle inference ────────────────────────────────────────────────────
  // Reads plain-language lifestyle cues from the message and remembers them in
  // _persona: the tenant's religiosity (secular / traditional / religious /
  // haredi) and whether they have a baby. Religiosity drives an area re-rank
  // (see _rankByLifestyle) so we actually surface neighbourhoods that fit; a
  // baby / Shabbat-observance additionally makes an elevator important, so we
  // fold it into the query and hard-drop high floors without a lift.
  void _applyLifestyle(String text) {
    final rel = LifestyleKnowledge.detectReligiosity(text);
    if (rel != null) _persona['religiosity'] = rel.name;
    final baby = RegExp(r'תינוק|תינוקת|עגל[הת]|פעוט|רך\s*נולד|עולל')
        .hasMatch(text);
    if (baby) _persona['baby'] = 'true';
    if (_needsElevator) {
      _query = _merge(_query, SearchQuery(amenities: {'feat_elevator'}));
    }
  }

  // The whole conversation, user turns only — the corpus we mine for cohort signals.
  String get _conversationText =>
      _messages.where((m) => m.role == 'user').map((m) => m.text).join(' ');

  // Persona/cohort signals for the backend engine: keyword scan of the whole
  // conversation, enriched with what the lifestyle layer already inferred.
  Map<String, String> _cohortSignals() {
    final s = SmartSearch.cohortSignals(_conversationText);
    final rel = _persona['religiosity'];
    if (rel == Religiosity.haredi.name) {
      s['religiousStream'] = 'charedi';
      s['isReligious'] = 'true';
    } else if (rel == Religiosity.religious.name) {
      s['religiousStream'] ??= 'dati_leumi';
      s['isReligious'] = 'true';
    } else if (rel == Religiosity.traditional.name) {
      s['isReligious'] = 'true';
    }
    if (_persona['baby'] == 'true') {
      s['hasChildren'] = 'true';
      s.putIfAbsent('childAge', () => '1');
    }
    return s;
  }

  // Cohort-aware ranking: routes candidates through the BACKEND 14-cohort engine
  // (PropertySearchRepository → resolveCohort/attachRankSignals) using the persona
  // signals mined from the conversation, then decorates the backend's cohort-ordered
  // candidates with the on-device scorecards for the cards — preserving server order.
  // Falls back to the pure on-device engine when the backend is unreachable /
  // unauthenticated (debug/guest) or returns nothing, so behaviour never regresses.
  // ponytail: community_fit/neighborhood_fit stay neutral until listings are
  // re-enriched server-side; pre-backfill the win is cohort weighting + price target.
  Future<List<ScoredProperty>> _cohortRanked(DatingProvider provider,
      {int limit = 40, SearchQuery? query}) async {
    final q = query ?? _query;
    final signals = _cohortSignals();
    final criteria = PropertySearchCriteria(
      city: q.city,
      minPrice: q.minPrice,
      maxPrice: q.maxPrice,
      minRooms: q.minRooms,
      amenityKeys: q.amenities,
      vibe: signals['vibe'],
      queryText: _conversationText,
      cohortSignals: signals,
    );
    List<RentalProperty> serverRanked = const [];
    try {
      serverRanked = await _repo.search(criteria, limit: limit < 60 ? 60 : limit);
    } catch (_) {}

    if (serverRanked.isEmpty) {
      return provider.recommendForTenant(provider.allProperties, q,
          limit: limit);
    }
    final scored = provider.recommendForTenant(serverRanked, q,
        limit: serverRanked.length);
    final byId = {for (final s in scored) s.property.id: s};
    final out = <ScoredProperty>[];
    for (final p in serverRanked) {
      final s = byId[p.id];
      if (s != null) out.add(s);
      if (out.length >= limit) break;
    }
    return out.isNotEmpty
        ? out
        : provider.recommendForTenant(provider.allProperties, q, limit: limit);
  }

  // Progressive relaxation for when nothing matches: widen budget, then drop soft
  // amenities + room floor, then (last resort) drop the city. So אתי always has
  // something close to show instead of dead-ending.
  List<({SearchQuery q, String note})> _wideningLadder(SearchQuery q) {
    final budget = q.maxPrice;
    final up = (double f) => budget == null ? null : (budget * f).round();
    return [
      (
        q: SearchQuery(
            city: q.city,
            neighborhood: q.neighborhood,
            minRooms: q.minRooms,
            maxPrice: up(1.25)),
        note: 'הרחבתי קצת את התקציב'
      ),
      (
        q: SearchQuery(city: q.city, maxPrice: up(1.6)),
        note: 'הרחבתי תקציב וויתרתי על חלק מהדרישות'
      ),
      (
        q: SearchQuery(maxPrice: up(1.6)),
        note: 'לא נמצא בדיוק בעיר הזו — הנה הכי קרוב באזורים אחרים'
      ),
    ];
  }

  // Shabbat-observant (religious/haredi) + a stroller both need a lift upstairs.
  bool get _needsElevator {
    final rel = _persona['religiosity'];
    return _persona['baby'] == 'true' ||
        rel == Religiosity.religious.name ||
        rel == Religiosity.haredi.name;
  }

  // Drops listings with no elevator above a floor a person can reasonably manage
  // on foot / with a stroller.
  List<ScoredProperty> _applyLifestyleFilter(List<ScoredProperty> input) {
    if (!_needsElevator) return input;
    final cap = _persona['baby'] == 'true' ? 1 : 2;
    return input.where((r) {
      final p = r.property;
      if (p.featureFlags.isEnabled('elevator')) return true;
      final floor = p.floorNumber;
      if (floor == null) return true; // unknown floor → don't over-filter
      return floor <= cap;
    }).toList();
  }

  // Re-ranks by how well each area's religious character fits the tenant, layered
  // on top of the engine's own score. No religiosity stated → order untouched.
  List<ScoredProperty> _rankByLifestyle(List<ScoredProperty> input) {
    final relName = _persona['religiosity'];
    if (relName == null) return input;
    final rel = Religiosity.values.firstWhere((r) => r.name == relName,
        orElse: () => Religiosity.traditional);
    final scored = [
      for (final r in input)
        (r, r.score + 0.18 * _religiosityBoost(rel, r.property)),
    ];
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  double _religiosityBoost(Religiosity rel, RentalProperty p) {
    final area = LifestyleKnowledge.areaCharacter(
        neighborhood: p.neighborhood, city: p.city);
    if (area == null) return 0; // unknown area → neutral
    return LifestyleKnowledge.religiosityFit(rel, area);
  }

  String? _lifestyleNote() {
    final relName = _persona['religiosity'];
    final rel = relName == null
        ? null
        : Religiosity.values.firstWhere((r) => r.name == relName,
            orElse: () => Religiosity.traditional);
    final parts = <String>[];
    if (rel != null) {
      const label = {
        'secular': 'חילוני',
        'traditional': 'מסורתי',
        'religious': 'דתי',
        'haredi': 'חרדי',
      };
      parts.add('נתתי עדיפות לאזורים שמתאימים לאורח חיים ${label[rel.name]}');
    }
    if (_needsElevator) {
      parts.add('ודילגתי על קומות גבוהות בלי מעלית 🛗');
    }
    if (parts.isEmpty) return null;
    return 'שמתי לב לכמה דברים: ${parts.join(', ')}.';
  }

  // The single most useful missing detail, as a question + quick-reply chips.
  (String, List<String>)? _clarifyingPrompt() {
    if (_query.city == null) {
      return ('באיזה אזור או עיר לחפש?', const [
        'תל אביב',
        'ירושלים',
        'חיפה',
        'מרכז',
      ]);
    }
    if (_query.maxPrice == null) {
      return ('מה התקציב החודשי שלך?', const [
        'עד ₪5,000',
        'עד ₪7,000',
        'עד ₪9,000',
      ]);
    }
    if (_query.minRooms == null && _query.maxRooms == null) {
      return ('כמה חדרים אתם צריכים?', const ['2 חדרים', '3 חדרים', '4 חדרים']);
    }
    return null;
  }

  // ── persona capture (consent-gated) ───────────────────────────────────────

  void _maybeCapturePersona(int resultCount) {
    // Accumulate into the durable per-user persona (local-first; the dataset
    // snapshot is exported only with consent). Amenities are a heuristic parse
    // → inferred; the rest the user stated → declared (higher confidence).
    final provider = context.read<DatingProvider>();
    if (_query.amenities.isNotEmpty) {
      provider.observePersona(
          {'amenities': _query.amenities.toList()}, PersonaSource.inferred);
    }
    provider.observePersona(
      {
        if (_persona['religiosity'] != null)
          'religiosity': _persona['religiosity'],
        if (_persona['baby'] == 'true') 'baby': true,
        if (_query.city != null) 'city': _query.city,
        if (_query.maxPrice != null) 'maxBudget': _query.maxPrice,
        if (_query.minRooms != null) 'minRooms': _query.minRooms,
      },
      PersonaSource.declared,
      export: _consent == true,
    );

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
      // Flush the persona we'd already accumulated (locally) before consent.
      if (mounted) context.read<DatingProvider>().exportPersonaSnapshot();
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
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/images/eti.jpg', fit: BoxFit.cover),
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
          if (m.locationRequest) _locationButtons(),
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
        children: [
          for (int i = 0; i < chips.length; i++)
            _AnimatedChip(
              delayMs: i * 70,
              child: GestureDetector(
                onTap: _busy ? null : () => _onChipTap(chips[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35)),
                  ),
                  child: Text(chips[i],
                      style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // אתי's GPS request → the user approves here; only then does the app capture.
  Widget _locationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        ElevatedButton.icon(
          onPressed: _busy ? null : _shareLocationNow,
          icon: const Icon(Icons.my_location, size: 18),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          label: const Text('שתף את המיקום שלי'),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _messages.removeWhere((m) => m.locationRequest);
                    _messages.add(_ChatMsg(
                        role: 'assistant',
                        text: 'אין בעיה — באיזו עיר או אזור לחפש?'));
                  }),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: BorderSide(color: AppColors.borderLight),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('אגיד עיר'),
        ),
      ]),
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
// Quick-reply chip that springs in (fade + scale + rise), staggered by index —
// a small, pleasant motion for the buttons אתי offers.
class _AnimatedChip extends StatefulWidget {
  const _AnimatedChip({required this.child, required this.delayMs});
  final Widget child;
  final int delayMs;
  @override
  State<_AnimatedChip> createState() => _AnimatedChipState();
}

class _AnimatedChipState extends State<_AnimatedChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: _c,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1.0).animate(curve),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(curve),
          child: widget.child,
        ),
      ),
    );
  }
}

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
