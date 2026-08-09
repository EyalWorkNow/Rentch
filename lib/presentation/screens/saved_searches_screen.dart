import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/saved_search.dart';
import 'package:dating_app/data/repositories/saved_search_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// "החיפושים שלי" — the tenant's saved searches.
///
/// Good apartments in Israel rent within days. A tenant who saves a search here
/// gets a calm local notification the moment a new matching listing appears, so
/// they don't have to live in the feed. Built for older / stressed users: big
/// text, generous spacing, a per-search alerts toggle, easy delete, and a warm
/// empty state.
class SavedSearchesScreen extends StatefulWidget {
  const SavedSearchesScreen({super.key, this.repository});

  final SavedSearchRepository? repository;

  /// Build a [SavedSearch] from the current discover-screen criteria and persist
  /// it. The discover/filters wiring (the integration agent) calls this with the
  /// values the tenant is currently browsing — see the file header for the call
  /// shape. Returns the saved search (so callers can confirm to the user).
  static Future<SavedSearch> saveCurrent({
    required BuildContext context,
    required String name,
    String? city,
    int? minBudget,
    int? maxBudget,
    double? minRooms,
    double? maxRooms,
    String? transactionType,
    List<String> requiredTags = const [],
    bool alertsOn = true,
    SavedSearchRepository? repository,
  }) async {
    final repo = repository ?? SavedSearchRepository();
    final l10n = AppLocalizations.of(context)!;
    final search = SavedSearch(
      id: 'ss_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? l10n.savedSearchesScreenC7d46456 : name.trim(),
      city: city,
      minBudget: minBudget,
      maxBudget: maxBudget,
      minRooms: minRooms,
      maxRooms: maxRooms,
      transactionType: transactionType,
      requiredTags: requiredTags,
      alertsOn: alertsOn,
    );
    await repo.save(search);
    return search;
  }

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  late final SavedSearchRepository _repo =
      widget.repository ?? SavedSearchRepository();

  List<SavedSearch> _searches = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final searches = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _searches = searches;
      _loading = false;
    });
  }

  Future<void> _toggleAlerts(SavedSearch search, bool value) async {
    final next = _searches
        .map((s) => s.id == search.id ? s.copyWith(alertsOn: value) : s)
        .toList();
    setState(() => _searches = next);
    await _repo.saveAll(next);
  }

  Future<void> _delete(SavedSearch search) async {
    final next = await _repo.delete(search.id);
    if (!mounted) return;
    setState(() => _searches = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: Text(
            l10n.savedSearchesScreenAce44591,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _searches.isEmpty
                ? _EmptyState(onTestAlert: _sendTestAlert)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _searches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final search = _searches[i];
                        return _SavedSearchCard(
                          search: search,
                          onToggle: (v) => _toggleAlerts(search, v),
                          onDelete: () => _confirmDelete(search),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  Future<void> _sendTestAlert() async {
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.testFireSavedSearch();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.savedSearchesScreenDe24f588)),
    );
  }

  Future<void> _confirmDelete(SavedSearch search) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title: Text(l10n.savedSearchesScreenA6ccd3f5),
          content: Text(
            l10n.savedSearchesScreenCa9c8510(search.name),
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.savedSearchesScreenA7c55a8d),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.savedSearchesScreen09b6bcca,
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _delete(search);
  }
}

class _SavedSearchCard extends StatelessWidget {
  _SavedSearchCard({
    required this.search,
    required this.onToggle,
    required this.onDelete,
  });

  final SavedSearch search;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = _summary(l10n);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  search.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textSecondary),
                tooltip: l10n.savedSearchesScreen09b6bcca,
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                search.alertsOn
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: search.alertsOn ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  search.alertsOn
                      ? l10n.savedSearchesScreen932eb7ab
                      : l10n.savedSearchesScreen0d57719f,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: search.alertsOn,
                activeColor: AppColors.primary,
                onChanged: onToggle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _summary(AppLocalizations l10n) {
    final parts = <String>[];
    final city = search.city?.trim();
    if (city != null && city.isNotEmpty) parts.add(city);

    if (search.minRooms != null || search.maxRooms != null) {
      parts.add(l10n.savedSearchesScreen0133e3ff(
          _rooms(search.minRooms, search.maxRooms, l10n)));
    }

    if (search.minBudget != null || search.maxBudget != null) {
      parts.add('${_budget(search.minBudget, search.maxBudget, l10n)} ₪');
    }

    switch (search.transactionType) {
      case 'rent':
        parts.add(l10n.savedSearchesScreenB336259f);
        break;
      case 'sale':
        parts.add(l10n.savedSearchesScreen609fac18);
        break;
    }

    if (search.requiredTags.isNotEmpty) {
      parts.add(search.requiredTags.join(', '));
    }
    return parts.join(' · ');
  }

  String _rooms(double? min, double? max, AppLocalizations l10n) {
    String fmt(double v) => v == v.roundToDouble() ? v.round().toString() : '$v';
    if (min != null && max != null) {
      return min == max ? fmt(min) : '${fmt(min)}–${fmt(max)}';
    }
    if (min != null) return l10n.savedSearchesScreenFe06d013(fmt(min));
    return l10n.savedSearchesScreen36f2a6b9(fmt(max!));
  }

  String _budget(int? min, int? max, AppLocalizations l10n) {
    if (min != null && max != null) return '$min–$max';
    if (min != null) return l10n.savedSearchesScreenA02655ab(min);
    return l10n.savedSearchesScreen09a44457(max!);
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState({required this.onTestAlert});

  final VoidCallback onTestAlert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 72, color: AppColors.primaryLight),
            const SizedBox(height: 20),
            Text(
              l10n.savedSearchesScreenC0e45e79,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '${l10n.savedSearchesScreen93343d42}'
              '${l10n.savedSearchesScreen962807e9}',
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: onTestAlert,
              child: Text(
                l10n.savedSearchesScreen023a3173,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
