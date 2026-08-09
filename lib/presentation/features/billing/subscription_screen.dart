import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/subscription.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/billing/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// "המנוי שלי" — landlord subscription management screen, restyled to 100% match
/// the sleek Light iOS luxury design system of PaywallScreen.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  bool _busy = false;
  List<Invoice> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<DatingProvider>();
    await provider.refreshSubscription();
    List<Invoice> invoices = const [];
    try {
      invoices = await AwsApiClient.instance.getInvoices();
    } catch (_) {
      invoices = const [];
    }
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _loading = false;
    });
  }

  String _shekel(int amount) => '₪${_thousands(amount)}';

  String _thousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _date(DateTime? d) {
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _planLabel(String? plan) {
    final l10n = AppLocalizations.of(context)!;
    return switch (plan) {
      'annual' => l10n.subscriptionScreenF29b6ff9,
      'monthly' => l10n.subscriptionScreen73934490,
      'vip' => l10n.subscriptionScreenA4257fc5,
      _ => l10n.subscriptionScreenB18c066f,
    };
  }

  Future<void> _openInvoice(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            l10n.subscriptionScreen2b7d5edc,
            style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
          ),
          content: Text(
            l10n.subscriptionScreenD9eefdcc,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.subscriptionScreen10a2352b,
                  style: const TextStyle(color: Color(0xFF64748B))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.subscriptionScreen00a5e771,
                style: const TextStyle(color: AppColors.coral, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _run(AwsApiClient.instance.cancelSubscription(),
        l10n.subscriptionScreen6ca6bd18);
  }

  Future<void> _resume() async {
    final l10n = AppLocalizations.of(context)!;
    await _run(
        AwsApiClient.instance.resumeSubscription(), l10n.subscriptionScreenA3c4c747);
  }

  Future<void> _run(Future<void> action, String okMessage) async {
    if (_busy) return;
    final provider = context.read<DatingProvider>();
    setState(() => _busy = true);
    try {
      await action;
      await provider.refreshSubscription();
      if (!mounted) return;
      _snack(okMessage, ok: true);
    } catch (_) {
      if (!mounted) return;
      _snack(AppLocalizations.of(context)!.subscriptionScreenA8ba6aa6);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Text(message),
      backgroundColor: ok ? const Color(0xFF22C55E) : AppColors.coral,
    ));
  }

  Future<void> _openPaywall() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'PaywallScreen'),
        builder: (_) => const PaywallScreen(),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<DatingProvider>().subscription;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'RENTLY',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
              )
            : (sub == null || !sub.entitled)
                ? _buildNoSubscription()
                : _buildActive(sub),
      ),
    );
  }

  Widget _buildNoSubscription() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          // 3D Cute House Artwork matching PaywallScreen
          SizedBox(
            height: 180,
            child: Image.asset(
              'assets/images/paywall_3d_hero.png',
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  IconsaxPlusBold.card,
                  size: 48,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.subscriptionScreen3c4641b6,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.subscriptionScreen1abb5cf0,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Feature List Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _FeatureHighlightRow(label: l10n.subscriptionScreen74b0f662),
                const SizedBox(height: 12),
                _FeatureHighlightRow(label: l10n.subscriptionScreen6e6d4e06),
                const SizedBox(height: 12),
                _FeatureHighlightRow(label: l10n.subscriptionScreen6b0e2fd9),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Primary CTA Button matching PaywallScreen
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: GestureDetector(
                onTap: _openPaywall,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B61F6), Color(0xFF4F46E5)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B61F6).withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.subscriptionScreenA324e706,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(Subscription sub) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _StatusPill(sub: sub),
        const SizedBox(height: 16),
        _InfoCard(sub: sub, planLabel: _planLabel, shekel: _shekel, date: _date),
        const SizedBox(height: 20),
        _buildAction(sub),
        if (_invoices.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            l10n.subscriptionScreen7aa12af9,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          for (final inv in _invoices) ...[
            _InvoiceRow(
              title: _planLabel(inv.plan),
              subtitle: _date(inv.issuedAt),
              amountLabel: _shekel(inv.sumAgorot ~/ 100),
              onTap: inv.url.isEmpty ? null : () => _openInvoice(inv.url),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _buildAction(Subscription sub) {
    final l10n = AppLocalizations.of(context)!;
    final canceling = sub.cancelAtPeriodEnd;
    final label = canceling
        ? l10n.subscriptionScreen680ede0e
        : l10n.subscriptionScreen00a5e771;
    final color = canceling ? const Color(0xFF4F46E5) : AppColors.coral;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: color.withOpacity(0.06),
        ),
        onPressed: _busy ? null : (canceling ? _resume : _cancel),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF4F46E5)),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color, bg) = sub.cancelAtPeriodEnd
        ? (l10n.subscriptionScreen6b44102c, const Color(0xFFEA580C), const Color(0xFFFFEDD5))
        : sub.entitled
            ? (l10n.subscriptionScreen09900e25, const Color(0xFF16A34A), const Color(0xFFDCFCE7))
            : (l10n.subscriptionScreen98e268e7, const Color(0xFF64748B), const Color(0xFFF1F5F9));
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.sub,
    required this.planLabel,
    required this.shekel,
    required this.date,
  });

  final Subscription sub;
  final String Function(String?) planLabel;
  final String Function(int) shekel;
  final String Function(DateTime?) date;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  planLabel(sub.plan),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                shekel(sub.priceAgorot ~/ 100),
                style: const TextStyle(
                  color: Color(0xFF4F46E5),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 16),
          _Line(
            icon: IconsaxPlusLinear.calendar_1,
            label: sub.cancelAtPeriodEnd
                ? l10n.subscriptionScreen03baa387
                : l10n.subscriptionScreenD4bd0d5c,
            value: date(sub.currentPeriodEnd),
          ),
          if (sub.card != null) ...[
            const SizedBox(height: 14),
            _Line(
              icon: IconsaxPlusLinear.card,
              label: l10n.subscriptionScreenA0d9b485,
              value: '${sub.card!.brand} •••• ${sub.card!.last4}'.trim(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String amountLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                amountLabel,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 10),
                const Icon(
                  IconsaxPlusLinear.document_download,
                  size: 18,
                  color: Color(0xFF4F46E5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureHighlightRow extends StatelessWidget {
  const _FeatureHighlightRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFF4F46E5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 12,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
