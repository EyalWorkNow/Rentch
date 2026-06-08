import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/chat_provider.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _bg = Color(0xFFF6FAFC);
const _surface = Colors.white;
const _border = Color(0xFFDCE8EF);
const _outgoing = Color(0xFF12AEB8); // teal bubble
const _incoming = Color(0xFFF0F5F8); // light-grey bubble
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

  Future<void> _pickAndSendMedia(DatingProvider provider, String senderName) async {
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

  Future<void> _pickAndSendFile(DatingProvider provider, String senderName) async {
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
            'האם לחסום את "$ownerName"?\n\nכל המודעות שלהם יוסרו מהפיד שלך מיידית. הדיווח יועבר לצוות Rentch.',
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
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActionsSheet(
        match: match,
        ownerName: property.ownerName,
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
            : () {
                Navigator.pop(context);
                provider.sendContract(match.id);
              },
        onOwnerSign: (!match.contractSent || match.ownerSigned)
            ? null
            : () {
                Navigator.pop(context);
                provider.signContract(match.id, asOwner: true);
              },
        onTenantSign: (!match.contractSent || match.tenantSigned)
            ? null
            : () {
                Navigator.pop(context);
                provider.signContract(match.id, asOwner: false);
              },
        onPropertyReview: () {
          Navigator.pop(context);
          _showReviewDialog(
            title: 'ביקורת על הדירה',
            onSubmit: (rating, text) => provider.addPropertyReview(
              propertyId: provider.matchById(widget.matchId)!.propertyId,
              rating: rating,
              text: text,
            ),
          );
        },
        onTenantReview: () {
          Navigator.pop(context);
          _showReviewDialog(
            title: 'ביקורת על השוכר',
            onSubmit: (rating, text) =>
                provider.addTenantReview(rating: rating, text: text),
          );
        },
        onBlockUser: () {
          Navigator.pop(context);
          _showBlockConfirm(provider, property.ownerName);
        },
      ),
    );
  }

  Future<void> _showReviewDialog({
    required String title,
    required Future<void> Function(int rating, String text) onSubmit,
  }) async {
    final controller = TextEditingController();
    var rating = 5;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(title,
              style: const TextStyle(
                  color: AppColors.navy, fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('דירוג',
                    style: TextStyle(
                        color: AppColors.navy, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Slider(
                    value: rating.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$rating',
                    activeColor: AppColors.primary,
                    onChanged: (v) => setS(() => rating = v.round()),
                  ),
                ),
                Text('$rating / 5',
                    style: const TextStyle(
                        color: AppColors.navy, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'כתוב ביקורת קצרה...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ביטול')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await onSubmit(rating, controller.text.trim());
              },
              child: const Text('שלח ביקורת'),
            ),
          ],
        ),
      ),
    );
  }

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

        return Scaffold(
          backgroundColor: _bg,
          resizeToAvoidBottomInset: true,

          // ── AppBar ──────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: _surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            shadowColor: _border,
            iconTheme: const IconThemeData(color: AppColors.navy),
            titleSpacing: 0,
            title: Row(children: [
              // Property thumbnail
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SafeImage(
                    source: imageUrl,
                    fallback: Container(
                      color: AppColors.primaryLight2,
                      child: const RentchIcon(IconsaxPlusLinear.building,
                          color: AppColors.primary, size: 18),
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
                        style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${property.priceLabel} · ${property.city}',
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
              // Connection dot
              if (isRemote)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
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
            ]),
            // Actions menu icon + block popup
            actions: [
              IconButton(
                icon: const RentchIcon(IconsaxPlusLinear.more_circle,
                    color: AppColors.navy, size: 22),
                tooltip: 'פעולות',
                onPressed: () =>
                    _showActions(provider, match, property, tenantName),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.navy, size: 22),
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
              child: Container(height: 1, color: _border),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                // Contract progress bar (compact strip, only when started)
                if (match.contractSent)
                  _ContractBar(
                    match: match,
                    onOwnerSign: (!match.ownerSigned)
                        ? () => provider.signContract(match.id, asOwner: true)
                        : null,
                    onTenantSign: (!match.tenantSigned)
                        ? () => provider.signContract(match.id, asOwner: false)
                        : null,
                  ),

                // Message list
                Expanded(
                  child: _buildMessageList(messages, tenantName, isLoading),
                ),

                // Input bar
                _MessageInput(
                  controller: _msgCtrl,
                  isSending: isSending,
                  onSend: () => _handleSend(provider, tenantName),
                  onActions: () =>
                      _showActions(provider, match, property, tenantName),
                ),
              ],
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
  ) {
    if (messages.isEmpty && !isLoading) return const _EmptyChat();

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

            return Column(
              children: [
                if (showDate) _DateDivider(date: msg.createdAt),
                _MessageBubble(
                  message: msg,
                  isTenant: isTenant,
                  showAvatar: showAvatar,
                  isPending: isPending,
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
                  color: AppColors.navy,
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

// ─── Compact contract strip ───────────────────────────────────────────────────

class _ContractBar extends StatelessWidget {
  const _ContractBar({
    required this.match,
    required this.onOwnerSign,
    required this.onTenantSign,
  });

  final RentalMatch match;
  final VoidCallback? onOwnerSign;
  final VoidCallback? onTenantSign;

  String get _label {
    if (!match.ownerSigned && !match.tenantSigned) {
      return 'חוזה נשלח · ממתין לחתימות';
    }
    if (!match.ownerSigned) return 'ממתין לחתימת בעלים';
    if (!match.tenantSigned) return 'ממתין לחתימת שוכר';
    return 'חוזה חתום על-ידי שני הצדדים ✓';
  }

  bool get _done => match.ownerSigned && match.tenantSigned;

  VoidCallback? get _primaryAction => onOwnerSign ?? onTenantSign;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _done ? const Color(0xFFE9F9F1) : const Color(0xFFEBF7FA),
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
        if (_primaryAction != null)
          GestureDetector(
            onTap: _primaryAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'חתום',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─── Actions bottom sheet ─────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({
    required this.match,
    required this.ownerName,
    required this.onQuickMessage,
    required this.onAttachFile,
    required this.onAttachMedia,
    required this.onSendContract,
    required this.onOwnerSign,
    required this.onTenantSign,
    required this.onPropertyReview,
    required this.onTenantReview,
    required this.onBlockUser,
  });

  final RentalMatch match;
  final String ownerName;
  final VoidCallback onQuickMessage;
  final VoidCallback onAttachFile;
  final VoidCallback onAttachMedia;
  final VoidCallback? onSendContract;
  final VoidCallback? onOwnerSign;
  final VoidCallback? onTenantSign;
  final VoidCallback onPropertyReview;
  final VoidCallback onTenantReview;
  final VoidCallback onBlockUser;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItem(
        icon: IconsaxPlusLinear.document_text,
        label: 'שליחת חוזה',
        subtitle: match.contractSent ? 'החוזה כבר נשלח' : 'שלח טיוטה לשוכר',
        enabled: !match.contractSent,
        onTap: onSendContract,
      ),
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
      _ActionItem(
        icon: IconsaxPlusLinear.star,
        label: 'ביקורת על הדירה',
        subtitle: 'הוסף משוב על הנכס',
        enabled: true,
        onTap: onPropertyReview,
      ),
      _ActionItem(
        icon: IconsaxPlusLinear.profile_circle,
        label: 'ביקורת על השוכר',
        subtitle: 'הוסף משוב על השוכר',
        enabled: true,
        onTap: onTenantReview,
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
          ...actions.map((a) => _ActionTile(item: a)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFF0F5F8)),
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
  const _QuickActionButton({
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
            color: const Color(0xFFF3F8FB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDEAF1)),
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
  const _ActionTile({required this.item});
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
                    : const Color(0xFFF0F5F8),
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
              const RentchIcon(IconsaxPlusLinear.arrow_left,
                  size: 14, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

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
              decoration: const BoxDecoration(
                color: AppColors.primaryLight2,
                shape: BoxShape.circle,
              ),
              child: const RentchIcon(IconsaxPlusLinear.message,
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
  const _MessageBubble({
    required this.message,
    required this.isTenant,
    required this.showAvatar,
    required this.isPending,
  });

  final ChatMessage message;
  final bool isTenant;
  final bool showAvatar;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isTenant ? _outgoing : _incoming;
    final textColor = isTenant ? Colors.white : AppColors.navy;
    final metaColor = isTenant
        ? Colors.white.withValues(alpha: 0.75)
        : AppColors.textSecondary;

    // Detect media messages (📷 / 📎 prefix) for richer bubble rendering.
    // Legacy __img__: paths are treated as plain text (no file path exposure).
    final isImg = message.text == '📷 [תמונה]';
    final isFile = message.text.startsWith('📎 [') && message.text.endsWith(']');
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
                style: const TextStyle(
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
                  Icon(
                    isPending ? Icons.done_rounded : Icons.done_all_rounded,
                    size: 12,
                    color: Colors.white
                        .withValues(alpha: isPending ? 0.5 : 0.85),
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
          bubble,
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
  const _SenderAvatar({required this.show});
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox(width: 28);
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight2,
        shape: BoxShape.circle,
      ),
      child: const RentchIcon(IconsaxPlusLinear.building,
          color: AppColors.primary, size: 12),
    );
  }
}

// ─── Date divider ─────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
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
    required this.onSend,
    required this.onActions,
  });

  final TextEditingController controller;
  final bool isSending;
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
          _SendBtn(isSending: isSending, onTap: onSend),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 118),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD3E2EA)),
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
          _IconBtn(
            icon: Icons.add_rounded,
            color: AppColors.navy,
            bg: const Color(0xFFF0F5F8),
            onTap: onActions,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  const _SendBtn({required this.isSending, required this.onTap});

  final bool isSending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSending ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
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
                : const LinearGradient(
                    colors: [Color(0xFF1BC7D5), Color(0xFF0EA5B2)],
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
                : const RentchIcon(
                    IconsaxPlusLinear.send_1,
                    color: Colors.white,
                    size: 18,
                  ),
          ),
        ),
      ),
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
  const _TemplateLibrarySheet({required this.onSelect});
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
                  child: const RentchIcon(IconsaxPlusLinear.message_text,
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
  const _TemplateTile({required this.template, required this.onTap});

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
            const RentchIcon(IconsaxPlusLinear.arrow_left,
                size: 14, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

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
