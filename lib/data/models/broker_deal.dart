/// Stage of a broker deal in the commission pipeline.
enum BrokerDealStage { open, won, lost }

extension BrokerDealStageX on BrokerDealStage {
  String get hebrewLabel {
    switch (this) {
      case BrokerDealStage.open:
        return 'פתוחה';
      case BrokerDealStage.won:
        return 'נסגרה';
      case BrokerDealStage.lost:
        return 'אבודה';
    }
  }
}

/// A single deal a broker is working, used to project and tally commission (₪).
///
/// Brokers rarely have a clear picture of money in flight: how much commission
/// is *expected* if open deals close, and how much was actually *won* this
/// month. This model holds just enough to answer both — honestly, with plain
/// multiplication and no hidden fees. Local, broker-private (SharedPreferences).
class BrokerDeal {
  BrokerDeal({
    required this.id,
    required this.propertyTitle,
    required this.clientName,
    required this.dealAmount,
    this.commissionPct = 0,
    this.stage = BrokerDealStage.open,
    this.closedMonth = '',
  });

  /// Stable local id (SharedPreferences list key + edit/delete target).
  final String id;
  final String propertyTitle;
  final String clientName;

  /// Total transaction value in ₪ (rent contract value or sale price).
  final double dealAmount;

  /// Broker commission percentage on [dealAmount] (e.g. 2 means 2%).
  final double commissionPct;
  final BrokerDealStage stage;

  /// Calendar month this deal was won, as 'YYYY-MM' (empty while open/lost).
  /// Used to total "won this month" without timezone ambiguity.
  final String closedMonth;

  /// Commission in ₪ this deal represents: amount × pct%. Never negative.
  double get commissionAmount =>
      (dealAmount <= 0 || commissionPct <= 0) ? 0 : dealAmount * commissionPct / 100;

  bool get isOpen => stage == BrokerDealStage.open;
  bool get isWon => stage == BrokerDealStage.won;

  /// 'YYYY-MM' for [when] (used to set/compare [closedMonth]).
  static String monthKey(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}';

  BrokerDeal copyWith({
    String? propertyTitle,
    String? clientName,
    double? dealAmount,
    double? commissionPct,
    BrokerDealStage? stage,
    String? closedMonth,
  }) {
    return BrokerDeal(
      id: id,
      propertyTitle: propertyTitle ?? this.propertyTitle,
      clientName: clientName ?? this.clientName,
      dealAmount: dealAmount ?? this.dealAmount,
      commissionPct: commissionPct ?? this.commissionPct,
      stage: stage ?? this.stage,
      closedMonth: closedMonth ?? this.closedMonth,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyTitle': propertyTitle,
        'clientName': clientName,
        'dealAmount': dealAmount,
        'commissionPct': commissionPct,
        'stage': stage.name,
        'closedMonth': closedMonth,
      };

  factory BrokerDeal.fromJson(Map<String, dynamic> json) {
    final rawStage = (json['stage'] ?? 'open').toString();
    return BrokerDeal(
      id: (json['id'] ?? '').toString(),
      propertyTitle: (json['propertyTitle'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      dealAmount: (json['dealAmount'] as num?)?.toDouble() ?? 0,
      commissionPct: (json['commissionPct'] as num?)?.toDouble() ?? 0,
      stage: BrokerDealStage.values.firstWhere(
        (s) => s.name == rawStage,
        orElse: () => BrokerDealStage.open,
      ),
      closedMonth: (json['closedMonth'] ?? '').toString(),
    );
  }
}
