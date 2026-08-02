import 'dart:async';
import 'dart:convert';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/property_draft_builder.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_capture_screen.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/assistant_screen.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "עזרא" — the landlord's personal assistant, as a full CHAT surface designed
/// to look EXACTLY like the tenant assistant אתי: the same light `cloud`
/// canvas, white/teal message bubbles (18/4-tail radius), typing indicator,
/// staggered quick-reply chips, and floating rounded input bar. The heavy
/// lifting is the SAME shared engine the voice orb uses ([AssistantService],
/// [buildPropertyFromErikDraft]); the voice orb ([AssistantScreen]) is a mode
/// reachable from here and shares the same transcript.
class ErikChatScreen extends StatefulWidget {
  const ErikChatScreen({super.key});

  @override
  State<ErikChatScreen> createState() => _ErikChatScreenState();
}

class _ErikChatScreenState extends State<ErikChatScreen> {
  final _service = AssistantService();
  final _picker = ImagePicker();
  final _storage = StorageService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<_ErikMsg> _messages = [];
  final List<String> _photoUrls = [];
  // A 360 tour captured in-chat, attached to the listing on publish.
  PropertyPanoramaTour? _panoramaTour;
  Map<String, dynamic>? _draft;

  bool _busy = false; // waiting on Erik
  bool _publishing = false;
  bool _speakReplies = false; // read replies aloud (older users) — off by default
  bool _picking = false;
  Timer? _streamTimer;

