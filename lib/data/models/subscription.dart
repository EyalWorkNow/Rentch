/// Landlord subscription state as returned by `GET /billing/subscription`.
///
/// Product (locked): free up to 3 ACTIVE properties; the 4th needs a paid plan.
/// Monthly ₪35 (3500 agorot), annual ₪350 (35000 agorot, VAT-incl.).
///
/// The client treats [entitled] as the single source of truth for "is paid",
/// and [canAddProperty] as the authoritative publish gate — both computed by
/// the backend from the live active-property count. A locally cached snapshot
/// keeps the gate working offline.
class Subscription {
  const Subscription({
    required this.status,
    required this.plan,
    required this.priceAgorot,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.card,
    required this.activeProperties,
    required this.freeLimit,
    required this.entitled,
    required bool canAddProperty,
    required this.graceUntil,
    required this.grandfatherUntil,
    this.boostQuota = 0,
    this.boostRemaining,
    this.boostUnlimited = false,
  }) : _canAddProperty = canAddProperty;

  /// Raw backend status ('active' | 'canceled' | 'none' | 'past_due' | ...).
  final String status;

  /// 'monthly' | 'annual' | null when there is no plan yet.
  final String? plan;

  /// Current plan price in agorot (3500 monthly / 35000 annual); 0 when none.
  final int priceAgorot;

  /// End of the current billing period (renewal / access-until date).
  final DateTime? currentPeriodEnd;

  /// True once the user asked to cancel — stays active until [currentPeriodEnd].
  final bool cancelAtPeriodEnd;

  /// The card on file, or null when there is none.
  final SubscriptionCard? card;

  /// Live count of the landlord's ACTIVE listings (server-computed).
  final int activeProperties;

  /// Free ACTIVE-property allowance before a subscription is required.
  final int freeLimit;

  /// True when the landlord is currently entitled (paid, or within grace).
  final bool entitled;

  /// Optional grace-period end (fail-open window after a failed renewal).
  final DateTime? graceUntil;

  /// Optional grandfather end (legacy free window for existing landlords).
  final DateTime? grandfatherUntil;

  final bool _canAddProperty;

  /// Boost quota for this billing month. [boostRemaining] is null when the plan
  /// is unlimited (VIP). [boostUnlimited] flags that case.
  final int boostQuota;
  final int? boostRemaining;
  final bool boostUnlimited;

  /// Can the landlord boost a listing right now? Entitled + quota left.
  bool get canBoost =>
      entitled && (boostUnlimited || (boostRemaining ?? 0) > 0);

  /// Authoritative publish gate: can the landlord add ANOTHER active property?
  /// Falls back to the free-limit arithmetic if the backend omits the flag.
  bool get canAddProperty =>
      _canAddProperty || entitled || activeProperties < freeLimit;

  /// Stricter gate for the publish BOUNDARY, where the caller already knows the
  /// local active count is at/over the free limit. Trusts only SERVER-confirmed
  /// signals (the backend flag or an active subscription) — NOT the client-side
  /// `activeProperties < freeLimit` arithmetic, whose cached `activeProperties`
  /// can be stale-low after a failed refresh and would let a free user publish
  /// past the limit. Fails closed on an unknown/stale state.
  bool get canPublishConfirmed => _canAddProperty || entitled;

  bool get isCanceling => cancelAtPeriodEnd && entitled;
  bool get hasPlan => (plan ?? '').isNotEmpty;

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final rawCard = json['card'];
    return Subscription(
      status: (json['status'] ?? 'none').toString(),
      plan: (json['plan'] as String?)?.trim().isNotEmpty == true
          ? (json['plan'] as String).trim()
          : null,
      priceAgorot: (json['priceAgorot'] as num?)?.toInt() ?? 0,
      currentPeriodEnd: _parseTs(json['currentPeriodEnd']),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
      card: rawCard is Map
          ? SubscriptionCard.fromJson(Map<String, dynamic>.from(rawCard))
          : null,
      activeProperties: (json['activeProperties'] as num?)?.toInt() ?? 0,
      freeLimit: (json['freeLimit'] as num?)?.toInt() ?? 3,
      entitled: json['entitled'] as bool? ?? false,
      canAddProperty: json['canAddProperty'] as bool? ??
          (json['entitled'] as bool? ?? false),
      graceUntil: _parseTs(json['graceUntil']),
      grandfatherUntil: _parseTs(json['grandfatherUntil']),
      boostQuota: (() {
        final b = json['boost'];
        return b is Map ? (b['quota'] as num?)?.toInt() ?? 0 : 0;
      })(),
      boostRemaining: (() {
        final b = json['boost'];
        return b is Map ? (b['remaining'] as num?)?.toInt() : null;
      })(),
      boostUnlimited: (() {
        final b = json['boost'];
        return b is Map ? (b['unlimited'] as bool? ?? false) : false;
      })(),
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'plan': plan,
        'priceAgorot': priceAgorot,
        'currentPeriodEnd': currentPeriodEnd?.millisecondsSinceEpoch,
        'cancelAtPeriodEnd': cancelAtPeriodEnd,
        'card': card?.toJson(),
        'activeProperties': activeProperties,
        'freeLimit': freeLimit,
        'entitled': entitled,
        'canAddProperty': _canAddProperty,
        'graceUntil': graceUntil?.millisecondsSinceEpoch,
        'grandfatherUntil': grandfatherUntil?.millisecondsSinceEpoch,
        'boost': {
          'quota': boostQuota,
          'remaining': boostRemaining,
          'unlimited': boostUnlimited,
        },
      };

  /// Accepts ms-epoch numbers, numeric strings, or ISO strings; null otherwise.
  static DateTime? _parseTs(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal();
    }
    final s = raw.toString();
    if (s.isEmpty) return null;
    final ms = int.tryParse(s);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateTime.tryParse(s)?.toLocal();
  }
}

/// The card on file (brand + last 4 digits) shown on the subscription screen.
class SubscriptionCard {
  const SubscriptionCard({required this.brand, required this.last4});

  final String brand;
  final String last4;

  factory SubscriptionCard.fromJson(Map<String, dynamic> json) => SubscriptionCard(
        brand: (json['brand'] ?? '').toString(),
        last4: (json['last4'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'brand': brand, 'last4': last4};
}

/// A single tax invoice as returned by `GET /billing/invoices` (`items[]`).
class Invoice {
  const Invoice({
    required this.id,
    required this.plan,
    required this.url,
    required this.sumAgorot,
    required this.issuedAt,
    required this.periodStart,
    required this.periodEnd,
  });

  final String id;
  final String? plan;
  final String url;
  final int sumAgorot;
  final DateTime? issuedAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: (json['id'] ?? '').toString(),
        plan: (json['plan'] as String?)?.trim().isNotEmpty == true
            ? (json['plan'] as String).trim()
            : null,
        url: (json['url'] ?? '').toString(),
        sumAgorot: (json['sumAgorot'] as num?)?.toInt() ?? 0,
        issuedAt: Subscription._parseTs(json['issuedAt']),
        periodStart: Subscription._parseTs(json['periodStart']),
        periodEnd: Subscription._parseTs(json['periodEnd']),
      );
}
