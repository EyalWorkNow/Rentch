import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Shows a rental contract's terms + both parties' e-signatures, and lets the
/// current user sign their part with a handwritten + cryptographic signature.
class ContractDetailScreen extends StatelessWidget {
  const ContractDetailScreen({
    super.key,
    required this.contractId,
    required this.matchId,
  });

  final String contractId;
  final String matchId;

  RentalContract? _find(DatingProvider p) {
    for (final c in p.contracts) {
      if (c.id == contractId) return c;
    }
    return p.contractForMatch(matchId);
  }

  void _showDocumentPreview(BuildContext context, RentalContract c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ContractDocumentPage(contract: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('חוזה שכירות'),
        actions: [
          IconButton(
            tooltip: 'תצוגה מקדימה של המסמך',
            icon: const Icon(IconsaxPlusLinear.document_text),
            onPressed: () {
              final c = _find(context.read<DatingProvider>());
              if (c != null) _showDocumentPreview(context, c);
            },
          ),
        ],
      ),
      body: Consumer<DatingProvider>(
        builder: (context, provider, _) {
          final contract = _find(provider);
          if (contract == null) {
            return const Center(child: Text('החוזה לא נמצא'));
          }
          final isLandlord = provider.isLandlord;
          final mySig = isLandlord
              ? contract.landlordSignature
              : contract.tenantSignature;
          final canSign = mySig == null &&
              contract.status != ContractStatus.cancelled &&
              contract.status != ContractStatus.declined;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _statusBanner(contract),
                    const SizedBox(height: 12),
                    _termsCard(contract),
                    const SizedBox(height: 12),
                    _SignatureSlot(
                      title: 'בעל הדירה',
                      name: contract.landlordName,
                      signature: contract.landlordSignature,
                      contract: contract,
                    ),
                    const SizedBox(height: 10),
                    _SignatureSlot(
                      title: 'השוכר/ת',
                      name: contract.tenantName,
                      signature: contract.tenantSignature,
                      contract: contract,
                    ),
                    const SizedBox(height: 16),
                    _securityNote(),
                  ],
                ),
              ),
              if (canSign)
                SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _openSignSheet(context, provider, contract, isLandlord),
                      icon: const Icon(IconsaxPlusLinear.edit, size: 18),
                      label: Text(
                          'חתום על החוזה כ${isLandlord ? "בעל הדירה" : "שוכר/ת"}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusBanner(RentalContract c) {
    final (label, color, icon) = switch (c.status) {
      ContractStatus.signed => (
          'החוזה נחתם על ידי שני הצדדים',
          AppColors.green,
          Icons.verified_rounded,
        ),
      ContractStatus.declined => (
          'החוזה נדחה',
          AppColors.coral,
          Icons.cancel_outlined,
        ),
      ContractStatus.cancelled => (
          'החוזה בוטל',
          AppColors.coral,
          Icons.cancel_outlined,
        ),
      _ => (
          c.isLandlordSigned || c.isTenantSigned
              ? 'ממתין לחתימת הצד השני'
              : 'ממתין לחתימות',
          AppColors.primary,
          Icons.hourglass_bottom_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _termsCard(RentalContract c) {
    String d(DateTime x) => '${x.day}/${x.month}/${x.year}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.propertyTitle.isNotEmpty ? c.propertyTitle : 'נכס להשכרה',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          const SizedBox(height: 14),
          _row('שכר דירה חודשי', '₪${c.monthlyRent}'),
          _row('פיקדון', c.deposit > 0 ? '₪${c.deposit}' : '—'),
          _row('תקופה', '${c.durationMonths} חודשים'),
          _row('כניסה', d(c.startDate)),
          _row('סיום', d(c.endDate)),
          if (c.additionalTerms.trim().isNotEmpty) ...[
            const Divider(height: 24, color: AppColors.borderLight),
            const Text('סעיפים נוספים',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(c.additionalTerms,
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: AppColors.navy)),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text(v,
                style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _securityNote() => Row(
        children: [
          Icon(IconsaxPlusLinear.shield_tick,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'חתימה דיגיטלית מאובטחת (Ed25519). המפתח הפרטי נשמר במכשיר בלבד; כל שינוי בתנאים מבטל חתימות שכבר נחתמו.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      );

  Future<void> _openSignSheet(
    BuildContext context,
    DatingProvider provider,
    RentalContract contract,
    bool asOwner,
  ) async {
    final controller = SignaturePadController();
    final signed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SignSheet(
        controller: controller,
        provider: provider,
        contract: contract,
        asOwner: asOwner,
      ),
    );
    controller.dispose();
    if (signed == true && context.mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('החתימה נשמרה בהצלחה ✍️')),
      );
    }
  }
}

class _SignSheet extends StatefulWidget {
  const _SignSheet({
    required this.controller,
    required this.provider,
    required this.contract,
    required this.asOwner,
  });

  final SignaturePadController controller;
  final DatingProvider provider;
  final RentalContract contract;
  final bool asOwner;

  @override
  State<_SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends State<_SignSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (widget.controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לחתום במסגרת לפני האישור')),
      );
      return;
    }
    setState(() => _busy = true);
    final png = await widget.controller.exportPng();
    await widget.provider.signRentalContract(
      widget.contract,
      asOwner: widget.asOwner,
      signatureImage: png,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('חתימה דיגיטלית',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
              const SizedBox(height: 4),
              const Text('חתמו עם האצבע במסגרת למטה',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              SignaturePad(controller: widget.controller),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.controller.clear,
                    icon: const Icon(IconsaxPlusLinear.refresh, size: 16),
                    label: const Text('נקה'),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(IconsaxPlusLinear.tick_circle, size: 18),
                  label: Text(_busy ? 'חותם…' : 'אשר חתימה'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One party's signature slot — shows the drawn signature + a tamper-evident
/// "verified" badge computed live against the contract's current terms.
class _SignatureSlot extends StatelessWidget {
  const _SignatureSlot({
    required this.title,
    required this.name,
    required this.signature,
    required this.contract,
  });

  final String title;
  final String name;
  final ContractSignature? signature;
  final RentalContract contract;

  @override
  Widget build(BuildContext context) {
    final sig = signature;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(name.isNotEmpty ? name : '—',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
                const SizedBox(height: 6),
                if (sig == null)
                  const Text('ממתין לחתימה',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600))
                else
                  _VerifiedLine(contract: contract, sig: sig),
              ],
            ),
          ),
          if (sig != null && sig.signatureImageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                sig.signatureImageUrl,
                width: 90,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            )
          else if (sig != null)
            const Icon(Icons.verified_rounded,
                color: AppColors.green, size: 26),
        ],
      ),
    );
  }
}

class _VerifiedLine extends StatelessWidget {
  const _VerifiedLine({required this.contract, required this.sig});
  final RentalContract contract;
  final ContractSignature sig;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DatingProvider>();
    return FutureBuilder<bool>(
      future: provider.verifyContractSignature(contract, sig),
      builder: (context, snap) {
        final ok = snap.data == true;
        final pending = !snap.hasData;
        final color = pending
            ? AppColors.textSecondary
            : (ok ? AppColors.green : AppColors.coral);
        final when = sig.signedAt;
        final dateStr = when == null
            ? ''
            : ' · ${when.day}/${when.month}/${when.year}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pending
                  ? Icons.hourglass_bottom_rounded
                  : (ok ? Icons.verified_rounded : Icons.error_outline_rounded),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                pending
                    ? 'מאמת…'
                    : (ok ? 'חתימה מאומתת$dateStr' : 'החתימה אינה תקפה'),
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Printable contract document preview ──────────────────────────────────────

class _ContractDocumentPage extends StatelessWidget {
  const _ContractDocumentPage({required this.contract});
  final RentalContract contract;

  String _d(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';

  @override
  Widget build(BuildContext context) {
    final c = contract;
    return Scaffold(
      backgroundColor: AppColors.slate100,
      appBar: AppBar(title: const Text('תצוגה מקדימה של החוזה')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Text('הסכם שכירות למגורים',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('נחתם דיגיטלית · ${_d(c.createdAt ?? DateTime.now())}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
                const Divider(height: 28),
                _para(
                    'הסכם זה נערך ונחתם בין **${c.landlordName}** ("המשכיר") לבין **${c.tenantName}** ("השוכר"), בנוגע להשכרת הנכס שכתובתו ${c.propertyTitle.isNotEmpty ? c.propertyTitle : "המפורט להלן"}.'),
                _clause('1. דמי השכירות',
                    'השוכר ישלם למשכיר דמי שכירות חודשיים בסך ${c.monthlyRent} ₪, אשר ישולמו מראש עד ה-10 בכל חודש.'),
                _clause('2. פיקדון',
                    c.deposit > 0
                        ? 'השוכר יפקיד בידי המשכיר פיקדון בסך ${c.deposit} ₪ להבטחת קיום התחייבויותיו.'
                        : 'לא נדרש פיקדון.'),
                _clause('3. תקופת השכירות',
                    'תקופת השכירות הינה ${c.durationMonths} חודשים, החל מיום ${_d(c.startDate)} ועד ${_d(c.endDate)}.'),
                if (c.additionalTerms.trim().isNotEmpty)
                  _clause('4. סעיפים ובקשות מיוחדות', c.additionalTerms.trim()),
                const Divider(height: 28),
                const Text('חתימות הצדדים',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: AppColors.navy)),
                const SizedBox(height: 12),
                _sigLine('המשכיר', c.landlordName, c.landlordSignature != null),
                const SizedBox(height: 10),
                _sigLine('השוכר', c.tenantName, c.tenantSignature != null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _para(String md) {
    // very light **bold** rendering
    final spans = <TextSpan>[];
    for (final part in md.split('**')) {
      spans.add(TextSpan(text: part));
    }
    // alternate bold
    final out = <TextSpan>[];
    final pieces = md.split('**');
    for (var i = 0; i < pieces.length; i++) {
      out.add(TextSpan(
        text: pieces[i],
        style: i.isOdd
            ? const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)
            : null,
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RichText(
        textAlign: TextAlign.right,
        text: TextSpan(
          style: const TextStyle(
              fontSize: 13.5, height: 1.7, color: AppColors.slate700),
          children: out.isNotEmpty ? out : spans,
        ),
      ),
    );
  }

  Widget _clause(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy)),
            const SizedBox(height: 3),
            Text(body,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, height: 1.6, color: AppColors.slate700)),
          ],
        ),
      );

  Widget _sigLine(String role, String name, bool signed) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$role: $name',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  height: 1,
                  color: AppColors.borderLight,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            signed ? Icons.verified_rounded : Icons.schedule_rounded,
            size: 18,
            color: signed ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(signed ? 'נחתם' : 'ממתין',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: signed
                      ? AppColors.green
                      : AppColors.textSecondary)),
        ],
      );
}
