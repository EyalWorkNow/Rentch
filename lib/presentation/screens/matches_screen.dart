import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/match_labels_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:flutter/services.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

String _relativeTime(BuildContext context, DateTime dt) {
  final l10n = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return l10n.matchesScreenMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.matchesScreenHoursAgo(diff.inHours);
  if (diff.inDays == 1) return l10n.matchesScreenYesterday;
  if (diff.inDays < 7) return l10n.matchesScreenDaysAgo(diff.inDays);
  if (diff.inDays < 14) return l10n.matchesScreenWeekAgo;
  return l10n.matchesScreenWeeksAgo((diff.inDays / 7).round());
}

// ─── Filter chip descriptors ──────────────────────────────────────────────────

const _kFilterAll = 'all';
const _kFilterNew = 'new';
const _kFilterOld = 'old';
const _kFilterTomorrow = 'tomorrow';

const _kNewMatchWindow = Duration(days: 7);

// Palette for private conversation tags (ARGB ints).
const List<int> _tagColors = [
  0xFF2563EB, // blue
  0xFF16A34A, // green
  0xFFDC2626, // red
  0xFFEA580C, // orange
  0xFF9333EA, // purple
  0xFF0891B2, // teal
  0xFFCA8A04, // amber
  0xFF64748B, // slate
];

DateTime _lastActivity(RentalMatch match) {
  if (match.messages.isEmpty) return match.createdAt;
  return match.messages.last.createdAt;
}

