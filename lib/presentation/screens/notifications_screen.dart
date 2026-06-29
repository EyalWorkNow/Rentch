import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/services/push_notification_service.dart';
import 'package:dating_app/data/models/app_notification.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// In-app notifications inbox. Hebrew RTL, large legible type for older users.
///
/// Tapping a notification marks it read and pops with the tapped
/// [AppNotification] as the route result, so the host (home_screen) can deep
/// link using its `data`. Returns the *true if anything was marked read* so the
/// host can refresh its bell badge regardless of how the screen was dismissed.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AwsApiClient.instance.getNotifications();
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
        _error = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationsScreen._load: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_items.every((n) => n.read)) return;
    setState(() => _items = _items.map((n) => n.copyWith(read: true)).toList());
    try {
      await AwsApiClient.instance.markNotificationsRead(all: true);
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationsScreen._markAllRead: $e');
    }
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.read) {
      setState(() => _items = _items
          .map((x) => x.id == n.id ? x.copyWith(read: true) : x)
          .toList());
      // Fire-and-forget; the optimistic UI already reflects the change.
      AwsApiClient.instance
          .markNotificationsRead(ids: [n.id]).catchError((Object e) {
        if (kDebugMode) debugPrint('mark-read ${n.id}: $e');
      });
    }
    if (mounted) Navigator.of(context).pop(n);
  }

  int get _unreadCount => _items.where((n) => !n.read).length;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          centerTitle: false,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: const Text(
            'התראות',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            if (_unreadCount > 0)
              TextButton(
                onPressed: _markAllRead,
                child: Text(
                  'סמן הכל כנקרא',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error && _items.isEmpty) {
      return _StateMessage(
        icon: IconsaxPlusLinear.wifi_square,
        title: 'לא הצלחנו לטעון התראות',
        subtitle: 'משכו למטה כדי לנסות שוב',
      );
    }
    if (_items.isEmpty) {
      return _StateMessage(
        icon: IconsaxPlusLinear.notification,
        title: 'אין התראות חדשות',
        subtitle: 'כאן יופיעו עדכונים על התאמות, הודעות ועוד',
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _NotificationTile(
        notification: _items[i],
        onTap: () => _onTap(_items[i]),
      ),
    );
  }
}

// ─── Bell + unread badge ────────────────────────────────────────────────────

/// Always-reachable bell that shows the unread count and opens the inbox.
///
/// Keeps its badge fresh *without polling*: it refreshes the unread count on
/// app resume (via [WidgetsBindingObserver]) and whenever an FCM message
/// arrives in the foreground (it hooks [PushNotificationService.onForegroundMessage]).
/// Opening the inbox clears the badge.
///
/// [onDeepLink] is invoked with the notification the user tapped inside the
/// inbox, so the host can navigate using its `data`.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    this.onDeepLink,
    this.iconColor = AppColors.textPrimary,
    this.iconSize = 22,
  });

  final void Function(AppNotification notification)? onDeepLink;
  final Color iconColor;
  final double iconSize;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh the badge when a push arrives while the app is foregrounded.
    // Chain rather than clobber any previously-set handler.
    final prev = PushNotificationService.instance.onForegroundMessage;
    PushNotificationService.instance.onForegroundMessage = (message) {
      prev?.call(message);
      _refresh();
    };
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final res = await AwsApiClient.instance.getNotifications();
      if (!mounted) return;
      if (res.unread != _unread) setState(() => _unread = res.unread);
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationBell._refresh: $e');
    }
  }

  Future<void> _open() async {
    final tapped = await Navigator.of(context).push<AppNotification>(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // Opening the inbox marks things read on the server; clear locally, then
    // re-sync to be safe.
    if (mounted) setState(() => _unread = 0);
    if (tapped != null) widget.onDeepLink?.call(tapped);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(IconsaxPlusLinear.notification,
                  size: widget.iconSize, color: widget.iconColor),
            ),
          ),
          if (_unread > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Tile ─────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final accent = _typeAccent(notification.type);
    return Material(
      color: unread ? Colors.white : const Color(0xFFFBFCFD),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread
                  ? accent.withValues(alpha: 0.30)
                  : const Color(0xFFE8EEF3),
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon(notification.type),
                    color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        height: 1.25,
                        fontWeight:
                            unread ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(notification.createdAt),
                      style: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Unread dot
              if (unread)
                Container(
                  margin: const EdgeInsets.only(top: 4, right: 2),
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty / error state ────────────────────────────────────────────────────

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Wrapped in a scroll view so pull-to-refresh works on the empty state too.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
        Icon(icon, size: 64, color: AppColors.textDisabled),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Helpers (shared with the bell) ─────────────────────────────────────────

IconData _typeIcon(String type) => switch (type) {
      'match' => IconsaxPlusBold.heart_circle,
      'message' => IconsaxPlusBold.message,
      'like' => IconsaxPlusBold.heart,
      'tour' => IconsaxPlusBold.video,
      'review' => IconsaxPlusBold.star_1,
      _ => IconsaxPlusBold.notification,
    };

Color _typeAccent(String type) => switch (type) {
      'match' => AppColors.coral,
      'message' => AppColors.primary,
      'like' => AppColors.coral,
      'tour' => AppColors.superLike,
      'review' => AppColors.warning,
      _ => AppColors.primary,
    };

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'עכשיו';
  if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
  if (diff.inHours < 24) return 'לפני ${diff.inHours} שע׳';
  if (diff.inDays == 1) return 'אתמול';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
  if (diff.inDays < 14) return 'לפני שבוע';
  return 'לפני ${(diff.inDays / 7).round()} שבועות';
}
