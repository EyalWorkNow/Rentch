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
  }) =>
      RenterDossier(
        docs: docs ?? this.docs,
        employerName: employerName ?? this.employerName,
        yearsAtJob: yearsAtJob ?? this.yearsAtJob,
        referenceName: referenceName ?? this.referenceName,
        referencePhone: referencePhone ?? this.referencePhone,
        referenceText: referenceText ?? this.referenceText,
        dataFirstMode: dataFirstMode ?? this.dataFirstMode,
      );

  RenterDossier withDoc(DossierDoc doc) => copyWith(
        docs: [
          for (final d in docs)
            if (d.type != doc.type) d,
          doc,
        ],
      );

  RenterDossier withoutDoc(DossierDocType type) => copyWith(
        docs: [
          for (final d in docs)
            if (d.type != type) d,
        ],
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
    );
  }
}
