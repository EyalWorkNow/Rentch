import 'dart:async';

import 'package:dating_app/core/chat/slot_message.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:dating_app/presentation/features/calendar/availability_calendar_screen.dart';
import 'package:dating_app/core/security/rate_limiter.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/chat_provider.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:dating_app/presentation/widgets/swipe_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/screens/contract_detail_screen.dart';
import 'package:dating_app/presentation/screens/contract_form_screen.dart';
import 'package:dating_app/presentation/screens/contract_sign_flow_screen.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:dating_app/presentation/widgets/fade_slide_entrance.dart';
import 'package:dating_app/presentation/widgets/pulse_widget.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _bg = AppColors.slate50;
const _surface = Colors.white;
const _border = AppColors.slate200;
Color get _outgoing => AppColors.primary; // brand bubble, follows accent
const _incoming = AppColors.slate100; // light-grey bubble

class _ChatThemeSpec {
  const _ChatThemeSpec({
    required this.backgroundColor,
    required this.appBarColor,
    required this.composerColor,
    required this.inputColor,
    required this.borderColor,
    required this.outgoingColor,
    required this.incomingColor,
    required this.primaryText,
    required this.secondaryText,
    required this.iconSurface,
    required this.accent,
    this.backgroundGradient,
    this.glassChrome = false,
  });

  final Color backgroundColor;
  final Color appBarColor;
  final Color composerColor;
  final Color inputColor;
  final Color borderColor;
  final Color outgoingColor;
  final Color incomingColor;
  final Color primaryText;
  final Color secondaryText;
  final Color iconSurface;
  final Color accent;
  final Gradient? backgroundGradient;
  final bool glassChrome;

  static final standard = _ChatThemeSpec(
    backgroundColor: _bg,
    appBarColor: _surface,
    composerColor: _surface,
    inputColor: Colors.white,
    borderColor: _border,
    outgoingColor: _outgoing,
    incomingColor: _incoming,
    primaryText: AppColors.navy,
    secondaryText: AppColors.textSecondary,
    iconSurface: AppColors.slate100,
    accent: AppColors.primary,
  );

