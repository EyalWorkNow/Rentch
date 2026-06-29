import 'package:dating_app/core/broker/broker_match.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/broker_client_repository.dart';
import 'package:dating_app/presentation/features/broker/broker_hot_matches_screen.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
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

  List<RentalProperty> get _myProperties =>
      context.read<DatingProvider>().myProperties;

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

  void _openMatches(BrokerClient client) {
    final matches = _matcher.rank(client, _myProperties);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ClientMatchesScreen(client: client, matches: matches),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on listing changes so the "X נכסים מתאימים" counts stay live.
    final properties = context.watch<DatingProvider>().myProperties;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: const Text(
            'פנקס לקוחות',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          onPressed: () => _addOrEdit(),
          icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          label: const Text(
            'לקוח חדש',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _clients.isEmpty
                ? const _EmptyState()
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

/// A tappable strip that opens the full hot-matches screen, showing the count of
/// brand-new listing↔client matches the broker hasn't seen yet.
class _HotMatchesStrip extends StatelessWidget {
  const _HotMatchesStrip({required this.clients, required this.properties});

  final List<BrokerClient> clients;
  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
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
                        'התאמות חמות',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'נכסים חדשים שמתאימים ללקוחות שלך',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
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
  const _ClientCard({
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

  String get _criteriaLine {
    final parts = <String>[];
    parts.add(client.isSale ? 'מכירה' : 'השכרה');
    if (client.areas.isNotEmpty) parts.add(client.areas.join(', '));
    if (client.minRooms != null) parts.add('${_num(client.minRooms!)}+ חדרים');
    if (client.budgetMax != null) {
      parts.add('עד ₪${_money(client.budgetMax!)}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
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
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('עריכה')),
                      PopupMenuItem(value: 'delete', child: Text('מחיקה')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _criteriaLine,
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
                          ? '$matchCount נכסים מתאימים'
                          : 'אין נכסים מתאימים כרגע',
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: Text(
            'נכסים ל${client.name}',
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        body: matches.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'אין כרגע נכסים שמתאימים לדרישות של ${client.name}.\n'
                    'ברגע שתעלה נכס מתאים — הוא יופיע כאן.',
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
  const _MatchRow({required this.match});

  final BrokerMatch match;

  @override
  Widget build(BuildContext context) {
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
                '${p.priceLabel} ${p.priceSuffixLabel} · ${p.roomsLabel} חדרים',
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
  const _ClientFormSheet({this.client});

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
        const SnackBar(content: Text('נא להזין שם לקוח')),
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
    return Directionality(
      textDirection: TextDirection.rtl,
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
                  widget.client == null ? 'לקוח חדש' : 'עריכת לקוח',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _field(_name, 'שם הלקוח'),
                _field(_phone, 'טלפון', keyboard: TextInputType.phone),
                const SizedBox(height: 8),
                _SegmentedType(
                  value: _transactionType,
                  onChanged: (v) => setState(() => _transactionType = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(_budgetMin, 'תקציב מ-',
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(_budgetMax, 'תקציב עד',
                          keyboard: TextInputType.number),
                    ),
                  ],
                ),
                _field(_minRooms, 'מינימום חדרים',
                    keyboard: TextInputType.number),
                _field(_areas, 'אזורים (מופרדים בפסיק)'),
                _field(_mustHaves, 'חובה שיכלול (מופרדים בפסיק)'),
                _field(_notes, 'הערות', maxLines: 3),
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
                    child: const Text(
                      'שמירה',
                      style: TextStyle(
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
  const _SegmentedType({required this.value, required this.onChanged});

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

    return Row(
      children: [
        seg('rent', 'השכרה'),
        const SizedBox(width: 12),
        seg('sale', 'מכירה'),
      ],
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
            Icon(Icons.contacts_outlined,
                size: 72, color: AppColors.primaryLight),
            const SizedBox(height: 16),
            const Text(
              'פנקס הלקוחות שלך ריק',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'הוסף לקוח עם מה שהוא מחפש, והאפליקציה תראה לך אילו '
              'מהנכסים שלך מתאימים לו.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
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
