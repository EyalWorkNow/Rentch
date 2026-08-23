import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/presentation/widgets/speed_mode_slider.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/core/search/engine/search_narrative.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/what_if_engine.dart';
import 'package:dating_app/core/search/budget_reality.dart';
import 'package:dating_app/core/search/lifestyle_knowledge.dart';
import 'package:dating_app/data/models/persona_profile.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/behavior_insights_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/recommendation_explainer.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/repositories/property_search_repository.dart';
import 'package:dating_app/data/repositories/search_history_repository.dart';
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/presentation/features/search/ati_voice_screen.dart';
import 'package:dating_app/presentation/features/search/ati_live_voice_screen.dart';
import 'package:dating_app/presentation/widgets/why_details.dart';
import 'package:dating_app/presentation/features/search/scorecard_view.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:dating_app/l10n/app_localizations.dart';
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

class _ChatMsg {
  _ChatMsg({
    required this.role,
    this.text = '',
    this.scored = const [],
    this.chips = const [],
    this.whatIfs = const [],
    this.isConsent = false,
    this.locationRequest = false,
  });
  final String role; // 'user' | 'assistant'
  String text; // mutable: the "how I chose" bubble is upgraded once the LLM returns
  List<ScoredProperty> scored; // mutable: scorecards get llmReason merged in async
  final List<String> chips;
  // "What-if" relaxations of the seeker's own constraints (thin-result recovery).
  List<WhatIfSuggestion> whatIfs;
  final bool isConsent;
  final bool locationRequest; // אתי asking to share GPS → renders a location button
  bool expanded = false; // "show more" toggle for result lists
  int widenLevel = 0; // how many times "הצג עוד" progressively relaxed the query
  bool widening = false; // a widen fetch is in flight
  bool noMore = false; // last widen returned nothing new → hide the button
}

class _SearchChatScreenState extends State<SearchChatScreen> {
  static const _consentPrefKey = 'dataset_persona_consent_v1';

  final _service = AssistantService();
  final _repo = PropertySearchRepository();
  final _history = SearchHistoryRepository();
  final _input = TextEditingController();

  // The user message currently being edited (long-press → עריכה). Sending
  // while set REPLACES that message: it and every later message are removed
  // and the corrected text runs through the normal send pipeline, so the
  // answers after it are recomputed.
  _ChatMsg? _editingMsg;
  final _scroll = ScrollController();

  final List<_ChatMsg> _messages = [];
  final List<String> _personaSnippets = [];
  final Map<String, String> _persona = {}; // household / vibe / timing ...
  SearchQuery _query = SearchQuery();

  int _userTurns = 0;
  bool _searched = false;
  // Search-style telemetry (fail-soft, no UX impact): running count of query
  // refinements this session, and whether the user ever opened a result — the
  // latter distinguishes an abandoned result set from an engaged one.
  int _refinementCount = 0;
  bool _openedResult = false;
  bool _busy = false;
  bool _lifestyleNoteShown = false; // show the "considered your lifestyle" note once
  bool _lastShowedResults = false; // did the last _send render listing cards
  String _lastReply = ''; // last assistant text, for the voice visualizer to speak
  // Voice-only: אתי asks permission before presenting apartments. True once she's
  // gathered enough and is waiting for the user's "כן" to actually show them.
  bool _voiceAwaitingConsent = false;
  bool _voiceConsented = false; // user already said yes → show results directly
  List<ScoredProperty> _voicePending = const []; // held results to reveal on "כן"
  String? _voicePendingLocationText; // held utterance until "share location" tapped
  bool? _consent;

  // Speed mode. Progressive rendering is ALWAYS on (instant on-device results,
  // then a background personalisation upgrade). In _immediateMode the background
  // LLM/cohort upgrade is skipped entirely → purely local, nothing to wait for.
  bool _immediateMode = false; // mirror of SpeedMode.immediate (shared with voice)
  bool _consentAsked = false;
  Map<String, dynamic>? _pendingPersona;

  // ── Personalization interview (מותאם אישית) ────────────────────────────────
  // In personalization mode אתי runs a short guided interview (4-6 adaptive
  // questions, each with a "why") BEFORE searching, so she genuinely understands
  // the person. Fast mode skips this and searches instantly. Tracks which
  // questions were already asked so we never repeat one and stop after ~6.
  final Set<String> _interviewAsked = {};
  bool _interviewIntroShown = false;

