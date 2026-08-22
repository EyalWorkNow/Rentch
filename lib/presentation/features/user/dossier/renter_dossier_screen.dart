import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/storage_service.dart';
import 'package:dating_app/data/models/renter_dossier.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// "תיק שוכר" — the renter builds their credibility card here: employment +
/// income (lives on the TenantProfile), supporting documents (uploaded to S3),
/// a previous-landlord reference, and the "נתונים לפני שם" (data-first)
/// presentation preference. The dossier summary travels with every like the
/// renter sends, so a landlord browsing leads sees what's substantiated.
class RenterDossierScreen extends StatefulWidget {
  const RenterDossierScreen({super.key});

  @override
  State<RenterDossierScreen> createState() => _RenterDossierScreenState();
}

class _RenterDossierScreenState extends State<RenterDossierScreen> {
  final _picker = ImagePicker();
  final _storage = StorageService();

  late final TextEditingController _employer;
  late final TextEditingController _income;
  late final TextEditingController _refName;
  late final TextEditingController _refPhone;
  late final TextEditingController _refText;

  DossierDocType? _uploading; // the tile currently mid-upload (spinner)
  bool _verifyingIncome = false;

  DatingProvider get _provider => context.read<DatingProvider>();
  RenterDossier get _dossier => _provider.renterDossier;

  @override
  void initState() {
    super.initState();
    final d = _provider.renterDossier;
    final tp = _provider.tenantProfile;
    _employer = TextEditingController(text: d.employerName);
    _income = TextEditingController(
        text: (tp?.monthlyIncome ?? 0) > 0 ? '${tp!.monthlyIncome}' : '');
    _refName = TextEditingController(text: d.referenceName);
    _refPhone = TextEditingController(text: d.referencePhone);
    _refText = TextEditingController(text: d.referenceText);
  }

  @override
  void dispose() {
    _employer.dispose();
    _income.dispose();
    _refName.dispose();
    _refPhone.dispose();
    _refText.dispose();
    super.dispose();
  }

  // ── persistence ────────────────────────────────────────────────────────────

