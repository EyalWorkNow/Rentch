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

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            surfaceTintColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      Text(
                        property.priceLabel,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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
                  child: match.messages.isEmpty
                      ? const _EmptyChat()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: match.messages.length,
                          itemBuilder: (context, index) {
                            final message = match.messages[index];
                            final isTenant = message.sender ==
                                (provider.tenantProfile?.name ?? 'השוכר');
                            return _MessageBubble(
                              message: message,
                              isTenant: isTenant,
                            );
                          },
                        ),
                ),
                _MessageInput(
                  controller: _messageController,
                  onSend: () async {
                    final text = _messageController.text.trim();
                    if (text.isEmpty) return;
                    final tenantName =
                        provider.tenantProfile?.name ?? 'השוכר';
                    await provider.sendMessage(
                      matchId: match.id,
                      sender: tenantName,
                      text: text,
                    );
                    _messageController.clear();
                    _scrollToBottom();
                  },
                ),
              ],
            ),
          ),
        );
      },
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

class _PropertyContractHeader extends StatelessWidget {
  const _PropertyContractHeader(
      {required this.match, required this.property});
  final RentalMatch match;
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const Icon(IconsaxPlusBold.document_text,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                _MiniStatus(
                  label: match.contractSent ? 'חוזה נשלח' : 'ללא חוזה',
                  active: match.contractSent,
                ),
                _MiniStatus(label: 'בעלים חתם', active: match.ownerSigned),
                _MiniStatus(label: 'שוכר חתם', active: match.tenantSigned),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.borderLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isEnabled
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isEnabled ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color:
                    isEnabled ? AppColors.primary : AppColors.textSecondary,
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusBold.message,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 14),
          const Text(
            'התחל שיחה',
            style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'שלח הודעה ראשונה לבעל הדירה',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isTenant});
  final ChatMessage message;
  final bool isTenant;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isTenant ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.74,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isTenant ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topRight: const Radius.circular(18),
            topLeft: const Radius.circular(18),
            bottomRight:
                isTenant ? Radius.zero : const Radius.circular(18),
            bottomLeft: isTenant ? const Radius.circular(18) : Radius.zero,
          ),
          border: isTenant
              ? null
              : Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: 0.5),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isTenant
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.sender,
              style: TextStyle(
                color: isTenant
                    ? Colors.white.withValues(alpha: 0.75)
                    : AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(
                fontSize: 15,
                color: isTenant ? Colors.white : AppColors.navy,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                color: isTenant
                    ? Colors.white.withValues(alpha: 0.6)
                    : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 16, offset: Offset(0, -6))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(
                    color: AppColors.navy, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'כתיבת הודעה...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(IconsaxPlusBold.send_1,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.borderLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.primary : AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
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
