/// A tenant's versioned, timestamped consent for how their DATA may be used —
/// the tenant-side analogue of the landlord's [PropertyLegal] (Phase-0 guardrail
/// of the targeting plan). Replaces the old single `SharedPreferences` boolean
/// with a real, auditable record: which rights, which version, when, from where.
///
/// The three load-bearing rights mirror the landlord's:
///  - [behavioralAnalyticsAllowed] — log & use behavioural signals for ranking.
///  - [personaDatasetAllowed]      — fold the persona into the exportable dataset.
///  - [aiTrainingAllowed]          — use the data to train cross-user models.
class TenantDataConsent {
  const TenantDataConsent({
    this.behavioralAnalyticsAllowed = false,
    this.personaDatasetAllowed = false,
    this.aiTrainingAllowed = false,
    this.consentVersion = '',
    this.consentTimestamp,
    this.consentSource = '',
  });

  final bool behavioralAnalyticsAllowed;
  final bool personaDatasetAllowed;
  final bool aiTrainingAllowed;
  final String consentVersion;
  final DateTime? consentTimestamp;
  final String consentSource;

  /// A record exists (the user made an explicit choice — even a decline is a
  /// stamped record with all rights false).
  bool get hasConsent => consentTimestamp != null && consentVersion.isNotEmpty;

  /// The empty/never-asked state.
  static const TenantDataConsent none = TenantDataConsent();

  TenantDataConsent copyWith({
    bool? behavioralAnalyticsAllowed,
    bool? personaDatasetAllowed,
    bool? aiTrainingAllowed,
    String? consentVersion,
    DateTime? consentTimestamp,
    String? consentSource,
  }) =>
      TenantDataConsent(
        behavioralAnalyticsAllowed:
            behavioralAnalyticsAllowed ?? this.behavioralAnalyticsAllowed,
        personaDatasetAllowed:
            personaDatasetAllowed ?? this.personaDatasetAllowed,
        aiTrainingAllowed: aiTrainingAllowed ?? this.aiTrainingAllowed,
        consentVersion: consentVersion ?? this.consentVersion,
        consentTimestamp: consentTimestamp ?? this.consentTimestamp,
        consentSource: consentSource ?? this.consentSource,
      );

  Map<String, dynamic> toJson() => {
        'behavioralAnalyticsAllowed': behavioralAnalyticsAllowed,
        'personaDatasetAllowed': personaDatasetAllowed,
        'aiTrainingAllowed': aiTrainingAllowed,
        'consentVersion': consentVersion,
        if (consentTimestamp != null)
          'consentTimestamp': consentTimestamp!.toIso8601String(),
        'consentSource': consentSource,
      };

  factory TenantDataConsent.fromJson(Map<String, dynamic> json) =>
      TenantDataConsent(
        behavioralAnalyticsAllowed:
            json['behavioralAnalyticsAllowed'] == true,
        personaDatasetAllowed: json['personaDatasetAllowed'] == true,
        aiTrainingAllowed: json['aiTrainingAllowed'] == true,
        consentVersion: json['consentVersion']?.toString() ?? '',
        consentTimestamp:
            DateTime.tryParse(json['consentTimestamp']?.toString() ?? ''),
        consentSource: json['consentSource']?.toString() ?? '',
      );
}
