import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/event_service.dart';
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

const _botName = 'נועה';

class _ChatMsg {
  _ChatMsg({
    required this.role,
    this.text = '',
    this.scored = const [],
    this.chips = const [],
    this.isConsent = false,
  });
  final String role; // 'user' | 'assistant'
  final String text;
  final List<ScoredProperty> scored;
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
  bool? _consent;
  bool _consentAsked = false;
  Map<String, dynamic>? _pendingPersona;

  // Gentle persona-building questions, asked one at a time.
  static const _personaQuestions = <(String, String)>[
    ('household', 'רגע לפני שנצלול — זה בשבילך לבד, לזוג, או עם שותפים? 🙂'),
    ('vibe', 'ומה הכי חשוב לך בסביבה — שקט וירוק, קרוב לעבודה/ללימודים, או דווקא בלב העניינים?'),
    ('timing', 'מתי בערך בא לך להיכנס? אין שום לחץ, רק שאדע לסנן נכון.'),
  ];

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
      _pendingPersonaKey = null;
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
    if (_query.city != null) {
      items.add(_removableChip('📍 ${_query.city}', () => _drop(city: true)));
    }
    if (_query.minRooms != null) {
      final r = _query.minRooms! % 1 == 0
          ? _query.minRooms!.toInt().toString()
          : _query.minRooms!.toString();
      items.add(_removableChip('🛏️ $r+ חד׳', () => _drop(rooms: true)));
    }
    if (_query.maxPrice != null) {
      items.add(
          _removableChip('💰 עד ₪${_money(_query.maxPrice!)}', () => _drop(price: true)));
    }
    if (_query.nearTrain) {
      items.add(_removableChip('🚉 ליד הרכבת', () => _drop(train: true)));
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

  void _drop(
      {bool city = false,
      bool rooms = false,
      bool price = false,
      bool train = false,
      String? amenity}) {
    setState(() {
      _query = SearchQuery(
        city: city ? null : _query.city,
        maxPrice: price ? null : _query.maxPrice,
        minRooms: rooms ? null : _query.minRooms,
        amenities: {..._query.amenities}..removeWhere((k) => k == amenity),
        nearTrain: train ? false : _query.nearTrain,
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
    final results = SmartSearch.rank(
        context.read<DatingProvider>().allProperties, _query,
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

  // ── conversation ──────────────────────────────────────────────────────────

  bool _wantsResultsNow(String t) => RegExp(
        r'תראה|הצג|חפש|מצא|דירות עכשיו|בוא נראה|show|search',
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

    // Store the answer to the last persona question we asked, if any.
    if (_pendingPersonaKey != null) {
      _persona[_pendingPersonaKey!] = text;
      _pendingPersonaKey = null;
    }

    // Structured extraction (LLM) augments the on-device keyword parser.
    Map<String, dynamic> llm = const {};
    try {
      final r = await _service.extractPropertyFields(text, currentFields: {});
      llm = r.fields;
    } catch (_) {}
    _query = _merge(_query, SmartSearch.parse(text, llm: llm));

    // Decide: keep getting to know them, or show listings.
    final hasIntent = !_query.isEmpty;
    final nextQ = _nextPersonaQuestion();
    final shouldSearch =
        hasIntent && (_searched || _wantsResultsNow(text) || _userTurns >= 2 || nextQ == null);

    final warm = await _warmReply(searching: shouldSearch);

    List<ScoredProperty> results = const [];
    bool anyExact = false;
    if (shouldSearch) {
      results = SmartSearch.rank(provider.allProperties, _query, limit: 10);
      anyExact = results.any((r) => r.exact);
    }

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMsg(role: 'assistant', text: warm));

      if (!shouldSearch) {
        // Give them room to explain — ask one gentle follow-up.
        if (nextQ != null) {
          _pendingPersonaKey = nextQ.$1;
          _messages.add(_ChatMsg(role: 'assistant', text: nextQ.$2));
        }
      } else {
        _messages.add(_ChatMsg(
          role: 'assistant',
          text: '🔎 אז ככה הבנתי אותך:\n${_query.describe()}',
        ));
        if (results.isEmpty) {
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: 'עוד לא צף לי משהו מושלם — בוא ננסה אזור אחר או תקציב קצת גמיש?',
          ));
        } else {
          _messages.add(_ChatMsg(
            role: 'assistant',
            text: anyExact
                ? 'מצאתי כמה דירות שממש מתאימות לך 🎯'
                : 'אין התאמה מושלמת ברגע זה, אבל אלה הכי קרובות עבורך:',
            scored: results,
            chips: _refineChips(),
          ));
        }
        _searched = true;
      }
      _busy = false;
    });
    _scrollToEnd();

    if (shouldSearch && results.isNotEmpty) _maybeCapturePersona(results.length);
  }

  String? _pendingPersonaKey;

  (String, String)? _nextPersonaQuestion() {
    for (final q in _personaQuestions) {
      if (!_persona.containsKey(q.$1)) return q;
    }
    return null;
  }

  int _warmIdx = 0;
  Future<String> _warmReply({required bool searching}) async {
    // Try Gemini for a natural reply; fall back to warm, varied copy.
    try {
      final history = _messages
          .where((m) => !m.isConsent && m.text.isNotEmpty)
          .map((m) => AssistantTurn(role: m.role, text: m.text))
          .toList();
      final reply = await _service.chat(history);
      final t = reply.reply.trim();
      if (t.isNotEmpty && t.length < 240) return t;
    } catch (_) {}

    if (searching) {
      const lines = [
        'יאללה, תן לי רגע לרוץ על האפשרויות בשבילך... ✨',
        'אהבתי. בוא נראה מה מצאתי שמתאים לך 👇',
        'סבבה, יש לי תמונה טובה — הנה מה שעולה לי:',
      ];
      return lines[(_warmIdx++) % lines.length];
    }
    const lines = [
      'כיף, נשמע שיש לך כיוון 🙌',
      'הבנתי אותך, תודה ששיתפת.',
      'מגניב, זה עוזר לי להכיר אותך טוב יותר.',
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
        maxPrice: b.maxPrice ?? a.maxPrice,
        minRooms: b.minRooms ?? a.minRooms,
        amenities: {...a.amenities, ...b.amenities},
        nearTrain: a.nearTrain || b.nearTrain,
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
            child: ListView.builder(
              controller: _scroll,
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
      child: Container(
        color: AppColors.background,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'ספר לי במילים שלך...',
                filled: true,
                fillColor: const Color(0xFFEDF1F5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_input.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: Icon(IconsaxPlusLinear.send_1,
                  color: AppColors.textOnPrimary, size: 22),
            ),
          ),
        ]),
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
                      media: p.primaryMedia,
                      fallback: Container(
                        color: AppColors.primaryLight2,
                        child: Icon(IconsaxPlusLinear.building,
                            color: AppColors.primary, size: 48),
                      ),
                      fit: BoxFit.cover,
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