// ─── MatchesScreen ────────────────────────────────────────────────────────────

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, this.embedded = false});

  /// When true, the screen renders as a self-contained body inside a merged
  /// host (no AppBar, transparent background). The toolbar/list/body stay
  /// intact.
  final bool embedded;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  String _query = '';
  String _ageFilter = _kFilterAll;
  String _scheduleFilter = _kFilterAll;
  // Filters start CLOSED — the bar only opens when the user taps the icon.
  bool _showFilters = false;
  // Paid message-requests (people with no match who paid extra to write you)
  // live behind a header icon, not stacked on top of the conversation list.
  bool _showRequests = false;
  final _searchCtrl = TextEditingController();

  // Private, on-device conversation labels (only this user sees them).
  final _labelsRepo = MatchLabelsRepository();
  Map<String, MatchLabel> _labels = {};

  @override
  void initState() {
    super.initState();
    // Pull the latest matches when the tab opens so a conversation created while
    // the user was elsewhere in the app (e.g. a landlord just accepted their
    // like) shows up without a relaunch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DatingProvider>().refreshMatchesFromBackend();
    });
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    final all = await _labelsRepo.loadAll();
    if (mounted) setState(() => _labels = all);
  }

  // Long-press on a conversation → private tag + unmatch.
  void _showCardActions(RentalMatch match, RentalProperty property) {
    HapticFeedback.selectionClick();
    final existing = _labels[match.id];
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(IconsaxPlusLinear.tag,
                    color: AppColors.primary),
                title: Text(existing == null
                    ? l10n.matchesScreenAddPrivateTag
                    : l10n.matchesScreenEditTag),
                subtitle: Text(l10n.matchesScreenOnlyYouSeeTag),
                onTap: () {
                  Navigator.pop(ctx);
                  _showTagEditor(match.id);
                },
              ),
              if (existing != null)
                ListTile(
                  leading: Icon(IconsaxPlusLinear.tag_cross,
                      color: AppColors.textSecondary),
                  title: Text(l10n.matchesScreenRemoveTag),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _labelsRepo.remove(match.id);
                    if (mounted) setState(() => _labels.remove(match.id));
                  },
                ),
              ListTile(
                leading: Icon(IconsaxPlusLinear.close_circle,
                    color: AppColors.coral),
                title: Text(l10n.matchesScreenUnmatch,
                    style: const TextStyle(color: AppColors.coral)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmUnmatch(match);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmUnmatch(RentalMatch match) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.matchesScreenConfirmUnmatchTitle),
          content: Text(l10n.matchesScreenConfirmUnmatchBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text(l10n.matchesScreenGoBack)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
              onPressed: () async {
                Navigator.pop(dctx);
                await context.read<DatingProvider>().unmatch(match.id);
                await _labelsRepo.remove(match.id);
                if (mounted) setState(() => _labels.remove(match.id));
              },
              child: Text(l10n.matchesScreenUnmatch),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagEditor(String matchId) {
    final existing = _labels[matchId];
    final ctrl = TextEditingController(text: existing?.text ?? '');
    var color = existing?.color ?? _tagColors.first;
    const colors = _tagColors;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Directionality(
            textDirection: Directionality.of(context),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.matchesScreenPrivateTag,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(l10n.matchesScreenPrivateTagHint,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ctrl,
                      maxLength: 24,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.matchesScreenTagPlaceholder,
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in colors)
                          GestureDetector(
                            onTap: () => setSheet(() => color = c),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == c
                                      ? AppColors.navy
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: color == c
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          final text = ctrl.text.trim();
                          if (text.isEmpty) {
                            Navigator.pop(ctx);
                            return;
                          }
                          final label = MatchLabel(text: text, color: color);
                          await _labelsRepo.set(matchId, label);
                          if (mounted) {
                            setState(() => _labels[matchId] = label);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Text(l10n.matchesScreenSaveTag,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Builds filtered pairs of (match, property) from the full match list.
  List<({RentalMatch match, RentalProperty property})> _applyFilters(
    List<RentalMatch> matches,
    DatingProvider provider,
  ) {
    final pairs = matches
        .map((m) {
          final p = provider.propertyById(m.propertyId);
          if (p == null) return null;
          return (match: m, property: p);
        })
        .whereType<({RentalMatch match, RentalProperty property})>()
        .toList();

    final q = _query.trim().toLowerCase();
    final afterSearch = q.isEmpty
        ? pairs
        : pairs.where((pair) {
            final prop = pair.property;
            return prop.address.toLowerCase().contains(q) ||
                prop.city.toLowerCase().contains(q) ||
                prop.neighborhood.toLowerCase().contains(q) ||
                pair.match.messages.any(
                  (message) => message.text.toLowerCase().contains(q),
                );
          }).toList();

    final now = DateTime.now();
    List<({RentalMatch match, RentalProperty property})> filtered;
    switch (_ageFilter) {
      case _kFilterNew:
        filtered = afterSearch
            .where((pair) =>
                now.difference(pair.match.createdAt) <= _kNewMatchWindow)
            .toList();
        break;
      case _kFilterOld:
        filtered = afterSearch
            .where((pair) =>
                now.difference(pair.match.createdAt) > _kNewMatchWindow)
            .toList();
        break;
      default:
        filtered = afterSearch;
    }

    if (_scheduleFilter == _kFilterTomorrow) {
      filtered = filtered
          .where((pair) => pair.match.messages.any(
                (message) => message.text.contains('מחר'),
              ))
          .toList();
    }

    filtered.sort(
      (a, b) => _lastActivity(b.match).compareTo(_lastActivity(a.match)),
    );
    return filtered;
  }

  bool get _isFiltering =>
      _query.trim().isNotEmpty ||
      _ageFilter != _kFilterAll ||
      _scheduleFilter != _kFilterAll;

  void _clearFilters() {
    setState(() {
      _query = '';
      _ageFilter = _kFilterAll;
      _scheduleFilter = _kFilterAll;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final allMatches = provider.matches;
        // One-sided "request to message" threads get their own section; the
        // normal conversations list excludes them.
        final requestPairs = allMatches
            .where((m) => m.isRequest)
            .map((m) {
              final p = provider.propertyById(m.propertyId);
              return p == null ? null : (match: m, property: p);
            })
            .whereType<({RentalMatch match, RentalProperty property})>()
            .toList();
        final filtered = _applyFilters(
            allMatches.where((m) => !m.isRequest).toList(), provider);

        return Scaffold(
          appBar: null,
          backgroundColor:
              widget.embedded ? Colors.transparent : AppColors.slate100,
          body: SafeArea(
            // When embedded in the merged לקוחות screen the host already applies
            // the top inset above the segment toggle — re-applying it here would
            // double the status-bar gap (NAV-A).
            top: !widget.embedded,
            bottom: false,
            child: provider.isLoading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : allMatches.isEmpty
                    ? _EmptyMatches(isLandlord: provider.isLandlord)
                    : Column(
                        children: [
                          // Paid message-requests entry — an icon + count that
                          // reveals the "paid to write you" inquiries on tap.
                          if (requestPairs.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: _RequestsToggle(
                                count: requestPairs.length,
                                active: _showRequests,
                                onTap: () => setState(
                                    () => _showRequests = !_showRequests),
                              ),
                            ),
                          _MatchesToolbar(
                            controller: _searchCtrl,
                            query: _query,
                            ageFilter: _ageFilter,
                            scheduleFilter: _scheduleFilter,
                            showFilters: _showFilters,
                            onFilterTap: () =>
                                setState(() => _showFilters = !_showFilters),
                            onQueryChanged: (value) =>
                                setState(() => _query = value),
                            onClearQuery: () => setState(() {
                              _query = '';
                              _searchCtrl.clear();
                            }),
                            onAgeFilterChanged: (value) =>
                                setState(() => _ageFilter = value),
                            onScheduleFilterChanged: (value) =>
                                setState(() => _scheduleFilter = value),
                          ),
                          Expanded(
                            child: (filtered.isEmpty && requestPairs.isEmpty)
                                ? _EmptyFilterResults(onClear: _clearFilters)
                                : Builder(builder: (context) {
                                    // Same ordered widget list the previous
                                    // ListView(children: [...]) produced via
                                    // its inline if/for spread — only the
                                    // widget itself changes below (eager
                                    // ListView -> lazy ListView.builder), not
                                    // the ordering/content of items.
                                    final listChildren = <Widget>[
                                      if (_showRequests &&
                                          requestPairs.isNotEmpty) ...[
                                        _MessagesSectionHeader(
                                          icon: Icons.mark_email_unread_outlined,
                                          label: l10n.matchesScreenPaidInquiries,
                                          count: requestPairs.length,
                                        ),
                                        const SizedBox(height: 10),
                                        for (final pair in requestPairs)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 14),
                                            child: _MatchCard(
                                              match: pair.match,
                                              property: pair.property,
                                              label: _labels[pair.match.id],
                                              onLongPress: () => _showCardActions(
                                                  pair.match, pair.property),
                                              onTap: () =>
                                                  Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  settings: const RouteSettings(
                                                      name: 'MessageScreen'),
                                                  builder: (_) => MessageScreen(
                                                      matchId: pair.match.id),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (filtered.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          _MessagesSectionHeader(
                                            icon: Icons.chat_bubble_outline_rounded,
                                            label: l10n.matchesScreenConversations,
                                            count: filtered.length,
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                      ],
                                      for (final pair in filtered)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 14),
                                          child: _MatchCard(
                                            match: pair.match,
                                            property: pair.property,
                                            label: _labels[pair.match.id],
                                            onLongPress: () => _showCardActions(
                                                pair.match, pair.property),
                                            onTap: () =>
                                                Navigator.of(context).push(
                                              MaterialPageRoute(
                                                settings: const RouteSettings(
                                                    name: 'MessageScreen'),
                                                builder: (_) => MessageScreen(
                                                    matchId: pair.match.id),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ];
                                    return ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 12, 16, 120),
                                      itemCount: listChildren.length,
                                      itemBuilder: (context, index) =>
                                          listChildren[index],
                                    );
                                  }),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class _MessagesSectionHeader extends StatelessWidget {
  _MessagesSectionHeader({
    required this.icon,
    required this.label,
    required this.count,
  });
  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Header pill that reveals the paid message-requests (tenants with no match who
/// paid extra to write the landlord about a listing). Tap to expand/collapse.
class _RequestsToggle extends StatelessWidget {
  _RequestsToggle({
    required this.count,
    required this.active,
    required this.onTap,
  });

  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_email_unread_rounded,
              size: 18,
              color: active ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                AppLocalizations.of(context)!.matchesScreenPaidInquiries,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color:
                    active ? Colors.white.withOpacity(0.25) : AppColors.coral,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              active ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchesToolbar extends StatelessWidget {
  _MatchesToolbar({
    required this.controller,
    required this.query,
    required this.ageFilter,
    required this.scheduleFilter,
    required this.showFilters,
    required this.onFilterTap,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onAgeFilterChanged,
    required this.onScheduleFilterChanged,
  });

  final TextEditingController controller;
  final String query;
  final String ageFilter;
  final String scheduleFilter;
  final bool showFilters;
  final VoidCallback onFilterTap;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onAgeFilterChanged;
  final ValueChanged<String> onScheduleFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const SizedBox(width: 10),
                const RentlyIcon(
                  IconsaxPlusLinear.search_normal,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onQueryChanged,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.matchesScreenSearchHint,
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: query.isNotEmpty ? 1.0 : 0.0,
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: query.isNotEmpty ? 1.0 : 0.0,
                    child: ScaleBounce(
                      onTap: onClearQuery,
                      scaleDownTo: 0.82,
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: RentlyIcon(
                          IconsaxPlusLinear.close_circle,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                ScaleBounce(
                  onTap: onFilterTap,
                  scaleDownTo: 0.88,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: showFilters
                          ? AppColors.primary
                          : AppColors.slate100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AnimatedRotation(
                        turns: showFilters ? 0.125 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: RentlyIcon(
                          IconsaxPlusLinear.setting_4,
                          size: 18,
                          color: showFilters ? Colors.white : AppColors.navy,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    _FilterPill(
                      label: l10n.matchesScreenFilterAll,
                      isSelected: ageFilter == _kFilterAll &&
                          scheduleFilter == _kFilterAll,
                      onTap: () {
                        onAgeFilterChanged(_kFilterAll);
                        onScheduleFilterChanged(_kFilterAll);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l10n.matchesScreenFilterNew,
                      isSelected: ageFilter == _kFilterNew,
                      onTap: () {
                        onAgeFilterChanged(_kFilterNew);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l10n.matchesScreenFilterOld,
                      isSelected: ageFilter == _kFilterOld,
                      onTap: () {
                        onAgeFilterChanged(_kFilterOld);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l10n.matchesScreenFilterMatchesTomorrow,
                      isSelected: scheduleFilter == _kFilterTomorrow,
                      onTap: () {
                        onScheduleFilterChanged(
                          scheduleFilter == _kFilterTomorrow
                              ? _kFilterAll
                              : _kFilterTomorrow,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            crossFadeState: showFilters
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  _FilterPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChipAnimated(
      isSelected: isSelected,
      onTap: onTap,
      activeColor: AppColors.primary,
      inactiveColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Empty filter results ─────────────────────────────────────────────────────

class _EmptyFilterResults extends StatelessWidget {
  _EmptyFilterResults({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: RentlyIcon(
                IconsaxPlusLinear.search_normal,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.matchesScreenNoResultsFound,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.matchesScreenNoResultsForSearch,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const RentlyIcon(IconsaxPlusLinear.close_circle, size: 16),
              label: Text(l10n.matchesScreenClearFilter),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Match card ───────────────────────────────────────────────────────────────

class _MatchCard extends StatefulWidget {
  _MatchCard({
    required this.match,
    required this.property,
    required this.onTap,
    this.onLongPress,
    this.label,
  });

  final RentalMatch match;
  final RentalProperty property;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Private on-device tag (only this user sees it).
  final MatchLabel? label;

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _isExpanded = false;

  ({String label, Color color, IconData icon}) _matchStage(RentalMatch match) {
    final l10n = AppLocalizations.of(context)!;
    if (match.ownerSigned && match.tenantSigned) {
      return (
        label: l10n.matchesScreenSigned,
        color: AppColors.success,
        icon: IconsaxPlusLinear.tick_circle,
      );
    }
    if (match.contractSent) {
      return (
        label: l10n.matchesScreenContractSent,
        color: AppColors.success,
        icon: IconsaxPlusLinear.document_text,
      );
    }
    return (
      label: l10n.matchesScreenOpenConversation,
      color: AppColors.primary,
      icon: IconsaxPlusLinear.message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = widget.property.primaryMedia;
    final lastMessage =
        widget.match.messages.isEmpty ? null : widget.match.messages.last;
    final stage = _matchStage(widget.match);
    final provider = context.read<DatingProvider>();
    final isLandlord = provider.isLandlord;
    final tenantName = provider.tenantProfile?.name ?? '';
    final awaitingReply = isLandlord &&
        lastMessage != null &&
        tenantName.isNotEmpty &&
        lastMessage.isMine(
            myUid: FirebaseAuth.instance.currentUser?.uid ?? '',
            myName: tenantName);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: ScaleBounce(
      onTap: widget.onTap,
      scaleDownTo: 0.97,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: AspectRatio(
                aspectRatio: 1.84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SafeMedia(
                        media: media,
                        fallback: Container(
                          color: AppColors.primaryLight2,
                          child: RentlyIcon(
                            IconsaxPlusLinear.building,
                            color: AppColors.primary,
                            size: 48,
                          ),
                        ),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.property.propertyType,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      // Private tag (only this user sees it).
                      if (widget.label != null)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Color(widget.label!.color),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(IconsaxPlusBold.tag,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(widget.label!.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _FreshnessBadge(match: widget.match),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const RentlyIcon(
                              IconsaxPlusLinear.send_2,
                              color: AppColors.navy,
                              size: 16,
                            ),
                            onPressed: () {
                              showPropertyShareSheet(context, widget.property);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const OnlineDotPulse(size: 8),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.property.street.isNotEmpty
                                        ? '${widget.property.street} ${widget.property.streetNumber}'
                                        : widget.property.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.property.city}, ${widget.property.neighborhood}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.property.priceLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _MockupChip(
                          icon: IconsaxPlusLinear.home,
                          label: l10n.matchesScreenRoomsCount(
                              widget.property.roomsLabel),
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: l10n.matchesScreenSquareMeters(
                              widget.property.sizeM2),
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.routing,
                          label: widget.property.features.firstOrNull ??
                              l10n.matchesScreenElevator,
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.wind,
                          label: widget.property.features.length > 1
                              ? widget.property.features[1]
                              : l10n.matchesScreenAirConditioned,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _MockupChip extends StatelessWidget {
  const _MockupChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.navy,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreshnessBadge extends StatelessWidget {
  _FreshnessBadge({required this.match});

  final RentalMatch match;

  @override
  Widget build(BuildContext context) {
    final lastActivity = match.messages.isNotEmpty
        ? match.messages.last.createdAt
        : match.createdAt;
    final isNew =
        DateTime.now().difference(match.createdAt) <= _kNewMatchWindow;
    final timeLabel = _relativeTime(context, lastActivity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (isNew ? AppColors.primary : AppColors.textSecondary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isNew && match.messages.isEmpty
            ? AppLocalizations.of(context)!.matchesScreenNew
            : timeLabel,
        style: TextStyle(
          color: isNew ? AppColors.primary : AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LastMessagePreview extends StatelessWidget {
  _LastMessagePreview({required this.message});

  final ChatMessage? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          RentlyIcon(
            IconsaxPlusLinear.message,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message?.text ??
                  AppLocalizations.of(context)!.matchesScreenNewConversationReady,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty matches (no matches at all) ───────────────────────────────────────

class _EmptyMatches extends StatelessWidget {
  _EmptyMatches({required this.isLandlord});
  final bool isLandlord;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: RentlyIcon(
                IconsaxPlusLinear.heart_tick,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.matchesScreenNoMatchesYet,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isLandlord
                  ? l10n.matchesScreenNoMatchesLandlordBody
                  : l10n.matchesScreenNoMatchesTenantBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
