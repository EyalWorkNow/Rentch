/// A tenant lead ranked by the server-side two-sided match model
/// (`POST /match/leads`). Lets a landlord see their interested tenants ordered
/// by genuine fit, with the reasons + any deal-breaker conflicts.
class RankedLead {
  const RankedLead({
    required this.tenantId,
    required this.tenantName,
    required this.propertyId,
    required this.propertyTitle,
    required this.score,
    required this.excluded,
    required this.reasons,
    required this.conflicts,
  });

  final String tenantId;
  final String tenantName;
  final String propertyId;
  final String propertyTitle;
  final int score;
  final bool excluded;
  final List<String> reasons;
  final List<String> conflicts;

  factory RankedLead.fromJson(Map<String, dynamic> json) {
    List<String> strs(Object? v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    return RankedLead(
      tenantId: json['tenantId']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? 'מתעניין',
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      excluded: json['excluded'] == true,
      reasons: strs(json['reasons']),
      conflicts: strs(json['conflicts']),
    );
  }
}