  factory _ChatThemeSpec.forBranding(BrokerBrandingConfig branding) {
    return switch (branding.chatTemplate) {
      BrokerChatTemplate.rentlyClassic => standard.copyWith(
          accent: branding.primaryColor,
          outgoingColor: branding.primaryColor,
        ),
      BrokerChatTemplate.softGlass => _ChatThemeSpec(
          backgroundColor: Color.alphaBlend(
            branding.primaryColor.withValues(alpha: 0.06),
            AppColors.slate50,
          ),
          appBarColor: Colors.white.withValues(alpha: 0.78),
          composerColor: Colors.white.withValues(alpha: 0.74),
          inputColor: Colors.white.withValues(alpha: 0.82),
          borderColor: branding.primaryColor.withValues(alpha: 0.14),
          outgoingColor: branding.primaryColor,
          incomingColor: Colors.white.withValues(alpha: 0.82),
          primaryText: branding.secondaryColor,
          secondaryText: branding.secondaryColor.withValues(alpha: 0.58),
          iconSurface: Colors.white.withValues(alpha: 0.76),
          accent: branding.primaryColor,
          glassChrome: true,
          backgroundGradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              branding.primaryColor.withValues(alpha: 0.14),
              branding.accentColor.withValues(alpha: 0.12),
              AppColors.slate50,
            ],
          ),
        ),
      BrokerChatTemplate.editorialLight => _ChatThemeSpec(
          backgroundColor: AppColors.cloud,
          appBarColor: AppColors.surface,
          composerColor: AppColors.surface,
          inputColor: Colors.white,
          borderColor: const Color(0xFFE9E0D2),
          outgoingColor: branding.secondaryColor,
          incomingColor: Colors.white,
          primaryText: branding.secondaryColor,
          secondaryText: const Color(0xFF8B8174),
          iconSurface: AppColors.slate200,
          accent: branding.primaryColor,
        ),
      BrokerChatTemplate.nightSuite => _ChatThemeSpec(
          backgroundColor: branding.secondaryColor,
          appBarColor: Color.alphaBlend(
            Colors.black.withValues(alpha: 0.18),
            branding.secondaryColor,
          ),
          composerColor: Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            branding.secondaryColor,
          ),
          inputColor: Colors.white.withValues(alpha: 0.10),
          borderColor: Colors.white.withValues(alpha: 0.14),
          outgoingColor: branding.primaryColor,
          incomingColor: Colors.white.withValues(alpha: 0.12),
          primaryText: Colors.white,
          secondaryText: Colors.white.withValues(alpha: 0.64),
          iconSurface: Colors.white.withValues(alpha: 0.12),
          accent: branding.accentColor,
          glassChrome: true,
          backgroundGradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              branding.primaryColor.withValues(alpha: 0.26),
              branding.secondaryColor,
              Colors.black.withValues(alpha: 0.86),
            ],
          ),
        ),
    };
  }

  _ChatThemeSpec copyWith({
    Color? accent,
    Color? outgoingColor,
  }) {
    return _ChatThemeSpec(
      backgroundColor: backgroundColor,
      appBarColor: appBarColor,
      composerColor: composerColor,
      inputColor: inputColor,
      borderColor: borderColor,
      outgoingColor: outgoingColor ?? this.outgoingColor,
      incomingColor: incomingColor,
      primaryText: primaryText,
      secondaryText: secondaryText,
      iconSurface: iconSurface,
      accent: accent ?? this.accent,
      backgroundGradient: backgroundGradient,
      glassChrome: glassChrome,
    );
  }
}
// ─── Screen ───────────────────────────────────────────────────────────────────

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  ChatProvider? _chatProvider;
  bool _chatInitialized = false;
  bool _actionsOpen = false;

  // ── Viewing scheduling ────────────────────────────────────────────────────
  final AvailabilityRepository _availabilityRepo = AvailabilityRepository();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_chatInitialized) {
      _chatInitialized = true;
      _initChat();
    }
  }

  void _initChat() {
    final dating = context.read<DatingProvider>();
    final match = dating.matchById(widget.matchId);
    if (match == null) return;

    final senderName = dating.tenantProfile?.name ?? 'השוכר';
    _chatProvider = ChatProvider(
      matchId: widget.matchId,
      senderName: senderName,
      seedMessages: match.messages,
    );
    _chatProvider!.addListener(_onChatUpdate);
    _chatProvider!.initialize();
  }

  void _onChatUpdate() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _chatProvider?.removeListener(_onChatUpdate);
    _chatProvider?.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  Future<void> _handleSend(DatingProvider provider, String senderName) async {
    final raw = _msgCtrl.text.trim();
    if (raw.isEmpty) return;

    if (InputSanitizer.isMessageTooLong(raw)) {
      _snack(
          'הודעה ארוכה מדי (מקסימום ${SecurityConfig.maxMessageLength} תווים)',
          error: true);
      return;
    }
    if (!RateLimiter.instance.allowMessage()) {
      _snack('שלחת יותר מדי הודעות. המתן רגע.', error: true);
      return;
    }
    if (InputSanitizer.containsObjectionableContent(raw)) {
      _snack('ההודעה מכילה תוכן לא הולם ולכן לא נשלחה.', error: true);
      return;
    }

    final text = InputSanitizer.sanitizeMessage(raw);
    _msgCtrl.clear();

    if (_chatProvider != null) {
      await _chatProvider!.sendMessage(text);
    } else {
      await provider.sendMessage(
        matchId: widget.matchId,
        sender: senderName,
        text: text,
      );
      _scrollToBottom();
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text(msg),
      backgroundColor: error ? AppColors.coral : AppColors.primary,
    ));
  }

  // ── Media / file picker ───────────────────────────────────────────────────

  Future<void> _pickAndSendMedia(
      DatingProvider provider, String senderName) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (file == null || !mounted) return;
      // SEC: never store local device paths in messages — they expose the
      // file system to the other party and are useless cross-device.
      await provider.sendMessage(
        matchId: widget.matchId,
        sender: senderName,
        text: '📷 [תמונה]',
      );
      _scrollToBottom();
    } catch (_) {
      if (mounted) _snack('לא ניתן לגשת לגלריה', error: true);
    }
  }

  Future<void> _pickAndSendFile(
      DatingProvider provider, String senderName) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      // SEC: send only the file name, never the full local path.
      final safeName = file.name.split('/').last.split('\\').last;
      await provider.sendMessage(
        matchId: widget.matchId,
        sender: senderName,
        text: '📎 [$safeName]',
      );
      _scrollToBottom();
    } catch (_) {
      if (mounted) _snack('לא ניתן לגשת לקבצים', error: true);
    }
  }

  // ── Block user ────────────────────────────────────────────────────────────

  void _showBlockConfirm(DatingProvider provider, String ownerName) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: AppColors.coral,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'חסום משתמש',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            'האם לחסום את "$ownerName"?\n\nכל המודעות שלהם יוסרו מהפיד שלך מיידית. הדיווח יועבר לצוות Rently.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text(
                'ביטול',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await provider.blockOwner(ownerName);
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text(
                'חסום',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────

  void _showTemplates() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TemplateLibrarySheet(
        onSelect: (text) {
          _msgCtrl.text = text;
          _msgCtrl.selection = TextSelection.collapsed(offset: text.length);
        },
      ),
    );
  }

  void _showActions(
    DatingProvider provider,
    RentalMatch match,
    RentalProperty property,
    String tenantName,
  ) async {
    setState(() => _actionsOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActionsSheet(
        match: match,
        ownerName: property.ownerName,
        // Proposing viewing times is a landlord/owner-only action.
        onProposeTimes: provider.isLandlord
            ? () {
                Navigator.pop(context);
                _showProposeTimes(provider, property, tenantName);
              }
            : null,
        onQuickMessage: () {
          Navigator.pop(context);
          _showTemplates();
        },
        onAttachFile: () {
          Navigator.pop(context);
          _pickAndSendFile(provider, tenantName);
        },
        onAttachMedia: () {
          Navigator.pop(context);
          _pickAndSendMedia(provider, tenantName);
        },
        onSendContract: match.contractSent
            ? null
            : () async {
                Navigator.pop(context);
                final existing = provider.contractForMatch(match.id);
                if (existing != null) {
                  _openContract(existing.id, match.id);
                } else if (provider.isLandlord) {
                  final confirmed = await SwipeToConfirmSheet.show(
                    context,
                    title: 'לשלוח חוזה?',
                    message:
                        'האם אתה בטוח שאתה רוצה לשלוח חוזה לצד השני?',
                  );
                  if (!confirmed || !mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ContractFormScreen(matchId: match.id),
                  ));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('ממתין שבעל הדירה ישלח חוזה לחתימה'),
                  ));
                }
              },
        onOwnerSign: (!match.contractSent || match.ownerSigned)
            ? null
            : () {
                Navigator.pop(context);
                _openContractForMatch(provider, match.id);
              },
        onTenantSign: (!match.contractSent || match.tenantSigned)
            ? null
            : () {
                Navigator.pop(context);
                _openContractForMatch(provider, match.id);
              },
        onBlockUser: () {
          Navigator.pop(context);
          _showBlockConfirm(provider, property.ownerName);
        },
      ),
    );
    if (mounted) {
      setState(() => _actionsOpen = false);
    }
  }

  void _openContract(String contractId, String matchId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ContractDetailScreen(contractId: contractId, matchId: matchId),
    ));
  }

  /// Opens the clean, built-in signing flow (review → parties → one-tap sign).
  void _openSignFlow(String contractId, String matchId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ContractSignFlowScreen(contractId: contractId, matchId: matchId),
    ));
  }

  void _openContractForMatch(DatingProvider provider, String matchId) {
    final contract = provider.contractForMatch(matchId);
    if (contract != null) {
      _openSignFlow(contract.id, matchId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('החוזה לא נמצא. נסו לרענן את הצ׳אט.'),
      ));
    }
  }

  // ── Viewing scheduling ────────────────────────────────────────────────────

  /// Send a structured (marker-carrying) chat message. Bypasses the plain-text
  /// sanitizer/objectionable-content filter so the `[[...]]` payload survives.
  Future<void> _sendStructured(
      DatingProvider provider, String senderName, String text) async {
    if (_chatProvider != null) {
      await _chatProvider!.sendMessage(text);
    } else {
      await provider.sendMessage(
          matchId: widget.matchId, sender: senderName, text: text);
      _scrollToBottom();
    }
  }

  /// Landlord action: pick up to 3 open, future availability slots and propose
  /// them to the tenant as an in-chat card.
  Future<void> _showProposeTimes(
    DatingProvider provider,
    RentalProperty property,
    String senderName,
  ) async {
    final selected = await showModalBottomSheet<List<AvailabilitySlot>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProposeTimesSheet(
        repo: _availabilityRepo,
        onAddTimes: () {
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AvailabilityCalendarScreen(),
          ));
        },
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final proposal = SlotProposal(
      propertyId: property.id,
      options: selected
          .map((s) => SlotOption(
                slotId: s.id,
                start: s.start,
                durationMinutes: s.durationMinutes,
              ))
          .toList(),
    );
    await _sendStructured(
        provider, senderName, SlotMessageCodec.encodeProposal(proposal));
  }

  /// Tenant action: confirm one proposed option. Sends a confirm card and books
  /// the tenant's own 1h-before reminder.
  Future<void> _confirmSlot(
    DatingProvider provider,
    String senderName,
    RentalProperty property,
    SlotOption option,
  ) async {
    final confirm = SlotConfirm(
      slotId: option.slotId,
      start: option.start,
      durationMinutes: option.durationMinutes,
      propertyId: property.id,
    );
    await _sendStructured(
        provider, senderName, SlotMessageCodec.encodeConfirm(confirm));
    await NotificationService.instance.scheduleReminder(
      id: NotificationService.instance.viewingReminderId(option.slotId),
      title: 'צפייה בדירה בעוד שעה',
      body: 'צפייה ב${property.address} בשעה ${_formatTime(option.start)}',
      when: option.start.subtract(const Duration(hours: 1)),
    );
    if (mounted) _snack('הצפייה אושרה — נשלחה הודעה ונקבעה תזכורת');
  }

  // Landlord-side confirm→booking processing now lives in
  // [DatingProvider.processViewingConfirms] so it is GLOBAL (scans every match
  // thread) and reactive — a tenant's confirmation books the slot + schedules
  // the landlord reminder + surfaces on the dashboard even if the landlord never
  // opens this specific chat (SCHED-4). It is idempotent and fail-soft, so the
  // per-thread trigger below and the merged-screen trigger both call it safely.

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final match = provider.matchById(widget.matchId);
        if (match == null) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: Text('ההתאמה לא נמצאה')),
          );
        }

        final property = provider.propertyById(match.propertyId);
        if (property == null) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: Text('הנכס לא נמצא')),
          );
        }

        final messages = _chatProvider?.messages ?? match.messages;
        final isSending = _chatProvider?.isSending ?? false;
        final isLoading = _chatProvider?.isLoading ?? false;
        final isRemote = _chatProvider?.isRemoteEnabled ?? false;
        final isConnected = _chatProvider?.realtimeConnected ?? false;
        final tenantName = provider.tenantProfile?.name ?? 'השוכר';
        final imageUrl =
            property.imageUrls.isNotEmpty ? property.imageUrls.first : '';
        final chatTheme = provider.isBroker
            ? _ChatThemeSpec.forBranding(provider.brokerBranding)
            : _ChatThemeSpec.standard;

        // Landlord: turn any tenant confirmations into calendar bookings +
        // reminders. Global + idempotent, so running it each rebuild is safe.
        if (provider.isLandlord) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) provider.processViewingConfirms();
          });
        }

        return Scaffold(
          backgroundColor: chatTheme.backgroundColor,
          resizeToAvoidBottomInset: true,

          // ── AppBar ──────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: chatTheme.appBarColor,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            shadowColor: chatTheme.borderColor,
            iconTheme: IconThemeData(color: chatTheme.primaryText),
            titleSpacing: 0,
            title: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(property: property),
                  ),
                );
              },
              child: Row(children: [
                // Property thumbnail
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: chatTheme.borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SafeImage(
                      source: imageUrl,
                      fallback: Container(
                        color: chatTheme.iconSurface,
                        child: RentlyIcon(IconsaxPlusLinear.building,
                            color: chatTheme.accent, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(property.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: chatTheme.primaryText,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '${property.priceLabel} · ${property.city}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: chatTheme.secondaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                // Connection dot
                if (isRemote)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PulseWidget(
                      scaleUpTo: 1.35,
                      duration: const Duration(milliseconds: 1500),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isConnected ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            // Actions menu icon + block popup
            actions: [
              IconButton(
                icon: RentlyIcon(IconsaxPlusLinear.more_circle,
                    color: chatTheme.primaryText, size: 22),
                tooltip: 'פעולות',
                onPressed: () =>
                    _showActions(provider, match, property, tenantName),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    color: chatTheme.primaryText, size: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (val) {
                  if (val == 'block') {
                    _showBlockConfirm(provider, property.ownerName);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'block',
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.coral.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.block_rounded,
                              size: 16, color: AppColors.coral),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'חסום משתמש זה',
                          style: TextStyle(
                            color: AppColors.coral,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: chatTheme.borderColor),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          body: SafeArea(
            top: false,
            bottom: false,
            child: _ChatBackground(
              theme: chatTheme,
              child: Column(
                children: [
                  // Contract progress bar (compact strip, only when started)
                  if (match.contractSent)
                    _ContractBar(
                      match: match,
                      isLandlord: provider.isLandlord,
                      onSign: () => _openContractForMatch(provider, match.id),
                      onView: () {
                        final c = provider.contractForMatch(match.id);
                        if (c != null) _openContract(c.id, match.id);
                      },
                    ),

                  // Message list
                  Expanded(
                    child: _buildMessageList(
                      messages,
                      tenantName,
                      isLoading,
                      chatTheme,
                      provider,
                      property,
                    ),
                  ),

                  if (isSending)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TypingIndicatorDots(color: chatTheme.secondaryText),
                            const SizedBox(width: 8),
                            Text(
                              'הצד השני מקליד...',
                              style: TextStyle(
                                color: chatTheme.secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Input bar
                  _MessageInput(
                    controller: _msgCtrl,
                    isSending: isSending,
                    actionsOpen: _actionsOpen,
                    theme: chatTheme,
                    onSend: () => _handleSend(provider, tenantName),
                    onActions: () =>
                        _showActions(provider, match, property, tenantName),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageList(
    List<ChatMessage> messages,
    String tenantName,
    bool isLoading,
    _ChatThemeSpec theme,
    DatingProvider provider,
    RentalProperty property,
  ) {
    if (messages.isEmpty && !isLoading) return _EmptyChat(theme: theme);

    // Every slotId that has been confirmed anywhere in the thread → drives the
    // "מאושר ✓ / disable the rest" state on proposal cards.
    final confirmedSlotIds = <String>{};
    for (final m in messages) {
      final r = SlotMessageCodec.parse(m.text);
      if (r is SlotConfirmMessage) confirmedSlotIds.add(r.confirm.slotId);
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final prev = index == 0 ? null : messages[index - 1];
            final isTenant = msg.sender == tenantName;
            final showDate =
                prev == null || !_isSameDay(prev.createdAt, msg.createdAt);
            final showAvatar =
                !isTenant && (prev == null || prev.sender != msg.sender);
            final isPending = msg.id.startsWith('temp_');

            final parsed = SlotMessageCodec.parse(msg.text);
            Widget row;
            if (parsed is SlotProposalMessage) {
              row = _SlotProposalCard(
                proposal: parsed.proposal,
                isMine: isTenant,
                createdAt: msg.createdAt,
                confirmedSlotIds: confirmedSlotIds,
                // Only the recipient (tenant) can confirm; sender = read-only.
                onConfirm: isTenant
                    ? null
                    : (opt) =>
                        _confirmSlot(provider, tenantName, property, opt),
              );
            } else if (parsed is SlotConfirmMessage) {
              row = _SlotConfirmCard(
                confirm: parsed.confirm,
                isMine: isTenant,
                createdAt: msg.createdAt,
              );
            } else {
              row = _MessageBubble(
                message: msg,
                isTenant: isTenant,
                showAvatar: showAvatar,
                isPending: isPending,
                theme: theme,
              );
            }

            return Column(
              children: [
                if (showDate) _DateDivider(date: msg.createdAt, theme: theme),
                FadeSlideEntrance(
                  duration: const Duration(milliseconds: 250),
                  offset: const Offset(0.0, 15.0),
                  child: row,
                ),
              ],
            );
          },
        ),
        if (isLoading)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: theme.primaryText,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text('טוען הודעות...',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({
    required this.theme,
    required this.child,
  });

  final _ChatThemeSpec theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        gradient: theme.backgroundGradient,
      ),
      child: child,
    );
  }
}

// ─── Compact contract strip ───────────────────────────────────────────────────

class _ContractBar extends StatelessWidget {
  _ContractBar({
    required this.match,
    required this.isLandlord,
    required this.onSign,
    required this.onView,
  });

  final RentalMatch match;
  final bool isLandlord;
  final VoidCallback onSign;
  final VoidCallback onView;

  bool get _done => match.ownerSigned && match.tenantSigned;

  /// Whether the *current* user still has to sign their own part.
  bool get _iNeedToSign =>
      !_done && (isLandlord ? !match.ownerSigned : !match.tenantSigned);

  String get _label {
    if (_done) return 'החוזה נחתם על-ידי שני הצדדים ✓';
    if (_iNeedToSign) {
      final other = isLandlord ? 'השוכר/ת' : 'בעל הדירה';
      final otherSigned = isLandlord ? match.tenantSigned : match.ownerSigned;
      return otherSigned ? '$other חתם/ה · ממתין לחתימתך' : 'ממתין לחתימתך';
    }
    // I already signed → waiting on the other side.
    final other = isLandlord ? 'השוכר/ת' : 'בעל הדירה';
    return 'חתמת · ממתין לחתימת $other';
  }

  @override
  Widget build(BuildContext context) {
    final action = _iNeedToSign ? onSign : onView;
    return GestureDetector(
      onTap: action,
      child: Container(
        color: _done ? AppColors.primaryLight2 : AppColors.primaryLight2,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(
            _done
                ? IconsaxPlusLinear.tick_circle
                : IconsaxPlusLinear.document_text,
            size: 16,
            color: _done ? AppColors.success : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _label,
              style: TextStyle(
                color: _done ? AppColors.success : AppColors.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _iNeedToSign ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: _iNeedToSign
                  ? null
                  : Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              _iNeedToSign ? 'חתום' : 'הצג',
              style: TextStyle(
                  color: _iNeedToSign ? Colors.white : AppColors.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Actions bottom sheet ─────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({
    required this.match,
    required this.ownerName,
    required this.onProposeTimes,
    required this.onQuickMessage,
    required this.onAttachFile,
    required this.onAttachMedia,
    required this.onSendContract,
    required this.onOwnerSign,
    required this.onTenantSign,
    required this.onBlockUser,
  });

  final RentalMatch match;
  final String ownerName;
  final VoidCallback? onProposeTimes;
  final VoidCallback onQuickMessage;
  final VoidCallback onAttachFile;
  final VoidCallback onAttachMedia;
  final VoidCallback? onSendContract;
  final VoidCallback? onOwnerSign;
  final VoidCallback? onTenantSign;
  final VoidCallback onBlockUser;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItem(
        icon: IconsaxPlusLinear.pen_tool,
        label: 'חתימת בעלים',
        subtitle: !match.contractSent
            ? 'זמין אחרי שליחת חוזה'
            : match.ownerSigned
                ? 'הושלם ✓'
                : 'חתום על החוזה',
        enabled: match.contractSent && !match.ownerSigned,
        onTap: onOwnerSign,
      ),
      _ActionItem(
        icon: IconsaxPlusLinear.edit,
        label: 'חתימת שוכר',
        subtitle: !match.contractSent
            ? 'זמין אחרי שליחת חוזה'
            : match.tenantSigned
                ? 'הושלם ✓'
                : 'אשר חתימת שוכר',
        enabled: match.contractSent && !match.tenantSigned,
        onTap: onTenantSign,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('פעולות שיחה',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: IconsaxPlusLinear.message_text,
                  label: 'הודעה מהירה',
                  onTap: onQuickMessage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickActionButton(
                  icon: IconsaxPlusLinear.document_upload,
                  label: 'קובץ',
                  onTap: onAttachFile,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickActionButton(
                  icon: IconsaxPlusLinear.gallery,
                  label: 'מדיה',
                  onTap: onAttachMedia,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (onProposeTimes != null) ...[
            _ProposeTimesCard(onTap: onProposeTimes!),
            const SizedBox(height: 10),
          ],
          _SendContractCard(
            sent: match.contractSent,
            onTap: onSendContract,
          ),
          const SizedBox(height: 6),
          ...actions.map((a) => _ActionTile(item: a)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.slate100),
          const SizedBox(height: 4),
          // ── Danger zone ──────────────────────────────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBlockUser,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        size: 18,
                        color: AppColors.coral,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'חסום משתמש זה',
                            style: TextStyle(
                              color: AppColors.coral,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            ownerName.isNotEmpty
                                ? 'הסר את "$ownerName" מהפיד שלך'
                                : 'הסר משתמש זה מהפיד שלך',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: AppColors.coral,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prominent, on-brand "send contract" CTA card used in the actions sheet.
class _SendContractCard extends StatelessWidget {
  _SendContractCard({required this.sent, required this.onTap});

  final bool sent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !sent && onTap != null;
    final accent = enabled ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.14),
                      AppColors.primaryLight2,
                    ],
                  )
                : null,
            color: enabled ? null : AppColors.cloud,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.30)
                  : AppColors.borderLight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled ? accent : AppColors.border,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  sent
                      ? IconsaxPlusLinear.tick_circle
                      : IconsaxPlusLinear.document_text,
                  size: 24,
                  color: enabled ? Colors.white : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'שליחת חוזה',
                      style: TextStyle(
                        color: enabled ? AppColors.navy : AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sent
                          ? 'החוזה כבר נשלח לצד השני'
                          : 'שלח טיוטת חוזה לחתימה דיגיטלית',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.keyboard_arrow_left_rounded,
                  size: 24,
                  color: accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
}

class _ActionTile extends StatelessWidget {
  _ActionTile({required this.item});
  final _ActionItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.enabled ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.enabled
                    ? AppColors.primaryLight2
                    : AppColors.slate100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: TextStyle(
                          color: item.enabled
                              ? AppColors.navy
                              : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  Text(item.subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (item.enabled)
              const RentlyIcon(IconsaxPlusLinear.arrow_left,
                  size: 14, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  _EmptyChat({required this.theme});

  final _ChatThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryLight2,
                shape: BoxShape.circle,
              ),
              child: RentlyIcon(IconsaxPlusLinear.message,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 16),
            const Text('הצ׳אט מוכן',
                style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text(
              'שלח הודעה כדי להתחיל את השיחה.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  _MessageBubble({
    required this.message,
    required this.isTenant,
    required this.showAvatar,
    required this.isPending,
    required this.theme,
  });

  final _ChatThemeSpec theme;
  final ChatMessage message;
  final bool isTenant;
  final bool showAvatar;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isTenant ? theme.accent : _incoming;
    final textColor = isTenant ? Colors.white : AppColors.navy;
    final metaColor = isTenant
        ? Colors.white.withValues(alpha: 0.75)
        : AppColors.textSecondary;

    // Detect media messages (📷 / 📎 prefix) for richer bubble rendering.
    // Legacy __img__: paths are treated as plain text (no file path exposure).
    final isImg = message.text == '📷 [תמונה]';
    final isFile =
        message.text.startsWith('📎 [') && message.text.endsWith(']');
    final isMedia = isImg || isFile;

    Widget messageContent;
    if (isImg) {
      messageContent = _MediaBubbleContent(
        icon: Icons.image_rounded,
        label: 'תמונה',
        color: isTenant ? Colors.white : AppColors.primary,
      );
    } else if (isFile) {
      final label = message.text.substring(4, message.text.length - 1);
      messageContent = _MediaBubbleContent(
        icon: Icons.attach_file_rounded,
        label: label.isNotEmpty ? label : 'קובץ',
        color: isTenant ? Colors.white : AppColors.primary,
      );
    } else {
      messageContent = Text(
        message.text,
        style: TextStyle(
          fontSize: 14.5,
          color: textColor,
          height: 1.48,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final bubble = AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isPending ? 0.6 : 1.0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (isMedia ? 0.62 : 0.74),
        ),
        margin: EdgeInsets.only(
          top: showAvatar || isTenant ? 8 : 3,
          bottom: 3,
        ),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topRight: const Radius.circular(20),
            topLeft: const Radius.circular(20),
            bottomRight:
                isTenant ? const Radius.circular(6) : const Radius.circular(20),
            bottomLeft:
                isTenant ? const Radius.circular(20) : const Radius.circular(6),
          ),
          border: isTenant ? null : Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment:
              isTenant ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isTenant && showAvatar) ...[
              Text(
                message.sender,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
            ],
            messageContent,
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    color: metaColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isTenant) ...[
                  const SizedBox(width: 3),
                  AnimatedScale(
                    scale: isPending ? 1.0 : 1.25,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    child: Icon(
                      isPending ? Icons.done_rounded : Icons.done_all_rounded,
                      size: 12,
                      color: isPending
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppColors.sky,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: isTenant ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment:
            isTenant ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isTenant) ...[
            _SenderAvatar(show: showAvatar),
            const SizedBox(width: 6),
          ],
          BubbleEntrance(
            isMe: isTenant,
            child: bubble,
          ),
        ],
      ),
    );
  }
}

class _MediaBubbleContent extends StatelessWidget {
  const _MediaBubbleContent({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  _SenderAvatar({required this.show});
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox(width: 28);
    return PulseRing(
      ringColor: AppColors.primary,
      maxRadius: 4.0,
      active: true,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          shape: BoxShape.circle,
        ),
        child: RentlyIcon(IconsaxPlusLinear.building,
            color: AppColors.primary, size: 12),
      ),
    );
  }
}

// ─── Date divider ─────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date, required this.theme});

  final _ChatThemeSpec theme;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        const Expanded(child: Divider(color: _border, thickness: 1)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _border),
          ),
          child: Text(_formatDay(date),
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const Expanded(child: Divider(color: _border, thickness: 1)),
      ]),
    );
  }
}

// ─── Message input bar ────────────────────────────────────────────────────────

class _MessageInput extends StatelessWidget {
  const _MessageInput({
    required this.controller,
    required this.isSending,
    required this.actionsOpen,
    required this.onSend,
    required this.onActions,
    required this.theme,
  });

  final _ChatThemeSpec theme;

  final TextEditingController controller;
  final bool isSending;
  final bool actionsOpen;
  final VoidCallback onSend;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 8 + bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Send on the right in RTL layouts.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              final hasText = value.text.trim().isNotEmpty;
              final isVisible = hasText || isSending;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: isVisible ? 58.0 : 0.0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: isVisible ? 1.0 : 0.0,
                  curve: Curves.easeOutBack,
                  child: isVisible
                      ? Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: _SendBtn(isSending: isSending, onTap: onSend),
                        )
                      : const SizedBox.shrink(),
                ),
              );
            },
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 118),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.slate200),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'כתיבת הודעה...',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Plus on the left in RTL layouts.
          AnimatedRotation(
            turns: actionsOpen ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: _IconBtn(
              icon: Icons.add_rounded,
              color: AppColors.navy,
              bg: AppColors.slate100,
              onTap: onActions,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.88,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  _SendBtn({required this.isSending, required this.onTap});

  final bool isSending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final btn = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 48,
      height: 44,
      decoration: BoxDecoration(
        gradient: isSending
            ? LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.45),
                  AppColors.primary.withValues(alpha: 0.3),
                ],
              )
            : LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: isSending
            ? const []
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.26),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Center(
        child: isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const RentlyIcon(
                IconsaxPlusLinear.send_1,
                color: Colors.white,
                size: 18,
              ),
      ),
    );

    if (isSending) {
      return btn;
    }

    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.88,
      child: btn,
    );
  }
}

// ─── Template library ─────────────────────────────────────────────────────────

class _TemplateMessage {
  const _TemplateMessage({
    required this.category,
    required this.label,
    required this.text,
    required this.icon,
  });
  final String category;
  final String label;
  final String text;
  final IconData icon;
}

class _TemplateLibrarySheet extends StatelessWidget {
  _TemplateLibrarySheet({required this.onSelect});
  final ValueChanged<String> onSelect;

  static const _templates = [
    _TemplateMessage(
      category: 'פתיחה',
      label: 'הודעת ברכה',
      text:
          'שלום! קיבלתי את הבקשה שלך. אשמח לענות על שאלות ולתאם ביקור. מתי נוח לך?',
      icon: IconsaxPlusLinear.home_2,
    ),
    _TemplateMessage(
      category: 'פתיחה',
      label: 'אישור עניין',
      text:
          'תודה על ההתעניינות! הדירה עדיין פנויה. אשמח לתאם ביקור בשבוע הקרוב.',
      icon: IconsaxPlusLinear.tick_circle,
    ),
    _TemplateMessage(
      category: 'ביקור',
      label: 'תיאום ביקור',
      text: 'אני זמין לביקור ביום __ בשעה __. האם מתאים לך?',
      icon: IconsaxPlusLinear.calendar,
    ),
    _TemplateMessage(
      category: 'ביקור',
      label: 'אישור ביקור',
      text: 'מעולה! מאשר ביקור ביום __ בשעה __. הכתובת: ___.',
      icon: IconsaxPlusLinear.location,
    ),
    _TemplateMessage(
      category: 'חוזה',
      label: 'שליחת חוזה',
      text: 'שלחתי את טיוטת החוזה. אנא קרא ותחזור אליי עם הערות.',
      icon: IconsaxPlusLinear.document_text,
    ),
    _TemplateMessage(
      category: 'חוזה',
      label: 'בקשה לחתימה',
      text: 'הכל מסודר מצידי — אנא חתום על החוזה כדי לסיים את התהליך.',
      icon: IconsaxPlusLinear.pen_tool,
    ),
    _TemplateMessage(
      category: 'סיום',
      label: 'דחייה עדינה',
      text: 'תודה על ההתעניינות. לצערי מצאנו שוכר מתאים. בהצלחה!',
      icon: IconsaxPlusLinear.close_circle,
    ),
    _TemplateMessage(
      category: 'סיום',
      label: 'ברכות כניסה',
      text: 'ברוך הבא לדירה! אני כאן לכל שאלה.',
      icon: IconsaxPlusLinear.house,
    ),
  ];

  Map<String, List<_TemplateMessage>> get _grouped {
    final map = <String, List<_TemplateMessage>>{};
    for (final t in _templates) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.primaryLight2,
                      borderRadius: BorderRadius.circular(12)),
                  child: RentlyIcon(IconsaxPlusLinear.message_text,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 10),
                const Text('תבניות הודעה',
                    style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ]),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('בחר תבנית — ניתן לערוך לפני שליחה',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                    16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: grouped.entries
                    .map((entry) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(entry.key,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5)),
                            ),
                            ...entry.value.map((t) => _TemplateTile(
                                  template: t,
                                  onTap: () {
                                    Navigator.pop(context);
                                    onSelect(t.text);
                                  },
                                )),
                          ],
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  _TemplateTile({required this.template, required this.onTap});

  final _TemplateMessage template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(template.icon, size: 15, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.label,
                      style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(template.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4)),
                ],
              ),
            ),
            const RentlyIcon(IconsaxPlusLinear.arrow_left,
                size: 14, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

// ─── Propose-viewing-times: actions-sheet CTA ─────────────────────────────────

/// On-brand "propose viewing times" CTA, matching [_SendContractCard]. Only the
/// landlord/owner sees this (gated at the call site).
class _ProposeTimesCard extends StatelessWidget {
  _ProposeTimesCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                AppColors.primary.withValues(alpha: 0.14),
                AppColors.primaryLight2,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.30),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(IconsaxPlusLinear.calendar_add,
                    size: 24, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'הצע זמנים לצפייה',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'בחר עד 3 מועדים פנויים לשליחה לשוכר',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_left_rounded,
                  size: 24, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Propose-viewing-times: slot picker sheet ─────────────────────────────────

/// Lists the landlord's upcoming OPEN slots; multi-select up to 3. Pops with the
/// chosen slots (or nothing on cancel). Empty state offers to open the calendar.
class _ProposeTimesSheet extends StatefulWidget {
  _ProposeTimesSheet({required this.repo, required this.onAddTimes});

  final AvailabilityRepository repo;
  final VoidCallback onAddTimes;

  @override
  State<_ProposeTimesSheet> createState() => _ProposeTimesSheetState();
}

class _ProposeTimesSheetState extends State<_ProposeTimesSheet> {
  static const int _maxPick = 3;

  List<AvailabilitySlot> _slots = const [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.repo.loadAll();
    final now = DateTime.now();
    final open = all
        .where((s) => s.isOpen && s.start.isAfter(now))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (!mounted) return;
    setState(() {
      _slots = open;
      _loading = false;
    });
  }

  void _toggle(AvailabilitySlot slot) {
    setState(() {
      if (_selected.contains(slot.id)) {
        _selected.remove(slot.id);
      } else {
        if (_selected.length >= _maxPick) return;
        _selected.add(slot.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(IconsaxPlusLinear.calendar_add,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('הצע זמנים לצפייה',
                      style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('בחר עד 3 מועדים פנויים — השוכר יוכל לאשר אחד מהם.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_slots.isEmpty)
              _emptyState()
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _slots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _slots[i];
                    final picked = _selected.contains(s.id);
                    final atLimit = !picked && _selected.length >= _maxPick;
                    return _SlotPickRow(
                      slot: s,
                      picked: picked,
                      disabled: atLimit,
                      onTap: () => _toggle(s),
                    );
                  },
                ),
              ),
            if (!_loading && _slots.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.slate200,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final chosen = _slots
                              .where((s) => _selected.contains(s.id))
                              .toList();
                          Navigator.pop(context, chosen);
                        },
                  child: Text(
                    _selected.isEmpty
                        ? 'בחר מועדים לשליחה'
                        : 'שלח ${_selected.length} מועדים לשוכר',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primaryLight2,
              shape: BoxShape.circle,
            ),
            child: Icon(IconsaxPlusLinear.calendar_1,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 14),
          const Text('אין זמנים פנויים',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'הוסף מועדים פנויים ביומן כדי שתוכל להציע אותם לשוכר.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onAddTimes,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(IconsaxPlusLinear.add, size: 18),
              label: const Text('הוסף זמנים ביומן',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotPickRow extends StatelessWidget {
  _SlotPickRow({
    required this.slot,
    required this.picked,
    required this.disabled,
    required this.onTap,
  });

  final AvailabilitySlot slot;
  final bool picked;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: picked ? AppColors.primaryLight2 : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: picked ? AppColors.primary : AppColors.slate200,
                width: picked ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  picked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: picked ? AppColors.primary : AppColors.slate200,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatSlotDate(slot.start),
                          style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatTime(slot.start)} · ${slot.durationMinutes} דק׳',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Proposal / confirm chat cards ────────────────────────────────────────────

/// In-chat card rendering a landlord's proposal of viewing times. Tenants (the
/// recipient) get an "אשר" button per option; the landlord (sender) sees each as
/// read-only. Once one option is confirmed, it shows "מאושר ✓" and the rest are
/// disabled.
class _SlotProposalCard extends StatelessWidget {
  _SlotProposalCard({
    required this.proposal,
    required this.isMine,
    required this.createdAt,
    required this.confirmedSlotIds,
    required this.onConfirm,
  });

  final SlotProposal proposal;
  final bool isMine;
  final DateTime createdAt;
  final Set<String> confirmedSlotIds;
  final void Function(SlotOption option)? onConfirm;

  @override
  Widget build(BuildContext context) {
    final anyConfirmed =
        proposal.options.any((o) => confirmedSlotIds.contains(o.slotId));

    final card = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
      ),
      margin: const EdgeInsets.only(top: 8, bottom: 3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(IconsaxPlusLinear.calendar_add,
                    color: AppColors.primary, size: 17),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('מועדים מוצעים לצפייה',
                    style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...proposal.options.map((o) {
            final confirmed = confirmedSlotIds.contains(o.slotId);
            return _SlotOptionRow(
              option: o,
              confirmed: confirmed,
              // Disable other options once one is chosen.
              dimmed: anyConfirmed && !confirmed,
              canConfirm: onConfirm != null && !anyConfirmed,
              onConfirm:
                  onConfirm == null ? null : () => onConfirm!(o),
            );
          }),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _formatTime(createdAt),
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: card,
    );
  }
}

class _SlotOptionRow extends StatelessWidget {
  _SlotOptionRow({
    required this.option,
    required this.confirmed,
    required this.dimmed,
    required this.canConfirm,
    required this.onConfirm,
  });

  final SlotOption option;
  final bool confirmed;
  final bool dimmed;
  final bool canConfirm;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: confirmed ? AppColors.primaryLight2 : AppColors.cloud,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: confirmed ? AppColors.success : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatSlotDate(option.start),
                      style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatTime(option.start)} · ${option.durationMinutes} דק׳',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(),
          ],
        ),
      ),
    );
  }

  Widget _trailing() {
    if (confirmed) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 16),
          SizedBox(width: 4),
          Text('מאושר',
              style: TextStyle(
                  color: AppColors.success,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900)),
        ],
      );
    }
    if (canConfirm) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        onPressed: onConfirm,
        child: const Text('אשר',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
      );
    }
    // Sender's read-only pending label (only when nothing chosen yet).
    if (!dimmed) {
      return const Text('ממתין לאישור',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700));
    }
    return const SizedBox.shrink();
  }
}

/// Compact "viewing confirmed" card shown to both sides.
class _SlotConfirmCard extends StatelessWidget {
  _SlotConfirmCard({
    required this.confirm,
    required this.isMine,
    required this.createdAt,
  });

  final SlotConfirm confirm;
  final bool isMine;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      margin: const EdgeInsets.only(top: 8, bottom: 3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('צפייה מאושרת',
                    style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  '${_formatSlotDate(confirm.start)} · ${_formatTime(confirm.start)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: card,
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

const _slotDaysHeb = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
const _slotMonthsHeb = [
  '',
  'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
  'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
];

/// e.g. "יום שני · 20 ביולי". RTL-safe (pure Hebrew + digits).
String _formatSlotDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(d.year, d.month, d.day);
  final diff = target.difference(today).inDays;
  final dayPart = diff == 0
      ? 'היום'
      : diff == 1
          ? 'מחר'
          : 'יום ${_slotDaysHeb[d.weekday % 7]}';
  return '$dayPart · ${d.day} ב${_slotMonthsHeb[d.month]}';
}

String _formatTime(DateTime v) {
  return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
}

String _formatDay(DateTime v) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(v.year, v.month, v.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'היום';
  if (diff == 1) return 'אתמול';
  return '${v.day.toString().padLeft(2, '0')}.${v.month.toString().padLeft(2, '0')}.${v.year}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
