import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final match = provider.matchById(widget.matchId);
        final property = provider.propertyById(match?.propertyId);

        if (match == null || property == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: Text('ההתאמה לא נמצאה')),
          );
        }

        final imageUrl =
            property.imageUrls.isNotEmpty ? property.imageUrls.first : '';
        final tenantName = provider.tenantProfile?.name ?? 'השוכר';

        return Scaffold(
          backgroundColor: const Color(0xFFF2F7FA),
          appBar: AppBar(
            toolbarHeight: 82,
            backgroundColor: AppColors.navy,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.5),
                        child: imageUrl.isEmpty
                            ? Container(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                child: const Icon(IconsaxPlusBold.building,
                                    color: Colors.white, size: 20),
                              )
                            : Image.network(imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  child: const Icon(IconsaxPlusBold.building,
                                      color: Colors.white, size: 20),
                                )),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF27AE60),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.navy, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        property.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        property.priceLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _HeaderTag(
                            icon: IconsaxPlusBold.message,
                            label: '${match.messages.length} הודעות',
                            isAccent: false,
                          ),
                          const SizedBox(width: 6),
                          _HeaderTag(
                            icon: IconsaxPlusBold.tick_circle,
                            label: match.contractSent ? 'תהליך פעיל' : 'צ׳אט חדש',
                            isAccent: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _PropertyContractHeader(match: match, property: property),
                _QuickActions(
                  match: match,
                  onSendContract: match.contractSent
                      ? null
                      : () => provider.sendContract(match.id),
                  onOwnerSign: !match.contractSent || match.ownerSigned
                      ? null
                      : () => provider.signContract(match.id, asOwner: true),
                  onTenantSign: !match.contractSent || match.tenantSigned
                      ? null
                      : () => provider.signContract(match.id, asOwner: false),
                  onPropertyReview: () => _showReviewDialog(
                    title: 'ביקורת על הדירה',
                    onSubmit: (rating, text) => provider.addPropertyReview(
                      propertyId: property.id,
                      rating: rating,
                      text: text,
                    ),
                  ),
                  onTenantReview: () => _showReviewDialog(
                    title: 'ביקורת על השוכר',
                    onSubmit: (rating, text) =>
                        provider.addTenantReview(rating: rating, text: text),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFF2F7FA),
                          Color(0xFFE5EEF3),
                        ],
                      ),
                    ),
                    child: match.messages.isEmpty
                        ? const _EmptyChat()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: match.messages.length,
                            itemBuilder: (context, index) {
                              final message = match.messages[index];
                              final previous = index == 0
                                  ? null
                                  : match.messages[index - 1];
                              final isTenant =
                                  message.sender == tenantName;
                              final showDateDivider = previous == null ||
                                  !_isSameDay(
                                      previous.createdAt, message.createdAt);
                              return Column(
                                children: [
                                  if (showDateDivider)
                                    _DateDivider(date: message.createdAt),
                                  _MessageBubble(
                                    message: message,
                                    isTenant: isTenant,
                                    showAvatar: !isTenant &&
                                        (previous == null ||
                                            previous.sender !=
                                                message.sender),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ),
                _MessageInput(
                  controller: _messageController,
                  onSend: () async {
                    final text = _messageController.text.trim();
                    if (text.isEmpty) return;
                    await provider.sendMessage(
                      matchId: match.id,
                      sender: tenantName,
                      text: text,
                    );
                    _messageController.clear();
                    _scrollToBottom();
                  },
                  onTemplates: () => _showTemplates(tenantName),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTemplates(String senderName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TemplateLibrarySheet(
        onSelect: (text) {
          _messageController.text = text;
          _messageController.selection = TextSelection.collapsed(
            offset: text.length,
          );
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
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Text(
                title,
                style: const TextStyle(
                    color: AppColors.navy, fontWeight: FontWeight.w900),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('דירוג',
                          style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Slider(
                          value: rating.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: '$rating',
                          activeColor: AppColors.primary,
                          onChanged: (v) =>
                              setDialogState(() => rating = v.round()),
                        ),
                      ),
                      Text('$rating/5',
                          style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'תוכן הביקורת...',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ביטול',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    await onSubmit(rating, text);
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  },
                  child: const Text('שמירה'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag({
    required this.icon,
    required this.label,
    required this.isAccent,
  });

  final IconData icon;
  final String label;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: isAccent
            ? AppColors.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isAccent
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: isAccent ? AppColors.primaryLight : Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isAccent ? AppColors.primaryLight : Colors.white.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyContractHeader extends StatelessWidget {
  const _PropertyContractHeader({required this.match, required this.property});
  final RentalMatch match;
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _StepInfo(label: 'צ׳אט', active: true, icon: IconsaxPlusBold.message),
      _StepInfo(label: 'חוזה נשלח', active: match.contractSent, icon: IconsaxPlusBold.document_text),
      _StepInfo(label: 'בעלים חתם', active: match.ownerSigned, icon: IconsaxPlusBold.pen_tool),
      _StepInfo(label: 'שוכר חתם', active: match.tenantSigned, icon: IconsaxPlusBold.edit),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08072946),
            blurRadius: 18,
            offset: Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(steps.length, (index) {
              final step = steps[index];
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: step.active
                                  ? const LinearGradient(
                                      colors: [AppColors.primary, AppColors.primaryDark],
                                    )
                                  : null,
                              color: step.active ? null : const Color(0xFFF2F7FA),
                              border: Border.all(
                                color: step.active
                                    ? Colors.transparent
                                    : AppColors.borderLight,
                                width: 1.5,
                              ),
                              boxShadow: step.active
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              step.icon,
                              size: 13,
                              color: step.active ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            step.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: step.active ? AppColors.navy : AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: step.active ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 2.5,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: steps[index + 1].active
                                  ? AppColors.primary
                                  : const Color(0xFFE2ECF1),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StepInfo {
  final String label;
  final bool active;
  final IconData icon;

  const _StepInfo({required this.label, required this.active, required this.icon});
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.match,
    required this.onSendContract,
    required this.onOwnerSign,
    required this.onTenantSign,
    required this.onPropertyReview,
    required this.onTenantReview,
  });

  final RentalMatch match;
  final VoidCallback? onSendContract;
  final VoidCallback? onOwnerSign;
  final VoidCallback? onTenantSign;
  final VoidCallback onPropertyReview;
  final VoidCallback onTenantReview;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ShortcutButton(
            icon: IconsaxPlusLinear.document_text,
            label: 'שליחת חוזה',
            onPressed: onSendContract,
          ),
          const SizedBox(width: 8),
          _ShortcutButton(
            icon: IconsaxPlusLinear.pen_tool,
            label: 'חתימת בעלים',
            onPressed: onOwnerSign,
          ),
          const SizedBox(width: 8),
          _ShortcutButton(
            icon: IconsaxPlusLinear.edit,
            label: 'חתימת שוכר',
            onPressed: onTenantSign,
          ),
          const SizedBox(width: 8),
          _ShortcutButton(
            icon: IconsaxPlusLinear.star,
            label: 'ביקורת דירה',
            onPressed: onPropertyReview,
          ),
          const SizedBox(width: 8),
          _ShortcutButton(
            icon: IconsaxPlusLinear.profile_circle,
            label: 'ביקורת שוכר',
            onPressed: onTenantReview,
          ),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isEnabled
              ? const LinearGradient(
                  colors: [Colors.white, Color(0xFFF5FCFD)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          color: isEnabled ? null : const Color(0xFFE9F1F5).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled
                ? AppColors.primary.withValues(alpha: 0.3)
                : const Color(0xFFD4E3EB),
            width: 1.2,
          ),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isEnabled
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 14,
                color: isEnabled ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isEnabled ? AppColors.navy : AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primaryLight.withValues(alpha: 0.12),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusBold.message,
                color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 18),
          const Text(
            'התחל שיחה',
            style: TextStyle(
                color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'שלח הודעה ראשונה לבעל הדירה',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isTenant,
    required this.showAvatar,
  });
  final ChatMessage message;
  final bool isTenant;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
      decoration: BoxDecoration(
        gradient: isTenant
            ? const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : null,
        color: isTenant ? null : Colors.white,
        borderRadius: BorderRadius.only(
          topRight: const Radius.circular(20),
          topLeft: const Radius.circular(20),
          bottomRight: isTenant ? const Radius.circular(4) : const Radius.circular(20),
          bottomLeft: isTenant ? const Radius.circular(20) : const Radius.circular(4),
        ),
        border: isTenant ? null : Border.all(color: const Color(0xFFE5EFF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06072946),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            isTenant ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            message.sender,
            style: TextStyle(
              color: isTenant
                  ? Colors.white.withValues(alpha: 0.8)
                  : AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message.text,
            style: TextStyle(
              fontSize: 14.5,
              color: isTenant ? Colors.white : AppColors.navy,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  color: isTenant
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.textSecondary.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isTenant) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.done_all_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ],
          ),
        ],
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
            _SenderAvatar(showAvatar: showAvatar),
            const SizedBox(width: 8),
          ],
          bubble,
        ],
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.showAvatar});

  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    if (!showAvatar) {
      return const SizedBox(width: 32);
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06072946),
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: const Center(
        child: Icon(
          IconsaxPlusBold.building,
          size: 13,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: AppColors.borderLight.withValues(alpha: 0.7),
              thickness: 1,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x04072946),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                )
              ],
            ),
            child: Text(
              _formatDay(date),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: AppColors.borderLight.withValues(alpha: 0.7),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerShell extends StatelessWidget {
  const _ComposerShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.onTemplates,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onTemplates;

  @override
  Widget build(BuildContext context) {
    return _ComposerShell(
      child: Container(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: onTemplates,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2ECF1)),
                ),
                child: const Icon(
                  IconsaxPlusLinear.message_text,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                minHeight: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FA),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2ECF1)),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'כתיבת הודעה...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.65),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    IconsaxPlusBold.send_1,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Feature #17: Template Message Library ────────────────────────────────────

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
      category: 'ברוך הבא',
      label: 'הודעת פתיחה',
      text:
          'שלום! קיבלתי את הבקשה שלך לגבי הדירה. אשמח לענות על שאלות ולתאם ביקור. מתי נוח לך?',
      icon: IconsaxPlusBold.home_2,
    ),
    _TemplateMessage(
      category: 'ברוך הבא',
      label: 'אישור עניין',
      text:
          'תודה על התעניינותך! הדירה עדיין פנויה. מחיר השכירות הוא כפי שפורסם. אשמח לתאם ביקור בשבוע הקרוב.',
      icon: IconsaxPlusBold.tick_circle,
    ),
    _TemplateMessage(
      category: 'ביקור',
      label: 'תיאום ביקור',
      text:
          'אני זמין לביקור ביום __ בשעה __. האם מתאים לך? אם לא, נסו להציע מועד נוח מצידך.',
      icon: IconsaxPlusBold.calendar,
    ),
    _TemplateMessage(
      category: 'ביקור',
      label: 'אישור ביקור',
      text:
          'מעולה! מאשר את הביקור ביום __ בשעה __. הכתובת: ___. אתקשר אם יהיה שינוי.',
      icon: IconsaxPlusBold.location,
    ),
    _TemplateMessage(
      category: 'חוזה',
      label: 'שליחת חוזה',
      text:
          'שלחתי לך את טיוטת החוזה לעיון. אנא קרא בעיון ותחזור אליי עם הערות אם יש. אשמח לענות על כל שאלה.',
      icon: IconsaxPlusBold.document_text,
    ),
    _TemplateMessage(
      category: 'חוזה',
      label: 'בקשה לחתימה',
      text:
          'הכל נראה מסודר מצידי. אנא חתום על החוזה ונסיים את התהליך. מחפש שוכר רציני לטווח ארוך.',
      icon: IconsaxPlusBold.pen_tool,
    ),
    _TemplateMessage(
      category: 'סיום',
      label: 'דחייה עדינה',
      text:
          'תודה על ההתעניינות. לצערי מצאנו שוכר מתאים. מאחל לך הצלחה במציאת דירה. בהצלחה!',
      icon: IconsaxPlusLinear.close_circle,
    ),
    _TemplateMessage(
      category: 'סיום',
      label: 'ברכות כניסה',
      text:
          'ברוך הבא לדירה! אני כאן לכל שאלה. יש כמה דברים שחשוב לדעת על הדירה — נדבר בביקור הראשון.',
      icon: IconsaxPlusBold.house,
    ),
  ];

  Map<String, List<_TemplateMessage>> get _byCategory {
    final map = <String, List<_TemplateMessage>>{};
    for (final t in _templates) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byCategory;
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(IconsaxPlusBold.message_text,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'תבניות הודעה מוכנות',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'בחר תבנית — תוכל לערוך לפני שליחה',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                    16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: grouped.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      ...entry.value.map(
                        (t) => _TemplateTile(
                          template: t,
                          onTap: () {
                            Navigator.pop(context);
                            onSelect(t.text);
                          },
                        ),
                      ),
                    ],
                  );
                }).toList(),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FA).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(template.icon, size: 16, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.label,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Center(
                child: Icon(
                  IconsaxPlusLinear.arrow_left,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDay(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(value.year, value.month, value.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'היום';
  if (diff == 1) return 'אתמול';
  return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
