import 'package:dating_app/core/broker/broker_match.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/broker_client_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/broker/broker_hot_matches_screen.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

/// "פנקס לקוחות" — the broker's (מתווך) client book / CRM.
///
/// Brokers lose deals because clients live in their head and on WhatsApp. This
/// screen turns that into a clean list: who they're sourcing for, what each one
/// wants, and — the payoff — how many of the broker's *own* listings already fit
/// each client ("X נכסים מתאימים"). Tapping a client opens its ranked matching
/// listings; a top strip surfaces brand-new hot matches. Built for older users:
/// big text, generous spacing, simple RTL form sheet.
class BrokerClientsScreen extends StatefulWidget {
  const BrokerClientsScreen({super.key, this.repository});

  final BrokerClientRepository? repository;

  @override
  State<BrokerClientsScreen> createState() => _BrokerClientsScreenState();
}

class _BrokerClientsScreenState extends State<BrokerClientsScreen> {
  late final BrokerClientRepository _repo =
      widget.repository ?? BrokerClientRepository();
  static const _matcher = BrokerMatcher();

  List<BrokerClient> _clients = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clients = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _loading = false;
    });
  }

  // Match a client against the whole loaded MARKET (own listings + the feed
  // catalog), not just the broker's own listings — a buyer's agent wants the
  // best flats across the market, not only the 3 they uploaded.
  List<RentalProperty> get _marketPool =>
      context.read<DatingProvider>().allProperties;

  Future<void> _addOrEdit([BrokerClient? existing]) async {
    final result = await showModalBottomSheet<BrokerClient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientFormSheet(client: existing),
    );
    if (result == null) return;
    final next = await _repo.save(result);
    if (!mounted) return;
    setState(() => _clients = next);
  }

  Future<void> _delete(BrokerClient client) async {
    final next = await _repo.delete(client.id);
    if (!mounted) return;
    setState(() => _clients = next);
  }

  // Bulk-import clients from the phone's contacts — the "won't hand-type 800
  // clients" fix. Picks name + first phone; criteria are filled in later per
  // client. Skips contacts whose number already exists in the book.
  Future<void> _importFromContacts() async {
    final l10n = AppLocalizations.of(context)!;
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (!mounted) return;
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.brokerClientsScreenContactsPermissionNeeded)));
      return;
    }
    final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone});
    final pickable = contacts
        .where((c) =>
            (c.displayName ?? '').trim().isNotEmpty && c.phones.isNotEmpty)
        .toList()
      ..sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
    if (!mounted) return;
    if (pickable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(l10n.brokerClientsScreenNoContactsWithPhoneFound)));
      return;
    }
    final selected = await showModalBottomSheet<List<Contact>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactPickerSheet(contacts: pickable),
    );
    if (selected == null || selected.isEmpty) return;

    final existing = _clients
        .map((c) => c.phone.replaceAll(RegExp(r'\D'), ''))
        .where((p) => p.isNotEmpty)
        .toSet();
    final toAdd = <BrokerClient>[];
    for (var i = 0; i < selected.length; i++) {
      final c = selected[i];
      // A selected contact may have no phone (email-only/company) — skip it
      // instead of crashing on an empty-list .first.
      if (c.phones.isEmpty) continue;
      final phone = c.phones.first.number;
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty && existing.contains(digits)) continue;
      toAdd.add(BrokerClient(
        id: 'c-${DateTime.now().microsecondsSinceEpoch}-$i',
        name: (c.displayName ?? '').trim(),
        phone: phone,
      ));
      if (digits.isNotEmpty) existing.add(digits);
    }
    // One disk write + one cloud push for the whole import, not one per contact.
    final next = await _repo.saveAll(toAdd);
    final added = toAdd.length;
    if (!mounted) return;
    setState(() => _clients = next);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.brokerClientsScreenContactsImported(added))));
  }

  void _openMatches(BrokerClient client) {
    final matches = _matcher.rank(client, _marketPool);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ClientMatchesScreen(client: client, matches: matches),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Rebuild on listing changes so the "X נכסים מתאימים" counts stay live.
    final properties = context.watch<DatingProvider>().allProperties;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(l10n.brokerClientsScreenClientBook),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
          actions: [
            IconButton(
              tooltip: l10n.brokerClientsScreenImportFromContacts,
              icon: const Icon(Icons.contacts_outlined),
              onPressed: _importFromContacts,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          onPressed: () => _addOrEdit(),
          icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          label: Text(
            l10n.brokerClientsScreenNewClient,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _clients.isEmpty
                ? _EmptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        _HotMatchesStrip(
                          clients: _clients,
                          properties: properties,
                        ),
                        const SizedBox(height: 4),
                        for (final c in _clients) ...[
                          _ClientCard(
                            client: c,
                            matchCount: _matcher.countFits(c, properties),
                            onTap: () => _openMatches(c),
                            onEdit: () => _addOrEdit(c),
                            onDelete: () => _delete(c),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// A tappable strip that opens the full hot-matches screen, showing the LIVE
/// count of strong listing↔client pairings across the broker's clients.
class _HotMatchesStrip extends StatelessWidget {
  _HotMatchesStrip({required this.clients, required this.properties});

  final List<BrokerClient> clients;
  final List<RentalProperty> properties;

  static const _matcher = BrokerMatcher();
  static const int _minHotScore = 70;

  int get _hotCount {
    var n = 0;
    for (final c in clients) {
      for (final m in _matcher.rank(c, properties)) {
        if (m.score >= _minHotScore) n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count = _hotCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BrokerHotMatchesScreen(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: AppColors.primaryDark, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.brokerClientsScreenHotMatches,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count > 0
                            ? l10n.brokerClientsScreenStrongMatchesWaiting(count)
                            : l10n.brokerClientsScreenPropertiesThatFitClients,
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900)),
                  ),
                Icon(Icons.chevron_left, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  _ClientCard({
    required this.client,
    required this.matchCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final BrokerClient client;
  final int matchCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _criteriaLine(AppLocalizations l10n) {
    final parts = <String>[];
    parts.add(client.isSale
        ? l10n.brokerClientsScreenSale
        : l10n.brokerClientsScreenRent);
    if (client.areas.isNotEmpty) parts.add(client.areas.join(', '));
    if (client.minRooms != null) {
      parts.add(l10n.brokerClientsScreenMinRoomsPlus(_num(client.minRooms!)));
    }
    if (client.budgetMax != null) {
      parts.add(
          l10n.brokerClientsScreenBudgetUpTo('₪${_money(client.budgetMax!)}'));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      client.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'edit',
                          child: Text(l10n.brokerClientsScreenEdit)),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.brokerClientsScreenDelete)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _criteriaLine(l10n),
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              if (client.mustHaves.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in client.mustHaves)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(t,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: matchCount > 0
                      ? AppColors.primaryLight2
                      : AppColors.divider,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      matchCount > 0 ? Icons.check_circle : Icons.search_off,
                      size: 18,
                      color: matchCount > 0
                          ? AppColors.primaryDark
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      matchCount > 0
                          ? l10n.brokerClientsScreenMatchingProperties(matchCount)
                          : l10n.brokerClientsScreenNoMatchingPropertiesNow,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: matchCount > 0
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
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

/// The ranked matching listings for a single client. Each row → PropertyDetail.
class _ClientMatchesScreen extends StatelessWidget {
  const _ClientMatchesScreen({required this.client, required this.matches});

  final BrokerClient client;
  final List<BrokerMatch> matches;

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
            l10n.brokerClientsScreenPropertiesForClient(client.name),
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        body: matches.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '${l10n.brokerClientsScreenNoMatchingPropertiesForClient(client.name)}\n'
                    '${l10n.brokerClientsScreenMatchWillAppearHere}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, color: AppColors.textSecondary),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _MatchRow(match: matches[i]),
              ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  _MatchRow({required this.match});

  final BrokerMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = match.property;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(property: p),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.address,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${match.score}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.brokerClientsScreenPriceRoomsSummary(
                    p.priceLabel, p.priceSuffixLabel, p.roomsLabel),
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              if (match.reasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in match.reasons.take(4))
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

/// The add / edit client form, as an RTL bottom sheet. Big inputs, simple.
class _ClientFormSheet extends StatefulWidget {
  _ClientFormSheet({this.client});

  final BrokerClient? client;

  @override
  State<_ClientFormSheet> createState() => _ClientFormSheetState();
}

class _ClientFormSheetState extends State<_ClientFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.client?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.client?.phone ?? '');
  late final TextEditingController _areas = TextEditingController(
      text: widget.client?.areas.join(', ') ?? '');
  late final TextEditingController _mustHaves = TextEditingController(
      text: widget.client?.mustHaves.join(', ') ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.client?.notes ?? '');
  late final TextEditingController _budgetMin = TextEditingController(
      text: widget.client?.budgetMin?.toString() ?? '');
  late final TextEditingController _budgetMax = TextEditingController(
      text: widget.client?.budgetMax?.toString() ?? '');
  late final TextEditingController _minRooms = TextEditingController(
      text: widget.client?.minRooms == null
          ? ''
          : _num(widget.client!.minRooms!));

  late String _transactionType = widget.client?.transactionType ?? 'rent';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _areas.dispose();
    _mustHaves.dispose();
    _notes.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _minRooms.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String raw) => raw
      .split(RegExp(r'[,\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.brokerClientsScreenEnterClientName)),
      );
      return;
    }
    final client = BrokerClient(
      id: widget.client?.id ??
          'bc_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: _phone.text.trim(),
      transactionType: _transactionType,
      budgetMin: int.tryParse(_budgetMin.text.trim()),
      budgetMax: int.tryParse(_budgetMax.text.trim()),
      areas: _splitCsv(_areas.text),
      minRooms: double.tryParse(_minRooms.text.trim()),
      mustHaves: _splitCsv(_mustHaves.text),
      notes: _notes.text.trim(),
      createdAt: widget.client?.createdAt,
    );
    Navigator.of(context).pop(client);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.client == null
                      ? l10n.brokerClientsScreenNewClient
                      : l10n.brokerClientsScreenEditClient,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _field(_name, l10n.brokerClientsScreenClientName),
                _field(_phone, l10n.brokerClientsScreenPhone,
                    keyboard: TextInputType.phone),
                const SizedBox(height: 8),
                _SegmentedType(
                  value: _transactionType,
                  onChanged: (v) => setState(() => _transactionType = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(_budgetMin, l10n.brokerClientsScreenBudgetFrom,
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(_budgetMax, l10n.brokerClientsScreenBudgetTo,
                          keyboard: TextInputType.number),
                    ),
                  ],
                ),
                _field(_minRooms, l10n.brokerClientsScreenMinRooms,
                    keyboard: TextInputType.number),
                _field(_areas, l10n.brokerClientsScreenAreasCommaSeparated),
                _field(_mustHaves, l10n.brokerClientsScreenMustHaveCommaSeparated),
                _field(_notes, l10n.brokerClientsScreenNotes, maxLines: 3),
                const SizedBox(height: 8),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(
                      l10n.brokerClientsScreenSave,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 16),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

class _SegmentedType extends StatelessWidget {
  _SegmentedType({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String type, String label) {
      final selected = value == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(type),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderLight,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        seg('rent', l10n.brokerClientsScreenRent),
        const SizedBox(width: 12),
        seg('sale', l10n.brokerClientsScreenSale),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contacts_outlined,
                size: 72, color: AppColors.primaryLight),
            const SizedBox(height: 16),
            Text(
              l10n.brokerClientsScreenClientBookEmpty,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.brokerClientsScreenEmptyStateBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _num(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

String _money(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Searchable multi-select of phone contacts → returns the chosen ones.
class _ContactPickerSheet extends StatefulWidget {
  _ContactPickerSheet({required this.contacts});
  final List<Contact> contacts;
  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _selected = <String>{}; // contact ids
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _q.trim();
    final list = q.isEmpty
        ? widget.contacts
        : widget.contacts
            .where((c) =>
                (c.displayName ?? '').toLowerCase().contains(q.toLowerCase()))
            .toList();
    return Directionality(
      textDirection: Directionality.of(context),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.brokerClientsScreenSelectContactsToImport,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold)),
                  ),
                  Text(
                      l10n.brokerClientsScreenSelectedCount(_selected.length),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: l10n.brokerClientsScreenSearchContact,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final id = c.id ?? '';
                    final on = _selected.contains(id);
                    return CheckboxListTile(
                      value: on,
                      activeColor: AppColors.primary,
                      title: Text(c.displayName ?? '',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          c.phones.isNotEmpty ? c.phones.first.number : '',
                          textDirection: TextDirection.ltr),
                      onChanged: (_) => setState(() =>
                          on ? _selected.remove(id) : _selected.add(id)),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(widget.contacts
                            .where((c) => _selected.contains(c.id ?? ''))
                            .toList()),
                    child: Text(
                        l10n.brokerClientsScreenImportClients(_selected.length),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
