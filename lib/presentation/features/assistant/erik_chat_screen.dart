import 'dart:async';
import 'dart:convert';

import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/property_draft_builder.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/assistant/erik_design.dart';
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

/// "אריק" — the landlord's personal assistant, as a full CHAT surface (on par
/// with the tenant assistant אתי): a scrollable conversation with streaming
/// replies, a typing indicator, quick-reply chips, an inline listing-draft
/// preview, and a one-tap voice mode (the premium orb) — all in Erik's calm,
/// dark, high-legibility identity built for older users.
///
/// The heavy lifting (Gemini chat, draft building, TTS) is the SAME shared
/// engine the voice orb uses ([AssistantService], [buildPropertyFromErikDraft]);
/// this screen is the text-first surface over it. The voice orb
/// ([AssistantScreen]) is reachable as a mode and shares the same transcript.
class ErikChatScreen extends StatefulWidget {
  const ErikChatScreen({super.key});

  @override
  State<ErikChatScreen> createState() => _ErikChatScreenState();
}

class _ErikChatScreenState extends State<ErikChatScreen>
    with TickerProviderStateMixin {
  final _service = AssistantService();
  final _picker = ImagePicker();
  final _storage = StorageService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  final List<_ErikMsg> _messages = [];
  final List<String> _photoUrls = [];
  Map<String, dynamic>? _draft;

  bool _busy = false; // waiting on Erik
  bool _publishing = false;
  bool _speakReplies = false; // read replies aloud (older users) — off by default
  bool _picking = false;
  Timer? _streamTimer;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _storeKey => 'erik_transcript_$_uid';

  static const _greeting =
      'שלום, נעים מאוד. קוראים לי אריק ואני כאן כדי לעזור לך.\n'
      'אפשר לספר לי על דירה שתרצה להשכיר ואבנה לך מודעה, לעזור לנסח תיאור, '
      'לתמחר, או פשוט לענות על שאלות. מה שנוח לך — לכתוב או לדבר.';

  // Concrete example prompts, shown on the welcome screen (like אתי's starters).
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
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
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
      _messages.add(_ErikMsg(role: 'assistant', text: _greeting, isWelcome: true));
    }
    if (mounted) setState(() {});
    _jumpToEnd();
  }

  Future<void> _saveTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final turns = _messages
          .where((m) => m.text.trim().isNotEmpty)
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
        ..add(_ErikMsg(role: 'assistant', text: _greeting, isWelcome: true));
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
        suggestions: reply.suggestions,
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

  // Word-by-word reveal (ported from אתי) — cheap, big perceived-speed win.
  void _startStreaming(_ErikMsg msg) {
    _streamTimer?.cancel();
    final total = msg.words.length;
    if (total <= 1) {
      msg.streaming = false;
      return;
    }
    _streamTimer = Timer.periodic(const Duration(milliseconds: 38), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        msg.shownWords += 1;
        if (msg.shownWords >= total) {
          msg.streaming = false;
          t.cancel();
        }
      });
      _scrollToEnd();
    });
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
        setState(() => _picking = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      final path = remoteUrl ?? localPath;
      final wasFirst = _photoUrls.isEmpty;
      setState(() {
        _photoUrls.add(path);
        _picking = false;
        _messages.add(_ErikMsg(
          role: 'user',
          text: video ? '🎥 סרטון נוסף' : '📷 תמונה נוספה',
          mediaUrls: [path],
        ));
        _messages.add(_ErikMsg(
          role: 'assistant',
          text: 'קיבלתי, תודה! ${_photoUrls.length == 1 ? 'זו התמונה הראשונה. ' : ''}'
              'אפשר להוסיף עוד, או להמשיך.',
        ));
      });
      _saveTranscript();
      _scrollToEnd();
      // If a draft was waiting only on a photo, offer to publish now.
      if (wasFirst && _draft != null) {
        setState(() => _messages.last.draft = _draft);
      }
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
      backgroundColor: ErikTokens.bgMid,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ErikTokens.rXl))),
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
                    color: ErikTokens.lineStrong,
                    borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 16),
              _mediaTile(IconsaxPlusBold.camera, 'צלם תמונה',
                  () => _pickMedia(ImageSource.camera)),
              _mediaTile(IconsaxPlusBold.gallery, 'בחר מהגלריה',
                  () => _pickMedia(ImageSource.gallery)),
              _mediaTile(IconsaxPlusBold.video, 'סרטון מהגלריה',
                  () => _pickMedia(ImageSource.gallery, video: true)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: ErikTokens.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: ErikTokens.accent, size: 22),
      ),
      title: Text(label,
          style: const TextStyle(
              color: ErikTokens.ink, fontSize: 17, fontWeight: FontWeight.w800)),
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
      final property = await buildPropertyFromErikDraft(
        draft,
        ownerName: ownerName,
        photoUrls: _photoUrls,
      );
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
        _publishing = false;
        // Clear the pending draft card so it can't be published twice.
        for (final m in _messages) {
          m.draft = null;
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
    // The orb may have added turns to the shared transcript — reload.
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ErikTokens.bgMid,
      content: Text(m, style: const TextStyle(color: ErikTokens.ink, fontSize: 15)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showWelcomeStarters =
        _messages.length == 1 && _messages.first.isWelcome;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: ErikTokens.bgDeep,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            _ambientBackground(),
            SafeArea(
              child: Column(
                children: [
                  _appBar(),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      behavior: HitTestBehavior.opaque,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                        itemCount: _messages.length +
                            (_busy ? 1 : 0) +
                            (showWelcomeStarters ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (_busy && i == _messages.length) {
                            return const _TypingBubble();
                          }
                          if (showWelcomeStarters && i == _messages.length) {
                            return _starterChips();
                          }
                          return _messageRow(_messages[i], i);
                        },
                      ),
                    ),
                  ),
                  _inputBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ambientBackground() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.3,
            colors: [ErikTokens.bgMid, ErikTokens.bgDeep],
          ),
        ),
        child: Stack(children: [
          Positioned(
            top: -80,
            right: -60,
            child: ErikAmbientGlow(size: 320, color: ErikTokens.accent.withValues(alpha: 0.14)),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: ErikAmbientGlow(size: 360, color: ErikTokens.accentGlow.withValues(alpha: 0.10)),
          ),
        ]),
      ),
    );
  }

  Widget _appBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          _glassCircle(IconsaxPlusLinear.arrow_right_3, () {
            HapticFeedback.selectionClick();
            Navigator.of(context).maybePop();
          }),
          const SizedBox(width: 10),
          // Erik identity — avatar orb + name + live presence dot
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ErikTokens.accentGlow, ErikTokens.accent],
              ),
              boxShadow: ErikTokens.accentShadow(opacity: 0.4, blur: 14),
            ),
            child: const Icon(IconsaxPlusBold.microphone_2, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('אריק · העוזר האישי שלך',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ErikTokens.ink,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900)),
                Row(children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: ErikTokens.online, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('כאן בשבילך',
                      style: TextStyle(
                          color: ErikTokens.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ],
            ),
          ),
          // Read-aloud toggle (helpful for older users)
          _glassCircle(
            _speakReplies ? IconsaxPlusBold.volume_high : IconsaxPlusLinear.volume_slash,
            () {
              HapticFeedback.selectionClick();
              setState(() => _speakReplies = !_speakReplies);
              _snack(_speakReplies ? 'אריק יקריא את התשובות' : 'הקראה כבויה');
            },
            active: _speakReplies,
          ),
          const SizedBox(width: 8),
          _glassCircle(IconsaxPlusLinear.refresh, _newConversation),
        ],
      ),
    );
  }

  Widget _glassCircle(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? ErikTokens.accent.withValues(alpha: 0.20) : ErikTokens.glassHi,
          shape: BoxShape.circle,
          border: Border.all(color: active ? ErikTokens.accent : ErikTokens.line),
        ),
        child: Icon(icon, color: active ? ErikTokens.accent : ErikTokens.ink, size: 21),
      ),
    );
  }

  // ── Message rendering ────────────────────────────────────────────────────────

  Widget _messageRow(_ErikMsg m, int index) {
    final isUser = m.role == 'user';
    final isLast = index == _messages.length - 1;
    final bubble = Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _textBubble(m, isUser),
        if (m.draft != null) ...[
          const SizedBox(height: 10),
          _draftCard(m.draft!),
        ],
        if (m.listings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...m.listings.take(3).map(_listingCard),
        ],
        if (!isUser && !m.streaming && m.suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _suggestionChips(m.suggestions),
        ],
        if (m.canRetry && !m.streaming) ...[
          const SizedBox(height: 8),
          _retryButton(m.retryText),
        ],
      ],
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.86),
          child: bubble,
        ),
      ),
    );
    // Gentle entrance for the newest bubble only (like אתי's _FadeSlideIn).
    return isLast ? ErikFadeInUp(child: row) : row;
  }

  Widget _textBubble(_ErikMsg m, bool isUser) {
    final text = m.streaming ? m.streamedText : m.text;
    if (text.trim().isEmpty && m.mediaUrls.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? ErikTokens.userSurface : ErikTokens.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(ErikTokens.rLg),
          topRight: const Radius.circular(ErikTokens.rLg),
          bottomLeft: Radius.circular(isUser ? ErikTokens.rLg : 5),
          bottomRight: Radius.circular(isUser ? 5 : ErikTokens.rLg),
        ),
        border: isUser ? null : Border.all(color: ErikTokens.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isUser ? Colors.white : ErikTokens.ink,
          fontSize: 17,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _suggestionChips(List<String> chips) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < chips.length; i++)
          ErikFadeInUp(
            delay: Duration(milliseconds: i * 70),
            offset: 10,
            child: ScaleBounce(
              onTap: () {
                HapticFeedback.selectionClick();
                _send(chips[i]);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ErikTokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ErikTokens.rPill),
                  border: Border.all(color: ErikTokens.accent.withValues(alpha: 0.42)),
                ),
                child: Text(chips[i],
                    style: TextStyle(
                        color: ErikTokens.accentGlow,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _starterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            child: Text('אפשר להתחיל מ:',
                style: TextStyle(
                    color: ErikTokens.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
          ),
          _suggestionChips(_starters),
        ],
      ),
    );
  }

  Widget _retryButton(String text) {
    return ScaleBounce(
      onTap: () => _send(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: ErikTokens.glassHi,
          borderRadius: BorderRadius.circular(ErikTokens.rPill),
          border: Border.all(color: ErikTokens.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(IconsaxPlusLinear.refresh, color: ErikTokens.ink, size: 18),
          const SizedBox(width: 8),
          const Text('נסה שוב',
              style: TextStyle(
                  color: ErikTokens.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // ── Inline listing-draft preview card (replaces the old raw bottom sheet) ──

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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            ErikTokens.accent.withValues(alpha: 0.16),
            ErikTokens.card,
          ],
        ),
        borderRadius: BorderRadius.circular(ErikTokens.rLg),
        border: Border.all(color: ErikTokens.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(IconsaxPlusBold.home_trend_up, color: ErikTokens.accentGlow, size: 22),
            const SizedBox(width: 8),
            const Text('טיוטת מודעה מוכנה',
                style: TextStyle(
                    color: ErikTokens.ink, fontSize: 17, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 12),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  Icon(r.$1, color: ErikTokens.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.$2,
                        style: const TextStyle(
                            color: ErikTokens.ink,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              )),
          Row(children: [
            Icon(
                _photoUrls.isEmpty ? IconsaxPlusLinear.gallery_slash : IconsaxPlusBold.gallery,
                color: _photoUrls.isEmpty ? ErikTokens.muted : ErikTokens.online,
                size: 18),
            const SizedBox(width: 10),
            Text(
                _photoUrls.isEmpty
                    ? 'עוד לא צורפו תמונות'
                    : '${_photoUrls.length} תמונות מצורפות',
                style: TextStyle(
                    color: _photoUrls.isEmpty ? ErikTokens.muted : ErikTokens.online,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ScaleBounce(
                onTap: _publishing ? null : () => _publish(draft),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: ErikTokens.accent,
                    borderRadius: BorderRadius.circular(ErikTokens.rMd),
                    boxShadow: ErikTokens.accentShadow(),
                  ),
                  child: Center(
                    child: _publishing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : const Text('פרסם עכשיו',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ScaleBounce(
              onTap: () => _editInForm(draft),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: ErikTokens.glassHi,
                  borderRadius: BorderRadius.circular(ErikTokens.rMd),
                  border: Border.all(color: ErikTokens.line),
                ),
                child: Row(children: [
                  Icon(IconsaxPlusLinear.edit_2, color: ErikTokens.ink, size: 18),
                  const SizedBox(width: 7),
                  const Text('עריכה',
                      style: TextStyle(
                          color: ErikTokens.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _listingCard(AssistantListing l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ErikTokens.glass(),
        child: Row(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: ErikTokens.glassLo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(IconsaxPlusBold.building_4, color: ErikTokens.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ErikTokens.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
                if (l.subtitle != null)
                  Text(l.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ErikTokens.muted, fontSize: 13)),
                if (l.price != null)
                  Text('₪${l.price}',
                      style: TextStyle(
                          color: ErikTokens.accentGlow,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Input bar ────────────────────────────────────────────────────────────────

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 10 + MediaQuery.viewInsetsOf(context).bottom * 0),
      decoration: BoxDecoration(
        color: ErikTokens.bgDeep.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: ErikTokens.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Add media
          _roundInputBtn(
            IconsaxPlusLinear.add,
            _openMediaSheet,
            filled: false,
          ),
          const SizedBox(width: 8),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 50, maxHeight: 130),
              decoration: BoxDecoration(
                color: ErikTokens.glassHi,
                borderRadius: BorderRadius.circular(ErikTokens.rXl),
                border: Border.all(color: ErikTokens.line),
              ),
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                textDirection: TextDirection.rtl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: const TextStyle(
                    color: ErikTokens.ink, fontSize: 16.5, fontWeight: FontWeight.w600),
                cursorColor: ErikTokens.accent,
                decoration: InputDecoration(
                  hintText: 'כתוב לאריק, או דבר איתו…',
                  hintStyle: TextStyle(
                      color: ErikTokens.muted, fontSize: 16, fontWeight: FontWeight.w500),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send OR voice, depending on whether there's text
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return hasText
                  ? _roundInputBtn(IconsaxPlusBold.send_1, () => _send(_input.text),
                      filled: true)
                  : _roundInputBtn(IconsaxPlusBold.microphone_2, _openVoice,
                      filled: true, gradient: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _roundInputBtn(IconData icon, VoidCallback onTap,
      {bool filled = false, bool gradient = false}) {
    return ScaleBounce(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient ? null : (filled ? ErikTokens.accent : ErikTokens.glassHi),
          gradient: gradient
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [ErikTokens.accentGlow, ErikTokens.accent])
              : null,
          border: filled ? null : Border.all(color: ErikTokens.line),
          boxShadow: filled ? ErikTokens.accentShadow(opacity: 0.35, blur: 16) : null,
        ),
        child: Icon(icon, color: filled ? Colors.white : ErikTokens.ink, size: 23),
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
    this.suggestions = const [],
    this.listings = const [],
    this.draft,
    this.isWelcome = false,
    this.canRetry = false,
    this.retryText = '',
  });

  final String role; // 'user' | 'assistant'
  final String text;
  final List<String> mediaUrls;
  final List<String> suggestions;
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

/// Three-dot "Erik is typing" bubble (dark variant of אתי's indicator).
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: ErikTokens.card,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(ErikTokens.rLg),
              topRight: Radius.circular(ErikTokens.rLg),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(ErikTokens.rLg),
            ),
            border: Border.all(color: ErikTokens.line),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _dot(i),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _dot(int i) {
    final phase = (_c.value + i * 0.2) % 1.0;
    final scale = 0.6 + 0.6 * (0.5 + 0.5 * (1 - (phase * 2 - 1).abs()));
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: ErikTokens.accent, shape: BoxShape.circle),
      ),
    );
  }
}