  Future<void> _saveTextFields() async {
    await _provider.updateRenterDossier(_dossier.copyWith(
      employerName: _employer.text,
      referenceName: _refName.text,
      referencePhone: _refPhone.text,
      referenceText: _refText.text,
    ));
    final income = int.tryParse(_income.text.trim());
    final tp = _provider.tenantProfile;
    if (tp != null && income != null && income > 0 && income != tp.monthlyIncome) {
      await _provider.updateTenantProfile(tp.copyWith(monthlyIncome: income));
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dossierSaved)),
    );
  }

  Future<void> _attachDoc(DossierDocType type) async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 2048, imageQuality: 88);
      if (file == null) return;
      setState(() => _uploading = type);
      final local = await _storage.saveImageLocally(file);
      final url = await _storage.uploadToCloud(local);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() => _uploading = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dossierUploadFailed)),
        );
        return;
      }
      await _provider.updateRenterDossier(_dossier.withDoc(DossierDoc(
        type: type,
        url: url,
        uploadedAt: DateTime.now(),
      )));
      if (!mounted) return;
      setState(() => _uploading = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dossierUploadFailed)),
      );
    }
  }

  Future<void> _verifyIncome() async {
    final l10n = AppLocalizations.of(context);
    // Fold any just-typed income into the profile first, so the server checks
    // against what the user actually sees on screen.
    final typed = int.tryParse(_income.text.trim());
    final tp = _provider.tenantProfile;
    if (tp != null && typed != null && typed > 0 && typed != tp.monthlyIncome) {
      await _provider.updateTenantProfile(tp.copyWith(monthlyIncome: typed));
    }
    setState(() => _verifyingIncome = true);
    final v = await _provider.verifyDossierIncome();
    if (!mounted) return;
    setState(() => _verifyingIncome = false);
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dossierVerifyFailed)),
      );
    }
    // Verified / mismatch states render from the stored verdict (see build).
  }

  Future<void> _viewDoc(DossierDoc doc) async {
    try {
      await launchUrl(Uri.parse(doc.url), mode: LaunchMode.externalApplication);
    } catch (_) {/* launch failed — nothing to do */}
  }

  Future<void> _removeDoc(DossierDocType type) async {
    await _provider.updateRenterDossier(_dossier.withoutDoc(type));
    if (mounted) setState(() {});
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  String _docLabel(AppLocalizations l10n, DossierDocType t) => switch (t) {
        DossierDocType.paySlip => l10n.dossierDocPaySlip,
        DossierDocType.employmentLetter => l10n.dossierDocEmployment,
        DossierDocType.bankStatement => l10n.dossierDocBank,
        DossierDocType.creditReport => l10n.dossierDocCredit,
        DossierDocType.landlordReference => l10n.dossierDocLandlordRef,
        DossierDocType.guarantorCommitment => l10n.dossierDocGuarantor,
      };

  IconData _docIcon(DossierDocType t) => switch (t) {
        DossierDocType.paySlip => IconsaxPlusLinear.receipt_1,
        DossierDocType.employmentLetter => IconsaxPlusLinear.briefcase,
        DossierDocType.bankStatement => IconsaxPlusLinear.bank,
        DossierDocType.creditReport => IconsaxPlusLinear.chart_1,
        DossierDocType.landlordReference => IconsaxPlusLinear.like_1,
        DossierDocType.guarantorCommitment => IconsaxPlusLinear.shield_tick,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // watch so the completeness meter and doc tiles update after each save.
    final provider = context.watch<DatingProvider>();
    final dossier = provider.renterDossier;
    final completeness =
        (dossier.completeness(provider.tenantProfile) * 100).round();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.dossierTitle,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.navy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(l10n.dossierSubtitle,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),

            // ── completeness meter ─────────────────────────────────────────
            _card(children: [
              Row(children: [
                Expanded(
                  child: Text(l10n.dossierCompleteness(completeness),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy)),
                ),
                Icon(
                    completeness >= 70
                        ? IconsaxPlusLinear.shield_tick
                        : IconsaxPlusLinear.shield,
                    size: 20,
                    color: AppColors.primary),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: completeness / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.primaryLight,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // ── employment & income ────────────────────────────────────────
            _sectionTitle(l10n.dossierSectionEmployment,
                IconsaxPlusLinear.briefcase),
            _card(children: [
              _field(_employer, l10n.dossierEmployerHint),
              const SizedBox(height: 10),
              _field(_income, l10n.dossierIncomeHint,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.dossierGuarantorToggle,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                value: provider.tenantProfile?.hasGuarantor ?? false,
                activeThumbColor: AppColors.primary,
                onChanged: (v) {
                  final tp = provider.tenantProfile;
                  if (tp != null) {
                    provider.updateTenantProfile(tp.copyWith(hasGuarantor: v));
                  }
                },
              ),
            ]),
            const SizedBox(height: 14),

            // ── documents ──────────────────────────────────────────────────
            _sectionTitle(l10n.dossierSectionDocs, IconsaxPlusLinear.document_text),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.dossierDocsHint,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            _card(children: [
              for (final (i, t) in DossierDocType.values.indexed) ...[
                if (i > 0)
                  const Divider(
                      height: 1, thickness: 1, color: AppColors.borderLight),
                _docTile(l10n, dossier, t),
              ],
            ]),
            const SizedBox(height: 10),

            // ── real income verification (server OCR on the pay slip) ──────
            _incomeVerificationCard(l10n, provider, dossier),
            const SizedBox(height: 14),

            // ── previous landlord reference ────────────────────────────────
            _sectionTitle(
                l10n.dossierSectionReference, IconsaxPlusLinear.like_1),
            _card(children: [
              _field(_refName, l10n.dossierRefName),
              const SizedBox(height: 10),
              _field(_refPhone, l10n.dossierRefPhone,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              _field(_refText, l10n.dossierRefText, maxLines: 3),
            ]),
            const SizedBox(height: 14),

            // ── data-first mode ────────────────────────────────────────────
            _card(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.dossierDataFirstTitle,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.dossierDataFirstBody,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary)),
                ),
                value: dossier.dataFirstMode,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => provider
                    .updateRenterDossier(dossier.copyWith(dataFirstMode: v)),
              ),
            ]),
            const SizedBox(height: 20),

            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saveTextFields,
              child: Text(l10n.dossierSaveButton,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  /// The "אימות הכנסה" block under the documents: real verification — the
  /// backend OCR-reads the attached pay slip and compares it to the declared
  /// income; only ITS verdict lights the badge. Renders one of four states:
  /// prerequisites missing / ready to verify / verified / mismatch.
  Widget _incomeVerificationCard(
      AppLocalizations l10n, DatingProvider provider, RenterDossier dossier) {
    final hasSlip = dossier.hasDoc(DossierDocType.paySlip);
    final declared = provider.tenantProfile?.monthlyIncome ?? 0;
    final typed = int.tryParse(_income.text.trim()) ?? 0;
    final hasIncome = declared > 0 || typed > 0;
    final v = dossier.incomeVerification;

    if (dossier.incomeVerified && v != null) {
      return _card(children: [
        Row(children: [
          Icon(IconsaxPlusLinear.verify, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.dossierIncomeVerifiedBadge,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryDark)),
                  if (v.grossMonthly != null)
                    Text(
                        '₪${v.grossMonthly}'
                        '${v.period.isEmpty ? '' : ' · ${v.period}'}'
                        '${v.employerName.isEmpty ? '' : ' · ${v.employerName}'}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary)),
                ]),
          ),
        ]),
      ]);
    }

    final mismatch = v != null && !v.verified && hasSlip;
    return _card(children: [
      if (mismatch)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            v.grossMonthly != null
                ? '${l10n.dossierIncomeMismatch} (₪${v.grossMonthly})'
                : l10n.dossierIncomeMismatch,
            style: const TextStyle(
                fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
          ),
        ),
      if (!hasSlip || !hasIncome)
        Text(l10n.dossierVerifyNeeds,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary))
      else
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _verifyingIncome ? null : _verifyIncome,
          icon: _verifyingIncome
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(IconsaxPlusLinear.scan, size: 17),
          label: Text(l10n.dossierVerifyIncomeButton,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  Widget _docTile(AppLocalizations l10n, RenterDossier dossier, DossierDocType t) {
    final doc = dossier.docOf(t);
    final busy = _uploading == t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_docIcon(t), size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_docLabel(l10n, t),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            if (doc != null)
              Text(
                  '${l10n.dossierDocAttached} · '
                  '${doc.uploadedAt.day}.${doc.uploadedAt.month}.${doc.uploadedAt.year}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark)),
          ]),
        ),
        if (busy)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2))
        else if (doc != null) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(IconsaxPlusLinear.eye,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => _viewDoc(doc),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => _removeDoc(t),
          ),
        ] else
          TextButton.icon(
            onPressed: () => _attachDoc(t),
            icon: Icon(IconsaxPlusLinear.document_upload,
                size: 16, color: AppColors.primary),
            label: Text(l10n.dossierDocAdd,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
      ]),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
        ]),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _field(TextEditingController c, String hint,
          {TextInputType? keyboardType, int maxLines = 1}) =>
      TextField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
      );
}