  List<String> _starterChips(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.searchChatScreen7ea53091,
      l10n.searchChatScreenC2031464,
      l10n.searchChatScreen13a0e834,
    ];
  }

  bool _greetingAdded = false;

  @override
  void initState() {
    super.initState();
    _loadConsent();
    _seedFromPersona();
    // Start pulling the FULL catalogue now (idempotent, ~10 extra pages) while
    // the user reads the greeting / types — otherwise search would rank over only
    // the first 150 loaded rows and miss listings on page 2+.
    unawaited(context.read<DatingProvider>().ensureFullCatalogLoaded());
    SpeedMode.immediate.addListener(_onSpeedModeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The greeting needs AppLocalizations, which isn't safely available in
    // initState() — didChangeDependencies is the correct place to read it once.
    if (!_greetingAdded) {
      _greetingAdded = true;
      _messages.add(_greetingMsg(context));
    }
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

  String _botName(BuildContext context) =>
      AppLocalizations.of(context)!.searchChatScreen8e4d1523;

  _ChatMsg _greetingMsg(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _ChatMsg(
      role: 'assistant',
      text: l10n.searchChatScreen4d424290(_botName(context)) +
          l10n.searchChatScreenE14f1c0d +
          l10n.searchChatScreen997d1274,
      chips: _starterChips(context),
    );
  }

  // "חיפושים אחרונים" — a compact sheet of the user's recent queries. Tapping
  // one starts a fresh conversation seeded with that query so it re-runs.
  Future<void> _showSearchHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final items = await _history.load();
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.searchChatScreenCcd6fad4),
        duration: const Duration(milliseconds: 1800),
      ));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(IconsaxPlusLinear.clock, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.searchChatScreenE13c91de,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await _history.clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(l10n.searchChatScreenE8b3a3d5,
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) => ListTile(
                    leading: Icon(IconsaxPlusLinear.search_normal_1,
                        size: 20, color: AppColors.primary),
                    title: Text(items[i],
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetConversation();
                      _send(items[i]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetConversation() {
    setState(() {
      _messages.clear();
      _personaSnippets.clear();
      _persona.clear();
      _query = SearchQuery();
      _userTurns = 0;
      _searched = false;
      _interviewAsked.clear();
      _interviewIntroShown = false;
      // Voice session flags — so a new conversation truly starts clean.
      _voiceAwaitingConsent = false;
      _voiceConsented = false;
      _voicePending = const [];
      _voicePendingLocationText = null;
      _lastReply = '';
      _lastShowedResults = false;
      _messages.add(_greetingMsg(context));
    });
    _scrollToEnd();
  }

  String _money(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  // ── editable active-criteria bar ──────────────────────────────────────────
  Widget _criteriaBar() {
    // A fresh conversation shows NO filters until the user has actually searched —
    // the persona seed still personalises ranking silently, it just isn't shown as
    // "הסינונים שלך" before the user has done anything.
    if (_query.isEmpty || !_searched) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final items = <Widget>[];
    if (_query.neighborhood != null) {
      items.add(_removableChip(IconsaxPlusLinear.location, _query.neighborhood!,
          () => _drop(neighborhood: true)));
    }
    if (_query.city != null) {
      items.add(_removableChip(
          IconsaxPlusLinear.location, _query.city!, () => _drop(city: true)));
    }
    if (_query.propertyType != null) {
      items.add(_removableChip(IconsaxPlusLinear.house, _query.propertyType!,
          () => _drop(propertyType: true)));
    }
    if (_query.minRooms != null || _query.maxRooms != null) {
      items.add(_removableChip(IconsaxPlusLinear.category,
          l10n.searchChatScreen9f2426ad(_roomsChipLabel()), () => _drop(rooms: true)));
    }
    if (_query.minPrice != null || _query.maxPrice != null) {
      items.add(_removableChip(
          IconsaxPlusLinear.wallet_money, _priceChipLabel(context), () => _drop(price: true)));
    }
    if (_query.nearTrain) {
      items.add(_removableChip(
          IconsaxPlusLinear.bus, l10n.searchChatScreen255d7425, () => _drop(train: true)));
    }
    if (_query.cheapPreference) {
      items.add(_removableChip(
          IconsaxPlusLinear.tag, l10n.searchChatScreen679a8520, () => _drop(cheap: true)));
    }
    for (final a in _query.amenities) {
      // Strip the emoji prefix the tag carries — the chip now uses an iconsax icon.
      final label = SmartSearch.amenityTag(a, l10n)
          .replaceFirst(RegExp(r'^[^֐-׿a-zA-Z]+'), '')
          .trim();
      items.add(_removableChip(
          IconsaxPlusLinear.tick_circle, label, () => _drop(amenity: a)));
    }
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Text('סינון:',
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

  Widget _removableChip(IconData icon, String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 6, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(label,
            // not const: AppColors.primary is a runtime theming color.
            style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Icon(IconsaxPlusLinear.close_circle,
              size: 15, color: AppColors.primary),
        ),
      ]),
    );
  }

  String _roomsChipLabel() {
    String f(double r) => r % 1 == 0 ? r.toInt().toString() : r.toString();
    final lo = _query.minRooms, hi = _query.maxRooms;
    if (lo != null && hi != null) return lo == hi ? f(lo) : '${f(lo)}-${f(hi)}';
    if (lo != null) return '${f(lo)}+';
    return AppLocalizations.of(context)!.searchChatScreen4d756cba(f(hi!));
  }

  String _priceChipLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lo = _query.minPrice, hi = _query.maxPrice;
    if (lo != null && hi != null) return '₪${_money(lo)}–${_money(hi)}';
    if (hi != null) return l10n.searchChatScreenB3cd0d47(_money(hi));
    return l10n.searchChatScreen043b90f3(_money(lo!));
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
    // Search refinement: dropping a constraint always BROADENS the result set.
    try {
      final changed = price
          ? 'price'
          : rooms
              ? 'rooms'
              : city
                  ? 'city'
                  : neighborhood
                      ? 'neighborhood'
                      : propertyType
                          ? 'propertyType'
                          : train
                              ? 'train'
                              : cheap
                                  ? 'cheap'
                                  : (amenity ?? 'filter');
      _refinementCount++;
      AppEvents.instance.service.logSearchRefined(
        changedField: changed,
        direction: RefinementDirection.broaden,
        refinementCount: _refinementCount,
      );
      BehaviorInsights.instance.noteSearchRefined(RefinementDirection.broaden);
    } catch (_) {/* fail-soft */}
    _rerunSearch();
  }

  Future<void> _rerunSearch() async {
    if (!_searched) return;
    final l10n = AppLocalizations.of(context)!;
    if (_query.isEmpty) {
      setState(() => _messages.add(_ChatMsg(
          role: 'assistant',
          text: l10n.searchChatScreenF85b1711)));
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
            ? l10n.searchChatScreen2611b32a
            : l10n.searchChatScreenA55284d7,
        scored: results,
        chips: results.isEmpty ? const [] : _refinePromptChips(),
      ));
    });
    _scrollToEnd();
  }

  // Collapsed result count before "show more". At least 5 so the seeker gets a
  // real shortlist to compare, not 1–2 flats. The pool itself is up to 10
  // (.take(10) in the search paths), which expand then reveals in full.
  static const int _kCollapsedResults = 5;

  Widget _resultList(_ChatMsg m) {
    final l10n = AppLocalizations.of(context)!;
    final total = m.scored.length;
    final show =
        m.expanded ? total : (total > _kCollapsedResults ? _kCollapsedResults : total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < show; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chat = the clean Messages-page card design. The card already
              // carries the full "למה זו?" breakdown (ScorecardView) — the old
              // separate "למה בחרתי לך את זו?" panel duplicated it and was removed.
              _AssistantPropertyCard(
                scored: m.scored[i],
                nearbyProfile: _seekerNearbyProfile(),
                onTap: () {
                  _openedResult = true; // engaged a result → not abandoned
                  Navigator.of(context).push(MaterialPageRoute(
                      settings:
                          const RouteSettings(name: 'PropertyDetailScreen'),
                      builder: (_) => PropertyDetailScreen(
                          property: m.scored[i].property,
                          entrySource: 'search',
                          entryRank: i)));
                },
              ),
            ],
          ),
        ),
      // "הצג עוד דירות" is ALWAYS available (until a widen genuinely returns
      // nothing new): first tap reveals the current pool, later taps progressively
      // relax the query and fetch ≥20 more nearby listings.
      if (!m.noMore)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onTap: m.widening ? null : () => _showMore(m),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: m.widening
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(l10n.searchChatScreen6f6b921d,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ])
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(_showMoreLabel(m, l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 4),
                      Icon(IconsaxPlusLinear.arrow_down_1,
                          size: 18, color: AppColors.primaryDark),
                    ]),
            ),
          ),
        ),
    ]);
  }

  String _showMoreLabel(_ChatMsg m, AppLocalizations l10n) {
    // Before expanding, offer the hidden pool count; after, it's a widen fetch.
    if (!m.expanded && m.scored.length > _kCollapsedResults) {
      return l10n.searchChatScreen4636c484(m.scored.length - _kCollapsedResults);
    }
    return l10n.searchChatScreenCc493224;
  }

  Future<void> _showMore(_ChatMsg m) async {
    // First tap reveals the already-fetched pool; subsequent taps widen + fetch.
    if (!m.expanded && m.scored.length > _kCollapsedResults) {
      setState(() => m.expanded = true);
      return;
    }
    await _widenAndAppend(m);
  }

  // Progressively relaxes the seeker's SOFT constraints (budget / rooms) each tap
  // while KEEPING the location and any HARD needs (parking, pets, mamad…), then
  // appends ≥20 fresh, still-relevant listings — so the seeker can always keep
  // scrolling for more without ever hitting a dead end.
  Future<void> _widenAndAppend(_ChatMsg m) async {
    if (m.widening) return;
    setState(() => m.widening = true);
    final provider = context.read<DatingProvider>();
    m.widenLevel++;
    final relaxed = _relaxQuery(_query, m.widenLevel);
    final shownIds = m.scored.map((s) => s.property.id).toSet();
    final more = provider
        .recommendForTenant(provider.allProperties, relaxed, limit: 120)
        .where((s) => !shownIds.contains(s.property.id))
        .take(20)
        .toList();
    if (!mounted) return;
    setState(() {
      m.expanded = true;
      if (more.isEmpty) {
        // Nothing new even after widening → stop offering the button honestly.
        m.noMore = true;
      } else {
        m.scored = [...m.scored, ...more];
      }
      m.widening = false;
    });
    _scrollToEnd();
  }

  // "More, but not too far": +15% budget and ±0.5 rooms per widen level. City and
  // requiredFeatures (hard gates) are intentionally preserved.
  SearchQuery _relaxQuery(SearchQuery q, int level) {
    final budgetFactor = 1 + 0.15 * level;
    return q.copyWith(
      maxPrice: q.maxPrice != null ? (q.maxPrice! * budgetFactor).round() : null,
      minRooms: q.minRooms != null
          ? (q.minRooms! - 0.5 * level).clamp(1.0, 20.0).toDouble()
          : null,
      maxRooms: q.maxRooms != null ? q.maxRooms! + 0.5 * level : null,
    );
  }

  Future<void> _loadConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_consentPrefKey)) {
        _consent = prefs.getBool(_consentPrefKey);
        _consentAsked = true;
      }
    } catch (_) {}
    // Speed mode is shared with the voice screen via a global notifier.
    await SpeedMode.init();
    if (mounted) setState(() => _immediateMode = SpeedMode.immediate.value);
  }

  void _onSpeedModeChanged() {
    if (mounted) setState(() => _immediateMode = SpeedMode.immediate.value);
  }

  Future<void> _setImmediateMode(bool v) => SpeedMode.set(v);

  @override
  void dispose() {
    // Search abandonment: results were surfaced but the user never opened any.
    // Best-effort — this tab lives in an IndexedStack, so dispose fires on
    // session teardown rather than every tab switch; it still captures a search
    // that ended with real results left untouched. Fail-soft.
    try {
      final count = _lastResultCount;
      if (_searched && count > 0 && !_openedResult) {
        AppEvents.instance.service.logSearchAbandoned(
          resultCount: count,
          dwellMs: 0,
          hadInteraction: true,
        );
        BehaviorInsights.instance.noteSearchAbandoned();
      }
    } catch (_) {/* fail-soft */}
    SpeedMode.immediate.removeListener(_onSpeedModeChanged);
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
    _resetConversation(); // every voice conversation is brand new
    // LIVE speech-to-speech (Gemini Live) when enabled — bypasses the trans-Atlantic
    // STT→LLM→TTS chain. Falls back to the turn-based screen if it can't connect.
    if (AppConfig.atiLiveVoice) {
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AtiLiveVoiceScreen(
          // On connect failure, REPLACE the live screen with the turn-based one
          // in a single transition (no pop-then-push flicker).
          onConnectFailed: () => _openTurnBasedVoice(replace: true),
          onSearch: (args) async {
            final r = await _handleRealtimeSearch(args);
            return (count: r.results.length, summary: r.summary);
          },
          // Feed each spoken user turn into the SAME conversation state text
          // messages use — it used to be painted on the live screen and
          // dropped, so cohort signals, lifestyle rules and cross-turn
          // constraint memory never saw voice input.
          onUserUtterance: (utterance) {
            if (!mounted) return;
            setState(() => _messages.add(_ChatMsg(role: 'user', text: utterance)));
            final provider = context.read<DatingProvider>();
            provider.observeCohortSignals(_cohortSignals());
          },
        ),
      ));
      _scrollToEnd();
      return;
    }
    await _openTurnBasedVoice();
    _scrollToEnd();
  }

  Future<void> _openTurnBasedVoice({bool replace = false}) async {
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AtiVoiceScreen(
        service: _service,
        onUtterance: _processVoiceUtterance,
        onShareLocation: _shareLocationVoice,
        onNewConversation: _resetConversation,
        criteria: const [], // fresh — no stale tags
        resultCount: 0,
      ),
    );
    // replace = coming from the failed live screen → swap it out in one motion.
    if (replace) {
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
  }

  // Runs a `search_listings` tool-call from the live voice agent: builds the query
  // from its args, runs the same cohort search as typed input, drops the cards
  // into the chat, and returns a short spoken summary + the results for אתי.
  Future<({List<ScoredProperty> results, String summary})> _handleRealtimeSearch(
      Map<String, dynamic> args) async {
    final l10n = AppLocalizations.of(context)!;
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
    // A single stated room count from the voice tool ("3 חדרים") arrives as
    // minRooms only; without an upper bound the ranking keeps 4/5/6-room units.
    // Mirror the typed-search band: a lone min with no max → tight [n, n+0.5].
    var vMinRooms = (args['minRooms'] as num?)?.toDouble();
    final vRooms = (args['rooms'] as num?)?.toDouble();
    vMinRooms ??= vRooms;
    var vMaxRooms = (args['maxRooms'] as num?)?.toDouble();
    if (vMaxRooms == null && vMinRooms != null) vMaxRooms = vMinRooms + 0.5;
    _query = _merge(
      _query,
      SearchQuery(
        city: args['city'] as String?,
        minRooms: vMinRooms,
        maxRooms: vMaxRooms,
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
              text: l10n.searchChatScreen7ce13a9c,
              scored: results,
              chips: _refinePromptChips()));
        }
      });
      _scrollToEnd();
    }
    final summary = results.isEmpty
        ? l10n.searchChatScreenA6e71e55
        : l10n.searchChatScreen61081906(results.length);
    return (results: results, summary: summary);
  }

  // Understood-criteria chips for the voice screen (mirrors the chat criteria bar).
  List<String> _voiceCriteria(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _query;
    final out = <String>[];
    if (q.city != null && q.city!.trim().isNotEmpty) out.add(q.city!.trim());
    if (q.neighborhood != null && q.neighborhood!.trim().isNotEmpty) {
      out.add(q.neighborhood!.trim());
    }
    if (q.minRooms != null) {
      final r = q.minRooms!;
      final label = r == r.roundToDouble() ? r.toInt().toString() : r.toString();
      out.add(l10n.searchChatScreenC0c2a8be(label));
    }
    if (q.maxPrice != null) {
      final p = q.maxPrice!.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
      out.add(l10n.searchChatScreen35e94525(p));
    }
    for (final a in q.amenities) {
      out.add(SmartSearch.amenityTag(a, l10n));
    }
    if (q.nearTrain) out.add(l10n.searchChatScreen840a3a9f);
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
  Future<VoiceTurn> _processVoiceUtterance(String transcript) async {
    final l10n = AppLocalizations.of(context)!;
    final t = transcript.trim();
    final wantsNow = _wantsResultsNow(t);

    // Waiting for the user's go-ahead to present apartments? DEFAULT TO SHOWING —
    // after "רוצה שאראה לך?", almost any reply ("כן"/"תציג"/"בטח"/"נו"/"בוא") means
    // yes. Only a clear NO or a reply that adds new criteria holds them back.
    if (_voiceAwaitingConsent) {
      _voiceAwaitingConsent = false;
      final holdsBack = _isNegative(t) || _looksLikeCriteria(t);
      if (!holdsBack) {
        _voiceConsented = true;
        final r = _voicePending.isNotEmpty ? _voicePending : _latestScored;
        return VoiceTurn(
          reply: r.isEmpty
              ? l10n.searchChatScreen5a4b1739
              : l10n.searchChatScreenBc3b9351,
          showResults: r.isNotEmpty,
          results: r,
        );
      }
      // A "no" or added criteria → fold it in below (re-search, then re-offer).
    }

    // Voice "באזור שלי / קרוב אליי" → pop the animated "share my location" button
    // (don't grab GPS silently). The held utterance runs once the user taps it.
    if (_locationRelative.hasMatch(t) && _query.city == null) {
      _voicePendingLocationText = transcript;
      return VoiceTurn(
        reply: l10n.searchChatScreen95335c81,
        needLocation: true,
      );
    }

    // Voice honours the speed mode: fast → on-device only; personalization → the
    // background AI upgrade runs too (still shows instant results first).
    await _send(transcript, enrich: !_immediateMode, isVoice: true);

    // Reality-check (voice): if the ask is a fantasy for that city+budget, אתי
    // SAYS so — with the realistic price + a nearby-city nudge — instead of
    // voicing mismatched flats. Only the clearly-impossible case interrupts; a
    // merely "tight" budget still flows to results below.
    final reality = BudgetRealityCheck.assess(_query);
    if (reality.verdict == RealityVerdict.unrealistic) {
      return VoiceTurn(reply: reality.message);
    }

    // Voice etiquette: don't dump apartments unasked. The FIRST time אתי has enough
    // to search, she ASKS — unless the user already consented or said "תראה לי".
    if (_lastShowedResults &&
        _latestScored.isNotEmpty &&
        !wantsNow &&
        !_voiceConsented) {
      _voiceAwaitingConsent = true;
      _voicePending = _latestScored; // hold them so "כן" reveals exactly these
      return VoiceTurn(
        reply: l10n.searchChatScreen1daddad9 + l10n.searchChatScreen39e1f421,
      );
    }

    // Explicit "show me" or a refinement AFTER consent → SHOW whatever she found.
    if (wantsNow) _voiceConsented = true;
    return VoiceTurn(
      reply: _lastReply.isEmpty
          ? l10n.searchChatScreen1f0defdc
          : _lastReply,
      showResults: _lastShowedResults,
      results: _lastShowedResults ? _latestScored : const <ScoredProperty>[],
    );
  }

  // The user tapped the animated "share my location" button in the voice screen →
  // capture GPS, fold in the city, and run the utterance we held.
  Future<VoiceTurn> _shareLocationVoice() async {
    final l10n = AppLocalizations.of(context)!;
    final held = _voicePendingLocationText ?? l10n.searchChatScreen7dae215b;
    _voicePendingLocationText = null;
    final city = await _captureGps();
    if (city == null || city.isEmpty) {
      return VoiceTurn(
        reply: _locationDeniedForever
            ? l10n.searchChatScreen320230a9
            : l10n.searchChatScreenE9aa1c0c,
      );
    }
    if (mounted) _query = _merge(_query, SearchQuery(city: city));
    // City is now set, so the location branch is skipped → this runs the search.
    return _processVoiceUtterance(held);
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
      r'(?<![\wא-ת])פה(?![\wא-ת])|(?<![\wא-ת])כאן(?![\wא-ת])|באזור הזה|באיזור הזה|בסביבה הזו|בסביבה שלי|ליד(?:י| שלי| הבית)?|'
      r'אזור שלי|איזור שלי|באזור שלי|באיזור שלי|האזור שלי|קרוב אלי|קרוב אליי|אצלי|'
      r'ה?מיקום שלי|במיקום שלי|איפה שאני|היכן שאני|ליד המיקום|ליד איפה ש|כאן לידי|'
      r'near me|around here|\bhere\b|my area|in my area|close to me|nearby|my location');

  // The USER tapped "share my location" on אתי's request → NOW capture the GPS
  // (the OS permission prompt is the approval), set the city, and search. This is
  // the only place that reads location, and only after an explicit user tap.
  Future<void> _shareLocationNow() async {
    final l10n = AppLocalizations.of(context)!;
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
            text: l10n.searchChatScreen3135f25b));
        _busy = false;
      });
      _scrollToEnd();
      return;
    }
    _query = _merge(_query, SearchQuery(city: city));
    setState(() => _messages.add(_ChatMsg(
        role: 'assistant',
        text: l10n.searchChatScreenF1e58bcd(city))));
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
            text: l10n.searchChatScreenD94e281c));
      } else {
        _messages.add(_ChatMsg(
            role: 'assistant',
            text: l10n.searchChatScreenD42b5de4,
            scored: results,
            chips: _refinePromptChips()));
      }
    });
    _scrollToEnd();
  }

  // Set when the OS reported location permission is permanently denied — the voice
  // flow uses it to tell the user to enable it in Settings (a re-prompt won't show).
  bool _locationDeniedForever = false;

  // Raw GPS capture → resolved city name (null if unavailable / denied). The OS
  // permission dialog IS the user's approval.
  Future<String?> _captureGps() async {
    _locationDeniedForever = false;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _locationDeniedForever = true;
        return null;
      }
      if (perm == LocationPermission.denied) return null;
      // Last-known position first (instant, works indoors), then try a fresh fix —
      // so a slow/blocked GPS lock doesn't leave "my area" empty.
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {/* keep last-known if the fresh fix timed out */}
      if (pos == null) return null;
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
  // The persona Etti inferred on the LAST extract ("young couple, first
  // apartment, prioritises commute…"). Used to be parsed and thrown away —
  // now it grounds the "how I chose" explanation alongside the profile tags.
  String _ettiPersona = '';

  Future<void> _ettiEnrich(String text) async {
    try {
      // Prior user turns (newest last, current excluded) so the extractor
      // reasons over the CONVERSATION instead of a single fragment.
      final priorTurns = [
        for (final m in _messages)
          if (m.role == 'user' && m.text.trim().isNotEmpty && m.text != text)
            m.text.trim(),
      ];
      final context = priorTurns.length > 4
          ? priorTurns.sublist(priorTurns.length - 4).join('\n')
          : priorTurns.join('\n');
      final resp = await AwsApiClient.instance.post('/assistant/extract', {
        'query': text,
        if (context.isNotEmpty) 'context': context,
      }).timeout(
        const Duration(seconds: 4),
      );
      final plan = EttiPlan.fromJson(resp);
      if (plan.persona.trim().isNotEmpty) _ettiPersona = plan.persona.trim();
      // The server enrich ADDS soft signals (persona weights/intents/features)
      // and fills gaps — but the deterministic on-device parse stays AUTHORITATIVE
      // for the explicit hard constraints the user actually typed. Re-overlaying
      // _query keeps its city/budget/rooms from being overwritten by a fuzzy Gemini
      // re-extraction of a single turn (which was silently degrading correct asks).
      if (!plan.isEmpty) {
        final enriched = plan.toQuery(fallback: _query);
        final merged = _merge(enriched, _query);
        // _merge puts the PRE-enrich on-device weights last ("b wins"), which
        // clobbered Etti's amplified importances for every factor SmartSearch
        // had already touched — her whole soft-weight layer was dead for the
        // factors that matter most. Re-apply her weights as a per-key MAX so
        // both signals survive and the stronger one decides.
        _query = merged.copyWith(weights: {
          ...merged.weights,
          for (final e in enriched.weights.entries)
            if (e.value > (merged.weights[e.key] ?? 0)) e.key: e.value,
        });
      }
    } catch (_) {
      // graceful — the on-device SmartSearch query already stands
    }
  }

  // [enrich] runs the extra backend LLM extraction. Voice passes false — the
  // on-device SmartSearch (city via CBS data + budget/rooms/features + the
  // transaction & required-feature inference rules) is enough, and dropping the
  // second network round-trip makes אתי answer MUCH faster (she was too slow).
  /// A short, instant reply shown the moment the on-device results render (or the
  /// only reply, in immediate mode). Empty when not searching → clarify handles it.
  /// A first message that already carries a real request (a city + at least one
  /// concrete constraint) → search RIGHT AWAY instead of waiting for turn 2, so a
  /// detailed ask like "דירה בהרצליה עד 4500 לא רחוק מהים" gets results immediately.
  bool _queryIsRich() =>
      _query.city != null &&
      (_query.maxPrice != null ||
          _query.minRooms != null ||
          _query.amenities.isNotEmpty);

  /// A friendly on-device acknowledgement so fast mode never leaves אתי silent
  /// when there's nothing to search or clarify yet.
  String _localAck() {
    final l10n = AppLocalizations.of(context)!;
    if (_query.isEmpty) {
      return l10n.searchChatScreen6f5e36b8;
    }
    return l10n.searchChatScreen3130f977;
  }

  String _instantReply(bool shouldSearch, List<ScoredProperty> results,
      bool anyExact, BuildContext context) {
    if (!shouldSearch || results.isEmpty) return '';
    final l10n = AppLocalizations.of(context)!;
    return anyExact
        ? l10n.searchChatScreenE9c8b415
        : l10n.searchChatScreen4027c8f4;
  }

  /// Background personalisation: after the instant on-device results are on
  /// screen, run the LLM enrich + the cohort/community-fit ranking + the warm
  /// reply, then quietly swap in the richer set. Skipped in immediate mode.
  Future<void> _upgradeSearch(String text, DatingProvider provider,
      _ChatMsg resultsMsg, _ChatMsg? howChoseMsg, _ChatMsg? replyMsg) async {
    // Guarantee the FULL catalogue is loaded before the (complete) re-rank swaps
    // in — the instant results ranked over whatever was loaded, this covers the
    // rest. Idempotent + fast if initState already finished loading.
    try {
      await provider.ensureFullCatalogLoaded();
    } catch (_) {}
    try {
      await _ettiEnrich(text);
    } catch (_) {}
    List<ScoredProperty> cohort;
    try {
      // Same anti-hallucination gate (_verifyResults) the INSTANT path applies —
      // otherwise the server-ranked swap-in could reintroduce geo-far / over-budget
      // flats that the instant results had already filtered out, so results would
      // visibly get WORSE a second after appearing.
      cohort = _verifyResults(_rankByLifestyle(_applyLifestyleFilter(
              await _cohortRanked(provider, limit: 40)))
          .take(10)
          .toList());
    } catch (_) {
      cohort = const [];
    }
    final sr = await _serverReply();
    if (!mounted) return;
    final upgraded = cohort.isNotEmpty ? cohort : resultsMsg.scored;
    setState(() {
      resultsMsg.scored = upgraded; // _latestScored getter reflects this
      _lastShowedResults = upgraded.isNotEmpty;
      if (sr.$1.isNotEmpty && replyMsg != null) replyMsg.text = sr.$1;
    });
    if (sr.$1.isNotEmpty) _lastReply = sr.$1;
    if (upgraded.isNotEmpty && howChoseMsg != null) {
      _fetchExplanations(
        results: upgraded,
        persona: _personaLabels(provider),
        howChoseMsg: howChoseMsg,
        resultsMsg: resultsMsg,
      );
    }
  }

  Future<void> _send(String raw,
      {bool enrich = true, bool isVoice = false, SearchQuery? forceQuery}) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<DatingProvider>();

    // Editing an earlier message: drop it and everything after, then run the
    // corrected text through the normal pipeline so the answers regenerate.
    // (The accumulated query state stays — the send's own merge lets the
    // corrected numbers/criteria override the old ones.)
    final editing = _editingMsg;
    if (editing != null) {
      final idx = _messages.indexOf(editing);
      if (idx >= 0) _messages.removeRange(idx, _messages.length);
      _editingMsg = null;
    }

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _personaSnippets.add(text);
      _userTurns++;
      _input.clear();
      _busy = true;
    });
    // Remember this query so it can be offered under "חיפושים אחרונים".
    unawaited(_history.add(text));
    _scrollToEnd();

    // If the user referred to their own area ("אזור שלי" / "פה"), אתי will RAISE a
    // location request instead of a warm reply (see below).
    final maybeLoc = _locationRelative.hasMatch(text);

    // A "what-if" tap applies a pre-built mutated query directly — no parse/merge,
    // so the exact relaxation the user chose is what we search.
    if (forceQuery != null) {
      _query = forceQuery;
    } else {
    // Deterministic base: SmartSearch parses explicit fields instantly on-device
    // (city / budget / rooms / features) — the fallback Etti folds over.
    final parsed = SmartSearch.parse(text);
    // CITY SWITCH mid-conversation: when this turn names a DIFFERENT city, drop the
    // previous location context entirely — old city / neighborhood / excluded-areas
    // / direction AND the accumulated rawText that named the old city — otherwise it
    // lingers (rawText, exclusions, sticky hood) and we keep showing the old city.
    // Non-location preferences (budget / rooms / amenities / intents) are kept.
    if (parsed.city != null &&
        _query.city != null &&
        _cityKey(parsed.city!) != _cityKey(_query.city!)) {
      _query = _merge(_prefsOnly(_query), parsed);
    } else {
      _query = _merge(_query, parsed);
    }
    }

    // Fold lifestyle signals from the whole conversation into the query (e.g.
    // "דתי לאומי" / "תינוק" → an elevator matters). See _applyLifestyle.
    _applyLifestyle(text);

    // SPEED: the LLM enrich no longer BLOCKS here. The deterministic on-device
    // parse (+ the 40 inference rules) is enough to rank instantly; the enrich +
    // cohort personalisation run in the background upgrade below and quietly
    // refine the ranking — so the user never waits on the network for results.

    // Location needed but unknown → אתי RAISES a GPS request (a button). The user
    // approves, then the app captures the location and searches. אתי never grabs
    // GPS silently herself.
    if (maybeLoc && _query.city == null) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMsg(
          role: 'assistant',
          text: l10n.searchChatScreen55799661,
          locationRequest: true,
        ));
        _busy = false;
      });
      _scrollToEnd();
      return;
    }

    // MODE: fast → search instantly (current behaviour). Personalization → run a
    // short guided INTERVIEW (4-6 adaptive questions, each with a "why") BEFORE
    // searching, so אתי genuinely understands the person and explains her choices.
    // The user can cut it short any time ("תראי לי כבר").
    bool shouldSearch;
    if (_immediateMode || isVoice) {
      // Fast mode (or the hands-free voice flow) searches without the interview.
      shouldSearch = !_query.isEmpty &&
          (_searched ||
              _wantsResultsNow(text) ||
              _userTurns >= 2 ||
              _queryIsRich());
    } else {
      final nextQ = _searched ? null : _nextInterviewQuestion();
      final asked = _interviewAsked.length;
      // A skip is offered from the SECOND question on (after the first is
      // answered); tapping it — or saying "תראי לי" — searches immediately.
      final wantsNow = _wantsResultsNow(text) && asked >= 1;
      // Focused interview: at most 3 questions, then search.
      final interviewDone = _searched || asked >= 3 || nextQ == null;
      if (!_query.isEmpty && (interviewDone || wantsNow)) {
        shouldSearch = true;
      } else if (nextQ != null) {
        // Ask the next question (with its "why") instead of searching yet.
        final intro = _interviewIntroShown
            ? ''
            : l10n.searchChatScreen9ccf780f;
        _interviewIntroShown = true;
        _interviewAsked.add(nextQ.key);
        // From the 2nd question on, add a skip chip so the user is never stuck.
        final chips = asked >= 1
            ? [...nextQ.chips, l10n.searchChatScreen37cee5fa]
            : nextQ.chips;
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: '$intro${nextQ.q}\n\n💡 ${nextQ.why}',
            chips: chips,
          ));
          _busy = false;
        });
        _scrollToEnd();
        return;
      } else {
        shouldSearch = !_query.isEmpty;
      }
    }

    // ⚡ IMMEDIATE — rank ON-DEVICE right now (no network, no LLM) so results +
    // a reply appear in well under a second. The community-fit cohort ranking +
    // the warm GPT reply arrive in the background upgrade and swap in silently.
    List<ScoredProperty> results = const [];
    bool anyExact = false;
    if (shouldSearch) {
      results = _rankByLifestyle(_applyLifestyleFilter(
              provider.recommendForTenant(provider.allProperties, _query,
                  limit: 40)))
          .take(10)
          .toList();
      // GEO-VERIFY: never surface a flat grossly far from the requested place.
      // Catches any name-gate leak — e.g. "כרכור" must NOT return רמת גן (~50km).
      results = _verifyResults(results);
      anyExact = results.any((r) => r.exact);
    }
    // Instant canned reply now; the warm GPT reply is upgraded in the background.
    final sr = (_instantReply(shouldSearch, results, anyExact, context), const <String>[]);

    // ANTI-HALLUCINATION: when the EXACT request has no match, do NOT silently
    // drop filters and show mismatched flats. First look for the SAME filters
    // within 10km of the city; if found, show them and say clearly they're just
    // nearby (not exact). If even that is empty, be honest and offer to relax.
    String? widenNote;
    if (shouldSearch && results.isEmpty) {
      final nearby = _nearbySameFilters(_query, provider, km: 10);
      if (nearby.isNotEmpty) {
        results = nearby;
        final city = _query.city?.trim() ?? l10n.searchChatScreen8b1aa6b1;
        widenNote = l10n.searchChatScreen8c180264(city) +
            l10n.searchChatScreenCeed4a22(city);
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
        // Reality-check heads-up: when the ask is a fantasy for that city+budget,
        // אתי says so honestly (with a raise-budget / nearby-city nudge) BEFORE the
        // results — instead of a wall of low-fit mismatches.
        final reality = BudgetRealityCheck.assess(_query);
        if (reality.needsGuidance) {
          final chips = <String>[
            if (reality.expected != null) l10n.searchChatScreenF7b15001(reality.expected!.toString()),
            if (reality.nearbyCity != null) l10n.searchChatScreenDc2e4dcf(reality.nearbyCity!),
          ];
          _messages.add(_ChatMsg(
              role: 'assistant', text: reality.message, chips: chips));
        }
        if (results.isEmpty) {
          // Honest — nothing matched, not even within 10km with the same filters.
          // Offer concrete ways to relax (tapping a chip re-runs the search).
          final city = _query.city?.trim() ?? l10n.searchChatScreen616a9ead;
          final chips = <String>[];
          if (_query.city != null) chips.add(l10n.searchChatScreenA62ac675(_query.city!));
          if (_query.maxPrice != null) {
            chips.add(l10n.searchChatScreenE8ad7744(
                (_query.maxPrice! * 1.2).round().toString()));
          }
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: l10n.searchChatScreen02622166(city) +
                l10n.searchChatScreen25b42314,
            chips: chips,
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
            text: _howIChoseFallback(results, context),
          );
          _messages.add(howChoseMsg!);
          final exactCount = results.where((r) => r.exact).length;
          resultsMsg = _ChatMsg(
            role: 'assistant',
            text: !anyExact
                ? l10n.searchChatScreen3a89ba73
                : exactCount == results.length
                    ? l10n.searchChatScreen94ee5876(exactCount.toString())
                    : l10n.searchChatScreenA5a08a80(exactCount.toString()) +
                        l10n.searchChatScreen19e1fa38,
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
      } else if (sr.$1.isEmpty) {
        // Fast mode (no warm LLM reply) with nothing to search OR clarify → never
        // leave her silent; acknowledge on-device so she always answers.
        _messages.add(_ChatMsg(role: 'assistant', text: _localAck()));
      }
      _busy = false;
    });
    if (replyMsg != null) _streamText(replyMsg, sr.$1);
    _scrollToEnd();

    // Fetch the LLM's number-grounded explanations WITHOUT blocking the cards:
    // they're already on screen; this fills llmReason + the "how I chose" bubble
    // when (and if) it returns within a short timeout. Degrades to engine reasons.
    _lastShowedResults = shouldSearch && results.isNotEmpty;
    // Immediate mode stays PURELY on-device — the engine's own "how I chose"
    // fallback is already shown; we don't call the LLM explainer. Progressive mode
    // fetches the richer LLM explanations inside _upgradeSearch on the final set.

    if (shouldSearch && results.isNotEmpty) _maybeCapturePersona(results.length);

    // 💡 WHAT-IF: on a THIN result set (incl. empty), offer QUANTIFIED relaxations
    // of the seeker's OWN constraints — "אם תעלה ל-X ₪ → עוד N דירות". Deferred to
    // after the cards paint so it never delays the results, and only shown when a
    // relaxation actually frees ≥3 more listings (WhatIfEngine's own gate).
    if (shouldSearch && results.length <= 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerWhatIfs());
    }

    // 🎯 BACKGROUND personalisation — the instant results are already on screen;
    // now quietly upgrade them with the LLM enrich + community-fit cohort ranking
    // + the warm GPT reply. Skipped in immediate mode (purely on-device) and for
    // the voice path (enrich:false), which runs its own fast loop.
    if (!_immediateMode &&
        enrich &&
        shouldSearch &&
        results.isNotEmpty &&
        resultsMsg != null) {
      unawaited(
          _upgradeSearch(text, provider, resultsMsg!, howChoseMsg, replyMsg));
    }
  }

  // Persona labels driving the ranking + sent to the explainer.
  List<String> _personaLabels(DatingProvider provider) {
    final p = provider.tenantProfile;
    return [
      // Etti's own inferred persona leads — it's the reasoning that actually
      // drove this ranking, and the explainer never saw it before.
      if (_ettiPersona.isNotEmpty) _ettiPersona,
      ...?(p == null ? null : [...p.importantDetails, ...p.dealBreakers]),
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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
  String _howIChoseFallback(List<ScoredProperty> results, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cards = results
        .map((r) => r.scorecard)
        .whereType<Scorecard>()
        .toList();
    if (cards.isEmpty) {
      return l10n.searchChatScreen642c3ded + l10n.searchChatScreenB35c8d26;
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
    final sb = StringBuffer(l10n.searchChatScreen316236bf);
    sb.write(topDims.isEmpty ? l10n.searchChatScreen5c0f04c1 : _joinHe(topDims, l10n));
    sb.write(l10n.searchChatScreenEcd67fb1);
    if (best.personaReasons.isNotEmpty) {
      sb.write(l10n.searchChatScreenB3622b1e(best.personaReasons.first));
    }
    sb.write(l10n.searchChatScreen2b144437(best.fitPct.toString()));
    if (best.tier.isNotEmpty) sb.write(' (${best.tier})');
    sb.write(l10n.searchChatScreenE9fe38e7);
    return sb.toString();
  }

  // Hebrew-friendly list join: "א, ב ו-ג".
  String _joinHe(List<String> items, AppLocalizations l10n) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    final head = items.sublist(0, items.length - 1).join(', ');
    return l10n.searchChatScreenE7d0c3b9(head, items.last);
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
    final l10n = AppLocalizations.of(context)!;
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
      parts.add(l10n.searchChatScreen121302b1(
          r == r.roundToDouble() ? r.toInt().toString() : r.toString()));
    }
    if (q.city != null && q.city!.trim().isNotEmpty) {
      parts.add(l10n.searchChatScreenD2776ad7(q.city!.trim()));
    }
    if (q.maxPrice != null) {
      final p = q.maxPrice!.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
      parts.add(l10n.searchChatScreen35e94525(p));
    }
    final summary = parts.join(' ');

    final openers = [
      l10n.searchChatScreen74c3e44d,
      l10n.searchChatScreen034ce5a9,
      l10n.searchChatScreen09cbbf65,
      l10n.searchChatScreen8135ce70,
    ];
    final opener = openers[(_openerIdx++) % openers.length];

    // Enough to search (city + budget or rooms) → reflect + go straight to results.
    final enough = q.city != null && (q.maxPrice != null || q.minRooms != null);
    if (enough || _searched || _userTurns >= 2) {
      return summary.isEmpty
          ? l10n.searchChatScreen62cb3d3d(opener)
          : l10n.searchChatScreen22a8276a(opener, summary);
    }
    // Otherwise ask ONE persona-appropriate follow-up (still no LLM).
    final follow = _cohortFollowup();
    return summary.isEmpty ? '$opener. $follow' : '$opener — $summary. $follow';
  }

  // A warm follow-up question tuned to the detected persona — a fixed, reused
  // library (no tokens).
  String _cohortFollowup() {
    final l10n = AppLocalizations.of(context)!;
    final s = SmartSearch.cohortSignals(_conversationText);
    if (s['household'] == 'family' || _persona['baby'] == 'true') {
      return l10n.searchChatScreen344ff8c5;
    }
    if (s['lifeStage'] == 'student' || s['household'] == 'student') {
      return l10n.searchChatScreen25af8375;
    }
    if (s['isInvestor'] == 'true') {
      return l10n.searchChatScreen4729c6ea;
    }
    if (s['lifeStage'] == 'senior' || s['accessibilityNeed'] == 'true') {
      return l10n.searchChatScreenDe6c778e;
    }
    if (s['wfh'] == 'true') return l10n.searchChatScreen1a7921f2;
    if (_persona['religiosity'] != null || s['isReligious'] == 'true') {
      return l10n.searchChatScreen6f0e9087;
    }
    return l10n.searchChatScreenB7874897;
  }

  // ── Personalization interview ──────────────────────────────────────────────
  /// The next question אתי should ask in the guided interview, or null when the
  /// interview is complete (all relevant questions asked). Adaptive: she skips
  /// what she already knows and asks only what's still missing — she DECIDES
  /// what matters — and every question carries a short "why". Ordered
  /// most-decisive first (area → budget → household → the #1 priority) and
  /// capped at 3 questions in [_send].
  ({String key, String q, String why, List<String> chips})? _nextInterviewQuestion() {
    final l10n = AppLocalizations.of(context)!;
    final s = SmartSearch.cohortSignals(_conversationText);
    final household = _persona['household'] ?? s['household'];
    bool has(String k) => _interviewAsked.contains(k);
    final out = <({String key, String q, String why, List<String> chips})>[];
    void add(String key, String q, String why, List<String> chips) {
      if (!has(key)) out.add((key: key, q: q, why: why, chips: chips));
    }

    // A FOCUSED interview: at most 3 short, precise questions (capped in
    // [_send]). Ordered most-decisive first, adaptive — she skips whatever she
    // already knows from the free text, so a rich opener may ask fewer.
    // 1) WHERE
    if (_query.city == null && _query.neighborhood == null) {
      add('area', l10n.searchChatScreenD3cb993d,
          l10n.searchChatScreen61710995,
          [
            l10n.searchChatScreen2c1f2bbd,
            l10n.searchChatScreen8e0dfe1e,
            l10n.searchChatScreenCa1cc213,
            l10n.searchChatScreenF3acedbf,
            l10n.searchChatScreen35529032,
          ]);
    }
    // 2) HOW MUCH
    if (_query.maxPrice == null) {
      add('budget', l10n.searchChatScreen8c19300f,
          l10n.searchChatScreenDd0caf20,
          [l10n.searchChatScreen1dc1a458, '4,000-6,000', '6,000-9,000', l10n.searchChatScreenBbdaa418]);
    }
    // 3) WHO (only while unknown)
    if (household == null) {
      add('household', l10n.searchChatScreen5e0214d0,
          l10n.searchChatScreen27e52fe1,
          [
            l10n.searchChatScreenCaef6ad4,
            l10n.searchChatScreen4df994d0,
            l10n.searchChatScreen52204c3c,
            l10n.searchChatScreenB5c68bd1,
          ]);
    }
    // The single most important factor — the always-relevant closer.
    add('priority', l10n.searchChatScreenEe542324,
        l10n.searchChatScreenB86b9b16,
        [
          l10n.searchChatScreenAb3f526d,
          l10n.searchChatScreen40d07087,
          l10n.searchChatScreen4e515b14,
          l10n.searchChatScreen68579629,
          l10n.searchChatScreenCd73f9c6,
        ]);

    return out.isEmpty ? null : out.first;
  }

  int _warmIdx = 0;
  String _warmFallback() {
    final l10n = AppLocalizations.of(context)!;
    final lines = [
      l10n.searchChatScreenC5847f1d,
      l10n.searchChatScreenE6d0829f,
      l10n.searchChatScreenC752e50e,
    ];
    return lines[(_warmIdx++) % lines.length];
  }

  // Concrete refinement suggestions — shown only AFTER the user opts to refine.
  List<String> _refineChips() {
    final l10n = AppLocalizations.of(context)!;
    final chips = <String>[];
    if (_query.maxPrice != null) {
      chips.add(l10n.searchChatScreen258a50bf(
          (_query.maxPrice! * 0.85).round().toString()));
    }
    if (_query.minRooms != null) {
      chips.add(l10n.searchChatScreenF83283b7(
          (_query.minRooms! + 1).toInt().toString()));
    }
    if (!_query.amenities.contains('feat_parking')) chips.add(l10n.searchChatScreen63cd0477);
    if (!_query.nearTrain) chips.add(l10n.searchChatScreenEe07d486);
    if (!_query.amenities.contains('feat_elevator')) chips.add(l10n.searchChatScreen706598a7);
    return chips.take(4).toList();
  }

  // Gentle refine prompt shown WITH the results (instead of dumping the options)
  // so אתי isn't naggy — she just offers to refine, and only asks the next
  // question if the user says yes.
  String _kRefineYes(BuildContext context) =>
      AppLocalizations.of(context)!.searchChatScreenE6452825;
  String _kRefineNo(BuildContext context) =>
      AppLocalizations.of(context)!.searchChatScreen113aa61a;
  List<String> _refinePromptChips() => _refineChips().isEmpty
      ? const []
      : [_kRefineYes(context), _kRefineNo(context)];

  // Routes a quick-reply chip: the refine prompt is handled locally (no LLM),
  // everything else goes through the normal turn.
  void _onChipTap(String c) {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (c == _kRefineYes(context)) {
      setState(() => _messages.add(_ChatMsg(
            role: 'assistant',
            text: l10n.searchChatScreen391e982f,
            chips: _refineChips(),
          )));
      _scrollToEnd();
      return;
    }
    if (c == _kRefineNo(context)) {
      setState(() => _messages.add(_ChatMsg(
            role: 'assistant',
            text: l10n.searchChatScreenD51433d2,
          )));
      _scrollToEnd();
      return;
    }
    _send(c);
  }

  SearchQuery _merge(SearchQuery a, SearchQuery b) => SearchQuery(
        city: b.city ?? a.city,
        neighborhood: b.neighborhood ?? a.neighborhood,
        excludeAreas: {...a.excludeAreas, ...b.excludeAreas}.toList(),
        areaDir: b.areaDir ?? a.areaDir,
        areaDirExclude: b.areaDir != null ? b.areaDirExclude : a.areaDirExclude,
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

  // Canonical city name for equality — strips the "- יפו" / parenthetical suffix
  // so "תל אביב" and "תל אביב - יפו" are the SAME city (never a false switch).
  String _cityKey(String c) =>
      c.split('-').first.split('(').first.trim();

  // The non-location PREFERENCES of a query (budget / rooms / features / intents /
  // weights) with the place + accumulated rawText dropped. Used on a city switch so
  // the seeker's real criteria carry over to the new city, but nothing that named
  // or scoped the OLD city lingers.
  SearchQuery _prefsOnly(SearchQuery q) => SearchQuery(
        minPrice: q.minPrice,
        maxPrice: q.maxPrice,
        minRooms: q.minRooms,
        maxRooms: q.maxRooms,
        propertyType: q.propertyType,
        amenities: {...q.amenities},
        nearTrain: q.nearTrain,
        cheapPreference: q.cheapPreference,
        transactionType: q.transactionType,
        intents: {...q.intents},
        weights: {...q.weights},
        requiredFeatures: {...q.requiredFeatures},
        // city / neighborhood / excludeAreas / areaDir / rawText intentionally dropped
      );

  // Compute + render "what-if" relaxations of the current (thin) query. Counts
  // STRICT matches (ALL hard constraints met) via the real ranker, so the "עוד N
  // דירות" reflects exactly what the seeker would actually get — not soft-ranked
  // near-misses. Runs post-frame, so it never delays the results themselves.
  void _offerWhatIfs() {
    if (!mounted || _busy) return;
    final provider = context.read<DatingProvider>();
    // `.exact` == the engine's strictMatch (ALL hard constraints met).
    int strict(SearchQuery q) => provider
        .recommendForTenant(provider.allProperties, q, limit: 120)
        .where((r) => r.exact)
        .length;
    final base = strict(_query);
    final ifs = WhatIfEngine.suggest(
        query: _query, countMatches: strict, baselineCount: base);
    if (ifs.isEmpty || !mounted) return;
    setState(() => _messages.add(_ChatMsg(
          role: 'assistant',
          text: AppLocalizations.of(context)!.searchChatScreen8b097eb6,
          whatIfs: ifs,
        )));
    _scrollToEnd();
  }

  // Applying a what-if: the pre-built mutated query is searched directly (no
  // re-parse), and the label doubles as the user's turn so the chat reads naturally.
  void _onWhatIfTap(WhatIfSuggestion s) {
    if (_busy) return;
    _send(s.label, forceQuery: s.mutated);
  }

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
    // Phase-0: fold this query's cohort signals into the evolving per-user
    // cohort belief (persisted, sharpens across sessions).
    provider.observeCohortSignals(signals);
    final criteria = PropertySearchCriteria(
      city: q.city,
      minPrice: q.minPrice,
      maxPrice: q.maxPrice,
      minRooms: q.minRooms,
      maxRooms: q.maxRooms,
      amenityKeys: q.amenities,
      vibe: signals['vibe'],
      queryText: _conversationText,
      cohortSignals: signals,
    );
    List<RentalProperty> serverRanked = const [];
    try {
      serverRanked = await _repo.search(criteria, limit: limit < 60 ? 60 : limit);
      // Hand the minted searchId to the provider so a later swipe/click/contact
      // on these cards can be labelled via POST /search/outcome.
      provider.setLastSearchId(_repo.lastSearchId);
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
    if (out.isEmpty) {
      return provider.recommendForTenant(provider.allProperties, q,
          limit: limit);
    }
    // Always give אתי a useful set to show: a strict filter (tight room band +
    // city + budget) can legitimately return only 1-3, but the user expects a
    // few options. Top up with the engine's CLOSEST near-misses (best-of-
    // everything, soft-gated → same-city / nearest room-count rank first),
    // deduped, up to [_kMinResults]. If the whole catalogue has fewer, we show
    // whatever exists.
    if (out.length < _kMinResults) {
      final seen = {for (final s in out) s.property.id};
      final relaxed =
          provider.recommendForTenant(provider.allProperties, q, limit: limit);
      for (final s in relaxed) {
        if (seen.add(s.property.id)) {
          out.add(s);
          if (out.length >= _kMinResults) break;
        }
      }
    }
    return out;
  }

  /// אתי always surfaces at least this many options when any exist — a single
  /// exact match reads as "nothing found" to a searcher, so we backfill with the
  /// closest near-misses.
  static const int _kMinResults = 4;

  // VERIFICATION GATE (fast-mode anti-hallucination): before showing anything,
  // confirm every result really matches what the user asked for, so אתי never
  // presents something wrong. Two gross-mismatch checks that the engine's soft
  // ranking could otherwise let through when stock is thin:
  //   • GEO — a flat grossly far from the requested town (name-gate leak).
  //   • BUDGET — a flat far over the stated ceiling isn't a "match".
  // Each check only prunes when something still remains (never invents empties),
  // and the honest "nothing here, but nearby…" flow catches a full wipe.
  // Splits the ranked candidates into strict matches (in-area AND in-budget) and
  // a labeled "nearby" backfill (just outside the town radius, or a little over
  // budget) used only to flesh out a thin shortlist. Anything grossly off — >2×
  // the town radius, or >35% over budget — is still dropped so אתי never presents
  // a flat 50km away or way over budget as if it fit.
  List<ScoredProperty> _verifyResults(List<ScoredProperty> results) {
    if (results.isEmpty) return results;
    final l10n = AppLocalizations.of(context)!;

    final city = _query.city?.trim();
    final loc = (city != null && city.isNotEmpty)
        ? GovData.instance.localityByName(city)
        : null;
    final strictKm =
        _query.intents.contains(SearchIntent.cityArea) ? 20.0 : 15.0;
    final wideKm = strictKm * 2; // still "nearby", just clearly labeled
    final cap = _query.maxPrice ?? 0;

    final strict = <ScoredProperty>[];
    final nearby = <ScoredProperty>[]; // relaxed, rank-ordered, note-tagged

    for (final r in results) {
      final km = loc == null
          ? 0.0
          : Geolocator.distanceBetween(
                  r.property.lat, r.property.lon, loc.lat, loc.lon) /
              1000;
      final price = r.property.price;
      final geoFar = loc != null && km > strictKm;
      final geoWayFar = loc != null && km > wideKm;
      final over = cap > 0 && price > 0 && price > cap;
      final wayOver = cap > 0 && price > 0 && price > cap * 1.35;

      // Grossly off — never surface (honest "nothing exact" instead).
      if (geoWayFar || wayOver) continue;

      if (!geoFar && !over) {
        strict.add(r);
        continue;
      }
      final notes = <String>[
        if (geoFar) l10n.searchChatScreenC911128e(km.round().toString(), city ?? ''),
        if (over) l10n.searchChatScreen2820c4fe,
      ];
      nearby.add(ScoredProperty(r.property, r.score, r.tags, r.trainKm, false,
          r.scorecard, notes.join(' · ')));
    }

    // Enough strict matches → show only those. Otherwise top up with the closest
    // labeled fallbacks so the seeker always gets a real shortlist to compare.
    if (strict.length >= _kCollapsedResults) return strict;
    return [
      ...strict,
      ...nearby.take((_kCollapsedResults - strict.length).clamp(0, nearby.length))
    ];
  }

  // Anti-hallucination: when NOTHING matches the exact request, look within [km]
  // of the searched city's centre with the SAME filters (budget/rooms/features
  // kept — only the town widened). Never invents a mismatch; returns [] if the
  // city centre is unknown or nothing within the radius fits.
  List<ScoredProperty> _nearbySameFilters(SearchQuery q, DatingProvider provider,
      {double km = 10}) {
    final city = q.city?.trim();
    if (city == null || city.isEmpty) return const [];
    final loc = GovData.instance.localityByName(city);
    if (loc == null) return const [];
    final near = provider.allProperties
        .where((p) =>
            Geolocator.distanceBetween(p.lat, p.lon, loc.lat, loc.lon) / 1000 <=
            km)
        .toList();
    if (near.isEmpty) return const [];
    // Same query WITHOUT the town name → the city gate won't re-exclude the
    // neighbours; budget / rooms / features still apply, so it's not a hallucination.
    final q2 = SearchQuery(
      minPrice: q.minPrice,
      maxPrice: q.maxPrice,
      minRooms: q.minRooms,
      maxRooms: q.maxRooms,
      propertyType: q.propertyType,
      amenities: q.amenities,
      requiredFeatures: q.requiredFeatures,
      transactionType: q.transactionType,
      nearTrain: q.nearTrain,
      intents: q.intents,
      weights: q.weights,
    );
    return _rankByLifestyle(_applyLifestyleFilter(
            provider.recommendForTenant(near, q2, limit: 40)))
        .take(10)
        .toList();
  }

  // Progressive relaxation for when nothing matches: widen budget, then drop soft
  // amenities + room floor, then (last resort) drop the city. So אתי always has
  // something close to show instead of dead-ending.
  List<({SearchQuery q, String note})> _wideningLadder(
      SearchQuery q, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final budget = q.maxPrice;
    final up = (double f) => budget == null ? null : (budget * f).round();
    return [
      (
        q: SearchQuery(
            city: q.city,
            neighborhood: q.neighborhood,
            minRooms: q.minRooms,
            maxPrice: up(1.25)),
        note: l10n.searchChatScreen55112a73
      ),
      (
        q: SearchQuery(city: q.city, maxPrice: up(1.6)),
        note: l10n.searchChatScreen917c8977
      ),
      (
        q: SearchQuery(maxPrice: up(1.6)),
        note: l10n.searchChatScreen0b5b99ea
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

  // The seeker's nearby-relevance profile — from their live query text plus any
  // captured persona (bio + important details). Drives which nearby-places
  // sections show in each result's "למה זו" preview (only what's relevant).
  NearbyProfile _seekerNearbyProfile() {
    // The SEARCH QUERY is authoritative for what the seeker wants RIGHT NOW:
    // "דירה באזור צעיר" must surface nightlife/dining/parks — NOT schools/gani/
    // synagogues leaked from a stale saved profile. Only when the query carries no
    // persona signal at all do we fall back to enriching with the stored profile.
    final fromQuery = NearbyProfile.fromText(_query.rawText);
    if (fromQuery.anySignal) return fromQuery;
    final tp = context.read<DatingProvider>().tenantProfile;
    return NearbyProfile.fromText('${_query.rawText} ${tp?.bio ?? ''} '
        '${(tp?.importantDetails ?? const <String>[]).join(' ')}');
  }

  double _religiosityBoost(Religiosity rel, RentalProperty p) {
    final area = LifestyleKnowledge.areaCharacter(
        neighborhood: p.neighborhood, city: p.city);
    if (area == null) return 0; // unknown area → neutral
    return LifestyleKnowledge.religiosityFit(rel, area);
  }

  String? _lifestyleNote() {
    final l10n = AppLocalizations.of(context)!;
    final relName = _persona['religiosity'];
    final rel = relName == null
        ? null
        : Religiosity.values.firstWhere((r) => r.name == relName,
            orElse: () => Religiosity.traditional);
    final parts = <String>[];
    if (rel != null) {
      final label = {
        'secular': l10n.searchChatScreenB6601495,
        'traditional': l10n.searchChatScreen50cb5eda,
        'religious': l10n.searchChatScreen21c1f153,
        'haredi': l10n.searchChatScreenFed27efc,
      };
      parts.add(l10n.searchChatScreenA4b6a21f(label[rel.name] ?? ''));
    }
    if (_needsElevator) {
      parts.add(l10n.searchChatScreen85c47725);
    }
    if (parts.isEmpty) return null;
    return l10n.searchChatScreen567bc622(parts.join(', '));
  }

  // The single most useful missing detail, as a question + quick-reply chips.
  (String, List<String>)? _clarifyingPrompt() {
    final l10n = AppLocalizations.of(context)!;
    if (_query.city == null) {
      return (l10n.searchChatScreenE3396557, [
        l10n.searchChatScreen2c1f2bbd,
        l10n.searchChatScreen8e0dfe1e,
        l10n.searchChatScreenCa1cc213,
        l10n.searchChatScreen3afe34bd,
      ]);
    }
    if (_query.maxPrice == null) {
      return (l10n.searchChatScreen73d294f3, [
        l10n.searchChatScreen808024f5,
        l10n.searchChatScreenBe87f690,
        l10n.searchChatScreenAe2323e0,
      ]);
    }
    if (_query.minRooms == null && _query.maxRooms == null) {
      return (l10n.searchChatScreen88a8e951, [
        l10n.searchChatScreen1f57228c,
        l10n.searchChatScreen535bb0c7,
        l10n.searchChatScreen0c3da33f,
      ]);
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
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _messages.add(_ChatMsg(
        role: 'assistant',
        isConsent: true,
        text: l10n.searchChatScreen32cd7c3b + l10n.searchChatScreenD5b92b5a,
      ));
    });
    _scrollToEnd();
  }

  Future<void> _resolveConsent(bool granted) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _consent = granted;
      _messages.removeWhere((m) => m.isConsent);
      _messages.add(_ChatMsg(
        role: 'assistant',
        text: granted
            ? l10n.searchChatScreenB2d293af
            : l10n.searchChatScreenB00e7ac4,
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

  Widget _floatingHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.30),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: l10n.searchChatScreen82c40bcf,
              icon: Icon(IconsaxPlusLinear.refresh_2,
                  color: AppColors.textSecondary, size: 20),
              onPressed: _resetConversation,
            ),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: l10n.searchChatScreenE13c91de,
              icon: Icon(IconsaxPlusLinear.clock,
                  color: AppColors.textSecondary, size: 19),
              onPressed: _showSearchHistory,
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _botName(context),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.searchChatScreenFaae8713,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/images/eti.jpg', fit: BoxFit.cover),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        body: Stack(
          children: [
            // Layer 1: Scrollable content extending underneath the floating header controls
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    topInset + 145,
                    12,
                    95 + bottomInset,
                  ),
                  itemCount: _messages.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _messages.length) return _Typing();
                    final isLast = i == _messages.length - 1;
                    final bubble = _bubble(_messages[i]);
                    return isLast ? _FadeSlideIn(child: bubble) : bubble;
                  },
                ),
              ),
            ),
            // Layer 2: Subtle Top Gradient Overlay (fades content into page background color at top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset + 150,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.cloud,
                        AppColors.cloud.withValues(alpha: 0.85),
                        AppColors.cloud.withValues(alpha: 0.4),
                        AppColors.cloud.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.4, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Layer 3: Floating Header Controls Overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _floatingHeader(context, l10n),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                      child: Center(
                        child: SpeedModeSlider(
                          immediate: _immediateMode,
                          onChanged: _setImmediateMode,
                        ),
                      ),
                    ),
                    _criteriaBar(),
                  ],
                ),
              ),
            ),
            // Layer 4: Subtle Bottom Gradient Overlay (fades content into page background color at bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: bottomInset + 90,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppColors.cloud,
                        AppColors.cloud.withValues(alpha: 0.85),
                        AppColors.cloud.withValues(alpha: 0.4),
                        AppColors.cloud.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.4, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Layer 5: Bottom Input Bar Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _inputBar(),
            ),
          ],
        ),
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
            GestureDetector(
              onLongPress: () => _showMsgActions(m),
              child: Container(
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
            ),
          if (m.scored.isNotEmpty) _resultList(m),
          if (m.whatIfs.isNotEmpty) _whatIfRow(m.whatIfs),
          if (m.chips.isNotEmpty) _chipsRow(m.chips),
          if (m.isConsent) _consentButtons(),
          if (m.locationRequest) _locationButtons(),
        ],
      ),
    );
  }

  // Distinct, richer style than plain chips: each is an ACTIONABLE relaxation with
  // its quantified payoff ("עד 9,600 ₪ · עוד 12 דירות").
  Widget _whatIfRow(List<WhatIfSuggestion> ifs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < ifs.length; i++)
            _AnimatedChip(
              delayMs: i * 70,
              child: GestureDetector(
                onTap: _busy ? null : () => _onWhatIfTap(ifs[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.45)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(ifs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('· ${ifs[i].gainText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5)),
                    ),
                  ]),
                ),
              ),
            ),
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
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        ElevatedButton.icon(
          onPressed: _busy ? null : _shareLocationNow,
          icon: const Icon(IconsaxPlusLinear.gps, size: 18),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          label: Text(l10n.searchChatScreen39e281e5),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _messages.removeWhere((m) => m.locationRequest);
                    _messages.add(_ChatMsg(
                        role: 'assistant',
                        text: l10n.searchChatScreenFab66f7b));
                  }),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: BorderSide(color: AppColors.borderLight),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(l10n.searchChatScreen542039da),
        ),
      ]),
    );
  }

  Widget _consentButtons() {
    final l10n = AppLocalizations.of(context)!;
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
          child: Text(l10n.searchChatScreen10289345),
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
          child: Text(l10n.searchChatScreen98c8a5b8),
        ),
      ]),
    );
  }

  // Long-press actions on a chat bubble: copy (any message), edit (own only).
  Future<void> _showMsgActions(_ChatMsg m) async {
    final l10n = AppLocalizations.of(context)!;
    final isUser = m.role == 'user';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 6),
          ListTile(
            leading: Icon(IconsaxPlusLinear.copy, color: AppColors.primary),
            title: Text(l10n.chatMsgCopy,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: m.text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  duration: const Duration(milliseconds: 1500),
                  content: Text(l10n.chatMsgCopied)));
            },
          ),
          if (isUser)
            ListTile(
              leading: Icon(IconsaxPlusLinear.edit_2, color: AppColors.primary),
              title: Text(l10n.chatMsgEdit,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l10n.chatMsgEditHint,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _editingMsg = m;
                  _input.text = m.text;
                  _input.selection = TextSelection.collapsed(
                      offset: _input.text.length);
                });
              },
            ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Widget _inputBar() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      // Floating, rounded, detached ≥13px from every edge.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 6, 13, 13),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Editing banner — makes the replace-and-regenerate behavior visible
          // and cancelable before sending.
          if (_editingMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(IconsaxPlusLinear.edit_2,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l10n.chatMsgEditingBanner,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark)),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _editingMsg = null;
                    _input.clear();
                  }),
                  child: const Icon(Icons.close_rounded,
                      size: 17, color: AppColors.textSecondary),
                ),
              ]),
            ),
          Container(
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
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.searchChatScreenD5d02271,
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
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
                  child: const Icon(IconsaxPlusLinear.voice_square,
                      color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ),
        ]),
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
  _AssistantPropertyCard(
      {required this.scored, required this.onTap, this.nearbyProfile});
  final ScoredProperty scored;
  final VoidCallback onTap;
  final NearbyProfile? nearbyProfile; // seeker relevance for the nearby dropdown

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
          border: Border.all(color: AppColors.border, width: 1),
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
                            Icon(IconsaxPlusBold.verify,
                                size: 13, color: AppColors.success),
                            const SizedBox(width: 3),
                            Text(l10n.searchChatScreen7de9ac58,
                                style: const TextStyle(
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
                          icon: saved ? IconsaxPlusBold.heart : IconsaxPlusLinear.heart,
                          color: saved ? AppColors.coral : AppColors.navy,
                          onTap: () =>
                              context.read<DatingProvider>().toggleSave(p.id),
                        ),
                        const SizedBox(width: 8),
                        _circleAction(
                          icon: IconsaxPlusLinear.export_1,
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
                  // Relaxed-backfill badge: this flat is nearby / a touch over
                  // budget, not an exact match — say so plainly on the card.
                  if (scored.fallbackNote != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(IconsaxPlusLinear.location,
                            size: 14, color: AppColors.warningDeep),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(scored.fallbackNote!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warningDeep)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                          label: l10n.searchChatScreenF0f71ca3(p.roomsLabel)),
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: l10n.searchChatScreen615d28b8(p.sizeM2.toString())),
                      // Geo "X מ׳ from …" tags moved into "למה זו" (above the data
                      // sources); only plain facts stay on this quick-facts row.
                      for (final t in scored.tags.where((t) => !isGeoTag(t))) ...[
                        const SizedBox(width: 8),
                        _InfoChip(label: _fitTagLabel(t, l10n)),
                      ],
                    ]),
                  ),
                  // Expandable transparency panel — the data-grounded "why this
                  // one" breakdown, with a RELEVANT-ONLY nearby-places dropdown at
                  // the very bottom (only what this seeker's search implies).
                  if (scored.scorecard != null)
                    ScorecardView(
                      card: scored.scorecard!,
                      lat: scored.property.lat,
                      lon: scored.property.lon,
                      city: scored.property.city,
                      nearbyProfile: nearbyProfile,
                    ),
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

/// DatingProvider.recommendForTenant packs the fit-score tag as a bare
/// "NN%" (locale-neutral — the provider has no BuildContext to localize
/// with); re-label it as a localized "N% match" string here. Other tags
/// (highlights) pass through unchanged.
final RegExp _bareFitPct = RegExp(r'^(\d+)%$');
String _fitTagLabel(String t, AppLocalizations l10n) {
  final m = _bareFitPct.firstMatch(t);
  if (m == null) return t;
  return l10n.datingProviderFitPercentLabel(m.group(1)!);
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
        color: AppColors.slate100,
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
  _Typing();
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
