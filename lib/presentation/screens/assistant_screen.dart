import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/assistant_service.dart';
import 'package:dating_app/core/services/assistant_live_service.dart';
import 'package:dating_app/core/services/property_draft_builder.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Keep Erik visually aligned with the rest of Rently while preserving the
// richer assistant interaction model.
Color get _kBgTop => AppColors.navy;
const _kBgMid = Color(0xFF0F3250); // slightly lighter navy
Color get _kBgBot => AppColors.navy;
const _kInk = Colors.white;
const _kMuted = Color(0xFF9EB5C8); // lighter muted blue-grey
const _kAssistantSurface = Color(0x1A5AD4DC); // translucent teal-blue
Color get _kUserSurface => AppColors.primary; // solid Teal
const _kPanelSurface = Color(0x1F072946); // translucent dark navy
const _kLine = Color(0x28FFFFFF); // thin white border for glassmorphism
Color get _kAccent => AppColors.primary; // Teal
Color get _kAccent2 => AppColors.primaryLight; // Light teal for glowing accents

/// "אריק" — a premium, interactive voice/text concierge for landlords (built so
/// both a 20-year-old and a 70-year-old breeze through it). Glass surfaces, soft
/// glow, animated entrances, tappable choice chips, and a publish flow that
/// requires a photo.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with TickerProviderStateMixin {
  final _service = AssistantService();
  final _live = AssistantLiveService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _storage = StorageService();

  final List<AssistantTurn> _turns = [];
  final List<String> _photoUrls = [];
  bool _pickingPhoto = false;
  Map<String, dynamic>? _draft;
  bool _thinking = false;
  bool _listening = false;
  bool _voiceReplies = true;
  bool _publishing = false;
  String _partial = '';
  bool _showVisualizer = true;

  // Hands-free continuous conversation: when on, Erik listens automatically,
  // the user speaks, Erik answers in voice and immediately resumes listening —
  // like a phone call, with no buttons. Built for older landlords.
  bool _conversationMode = false;

  // Real-time Gemini Live voice conversation (the premium experience). Audio
  // streams both ways with sub-second latency and barge-in. Falls back to the
  // turn-based hands-free loop above if Live can't connect.
  bool _liveActive = false;
  LiveStatus _liveStatus = LiveStatus.idle;
  String _liveUserText = '';
  String _liveErikText = '';

  late final AnimationController _pulse;
  late final AnimationController _uploadPanelCtrl;
  late final Animation<Offset> _uploadPanelOffset;

  static const _greeting =
      'שלום, נעים מאוד. קוראים לי אריק ואני כאן כדי לעזור לך.\n'
      'ספר לי בבקשה בכמה מילים על הדירה שאתה רוצה להשכיר — איפה היא, כמה חדרים, '
      'וכל מה שבא לך לספר. מתוך מה שתספר אני כבר אבין הרבה, ואשאל רק על מה שחסר.\n'
      'אפשר לדבר איתי או לכתוב, איך שנוח לך.';

  static const _welcomeCards = [
    AssistantCard(
      type: 'actions',
      title: 'פעולות מהירות',
      subtitle: 'אפשר להתחיל מכאן',
      items: [
        {'label': 'הוסף דירה חדשה', 'icon': 'add'},
        {'label': 'עדכן מחיר שכירות', 'icon': 'edit'},
        {'label': 'פרטי הדירה שלי', 'icon': 'home'},
        {'label': 'שאל שאלה חופשית', 'icon': 'question'},
      ],
    ),
  ];

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _storeKey => 'erik_transcript_$_uid';

  final ValueNotifier<double> _soundLevelNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    
    _uploadPanelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _uploadPanelOffset = Tween<Offset>(
      begin: const Offset(0.0, 1.2), // completely below screen
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _uploadPanelCtrl,
      curve: Curves.easeOutBack,
    ));

    _loadTranscript();
  }

  @override
  void dispose() {
    _conversationMode = false;
    _liveActive = false;
    _live.dispose();
    _pulse.dispose();
    _uploadPanelCtrl.dispose();
    _service.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _soundLevelNotifier.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  AssistantTurn _welcomeTurn() => const AssistantTurn(
        role: 'assistant',
        text: _greeting,
        cards: _welcomeCards,
      );

  Future<void> _loadTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _turns.addAll(list.whereType<Map>().map(
              (e) => AssistantTurn.fromJson(Map<String, dynamic>.from(e)),
            ));
      }
    } catch (_) {}
    if (_turns.isEmpty) {
      _turns.add(_welcomeTurn());
    }
    if (mounted) setState(() {});
    _scrollToEnd();
  }

  Future<void> _saveTranscript() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storeKey,
        jsonEncode(_turns.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _clearTranscript() async {
    await _service.stopSpeaking();
    setState(() {
      _turns
        ..clear()
        ..add(_welcomeTurn());
      _draft = null;
      _photoUrls.clear();
      _showVisualizer = true;
    });
    _saveTranscript();
  }

  // ── Conversation ──────────────────────────────────────────────────────────────

  Future<void> _send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _thinking) return;
    _inputCtrl.clear();
    setState(() {
      _turns.add(AssistantTurn(role: 'user', text: clean));
      _thinking = true;
      _partial = '';
      // NOTE: do NOT clear _draft here. A draft Erik already built must stay
      // publishable across the rest of the conversation (the user keeps talking,
      // especially in hands-free voice mode) until it is actually published.
    });
    _scrollToEnd();
    _saveTranscript();

    try {
      final history = _turns.where((t) => t.text != _greeting).toList();
      final reply = await _service.chat(history);
      if (!mounted) return;
      final cards = _cardsForReply(reply);
      setState(() {
        _turns.add(AssistantTurn(
          role: 'assistant',
          text: reply.reply,
          cards: cards,
        ));
        // Only replace the pending draft when Erik produced a new one; keep the
        // previous draft otherwise so its publish button never disappears.
        if (reply.propertyDraft != null) _draft = reply.propertyDraft;
        _thinking = false;
      });
      _saveTranscript();
      _scrollToEnd();
      if (_asksForPhotos(reply.reply)) {
        _openUploadPanel();
      }
      if (_conversationMode) {
        await _speakAndContinue(reply.reply);
      } else if (_voiceReplies) {
        _service.speak(reply.reply);
      }
    } on AssistantException catch (e) {
      _onError(e.message);
    } catch (_) {
      _onError('משהו השתבש. אפשר לנסות שוב.');
    }
  }

  /// Speaks Erik's reply and, while in hands-free conversation mode, resumes
  /// listening as soon as he finishes — so the user just keeps talking.
  Future<void> _speakAndContinue(String text) async {
    if (_voiceReplies) {
      await _service.speak(text);
    }
    if (_conversationMode && mounted && !_thinking && !_publishing) {
      _listenTurn();
    }
  }

  List<AssistantCard> _cardsForReply(AssistantReply reply) {
    final cards = <AssistantCard>[...reply.cards];
    if (reply.propertyDraft != null &&
        !cards.any((c) => c.type == 'propertyDraft')) {
      cards.add(AssistantCard(
        type: 'propertyDraft',
        title: 'טיוטת דירה',
        subtitle: 'אפשר לפרסם מהשיחה',
        data: reply.propertyDraft!,
      ));
    }
    if (reply.suggestions.isNotEmpty &&
        !cards.any((c) => c.type == 'actions')) {
      cards.add(AssistantCard(
        type: 'actions',
        title: 'אפשר להמשיך מכאן',
        items: reply.suggestions.map((s) => {'label': s}).toList(),
      ));
    }
    if (_voiceReplies && reply.reply.trim().isNotEmpty) {
      cards.add(AssistantCard(
        type: 'audio',
        title: 'תשובה קולית',
        subtitle: _estimateVoiceDuration(reply.reply),
      ));
    }
    return cards;
  }

  String _estimateVoiceDuration(String text) {
    final seconds =
        math.max(4, math.min(99, (text.runes.length / 8.5).round()));
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  void _onError(String message) {
    if (!mounted) return;
    setState(() {
      _turns.add(AssistantTurn(role: 'assistant', text: message));
      _thinking = false;
    });
    _scrollToEnd();
    // Keep the hands-free call alive: speak the message and listen again.
    if (_conversationMode) {
      unawaited(_speakAndContinue(message));
    }
  }

  void _openUploadPanel() {
    _uploadPanelCtrl.forward();
  }

  void _closeUploadPanel() {
    _uploadPanelCtrl.reverse();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final file = await _picker.pickImage(
          source: source, imageQuality: 88, maxWidth: 2000);
      if (file == null) {
        if (mounted) setState(() => _pickingPhoto = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      if (!mounted) return;
      final mediaPath = remoteUrl ?? localPath;
      setState(() {
        _photoUrls.add(mediaPath);
        _turns.add(AssistantTurn(
          role: 'user',
          text: 'הוספתי תמונה לדירה',
          mediaUrls: [mediaPath],
        ));
        _pickingPhoto = false;
      });
      _scrollToEnd();
      _saveTranscript();
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingPhoto = false);
      _onError('לא הצלחתי להוסיף את התמונה. אפשר לנסות שוב.');
    }
  }

  Future<void> _publishDraft([Map<String, dynamic>? draftOverride]) async {
    final draft = draftOverride ?? _draft;
    if (draft == null || _publishing) return;
    if (_photoUrls.isEmpty) {
      setState(() {
        _turns.add(const AssistantTurn(
          role: 'assistant',
          text:
              'רק רגע — כדי לפרסם צריך לפחות תמונה אחת של הדירה. אפשר לצלם עכשיו או לבחור תמונה מהטלפון.',
        ));
      });
      _openUploadPanel();
      _scrollToEnd();
      return;
    }
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
      final msg =
          'מצוין! פרסמתי את הדירה שלך${addr.isNotEmpty ? ' ב$addr' : ''}, היא כבר באוויר.\n'
          'אם תרצה, אפשר להוסיף עוד תמונות בכל רגע מהמסך "הדירות שלי".\n'
          'אני כאן אם תצטרך עוד משהו.';
      setState(() {
        _draft = null;
        _publishing = false;
        _photoUrls.clear();
        _turns.add(AssistantTurn(
          role: 'assistant',
          text: msg,
          cards: [
            if (_voiceReplies)
              AssistantCard(
                type: 'audio',
                title: 'תשובה קולית',
                subtitle: _estimateVoiceDuration(msg),
              ),
          ],
        ));
      });
      _saveTranscript();
      _scrollToEnd();
      if (_voiceReplies) _service.speak(msg);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Erik publishDraft failed: $e\n$st');
      if (!mounted) return;
      setState(() => _publishing = false);
      _onError(
          'סליחה, הייתה בעיה בפרסום. אפשר לנסות שוב, או להוסיף תמונות ידנית.');
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _service.stopListening();
      setState(() => _listening = false);
      _soundLevelNotifier.value = 0.0;
      if (_partial.trim().isNotEmpty) _send(_partial);
      return;
    }
    await _service.stopSpeaking();
    try {
      setState(() {
        _listening = true;
        _partial = '';
      });
      await _service.startListening(
        onResult: (text, isFinal) {
          setState(() => _partial = text);
          if (isFinal) {
            setState(() => _listening = false);
            _soundLevelNotifier.value = 0.0;
            if (text.trim().isNotEmpty) _send(text);
          }
        },
        onSoundLevelChange: (level) {
          _soundLevelNotifier.value = level;
        },
      );
    } on AssistantException catch (e) {
      setState(() => _listening = false);
      _soundLevelNotifier.value = 0.0;
      _onError(e.message);
    }
  }

  // ── Hands-free continuous conversation (on-device fallback for Live) ──────────

  /// One listening turn within conversation mode. On a final result it sends the
  /// text (which then speaks + loops back here). If nothing was heard, it keeps
  /// listening so a quiet pause never ends the call.
  Future<void> _listenTurn() async {
    if (!_conversationMode || !mounted || _thinking) return;
    await _service.stopSpeaking();
    if (!_conversationMode || !mounted) return;
    try {
      setState(() {
        _listening = true;
        _partial = '';
      });
      await _service.startListening(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() => _partial = text);
          if (isFinal) {
            setState(() => _listening = false);
            _soundLevelNotifier.value = 0.0;
            final clean = text.trim();
            if (clean.isNotEmpty) {
              _send(clean);
            } else if (_conversationMode) {
              _listenTurn();
            }
          }
        },
        onSoundLevelChange: (level) {
          _soundLevelNotifier.value = level;
        },
      );
    } on AssistantException catch (e) {
      // Mic unavailable / permission denied — end the call cleanly.
      setState(() {
        _listening = false;
        _conversationMode = false;
      });
      _soundLevelNotifier.value = 0.0;
      _onError(e.message);
    }
  }

  // ── Real-time Gemini Live conversation ───────────────────────────────────────

  Future<void> _toggleLive() async {
    if (_liveActive) {
      await _stopLive();
    } else {
      await _startLive();
    }
  }

  Future<void> _startLive() async {
    // Make sure the turn-based loop + any device speech are fully stopped first.
    _conversationMode = false;
    _livePublishedKeys.clear();
    await _service.stopSpeaking();
    await _service.stopListening();
    if (!mounted) return;
    setState(() {
      _liveActive = true;
      _liveStatus = LiveStatus.connecting;
      _liveUserText = '';
      _liveErikText = '';
      _listening = false;
    });
    _live
      ..onStatus = (s) {
        if (mounted) setState(() => _liveStatus = s);
      }
      ..onUserText = (delta) {
        if (mounted) setState(() => _liveUserText += delta);
      }
      ..onErikText = (delta) {
        if (mounted) setState(() => _liveErikText += delta);
      }
      ..onTurnComplete = _commitLivePartials
      ..onInterrupted = () {
        if (mounted) setState(() {});
      }
      ..onCreateProperty = _onLiveCreateProperty
      ..onError = (message) {
        if (!mounted) return;
        setState(() {
          _liveActive = false;
          _liveStatus = LiveStatus.error;
        });
        _turns.add(AssistantTurn(
          role: 'assistant',
          text: '$message אפשר להמשיך לדבר איתי בשיחה רגילה — אני מקשיב.',
        ));
        _scrollToEnd();
        // Graceful fallback: keep voice working via the on-device hands-free
        // loop when the live session can't be established.
        _conversationMode = true;
        _listenTurn();
      };
    await _live.connect();
  }

  Future<void> _stopLive() async {
    await _live.disconnect();
    _commitLivePartials();
    if (!mounted) return;
    setState(() {
      _liveActive = false;
      _liveStatus = LiveStatus.idle;
    });
  }

  /// Folds the streaming partial transcripts into committed chat bubbles.
  void _commitLivePartials() {
    final u = _liveUserText.trim();
    final e = _liveErikText.trim();
    if (u.isEmpty && e.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (u.isNotEmpty) _turns.add(AssistantTurn(role: 'user', text: u));
      if (e.isNotEmpty) _turns.add(AssistantTurn(role: 'assistant', text: e));
      _liveUserText = '';
      _liveErikText = '';
    });
    _saveTranscript();
    _scrollToEnd();
  }

  // Dedupe key per published listing so a repeated tool call in one live
  // session doesn't create the same apartment twice.
  final Set<String> _livePublishedKeys = {};

  /// Erik emitted a create_property tool call during the live conversation. In a
  /// voice call the user can't tap a publish button, so we publish the listing
  /// for real right here — it lands in "הדירות שלי" and is saved to the server.
  /// Photos aren't required (they can be added later from "הדירות שלי").
  void _onLiveCreateProperty(Map<String, dynamic> args) {
    if (!mounted) return;
    _commitLivePartials();
    unawaited(_publishFromLive(args));
  }

  Future<void> _publishFromLive(Map<String, dynamic> args) async {
    final key = [
      args['city'],
      args['street'],
      args['streetNumber'],
      args['price'],
      args['rooms'],
    ].join('|');
    if (_livePublishedKeys.contains(key)) return; // already created this one
    _livePublishedKeys.add(key);

    if (_photoUrls.isEmpty) {
      _livePublishedKeys.remove(key); // allow retry
      setState(() {
        _turns.add(const AssistantTurn(
          role: 'assistant',
          text:
              'רק רגע — כדי לפרסם את המודעה צריך להוסיף לפחות תמונה אחת של הדירה. '
              'העליתי לך את אזור העלאת התמונות למטה, אנא בחר תמונה כדי שנפרסם את הדירה.',
        ));
      });
      _openUploadPanel();
      _scrollToEnd();
      return;
    }

    try {
      final provider = context.read<DatingProvider>();
      final ownerName = provider.tenantProfile?.name ?? '';
      final property = await buildPropertyFromErikDraft(
        args,
        ownerName: ownerName,
        photoUrls: _photoUrls, // usually empty in a voice call — that's fine
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
        _turns.add(AssistantTurn(
          role: 'assistant',
          text:
              'מצוין! פרסמתי את הדירה${addr.isNotEmpty ? ' ב$addr' : ''} — היא כבר '
              'מופיעה אצלך ב"הדירות שלי". אפשר להוסיף תמונות בכל רגע משם.',
          cards: [
            AssistantCard(
              type: 'info',
              title: 'הדירה פורסמה',
              subtitle: addr.isNotEmpty ? addr : 'המודעה עלתה לאוויר',
              description: 'אפשר להוסיף תמונות מהמסך "הדירות שלי".',
            ),
          ],
        ));
      });
      _saveTranscript();
      _scrollToEnd();
    } catch (e) {
      _livePublishedKeys.remove(key); // allow a retry
      if (kDebugMode) debugPrint('Erik live publish failed: $e');
      if (!mounted) return;
      setState(() {
        _turns.add(const AssistantTurn(
          role: 'assistant',
          text: 'הייתה בעיה קטנה בפרסום הדירה. אפשר לנסות שוב בעוד רגע.',
        ));
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 240,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBot,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_kBgTop, _kBgMid, _kBgBot],
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          // Soft, brand-driven ambient glows — calm and on-theme (auto black for
          // brokers, teal for tenants). Kept subtle so text stays restful.
          Positioned(
            top: -140,
            right: -110,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kAccent2.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -120,
            child: IgnorePointer(
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kAccent.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _showVisualizer
                        ? _buildVoiceChatThread()
                        : _buildChatThread(),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _uploadPanelOffset,
              child: _buildUploadPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          decoration: BoxDecoration(
            color: const Color(0xFF072946).withOpacity(0.92),
            border: const Border(
              top: BorderSide(color: Color(0x28FFFFFF)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'הוספת מדיה לדירה',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  GestureDetector(
                    onTap: _closeUploadPanel,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(IconsaxPlusLinear.close_circle, color: Colors.white70, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_photoUrls.isEmpty)
                Container(
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'טרם הוספת תמונות לדירה זו',
                    style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                )
              else
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photoUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _thumb(_photoUrls[i]),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _photoUrls.removeAt(i);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                IconsaxPlusLinear.close_circle,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _panelActionBtn(
                      icon: IconsaxPlusBold.camera,
                      label: 'צלם תמונה',
                      color: _kAccent,
                      onTap: () => _pickPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _panelActionBtn(
                      icon: IconsaxPlusBold.gallery,
                      label: 'גלריה',
                      color: AppColors.superLike,
                      onTap: () => _pickPhoto(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _panelActionBtn(
                      icon: IconsaxPlusBold.video_play,
                      label: 'צלם וידאו',
                      color: AppColors.coral,
                      onTap: () => _pickVideo(ImageSource.camera),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _kUserSurface,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _closeUploadPanel,
                child: const Text(
                  'סיימתי, המשך בשיחה',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatThread() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            itemCount: _turns.length + (_thinking ? 1 : 0),
            itemBuilder: (context, i) {
              if (i < _turns.length) {
                return _FadeInUp(child: _bubble(_turns[i]));
              }
              return _FadeInUp(child: _thinkingBubble());
            },
          ),
        ),
        if (_listening) _listeningStrip(),
        _composer(),
      ],
    );
  }

  Widget _buildVoiceChatThread() {
    // Calm, inviting hero before any conversation has begun — the orb is the
    // hero and a single big button starts the real-time call.
    final idle = !_liveActive &&
        _turns.length <= 1 &&
        _liveUserText.isEmpty &&
        _liveErikText.isEmpty;
    if (idle) return _buildVoiceWelcomeHero();

    return Column(
      children: [
        _voiceChatHeader(),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            itemCount: _turns.length + (_thinking ? 1 : 0),
            itemBuilder: (context, i) {
              if (i < _turns.length) {
                return _FadeInUp(child: _bubble(_turns[i]));
              }
              return _FadeInUp(child: _thinkingBubble());
            },
          ),
        ),
        if (_listening) _listeningStrip(),
        _composer(),
      ],
    );
  }

  Widget _buildVoiceWelcomeHero() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _toggleLive,
                  child: _VoiceOrb(
                    size: 156,
                    listening: false,
                    speaking: false,
                    connecting: false,
                    soundLevelNotifier: _soundLevelNotifier,
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  'שלום, אני אריק',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kInk,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'העוזר האישי שלך. פשוט דבר איתי על הדירה שתרצה להשכיר — '
                  'איפה היא, כמה חדרים, מחיר — ואני אבנה לך את המודעה. בלי טפסים.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 17,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 30),
                _bigStartButton(),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => setState(() => _showVisualizer = false),
                  icon: const Icon(IconsaxPlusLinear.keyboard, size: 18),
                  style: TextButton.styleFrom(foregroundColor: _kMuted),
                  label: const Text(
                    'מעדיף לכתוב? עבור לצ׳אט',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bigStartButton() {
    return GestureDetector(
      onTap: _toggleLive,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 19),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kAccent, _kAccent2],
          ),
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: _kAccent.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusBold.microphone_2, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text(
              'התחל שיחה עם אריק',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceChatHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _toggleLive,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final connecting = _liveStatus == LiveStatus.connecting;
              final speaking = _liveActive && _liveStatus == LiveStatus.speaking;
              final liveListening =
                  _liveActive && _liveStatus == LiveStatus.listening;
              final active = _liveActive || _listening || _thinking;

              final title = !_liveActive
                  ? 'שיחה קולית בזמן אמת'
                  : connecting
                      ? 'מתחבר לאריק...'
                      : speaking
                          ? 'אריק מדבר...'
                          : 'מקשיב לך... דבר חופשי';

              final livePartial =
                  speaking ? _liveErikText.trim() : _liveUserText.trim();
              final subtitle = _liveActive
                  ? (livePartial.isNotEmpty
                      ? livePartial
                      : connecting
                          ? 'רגע, מתחבר לשיחה החיה...'
                          : 'דבר חופשי — אריק שומע ועונה בזמן אמת. אפשר גם לקטוע אותו. גע כאן כדי לסיים.')
                  : 'גע כאן ודבר עם אריק כמו בטלפון — שיחה חיה בזמן אמת. הוא שומע, עונה בקול, ואפשר אפילו לקטוע אותו באמצע.';

              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _kPanelSurface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: active ? _kAccent.withValues(alpha: 0.45) : _kLine,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kInk.withValues(alpha: active ? 0.10 : 0.06),
                      blurRadius: active ? 22 : 16,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: _liveActive ? _kAccent : _kInk,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            textAlign: TextAlign.right,
                            maxLines: livePartial.isNotEmpty ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _conversationPill(),
                          const SizedBox(height: 10),
                          _compactWave(isActive: active && !connecting),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _VoiceOrb(
                      size: 66,
                      listening: liveListening || _listening,
                      speaking: speaking,
                      connecting: connecting || _thinking,
                      soundLevelNotifier: _soundLevelNotifier,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Big, unmistakable start/end-call pill for the real-time live conversation.
  Widget _conversationPill() {
    final on = _liveActive;
    final color = on ? const Color(0xFFE5484D) : _kAccent;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? IconsaxPlusBold.close_circle : IconsaxPlusBold.microphone_2,
                color: color, size: 18),
            const SizedBox(width: 7),
            Text(
              on ? 'סיים שיחה' : 'התחל שיחה בזמן אמת',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactWave({required bool isActive}) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: List.generate(26, (index) {
          final phase = (_pulse.value + index * 0.06) % 1;
          final wave = 0.35 + 0.65 * math.sin(phase * math.pi);
          final height = isActive ? 6 + wave * 16 : 5 + (index % 4) * 2.2;
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: (isActive ? _kAccent : _kMuted).withValues(
                alpha: isActive ? 0.70 : 0.32,
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }

  Widget _glassCircleBtn(IconData icon, VoidCallback onTap,
      {Color? color, String? tooltip}) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: _kInk.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: color ?? _kInk, size: 22),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Row(
        children: [
          _glassCircleBtn(IconsaxPlusLinear.arrow_right_3,
              () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          // Animated avatar orb with a soft breathing halo ring — friendly
          // concierge, not a generic chat icon.
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              final active = _listening || _thinking;
              return SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Breathing halo ring.
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _kAccent.withValues(
                              alpha: (active ? 0.45 : 0.22) * (0.6 + 0.4 * t)),
                          width: 2,
                        ),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_kAccent2, _kAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _kAccent.withValues(
                                alpha: (active ? 0.55 : 0.30) * (0.6 + 0.4 * t)),
                            blurRadius: 14 + 8 * t,
                            spreadRadius: 1 + 1.5 * t,
                          ),
                        ],
                      ),
                      child: const Icon(IconsaxPlusBold.message_favorite,
                          color: Colors.white, size: 23),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('אריק',
                        style: TextStyle(
                            color: _kInk,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0)),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: _kAccent.withValues(alpha: 0.35)),
                      ),
                      child: Text('AI',
                          style: TextStyle(
                              color: _kAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    key: ValueKey(_listening
                        ? 0
                        : _thinking
                            ? 1
                            : 2),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_listening || _thinking)
                              ? _kAccent
                              : const Color(0xFF4ADE80),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _listening
                            ? 'מקשיב לך...'
                            : _thinking
                                ? 'חושב על תשובה...'
                                : 'העוזר האישי שלך · זמין',
                        style: TextStyle(
                            color:
                                (_listening || _thinking) ? _kAccent : _kMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_showVisualizer) ...[
            _glassCircleBtn(
              IconsaxPlusBold.microphone_2,
              () => setState(() => _showVisualizer = true),
              color: _kAccent,
              tooltip: 'חזור לשיחה קולית',
            ),
            const SizedBox(width: 8),
          ],
          _glassCircleBtn(
            IconsaxPlusLinear.more,
            _showOptionsMenu,
            color: _kInk.withValues(alpha: 0.72),
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            decoration: BoxDecoration(
              color: const Color(0xFF072946).withValues(alpha: 0.94),
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _kMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _OptionTile(
                    icon: _showVisualizer
                        ? IconsaxPlusBold.messages_1
                        : IconsaxPlusBold.microphone_2,
                    label: _showVisualizer ? 'כתיבה בלבד' : 'שיחה קולית מלאה',
                    subtitle: _showVisualizer
                        ? 'הסתר את פאנל הדיבור וה-Orb'
                        : 'מעבר לשיחה חיה וקולית עם אריק',
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _showVisualizer = !_showVisualizer);
                    },
                  ),
                  const SizedBox(height: 8),
                  _OptionTile(
                    icon: _voiceReplies
                        ? IconsaxPlusLinear.volume_slash
                        : IconsaxPlusBold.volume_high,
                    label: _voiceReplies ? 'השתק קול' : 'הפעל קול',
                    subtitle: _voiceReplies
                        ? 'אריק לא ידבר בקול'
                        : 'אריק ידבר את תשובותיו בקול',
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (_voiceReplies) await _service.stopSpeaking();
                      setState(() => _voiceReplies = !_voiceReplies);
                    },
                  ),
                  const SizedBox(height: 8),
                  _OptionTile(
                    icon: IconsaxPlusLinear.refresh,
                    label: 'שיחה חדשה',
                    subtitle: 'מחק היסטוריה והתחל מחדש',
                    onTap: () {
                      Navigator.pop(ctx);
                      _clearTranscript();
                    },
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _asksForPhotos(String text) {
    final clean = text.toLowerCase();
    return clean.contains('תמונה') ||
        clean.contains('תמונות') ||
        clean.contains('לצלם') ||
        clean.contains('סרטון') ||
        clean.contains('סירטון') ||
        clean.contains('גלריה');
  }

  Widget _bubble(AssistantTurn t) {
    final isErik = t.role == 'assistant';
    final isLastAssistant = isErik &&
        _turns.indexOf(t) ==
            _turns.lastIndexWhere((turn) => turn.role == 'assistant');
    final showInlineMedia = isLastAssistant && _asksForPhotos(t.text);
    final maxWidth = MediaQuery.of(context).size.width * 0.84;

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(isErik ? 7 : 22),
          bottomRight: Radius.circular(isErik ? 22 : 7),
        ),
        child: BackdropFilter(
          filter: isErik
              ? ImageFilter.blur(sigmaX: 14, sigmaY: 14)
              : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            constraints: BoxConstraints(maxWidth: maxWidth),
            decoration: BoxDecoration(
              gradient: isErik
                  ? LinearGradient(
                      colors: [
                        _kAccent.withValues(alpha: 0.20),
                        _kAccent.withValues(alpha: 0.09),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        const Color(0xFF1A4063), // calm neutral navy surface
                        const Color(0xFF143350),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.circular(isErik ? 7 : 22),
                bottomRight: Radius.circular(isErik ? 22 : 7),
              ),
              border: Border.all(
                color: isErik
                    ? _kAccent.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isErik
                      ? _kAccent.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.text.trim().isNotEmpty)
                  Text(
                    t.text,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: isErik
                          ? _kInk
                          : Colors.white.withValues(alpha: 0.96),
                      fontSize: 17,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                if (t.mediaUrls != null && t.mediaUrls!.isNotEmpty)
                  _messageMediaStrip(t.mediaUrls!),
                if (showInlineMedia) ...[
                  if (t.text.trim().isNotEmpty) const SizedBox(height: 8),
                  _buildInlineMediaBox(),
                ],
                if (isErik && t.cards.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ..._assistantCards(t, isLastAssistant),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!isErik) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _assistantAvatar(),
            const SizedBox(width: 8),
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }

  Widget _assistantAvatar() {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [_kAccent2, _kAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _kAccent2.withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child:
          const Icon(IconsaxPlusBold.magic_star, color: Colors.white, size: 19),
    );
  }

  Widget _messageMediaStrip(List<String> urls) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 80,
        child: ListView.separated(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                _thumb(urls[i]),
                if (_isVideoPath(urls[i]))
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: Icon(
                        IconsaxPlusBold.video_play,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isVideoPath(String path) {
    final clean = path.toLowerCase();
    return clean.contains('mp4') ||
        clean.contains('mov') ||
        clean.contains('video');
  }

  /// True when [turn] is the most recent assistant turn that carries a property
  /// draft — so the publish button stays on the latest draft, even after the
  /// conversation continues past it.
  bool _isLatestDraftTurn(AssistantTurn turn) {
    final idx = _turns.lastIndexWhere(
      (t) =>
          t.role == 'assistant' &&
          t.cards.any((c) => c.type == 'propertyDraft'),
    );
    return idx >= 0 && _turns.indexOf(turn) == idx;
  }

  List<Widget> _assistantCards(AssistantTurn turn, bool isLatestAssistant) {
    return turn.cards
        .map((card) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _assistantCard(card, turn, isLatestAssistant),
            ))
        .toList();
  }

  Widget _assistantCard(
    AssistantCard card,
    AssistantTurn turn,
    bool isLatestAssistant,
  ) {
    switch (card.type) {
      case 'propertyDraft':
        // Keep the draft publishable as long as it is the most recent draft and
        // it hasn't been published yet — NOT only while it's the last message.
        return _propertyDraftCard(
          card.data,
          isActive: _draft != null && _isLatestDraftTurn(turn),
        );
      case 'actions':
        return _actionsCard(card);
      case 'audio':
        return _audioCard(turn, card);
      case 'document':
      case 'documents':
        return _documentCard(card);
      default:
        return _infoCard(card);
    }
  }

  Widget _buildInlineMediaBox() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Icon(IconsaxPlusBold.gallery_add,
                  color: _kAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                _photoUrls.isEmpty
                    ? 'הוסף תמונות או סרטון לדירה:'
                    : 'תמונות שנוספו:',
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: _openUploadPanel,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.35),
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Icon(
                      IconsaxPlusBold.add,
                      color: _kAccent,
                      size: 28,
                    ),
                  ),
                ),
                if (_photoUrls.isNotEmpty) const SizedBox(width: 8),
                for (int index = 0; index < _photoUrls.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _thumb(_photoUrls[index]),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _photoUrls.removeAt(index);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                IconsaxPlusLinear.close_circle,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: _kPanelSurface.withValues(alpha: 0.96),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.70)),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _kMuted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'הוספת מדיה לשיחה',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _mediaOptionItem(
                          icon: IconsaxPlusBold.camera,
                          label: 'צלם תמונה',
                          color: _kAccent,
                          onTap: () {
                            Navigator.pop(context);
                            _pickPhoto(ImageSource.camera);
                          },
                        ),
                        _mediaOptionItem(
                          icon: IconsaxPlusBold.gallery,
                          label: 'גלריית תמונות',
                          color: AppColors.superLike,
                          onTap: () {
                            Navigator.pop(context);
                            _pickPhoto(ImageSource.gallery);
                          },
                        ),
                        _mediaOptionItem(
                          icon: IconsaxPlusBold.video_play,
                          label: 'צלם סרטון',
                          color: AppColors.coral,
                          onTap: () {
                            Navigator.pop(context);
                            _pickVideo(ImageSource.camera);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mediaOptionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _kInk,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final file = await _picker.pickVideo(
          source: source, maxDuration: const Duration(seconds: 30));
      if (file == null) {
        if (mounted) setState(() => _pickingPhoto = false);
        return;
      }
      final localPath =
          await _storage.saveImageLocally(file, folderName: 'erik_property');
      final remoteUrl = await _storage.uploadToCloud(localPath);
      if (!mounted) return;
      final mediaPath = remoteUrl ?? localPath;
      setState(() {
        _photoUrls.add(mediaPath);
        _turns.add(AssistantTurn(
          role: 'user',
          text: 'הוספתי סרטון לדירה',
          mediaUrls: [mediaPath],
        ));
        _pickingPhoto = false;
      });
      _scrollToEnd();
      _saveTranscript();
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickingPhoto = false);
      _onError('לא הצלחתי להוסיף את הסרטון. אפשר לנסות שוב.');
    }
  }

  Widget _thinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _assistantAvatar(),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _kAssistantSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(19),
                topRight: Radius.circular(19),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(19),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: _TypingDots(pulse: _pulse),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(AssistantCard card) {
    return _cardShell(
      icon: IconsaxPlusBold.message_question,
      title: card.title,
      subtitle: card.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < card.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildVerticalActionRow(
              index: i,
              label: (card.items[i]['label'] ?? card.items[i]['title'] ?? '').toString(),
              onTap: () {
                final label = (card.items[i]['label'] ??
                        card.items[i]['title'] ??
                        card.items[i]['text'] ??
                        '')
                    .toString()
                    .trim();
                if (label.isNotEmpty) _send(label);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerticalActionRow({
    required int index,
    required String label,
    required VoidCallback onTap,
  }) {
    IconData getActionIcon(String l) {
      if (l.contains('הוסף') || l.contains('חדש')) return IconsaxPlusBold.add;
      if (l.contains('מחיר') || l.contains('שכירות')) return IconsaxPlusBold.wallet_3;
      if (l.contains('פרטי') || l.contains('דירה') || l.contains('בית')) return IconsaxPlusBold.house_2;
      if (l.contains('שאלה') || l.contains('שאל')) return IconsaxPlusBold.message_question;
      return IconsaxPlusLinear.arrow_left_2;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _kAccent.withValues(alpha: 0.18),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    getActionIcon(label),
                    color: _kAccent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  IconsaxPlusLinear.arrow_left_2,
                  color: _kMuted.withValues(alpha: 0.5),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioCard(AssistantTurn turn, AssistantCard card) {
    final seed = turn.text.hashCode;
    return GestureDetector(
      onTap: () => _service.speak(turn.text),
      child: _cardShell(
        icon: IconsaxPlusBold.volume_high,
        title: card.title,
        subtitle: card.subtitle,
        trailing: const Icon(IconsaxPlusBold.play, color: _kInk, size: 22),
        child: Row(
          children: [
            Expanded(child: _waveform(seed)),
            const SizedBox(width: 12),
            Text(
              card.subtitle ?? _estimateVoiceDuration(turn.text),
              style: const TextStyle(
                color: _kMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentCard(AssistantCard card) {
    final items = card.items.isEmpty ? [card.data] : card.items;
    return _cardShell(
      icon: IconsaxPlusBold.document_text,
      title: card.title,
      subtitle: card.subtitle,
      description: card.description,
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final item = items[i];
            final title =
                (item['title'] ?? item['name'] ?? item['fileName'] ?? 'מסמך')
                    .toString();
            final ext = (item['type'] ?? item['extension'] ?? 'doc').toString();
            return Container(
              width: 132,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(_documentIcon(ext), color: _kAccent, size: 24),
                  const Spacer(),
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _infoCard(AssistantCard card) {
    return _cardShell(
      icon: IconsaxPlusBold.info_circle,
      title: card.title,
      subtitle: card.subtitle,
      description: card.description,
    );
  }

  Widget _propertyDraftCard(
    Map<String, dynamic> d, {
    required bool isActive,
  }) {
    String v(String k) => (d[k]?.toString() ?? '').trim();
    final addr = [v('street'), v('streetNumber'), v('city')]
        .where((e) => e.isNotEmpty)
        .join(' ');
    final lines = <String>[
      if (addr.isNotEmpty) '📍  $addr',
      if (v('rooms').isNotEmpty) '🚪  ${v('rooms')} חדרים',
      if (v('floor').isNotEmpty) '🏢  קומה ${v('floor')}',
      if (v('price').isNotEmpty) '💰  ${v('price')} ₪ לחודש',
      if (v('sizeM2').isNotEmpty) '📐  ${v('sizeM2')} מ"ר',
      if (v('condition').isNotEmpty) '✨  ${v('condition')}',
      if (v('entryDate').isNotEmpty) '📅  כניסה: ${v('entryDate')}',
    ];

    return _cardShell(
      icon: IconsaxPlusBold.house_2,
      title: 'טיוטת דירה',
      subtitle: isActive ? 'אפשר לפרסם מכאן' : 'טיוטה מהשיחה',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.5),
                child: Text(
                  l,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              )),
          if (isActive) ...[
            const SizedBox(height: 14),
            _photoSection(),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kUserSurface,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(IconsaxPlusBold.tick_circle, size: 20),
                label: Text(
                  _publishing ? 'מפרסם את הדירה...' : 'כן, פרסם את הדירה',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                onPressed: _publishing ? null : () => _publishDraft(d),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _publishing
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AddPropertyScreen(initialDraft: d),
                        )),
                child: const Text(
                  'פתח עריכה מלאה',
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardShell({
    required IconData icon,
    required String title,
    String? subtitle,
    String? description,
    Widget? trailing,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.04),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kAccent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (trailing != null) trailing,
              if (trailing != null) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: _kMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _kAccent, size: 20),
              ),
            ],
          ),
          if (description != null && description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _kInk,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.42,
              ),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }

  Widget _waveform(int seed) {
    final random = math.Random(seed.abs());
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(34, (index) {
          final height = 7 + random.nextDouble() * 24;
          return Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: 2.5,
                height: height,
                decoration: BoxDecoration(
                  color: index < 20
                      ? _kInk.withValues(alpha: 0.62)
                      : _kMuted.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  IconData _documentIcon(String type) {
    final clean = type.toLowerCase();
    if (clean.contains('xls') || clean.contains('sheet')) {
      return IconsaxPlusBold.document_code;
    }
    if (clean.contains('pdf')) return IconsaxPlusBold.document_text;
    return IconsaxPlusBold.document;
  }

  Widget _photoSection() {
    final has = _photoUrls.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              has
                  ? 'נוספו ${_photoUrls.length} תמונות'
                  : 'צריך לפחות תמונה אחת',
              style: TextStyle(
                  color: has ? _kAccent : AppColors.coral,
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Icon(has ? IconsaxPlusBold.tick_circle : IconsaxPlusBold.gallery,
                color: has ? _kAccent : AppColors.coral, size: 20),
          ],
        ),
        if (has) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _thumb(_photoUrls[i]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _photoBtn(
            IconsaxPlusBold.gallery_add,
            'הוסף או ערוך תמונות',
            _openUploadPanel,
          ),
        ),
      ],
    );
  }

  Widget _photoBtn(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: (_pickingPhoto || _publishing) ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _kAccent,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide(color: _kAccent.withValues(alpha: 0.35), width: 1.3),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: _pickingPhoto
          ? SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2.2, color: _kAccent))
          : Icon(icon, size: 20),
      label: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }

  Widget _thumb(String url) {
    const fallback = SizedBox(
      width: 72,
      height: 72,
      child: ColoredBox(
        color: Color(0x1F5AD4DC),
        child: Icon(IconsaxPlusLinear.gallery, color: _kMuted),
      ),
    );
    if (url.startsWith('http')) {
      return Image.network(url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback);
    }
    return Image.file(File(url),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback);
  }

  Widget _listeningStrip() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kAccent.withValues(alpha: 0.20),
            _kAccent.withValues(alpha: 0.08),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent.withValues(alpha: 0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final scale = 1 + 0.18 * _pulse.value;
              return Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withValues(alpha: 0.16 * scale),
                ),
                child: Icon(IconsaxPlusBold.microphone,
                    color: _kAccent, size: 22),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _partial.isEmpty ? 'מקשיב לך... דבר בנחת' : _partial,
              style: const TextStyle(
                  color: _kInk, fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _ComposerCircleButton(
                icon: IconsaxPlusBold.add,
                backgroundColor: const Color(0xFFF1F5F8),
                foregroundColor: AppColors.textSecondary,
                tooltip: 'הוסף מדיה',
                onTap: _openUploadPanel,
                size: 48,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: AppColors.primary,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: _showVisualizer ? 'כתוב או דבר עם אריק...' : 'כתוב הודעה...',
                    hintStyle: TextStyle(
                        fontSize: 16, color: AppColors.textSecondary.withValues(alpha: 0.55)),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 11),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  onSubmitted: _send,
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _inputCtrl,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return _ComposerCircleButton(
                    icon: hasText
                        ? IconsaxPlusBold.send_1
                        : (_listening
                            ? IconsaxPlusBold.stop
                            : IconsaxPlusBold.microphone_2),
                    backgroundColor: hasText ? AppColors.primary : AppColors.coral,
                    foregroundColor: Colors.white,
                    tooltip: hasText ? 'שלח' : 'דיבור',
                    onTap: hasText ? () => _send(_inputCtrl.text) : _toggleMic,
                    useGradient: true,
                    gradientColors: hasText
                        ? [AppColors.primary, AppColors.primaryLight]
                        : (_listening
                            ? const [Color(0xFFE5484D), Color(0xFFFF8E99)]
                            : const [AppColors.coral, Color(0xFFFF8E99)]),
                    size: 52,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Option tile used in the kebab options sheet ───────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : _kAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: destructive ? color : _kInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: _kMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_left_2,
                color: _kMuted.withValues(alpha: 0.55), size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Animation helpers ─────────────────────────────────────────────────────────

/// One-shot fade + slide-up used for message bubbles and cards.
class _FadeInUp extends StatefulWidget {
  const _FadeInUp({required this.child});
  final Widget child;
  @override
  State<_FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<_FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420))
    ..forward();
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
            offset: Offset(0, (1 - _a.value) * 16), child: child),
      ),
      child: widget.child,
    );
  }
}

/// A staggered, springy quick-reply chip.
class _AnimatedChip extends StatefulWidget {
  const _AnimatedChip({
    super.key,
    required this.index,
    required this.label,
    required this.onTap,
  });
  final int index;
  final String label;
  final VoidCallback onTap;
  @override
  State<_AnimatedChip> createState() => _AnimatedChipState();
}

class _AnimatedChipState extends State<_AnimatedChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 70 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  IconData _getChipIcon(String label) {
    if (label.contains('הוסף') || label.contains('חדש')) return IconsaxPlusBold.add;
    if (label.contains('מחיר') || label.contains('שכירות')) return IconsaxPlusBold.wallet_3;
    if (label.contains('פרטי') || label.contains('דירה') || label.contains('בית')) return IconsaxPlusBold.house_2;
    if (label.contains('שאלה') || label.contains('שאל')) return IconsaxPlusBold.message_question;
    return IconsaxPlusLinear.arrow_left_3;
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _a,
      child: FadeTransition(
        opacity: _c,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                  color: _kAccent.withValues(alpha: 0.32), width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getChipIcon(widget.label),
                  color: _kAccent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _VoiceOrb extends StatefulWidget {
  const _VoiceOrb({
    required this.size,
    required this.listening,
    required this.speaking,
    required this.connecting,
    this.soundLevelNotifier,
  });

  final double size;
  final bool listening;
  final bool speaking;
  final bool connecting;
  final ValueNotifier<double>? soundLevelNotifier;

  @override
  State<_VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<_VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  double _level = 0.0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.size * 1.85;
    return SizedBox(
      width: field,
      height: field,
      child: ValueListenableBuilder<double>(
        valueListenable:
            widget.soundLevelNotifier ?? ValueNotifier<double>(0.0),
        builder: (context, raw, _) {
          final target = ((raw + 2.0) / 12.0).clamp(0.0, 1.0);
          // Snap up fast on sound, ease down slowly — feels reactive but smooth.
          final k = target > _level ? 0.5 : 0.12;
          _level += (target - _level) * k;
          return AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              return CustomPaint(
                size: Size(field, field),
                painter: _DotBlobPainter(
                  t: _anim.value,
                  level: _level,
                  listening: widget.listening,
                  speaking: widget.speaking,
                  connecting: widget.connecting,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Rently's living "AI orb": an asymmetric blob that constantly loses its shape
/// — far more when it hears or speaks — rendered as a flowing field of dots
/// (phyllotaxis) that deform with the surface, lit from within. App palette,
/// pure Canvas.
class _DotBlobPainter extends CustomPainter {
  _DotBlobPainter({
    required this.t,
    required this.level,
    required this.listening,
    required this.speaking,
    required this.connecting,
  });

  final double t; // 0..1 seamless loop
  final double level; // 0..1 smoothed audio amplitude
  final bool listening;
  final bool speaking;
  final bool connecting;

  // App palette.
  static const _bright = Color(0xFFB8FBFF);
  static const _tealLight = Color(0xFF5AD4DC);
  static const _teal = Color(0xFF13BEC9);
  static const _blue = Color(0xFF4A6CF7);
  static const _coral = Color(0xFFFF5A67);
  static const _deep = Color(0xFF06303A);

  static const int _dotCount = 150;
  // Phyllotaxis (sunflower) layout — even disk fill. (angle, normRadius, seed).
  static final List<_PolarDot> _dots = _build();
  static List<_PolarDot> _build() {
    final out = <_PolarDot>[];
    const golden = 2.399963229; // golden angle (rad)
    for (var i = 0; i < _dotCount; i++) {
      final rho = math.sqrt(i / _dotCount) * 1.14; // a few spill past the edge
      out.add(_PolarDot(golden * i, rho, (i * 53) % 100 / 100.0));
    }
    return out;
  }

  double get _tau => 2 * math.pi;

  // Multi-harmonic organic noise → big asymmetric lobes. Seamless over t∈[0,1].
  double _noise(double a) {
    final p = t * _tau;
    return 0.50 * math.sin(2 * a + p) +
        0.34 * math.sin(3 * a - 2 * p + 1.3) +
        0.22 * math.sin(5 * a + 3 * p + 0.5) +
        0.14 * math.sin(7 * a - p * 1.5 + 0.6);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;
    final base = s * 0.26;
    final active = listening || speaking || connecting;

    // It is ALWAYS morphing; sound (in = listening, out = speaking) drives it
    // much harder, so the orb visibly "loses its shape".
    double deform = 0.16 + 0.05 * math.sin(t * _tau * 1.5);
    if (connecting) deform += 0.05;
    if (speaking) deform += 0.14 * (0.4 + 0.6 * math.sin(t * _tau * 5).abs());
    if (listening) deform += 0.16 + level * 0.6;
    deform += level * 0.35;

    final warm = listening ? (0.4 + level * 0.4).clamp(0.0, 0.85) : 0.0;
    Color mix(Color x) => Color.lerp(x, _coral, warm)!;

    final breathe = 1 + 0.05 * math.sin(t * _tau) + level * 0.12;
    final baseR = base * breathe;

    double blobR(double a) => baseR * (1 + deform * _noise(a));

    // 1 ── Ambient glow.
    final glowR = baseR * 2.2;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            mix(_teal).withValues(alpha: (active ? 0.30 : 0.16) + level * 0.20),
            mix(_blue).withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: glowR))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // 2 ── Soft luminous body under the dots (follows the morph).
    final bodyPath = _blobPath(c, blobR);
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            mix(_tealLight).withValues(alpha: 0.55),
            mix(_teal).withValues(alpha: 0.40),
            _deep.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: baseR * 1.2))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // 3 ── The dot field — texture that flows with the surface.
    final dotPaint = Paint();
    for (final d in _dots) {
      final r = d.rho * blobR(d.angle);
      final pos = Offset(
        c.dx + r * math.cos(d.angle),
        c.dy + r * math.sin(d.angle),
      );
      // colour by radial position: bright core → teal → blue rim.
      final Color col = d.rho < 0.5
          ? Color.lerp(_bright, _teal, d.rho * 2)!
          : Color.lerp(_teal, _blue, ((d.rho - 0.5) / 0.64).clamp(0.0, 1.0))!;
      // twinkle + fade out past the edge.
      final twinkle = 0.65 + 0.35 * math.sin(t * _tau * 3 + d.seed * _tau);
      final edgeFade = d.rho > 1.0 ? (1.15 - d.rho) / 0.15 : 1.0;
      final op = ((1.0 - d.rho * 0.45) * twinkle * edgeFade * (active ? 1.0 : 0.85))
          .clamp(0.0, 1.0);
      final dotR = s * 0.0095 * (1.15 - 0.45 * d.rho) * (1 + level * 0.25);
      dotPaint.color = mix(col).withValues(alpha: op);
      canvas.drawCircle(pos, math.max(0.4, dotR), dotPaint);
    }

    // 4 ── Inner light — a soft pulsing glow from the core (lights the dots).
    final pulse = 0.5 +
        0.5 * math.sin(t * _tau * (speaking ? 5 : 2)).abs() +
        level * 0.4;
    final lc = Offset(c.dx - baseR * 0.1, c.dy - baseR * 0.12);
    canvas.drawCircle(
      lc,
      baseR * 0.7,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _bright.withValues(alpha: (0.30 + 0.32 * pulse).clamp(0.0, 0.75)),
            mix(_teal).withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: lc, radius: baseR * 0.7))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  Path _blobPath(Offset c, double Function(double a) radius) {
    const n = 96;
    final pts = List<Offset>.generate(n, (i) {
      final a = (i / n) * _tau;
      final r = radius(a);
      return Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    });
    final path = Path();
    final start = Offset(
        (pts[0].dx + pts[n - 1].dx) / 2, (pts[0].dy + pts[n - 1].dy) / 2);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      path.quadraticBezierTo(
          cur.dx, cur.dy, (cur.dx + next.dx) / 2, (cur.dy + next.dy) / 2);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _DotBlobPainter old) =>
      old.t != t ||
      old.level != level ||
      old.listening != listening ||
      old.speaking != speaking ||
      old.connecting != connecting;
}

class _PolarDot {
  const _PolarDot(this.angle, this.rho, this.seed);
  final double angle;
  final double rho;
  final double seed;
}
class _ComposerCircleButton extends StatelessWidget {
  const _ComposerCircleButton({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.tooltip,
    required this.onTap,
    this.useGradient = false,
    this.gradientColors,
    this.size = 50.0,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final String tooltip;
  final VoidCallback onTap;
  final bool useGradient;
  final List<Color>? gradientColors;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gColors = gradientColors ?? [_kAccent, _kAccent2];
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: useGradient ? null : backgroundColor,
            gradient: useGradient
                ? LinearGradient(
                    colors: gColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: (useGradient ? gColors.first : _kInk).withValues(alpha: useGradient ? 0.35 : 0.10),
                blurRadius: useGradient ? 18 : 16,
                offset: Offset(0, useGradient ? 6 : 8),
              ),
            ],
          ),
          child: Icon(icon, color: foregroundColor, size: size * 0.48),
        ),
      ),
    );
  }
}

/// Three breathing dots used for the "Erik is thinking" bubble.
class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.pulse});
  final Animation<double> pulse;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (pulse.value + i * 0.33) % 1.0;
            final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      color: _kAccent, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
