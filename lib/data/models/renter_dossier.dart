import 'package:dating_app/data/models/rental_models.dart' show TenantProfile;

/// The kinds of supporting documents a renter can attach to their dossier.
/// Stored by [name] key — adding a kind is backward compatible; unknown stored
/// keys are dropped on load.
enum DossierDocType {
  paySlip, // תלוש שכר
  employmentLetter, // אישור העסקה
  bankStatement, // אישור בנק / תדפיס
  creditReport, // דוח נתוני אשראי
  landlordReference, // מכתב המלצה ממשכיר קודם
  guarantorCommitment, // התחייבות ערב
}

/// One uploaded supporting document (already on S3 — [url] is the cloud copy).
class DossierDoc {
  const DossierDoc({
    required this.type,
    required this.url,
    required this.uploadedAt,
  });

  final DossierDocType type;
  final String url;
  final DateTime uploadedAt;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'url': url,
        'uploadedAt': uploadedAt.toUtc().toIso8601String(),
      };

  static DossierDoc? fromJson(Map<dynamic, dynamic> json) {
    final typeKey = json['type']?.toString();
    final url = json['url']?.toString() ?? '';
    if (typeKey == null || url.isEmpty) return null;
    DossierDocType? type;
    for (final t in DossierDocType.values) {
      if (t.name == typeKey) type = t;
    }
    if (type == null) return null; // unknown kind from a newer app version
    return DossierDoc(
      type: type,
      url: url,
      uploadedAt:
          DateTime.tryParse(json['uploadedAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

/// The SERVER's verdict from OCR-reading the uploaded pay slip against the
/// declared income (POST /dossier/verify-income). Stored on the dossier so the
/// "הכנסה מאומתת" badge survives restarts; only ever minted by the backend.
class IncomeVerification {
  const IncomeVerification({
    required this.verified,
    required this.verifiedAt,
    this.grossMonthly,
    this.netMonthly,
    this.employerName = '',
    this.period = '',
    this.confidence = 0,
  });

  final bool verified;
  final DateTime verifiedAt;
  final int? grossMonthly;
  final int? netMonthly;
  final String employerName;
  final String period; // YYYY-MM as printed on the slip
  final double confidence;

  Map<String, dynamic> toJson() => {
        'verified': verified,
        'verifiedAt': verifiedAt.toUtc().toIso8601String(),
        if (grossMonthly != null) 'grossMonthly': grossMonthly,
        if (netMonthly != null) 'netMonthly': netMonthly,
        if (employerName.isNotEmpty) 'employerName': employerName,
        if (period.isNotEmpty) 'period': period,
        'confidence': confidence,
      };

  static IncomeVerification? fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return null;
    final at = DateTime.tryParse(json['verifiedAt']?.toString() ?? '');
    if (at == null) return null;
    return IncomeVerification(
      verified: json['verified'] == true,
      verifiedAt: at,
      grossMonthly: (json['grossMonthly'] as num?)?.round(),
      netMonthly: (json['netMonthly'] as num?)?.round(),
      employerName: json['employerName']?.toString() ?? '',
      period: json['period']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// "תיק שוכר" — the renter's trust dossier. Everything a landlord needs to say
/// "this person is safe" WITHOUT the crude filters the market uses today
/// (name, accent, age, family status). Documents live on S3; this object holds
/// their URLs plus the self-declared parts (employer, previous-landlord
/// reference) and the data-first presentation preference.
///
/// HONESTY RULE: nothing here is labeled "מאומת" unless a document backs it.
/// The UI distinguishes "הצהרה" (typed) from "מגובה במסמך" (file attached).
class RenterDossier {
  const RenterDossier({
    this.docs = const [],
    this.employerName = '',
    this.yearsAtJob,
    this.referenceName = '',
    this.referencePhone = '',
    this.referenceText = '',
    this.dataFirstMode = false,
    this.incomeVerification,
  });

  final List<DossierDoc> docs;

  /// Current employer, self-declared (backed by an employmentLetter doc when
  /// one is attached).
  final String employerName;
  final double? yearsAtJob;

  /// Previous-landlord reference — the single strongest trust signal a renter
  /// can carry. Free text + contact so the next landlord can verify.
  final String referenceName;
  final String referencePhone;
  final String referenceText;

  /// "נתונים לפני שם": when true, the renter asks to be presented to landlords
  /// as verified attributes FIRST (income band, occupation, docs) with the
  /// name/photo revealed only after the landlord engages — countering
  /// name/accent-based filtering.
  final bool dataFirstMode;

  /// Server-issued pay-slip OCR verdict, null until a verification ran.
  final IncomeVerification? incomeVerification;

  /// The income badge is honest only while the verified slip is still the
  /// attached one — replacing/removing the pay slip voids the verdict.
  bool get incomeVerified =>
      incomeVerification?.verified == true && hasDoc(DossierDocType.paySlip);

  bool hasDoc(DossierDocType type) => docs.any((d) => d.type == type);

  DossierDoc? docOf(DossierDocType type) {
    for (final d in docs) {
      if (d.type == type) return d;
    }
    return null;
  }

  /// Any document that substantiates income/employment.
  bool get hasIncomeProofDoc =>
      hasDoc(DossierDocType.paySlip) ||
      hasDoc(DossierDocType.employmentLetter) ||
      hasDoc(DossierDocType.bankStatement);

  bool get hasReference =>
      referenceText.trim().isNotEmpty || hasDoc(DossierDocType.landlordReference);

  bool get isEmpty =>
      docs.isEmpty &&
      employerName.trim().isEmpty &&
      referenceName.trim().isEmpty &&
      referenceText.trim().isEmpty &&
      !dataFirstMode;

  /// Wire keys of the attached doc types — the lead payload carries THIS (not
  /// the URLs: a landlord browsing leads sees what's backed, and requests the
  /// actual files in chat).
  List<String> get docTypeKeys =>
      docs.map((d) => d.type.name).toSet().toList(growable: false);

  /// 0..1 dossier completeness, folding in the profile fields the dossier
  /// presents (occupation/income/guarantor live on [TenantProfile]).
  double completeness(TenantProfile? profile) {
    var score = 0.0;
    if ((profile?.occupation ?? '').isNotEmpty) score += 0.15;
    if ((profile?.monthlyIncome ?? 0) > 0) score += 0.15;
    if (employerName.trim().isNotEmpty) score += 0.10;
    if (hasIncomeProofDoc) score += 0.25;
    if (hasReference) score += 0.20;
    if (profile?.hasGuarantor == true ||
        hasDoc(DossierDocType.guarantorCommitment)) {
      score += 0.15;
    }
    return score.clamp(0.0, 1.0);
  }

  RenterDossier copyWith({
    List<DossierDoc>? docs,
    String? employerName,
    double? yearsAtJob,
    String? referenceName,
    String? referencePhone,
    String? referenceText,
    bool? dataFirstMode,
    IncomeVerification? incomeVerification,
    bool clearIncomeVerification = false,
  }) =>
      RenterDossier(
        docs: docs ?? this.docs,
        employerName: employerName ?? this.employerName,
        yearsAtJob: yearsAtJob ?? this.yearsAtJob,
        referenceName: referenceName ?? this.referenceName,
        referencePhone: referencePhone ?? this.referencePhone,
        referenceText: referenceText ?? this.referenceText,
        dataFirstMode: dataFirstMode ?? this.dataFirstMode,
        incomeVerification: clearIncomeVerification
            ? null
            : (incomeVerification ?? this.incomeVerification),
      );

  // Replacing or removing the pay slip VOIDS a prior income verification —
  // the verdict belongs to the exact slip it was issued against.
  RenterDossier withDoc(DossierDoc doc) => copyWith(
        docs: [
          for (final d in docs)
            if (d.type != doc.type) d,
          doc,
        ],
        clearIncomeVerification: doc.type == DossierDocType.paySlip,
      );

  RenterDossier withoutDoc(DossierDocType type) => copyWith(
        docs: [
          for (final d in docs)
            if (d.type != type) d,
        ],
        clearIncomeVerification: type == DossierDocType.paySlip,
      );

  Map<String, dynamic> toJson() => {
        'docs': [for (final d in docs) d.toJson()],
        if (employerName.trim().isNotEmpty) 'employerName': employerName.trim(),
        if (yearsAtJob != null) 'yearsAtJob': yearsAtJob,
        if (referenceName.trim().isNotEmpty)
          'referenceName': referenceName.trim(),
        if (referencePhone.trim().isNotEmpty)
          'referencePhone': referencePhone.trim(),
        if (referenceText.trim().isNotEmpty)
          'referenceText': referenceText.trim(),
        'dataFirstMode': dataFirstMode,
        if (incomeVerification != null)
          'incomeVerification': incomeVerification!.toJson(),
      };

  static RenterDossier fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return const RenterDossier();
    final rawDocs = json['docs'];
    final docs = <DossierDoc>[];
    if (rawDocs is List) {
      for (final d in rawDocs) {
        if (d is! Map) continue;
        final doc = DossierDoc.fromJson(d);
        if (doc != null) docs.add(doc);
      }
    }
    return RenterDossier(
      docs: docs,
      employerName: json['employerName']?.toString() ?? '',
      yearsAtJob: (json['yearsAtJob'] as num?)?.toDouble(),
      referenceName: json['referenceName']?.toString() ?? '',
      referencePhone: json['referencePhone']?.toString() ?? '',
      referenceText: json['referenceText']?.toString() ?? '',
      dataFirstMode: json['dataFirstMode'] == true,
      incomeVerification: json['incomeVerification'] is Map
          ? IncomeVerification.fromJson(
              json['incomeVerification'] as Map<dynamic, dynamic>)
          : null,
    );
  }
}
