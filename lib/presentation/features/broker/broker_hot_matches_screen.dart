import 'package:dating_app/core/broker/broker_match.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/broker_client_repository.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One fresh, not-yet-seen listing↔client match.
class _HotMatch {
  const _HotMatch({required this.client, required this.match});
  final BrokerClient client;
  final BrokerMatch match;

  /// Stable key for the seen-set: a given listing newly matching a given client.
  String get key => '${client.id}|${match.property.id}';
}

/// "התראות התאמה חמה" — brand-new listing↔client matches the broker hasn't seen.
///
/// The pain: a great new listing comes in and the broker forgets which waiting
/// client it's perfect for, so the lead goes cold. This screen surfaces, for
/// every recently-added listing, the clients it *newly* matches —
/// "נכס חדש מתאים ל{client}" — and remembers which alerts the broker already saw
/// (persisted locally), so only genuinely new ones show. Read-only over the
/// broker's own data; no backend.
class BrokerHotMatchesScreen extends StatefulWidget {
  const BrokerHotMatchesScreen({super.key, this.clientRepository});

  final BrokerClientRepository? clientRepository;

  @override
  State<BrokerHotMatchesScreen> createState() => _BrokerHotMatchesScreenState();
}

class _BrokerHotMatchesScreenState extends State<BrokerHotMatchesScreen> {
  static const _matcher = BrokerMatcher();
  static const _seenKey = 'broker_seen_hot_matches';

  late final BrokerClientRepository _repo =
      widget.clientRepository ?? BrokerClientRepository();

  List<_HotMatch> _hot = const [];
  Set<String> _seen = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clients = await _repo.loadAll();
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey)?.toSet() ?? <String>{};
    if (!mounted) return;

    final properties = context.read<DatingProvider>().myProperties;
    final hot = _computeHot(clients, properties, seen);

    setState(() {
      _seen = seen;
      _hot = hot;
      _loading = false;
    });
  }

  /// STRONG client↔listing pairings the broker hasn't dismissed yet. A "hot
  /// match" is a genuinely good fit (score ≥ [_minHotScore]) over the WHOLE
  /// inventory — not gated on [isNewListing], which is inert for market listings
  /// that carry no createdAt (so the old gate silently showed nothing for a
  /// broker who works market inventory). Fresh listings are surfaced first.
  static const int _minHotScore = 70;

  List<_HotMatch> _computeHot(
    List<BrokerClient> clients,
    List<RentalProperty> properties,
    Set<String> seen,
  ) {
    final out = <_HotMatch>[];
    for (final client in clients) {
      for (final m in _matcher.rank(client, properties)) {
        if (m.score < _minHotScore) continue;
        final hot = _HotMatch(client: client, match: m);
        if (!seen.contains(hot.key)) out.add(hot);
      }
    }
    out.sort((a, b) {
      final fa = a.match.property.isNewListing ? 1 : 0;
      final fb = b.match.property.isNewListing ? 1 : 0;
      if (fa != fb) return fb - fa; // fresh listings first
      return b.match.score.compareTo(a.match.score);
    });
    return out;
  }

  Future<void> _markSeen(_HotMatch hot) async {
    final next = {..._seen, hot.key};
    setState(() {
      _seen = next;
      _hot = _hot.where((h) => h.key != hot.key).toList();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenKey, next.toList());
  }

  Future<void> _dismissAll() async {
    final next = {..._seen, ..._hot.map((h) => h.key)};
    setState(() {
      _seen = next;
      _hot = const [];
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenKey, next.toList());
  }

  void _open(_HotMatch hot) {
    // Opening the listing counts as "seen", so it won't re-alert.
    _markSeen(hot);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(property: hot.match.property),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('התאמות חמות'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
          actions: [
            if (_hot.isNotEmpty)
              TextButton(
                onPressed: _dismissAll,
                child: const Text('סמן הכל כנקרא',
                    style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _hot.isEmpty
                ? const _EmptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _hot.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _HotMatchCard(
                        hot: _hot[i],
                        onOpen: () => _open(_hot[i]),
                        onDismiss: () => _markSeen(_hot[i]),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _HotMatchCard extends StatelessWidget {
  const _HotMatchCard({
    required this.hot,
    required this.onOpen,
    required this.onDismiss,
  });

  final _HotMatch hot;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = hot.match.property;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: AppColors.primaryDark, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'נכס חדש מתאים ל${hot.client.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: onDismiss,
                    tooltip: 'סמן כנקרא',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.address,
                style: const TextStyle(
                    fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                '${p.priceLabel} ${p.priceSuffixLabel} · ${p.roomsLabel} חדרים · '
                'התאמה ${hot.match.score}%',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              if (hot.match.reasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in hot.match.reasons.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight2,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(r,
                            style: TextStyle(
                                fontSize: 13, color: AppColors.primaryDark)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_outlined,
                size: 72, color: AppColors.primaryLight),
            const SizedBox(height: 16),
            const Text(
              'אין התאמות חדשות כרגע',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'כשתעלה נכס חדש שמתאים לאחד מהלקוחות בפנקס — נראה לך אותו כאן.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
