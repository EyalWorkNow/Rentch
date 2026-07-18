import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/material.dart';

/// ─── ADMIN BROADCAST CONSOLE ────────────────────────────────────────────────
///
/// Reachable ONLY by the Firebase user holding the custom claim
/// `notifAdmin: true`. The post-login seam (see `auth_screen._onEnter` and the
/// startup gate in `main.dart`) reads the ID-token claims and routes the admin
/// here instead of [HomeScreen].
///
/// The admin composes a COMPANY/SYSTEM notification end-to-end: title, body,
/// optional image URL, one of four Duolingo-style DESIGN TEMPLATES (each a named
/// style + a live preview card), audience = all users, a preview, then SEND →
/// `POST /admin/broadcast`. A history list is loaded from `GET /admin/broadcasts`.
class NotifConsoleScreen extends StatefulWidget {
  const NotifConsoleScreen({super.key});

  @override
  State<NotifConsoleScreen> createState() => _NotifConsoleScreenState();
}

/// One Duolingo-style preset. `id` is the wire value sent to the backend under
/// `template`; the rest only drive the live preview card.
class _Template {
  const _Template({
    required this.id,
    required this.label,
    required this.emoji,
    required this.accent,
    required this.showBigImage,
    required this.bold,
  });

  final String id;
  final String label;
  final String emoji;
  final Color accent;
  final bool showBigImage; // big-image hero layout
  final bool bold; // bold-color / emoji-celebration emphasis
}

const List<_Template> _templates = [
  _Template(
    id: 'big-image',
    label: 'תמונה גדולה',
    emoji: '🖼️',
    accent: Color(0xFF1CB0F6),
    showBigImage: true,
    bold: false,
  ),
  _Template(
    id: 'bold-color',
    label: 'צבע נועז',
    emoji: '🔥',
    accent: AppColors.red,
    showBigImage: false,
    bold: true,
  ),
  _Template(
    id: 'emoji-celebration',
    label: 'חגיגת אימוג׳י',
    emoji: '🎉',
    accent: Color(0xFF58CC02),
    showBigImage: false,
    bold: true,
  ),
  _Template(
    id: 'minimal',
    label: 'מינימלי',
    emoji: '✨',
    accent: AppColors.slate700,
    showBigImage: false,
    bold: false,
  ),
];

class _NotifConsoleScreenState extends State<NotifConsoleScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();

  _Template _selected = _templates.first;
  bool _sending = false;
  bool _loadingHistory = true;
  List<BroadcastRecord> _history = const [];
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onChanged);
    _bodyCtrl.addListener(_onChanged);
    _imageCtrl.addListener(_onChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final items = await AwsApiClient.instance.getBroadcasts();
      if (!mounted) return;
      setState(() {
        _history = items;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = 'טעינת ההיסטוריה נכשלה';
      });
    }
  }

  bool get _canSend =>
      !_sending &&
      _titleCtrl.text.trim().isNotEmpty &&
      _bodyCtrl.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('לשלוח לכל המשתמשים?'),
          content: const Text(
              'ההתראה תישלח לכל משתמשי האפליקציה. הפעולה אינה ניתנת לביטול.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('שליחה'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final result = await AwsApiClient.instance.broadcastNotification(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        imageUrl: _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
        template: _selected.id,
        data: {'source': 'admin_console', 'template': _selected.id},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
              'נשלח בהצלחה • הצליחו ${result.sent} • נכשלו ${result.failed}'),
        ),
      );
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _imageCtrl.clear();
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: const Text('השליחה נכשלה. נסו שוב.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text(
            'קונסולת התראות',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _audienceBanner(),
            const SizedBox(height: 20),
            _sectionLabel('עיצוב ההתראה'),
            const SizedBox(height: 10),
            _templatePicker(),
            const SizedBox(height: 20),
            _sectionLabel('תוכן'),
            const SizedBox(height: 10),
            _field(_titleCtrl, 'כותרת', maxLines: 1),
            const SizedBox(height: 12),
            _field(_bodyCtrl, 'תוכן ההתראה', maxLines: 3),
            const SizedBox(height: 12),
            _field(_imageCtrl, 'כתובת תמונה (אופציונלי)', maxLines: 1),
            const SizedBox(height: 24),
            _sectionLabel('תצוגה מקדימה'),
            const SizedBox(height: 10),
            _PreviewCard(
              template: _selected,
              title: _titleCtrl.text.trim(),
              body: _bodyCtrl.text.trim(),
              imageUrl: _imageCtrl.text.trim(),
            ),
            const SizedBox(height: 24),
            _sendButton(),
            const SizedBox(height: 32),
            _sectionLabel('היסטוריית שליחות'),
            const SizedBox(height: 10),
            _historyList(),
          ],
        ),
      ),
    );
  }

  Widget _audienceBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_rounded, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'קהל יעד: כל המשתמשים',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _templatePicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _templates.map((t) {
        final selected = t.id == _selected.id;
        return GestureDetector(
          onTap: () => setState(() => _selected = t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? t.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? t.accent : AppColors.borderLight,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  t.label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _field(TextEditingController c, String hint, {required int maxLines}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _sendButton() {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _canSend ? _send : null,
        style: FilledButton.styleFrom(
          backgroundColor: _selected.accent,
          disabledBackgroundColor: AppColors.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _sending
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Text(
                'שליחה לכל המשתמשים',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
      ),
    );
  }

  Widget _historyList() {
    if (_loadingHistory) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_historyError != null) {
      return _emptyState(_historyError!);
    }
    if (_history.isEmpty) {
      return _emptyState('עדיין לא נשלחו התראות');
    }
    return Column(
      children: _history.map(_historyTile).toList(),
    );
  }

  Widget _historyTile(BroadcastRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.template,
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'הצליחו ${r.sent} • נכשלו ${r.failed} • ${_fmtDate(r.createdAt)}',
            style: const TextStyle(
                color: AppColors.textDisabled,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textDisabled),
          ),
        ),
      );

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Live preview card showing how the composed notification will look in the
/// chosen template style.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.template,
    required this.title,
    required this.body,
    required this.imageUrl,
  });

  final _Template template;
  final String title;
  final String body;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    final shownTitle = title.isEmpty ? 'כותרת ההתראה' : title;
    final shownBody = body.isEmpty ? 'תוכן ההתראה יופיע כאן…' : body;

    return Container(
      decoration: BoxDecoration(
        color: template.bold ? template.accent : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: template.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: template.accent.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (template.showBigImage && hasImage)
            _PreviewImage(url: imageUrl, height: 150),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shownTitle,
                        style: TextStyle(
                          color:
                              template.bold ? Colors.white : AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shownBody,
                        style: TextStyle(
                          color: template.bold
                              ? Colors.white.withValues(alpha: 0.92)
                              : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!template.showBigImage && hasImage) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _PreviewImage(url: imageUrl, width: 56, height: 56),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: AppColors.divider,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            color: AppColors.textDisabled),
      ),
    );
  }
}