  String get _uid {
    // Fail-soft: FirebaseAuth.instance throws if no app is initialised (e.g.
    // tests / a cold boot before Firebase). A guest transcript is fine then.
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    } catch (_) {
      return 'guest';
    }
  }

  String get _storeKey => 'erik_transcript_$_uid';

  static const _botName = 'עזרא';

  static const _greeting =
      'שלום, נעים מאוד. קוראים לי עזרא ואני כאן כדי לעזור לך.\n'
      'אפשר לספר לי על דירה שתרצה להשכיר ואבנה לך מודעה, לעזור לנסח תיאור, '
      'לתמחר, או פשוט לענות על שאלות. מה שנוח לך — לכתוב או לדבר.';

  // Concrete example prompts, shown as chips on the welcome message (like אתי).
  static const _starters = [
    'אני רוצה לפרסם דירה חדשה',
    'עזור לי לנסח תיאור לדירה',
    'מה כדאי לצלם בדירה?',
    'איך לתמחר נכון?',
  ];

  @override
  void initState() {
    super.initState();
    _service.ttsVoice = 'onyx'; // Erik — a natural male voice (אתי stays 'coral')
    _loadTranscript();
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _service.dispose(); // owns AudioPlayer/recorder/TTS/HttpClient — don't leak
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Transcript (shared with the voice orb via the same key) ────────────────

  Future<void> _loadTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        final turns = list.whereType<Map>().map(
            (e) => AssistantTurn.fromJson(Map<String, dynamic>.from(e)));
        _messages
          ..clear()
          ..addAll(turns.map((t) => _ErikMsg(
                role: t.role,
                text: t.text,
                mediaUrls: t.mediaUrls ?? const [],
              )));
      }
    } catch (_) {}
    if (_messages.isEmpty) {
      _messages.add(_ErikMsg(
          role: 'assistant',
          text: _greeting,
          isWelcome: true,
          chips: _starters));
    }
    if (mounted) setState(() {});
    _jumpToEnd();
  }

  Future<void> _saveTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final turns = _messages
          // Never persist the welcome turn: on reload it would lose its starter
          // chips AND get replayed to the backend as wasted history.
          .where((m) => m.text.trim().isNotEmpty && !m.isWelcome)
          .map((m) => AssistantTurn(
                role: m.role,
                text: m.text,
                mediaUrls: m.mediaUrls.isEmpty ? null : m.mediaUrls,
              ).toJson())
          .toList();
      await prefs.setString(_storeKey, jsonEncode(turns));
    } catch (_) {}
  }

  Future<void> _newConversation() async {
    HapticFeedback.selectionClick();
    _streamTimer?.cancel();
    setState(() {
      _messages
        ..clear()
        ..add(_ErikMsg(
            role: 'assistant',
            text: _greeting,
            isWelcome: true,
            chips: _starters));
      _draft = null;
      _photoUrls.clear();
      _busy = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storeKey);
    } catch (_) {}
  }

  // ── Send / receive ─────────────────────────────────────────────────────────

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    HapticFeedback.lightImpact();
    _input.clear();
    setState(() {
      _messages.add(_ErikMsg(role: 'user', text: text));
      _busy = true;
    });
    _saveTranscript();
    _scrollToEnd();

    if (!_service.isConfigured) {
      _finishBusy(_ErikMsg(
        role: 'assistant',
        text: 'העוזר האישי אינו זמין כרגע. אפשר לנסות שוב מאוחר יותר.',
      ));
      return;
    }

    try {
      final history = _messages
          .where((m) => !m.isWelcome && m.text.trim().isNotEmpty)
          .map((m) => AssistantTurn(
                role: m.role,
                text: m.text,
                mediaUrls: m.mediaUrls.isEmpty ? null : m.mediaUrls,
              ))
          .toList();
      final reply = await _service.chat(history);
      if (!mounted) return;
      if (reply.propertyDraft != null) _draft = reply.propertyDraft;
      final msg = _ErikMsg(
        role: 'assistant',
        text: reply.reply,
        chips: reply.suggestions,
        listings: reply.listings,
        draft: reply.propertyDraft,
      );
      _finishBusy(msg, stream: true);
      if (_speakReplies && reply.reply.trim().isNotEmpty) {
        _service.speak(reply.reply);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erik chat failed: $e');
      _finishBusy(_ErikMsg(
        role: 'assistant',
        text: 'סליחה, הייתה תקלה רגעית. אפשר לנסות שוב.',
        canRetry: true,
        retryText: text,
      ));
    }
  }

  void _finishBusy(_ErikMsg msg, {bool stream = false}) {
    setState(() {
      _busy = false;
      if (stream) {
        msg.streaming = true;
        msg.shownWords = 0;
      }
      _messages.add(msg);
    });
    _saveTranscript();
    _scrollToEnd();
    if (stream) _startStreaming(msg);
  }

  // A brief chunked reveal — enough to feel alive, but CAPPED to ~0.4s total
  // (not 38ms/word, which added ~1.5s of fake delay on a long reply). Short
  // replies appear at once. Scrolls once at the end, not per tick (no jank).
  void _startStreaming(_ErikMsg msg) {
    _streamTimer?.cancel();
    final total = msg.words.length;
    if (total <= 4) {
      msg.streaming = false;
      _scrollToEnd();
      return;
    }
    const steps = 12; // whole reveal finishes in ~steps * 32ms ≈ 0.4s
    final perStep = (total / steps).ceil();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 32), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        msg.shownWords += perStep;
        if (msg.shownWords >= total) {
          msg.shownWords = total;
          msg.streaming = false;
          t.cancel();
        }
      });
      if (!msg.streaming) _scrollToEnd();
    });
  }

  void _onChipTap(String chip) {
    HapticFeedback.selectionClick();
    _send(chip);
  }

  // ── Media ───────────────────────────────────────────────────────────────────

  Future<void> _pickMedia(ImageSource source, {bool video = false}) async {
    if (_picking) return;
    Navigator.of(context).maybePop(); // close the media sheet if open
    setState(() => _picking = true);
    try {
      final XFile? file = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source, imageQuality: 85);
      if (file == null) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      if (!mounted) return;
      final path = remoteUrl ?? localPath;
      // Just add the photo and let the draft card update live (it shows the new
      // count + keeps its publish button) — no chat spam, the card stays put so
      // the user can publish from the very same card. If there's no pending
      // draft, drop a light user bubble so the attachment is still visible.
      setState(() {
        _photoUrls.add(path);
        _picking = false;
        if (_draft == null) {
          _messages.add(_ErikMsg(
            role: 'user',
            text: video ? '🎥 סרטון נוסף' : '📷 תמונה נוספה',
            mediaUrls: [path],
          ));
        }
      });
      _saveTranscript();
      _snack(video ? 'סרטון נוסף ✓' : 'תמונה נוספה ✓ (${_photoUrls.length})');
      if (_draft == null) _scrollToEnd();
    } catch (e) {
      if (kDebugMode) debugPrint('Erik pickMedia failed: $e');
      if (mounted) {
        setState(() => _picking = false);
        _snack('לא הצלחתי לצרף את הקובץ. אפשר לנסות שוב.');
      }
    }
  }

  void _openMediaSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 16),
              _mediaTile(IconsaxPlusBold.camera, 'צלם תמונה',
                  () => _pickMedia(ImageSource.camera)),
              _mediaTile(IconsaxPlusBold.gallery, 'בחר מהגלריה',
                  () => _pickMedia(ImageSource.gallery)),
              _mediaTile(IconsaxPlusBold.video, 'סרטון מהגלריה',
                  () => _pickMedia(ImageSource.gallery, video: true)),
              _mediaTile(IconsaxPlusBold.rotate_left, 'סיור 360°', _capture360),
            ],
          ),
        ),
      ),
    );
  }

  // Capture a 360 tour right from the assistant — reuses the full capture flow
  // and holds the result until publish, when it's attached to the listing.
  Future<void> _capture360() async {
    Navigator.of(context).maybePop(); // close the media sheet
    final tour = await Navigator.of(context).push<PropertyPanoramaTour>(
      MaterialPageRoute(
        builder: (_) => PanoramaCaptureScreen(initial: _panoramaTour),
      ),
    );
    if (tour == null || tour.isEmpty || !mounted) return;
    setState(() => _panoramaTour = tour);
    _snack('סיור 360° נוסף ✓');
  }

  Widget _mediaTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      title: Text(label,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w700)),
    );
  }

  // ── Publish ─────────────────────────────────────────────────────────────────

  Future<void> _publish(Map<String, dynamic> draft) async {
    if (_publishing) return;
    if (_photoUrls.isEmpty) {
      setState(() {
        _messages.add(_ErikMsg(
          role: 'assistant',
          text:
              'רק רגע — כדי לפרסם צריך לפחות תמונה אחת של הדירה. אפשר לצלם עכשיו או לבחור מהטלפון.',
        ));
      });
      _scrollToEnd();
      _openMediaSheet();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _publishing = true);
    try {
      final provider = context.read<DatingProvider>();
      final ownerName = provider.tenantProfile?.name ?? '';
      var property = await buildPropertyFromErikDraft(
        draft,
        ownerName: ownerName,
        photoUrls: _photoUrls,
      );
      // Attach a 360 tour captured in-chat, if any.
      if (_panoramaTour != null && !_panoramaTour!.isEmpty) {
        property = property.copyWith(panoramaTour: _panoramaTour);
      }
      await provider.addLandlordProperty(property);
      if (!mounted) return;
      final addr = [
        property.street,
        property.streetNumber > 0 ? '${property.streetNumber}' : '',
        property.city,
      ].where((e) => e.isNotEmpty).join(' ');
      setState(() {
        _draft = null;
        _photoUrls.clear();
        _panoramaTour = null;
        _publishing = false;
        for (final m in _messages) {
          m.draft = null; // clear the pending card so it can't publish twice
        }
        _messages.add(_ErikMsg(
          role: 'assistant',
          text:
              'מצוין! פרסמתי את הדירה שלך${addr.isNotEmpty ? ' ב$addr' : ''}, היא כבר באוויר. 🎉\n'
              'אפשר להוסיף עוד תמונות בכל רגע מהמסך "הדירות שלי". אני כאן אם תצטרך עוד משהו.',
        ));
      });
      _saveTranscript();
      _scrollToEnd();
    } catch (e) {
      if (kDebugMode) debugPrint('Erik publish failed: $e');
      if (!mounted) return;
      setState(() => _publishing = false);
      _snack('הייתה בעיה בפרסום. אפשר לנסות שוב, או לערוך בטופס המלא.');
    }
  }

  void _editInForm(Map<String, dynamic> draft) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddPropertyScreen(initialDraft: draft),
    ));
  }

  // ── Voice mode (the premium orb, shares the transcript) ────────────────────

  Future<void> _openVoice() async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const AssistantScreen(),
    ));
    _streamTimer?.cancel();
    await _loadTranscript();
  }

  // ── Scroll / misc ────────────────────────────────────────────────────────────

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Build (identical layout language to אתי's chat) ──────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0.5,
          titleSpacing: 0,
          title: Row(children: [
            const SizedBox(width: 12),
            // Erik has no photo — a primary orb with a mic, framed like אתי's.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryLight, AppColors.primary],
                ),
                border: Border.all(color: AppColors.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Icon(IconsaxPlusBold.microphone_2,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_botName · העוזר האישי',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Row(children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: AppColors.success, shape: BoxShape.circle)),
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
              tooltip: _speakReplies ? 'הקראה פעילה' : 'הקראה כבויה',
              icon: Icon(
                  _speakReplies
                      ? IconsaxPlusBold.volume_high
                      : IconsaxPlusLinear.volume_slash,
                  color: _speakReplies ? AppColors.primary : AppColors.textSecondary,
                  size: 24),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _speakReplies = !_speakReplies);
                _snack(_speakReplies ? 'עזרא יקריא את התשובות' : 'הקראה כבויה');
              },
            ),
            IconButton(
              tooltip: 'שיחה חדשה',
              icon: Icon(IconsaxPlusLinear.refresh_2,
                  color: AppColors.textSecondary, size: 24),
              onPressed: _newConversation,
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
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
                  final bubble = _bubble(_messages[i], isLast);
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

  Widget _bubble(_ErikMsg m, bool isLast) {
    final isUser = m.role == 'user';
    final text = m.streaming ? m.streamedText : m.text;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
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
              child: Text(text,
                  style: TextStyle(
                      color: isUser
                          ? AppColors.textOnPrimary
                          : AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.45)),
            ),
          if (m.draft != null && !m.streaming) _draftCard(m.draft!),
          if (m.listings.isNotEmpty && !m.streaming)
            ...m.listings.take(3).map(_listingCard),
          if (!isUser && !m.streaming && m.chips.isNotEmpty) _chipsRow(m.chips),
          if (m.canRetry && !m.streaming) _retryButton(m.retryText),
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

  Widget _retryButton(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton.icon(
        onPressed: () => _send(text),
        icon: Icon(IconsaxPlusLinear.refresh, size: 18, color: AppColors.primary),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        label: const Text('נסה שוב'),
      ),
    );
  }

  // ── Inline listing-draft preview card (light, אתי card language) ────────────

  Widget _draftCard(Map<String, dynamic> draft) {
    String s(String key) => (draft[key]?.toString().trim() ?? '');
    final street = s('street');
    final num = s('streetNumber');
    final city = s('city');
    final addr = [street, num, city].where((e) => e.isNotEmpty).join(' ');
    final rows = <(IconData, String)>[
      if (addr.isNotEmpty) (IconsaxPlusBold.location, addr),
      if (s('rooms').isNotEmpty) (IconsaxPlusBold.home_2, '${s('rooms')} חדרים'),
      if (s('sizeM2').isNotEmpty) (IconsaxPlusBold.maximize_4, '${s('sizeM2')} מ״ר'),
      if (s('floor').isNotEmpty) (IconsaxPlusBold.buildings_2, 'קומה ${s('floor')}'),
      if (s('price').isNotEmpty) (IconsaxPlusBold.money_recive, '₪${s('price')} לחודש'),
      if (s('entryDate').isNotEmpty) (IconsaxPlusBold.calendar_1, 'כניסה: ${s('entryDate')}'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: MediaQuery.of(context).size.width * 0.82,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
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
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryLight2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(IconsaxPlusBold.home_trend_up,
                  color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 10),
            Text('טיוטת מודעה מוכנה',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  Icon(r.$1, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.$2,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              )),
          // Tappable "add photos" affordance — the natural way to attach photos
          // AFTER the details are in, without having to hit publish and be
          // rejected first.
          ScaleBounce(
            onTap: _openMediaSheet,
            scaleDownTo: 0.98,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: _photoUrls.isEmpty
                    ? AppColors.primaryLight2
                    : AppColors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _photoUrls.isEmpty
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : AppColors.success.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Icon(
                    _photoUrls.isEmpty
                        ? IconsaxPlusBold.camera
                        : IconsaxPlusBold.gallery,
                    color:
                        _photoUrls.isEmpty ? AppColors.primary : AppColors.success,
                    size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      _photoUrls.isEmpty
                          ? 'הוסף תמונות של הדירה'
                          : '${_photoUrls.length} תמונות · הוסף עוד',
                      style: TextStyle(
                          color: _photoUrls.isEmpty
                              ? AppColors.primaryDark
                              : AppColors.success,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                ),
                Icon(IconsaxPlusLinear.add,
                    color:
                        _photoUrls.isEmpty ? AppColors.primary : AppColors.success,
                    size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ScaleBounce(
                onTap: _publishing ? null : () => _publish(draft),
                scaleDownTo: 0.97,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _publishing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : Text('פרסם עכשיו',
                            style: TextStyle(
                                color: AppColors.textOnPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ScaleBounce(
              onTap: () => _editInForm(draft),
              scaleDownTo: 0.97,
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(children: [
                  Icon(IconsaxPlusLinear.edit_2,
                      color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 7),
                  Text('עריכה',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _listingCard(AssistantListing l) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      width: MediaQuery.of(context).size.width * 0.82,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primaryLight2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(IconsaxPlusBold.building_4, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              if (l.subtitle != null)
                Text(l.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              if (l.price != null)
                Text('₪${l.price}',
                    style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Input bar (identical to אתי's floating rounded bar) ─────────────────────

  Widget _inputBar() {
    return SafeArea(
      top: false,
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
              // Attach media (+) — add photos/video any time, not only from the
              // draft card. Outlined so it reads as secondary to send/voice.
              GestureDetector(
                onTap: _openMediaSheet,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight2,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.30)),
                  ),
                  child: Icon(IconsaxPlusLinear.add,
                      color: AppColors.primary, size: 24),
                ),
              ),
              const SizedBox(width: 6),
              // Voice-conversation button → opens the premium orb visualizer.
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
      ),
    );
  }
}

/// A single chat message with per-message UI state (streaming, chips, draft).
class _ErikMsg {
  _ErikMsg({
    required this.role,
    required this.text,
    this.mediaUrls = const [],
    this.chips = const [],
    this.listings = const [],
    this.draft,
    this.isWelcome = false,
    this.canRetry = false,
    this.retryText = '',
  });

  final String role; // 'user' | 'assistant'
  final String text;
  final List<String> mediaUrls;
  final List<String> chips;
  final List<AssistantListing> listings;
  Map<String, dynamic>? draft;
  final bool isWelcome;
  final bool canRetry;
  final String retryText;

  // Streaming reveal state.
  bool streaming = false;
  int shownWords = 0;
  List<String> get words => text.split(' ');
  String get streamedText => words.take(shownWords).join(' ');
}

// ── Shared animation widgets, copied 1:1 from אתי's chat so the two surfaces
//    are visually identical. ────────────────────────────────────────────────

/// Quick-reply chip that springs in (fade + scale + rise), staggered by index.
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

/// Gentle fade + slide-up for the newest bubble.
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

/// Three-dot "Erik is typing" bubble — identical to אתי's.
class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
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
