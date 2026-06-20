import 'package:dating_app/core/services/signature_service.dart';

enum ContractStatus { draft, sent, signed, declined, cancelled }

ContractStatus contractStatusFromString(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'sent':
      return ContractStatus.sent;
    case 'signed':
      return ContractStatus.signed;
    case 'declined':
      return ContractStatus.declined;
    case 'cancelled':
      return ContractStatus.cancelled;
    default:
      return ContractStatus.draft;
  }
}

/// One party's cryptographic signature over the contract's content hash, plus
/// the optional handwritten signature image they drew.
class ContractSignature {
  const ContractSignature({
    required this.role, // 'landlord' | 'tenant'
    required this.signerUserId,
    required this.signerName,
    required this.publicKey,
    required this.signature,
    required this.signedHash,
    this.signatureImageUrl = '',
    this.signedAt,
  });

  final String role;
  final String signerUserId;
  final String signerName;
  final String publicKey; // base64 Ed25519 public key
  final String signature; // base64 Ed25519 signature over signedHash
  final String signedHash; // base64 SHA-256 of the canonical content at signing
  final String signatureImageUrl;
  final DateTime? signedAt;

  factory ContractSignature.fromJson(Map<String, dynamic> json) {
    return ContractSignature(
      role: json['role']?.toString() ?? '',
      signerUserId: json['signerUserId']?.toString() ?? '',
      signerName: json['signerName']?.toString() ?? '',
      publicKey: json['publicKey']?.toString() ?? '',
      signature: json['signature']?.toString() ?? '',
      signedHash: json['signedHash']?.toString() ?? '',
      signatureImageUrl: json['signatureImageUrl']?.toString() ?? '',
      signedAt: DateTime.tryParse(json['signedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'signerUserId': signerUserId,
        'signerName': signerName,
        'publicKey': publicKey,
        'signature': signature,
        'signedHash': signedHash,
        'signatureImageUrl': signatureImageUrl,
        'signedAt': (signedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };
}

/// A rental agreement between a landlord and a tenant, signed end-to-end with
/// device-held keys. The binding terms are hashed into [contentHash]; both
/// parties sign that hash so the agreement is tamper-evident.
class RentalContract {
  const RentalContract({
    required this.id,
    required this.matchId,
    required this.propertyId,
    required this.propertyTitle,
    required this.landlordUserId,
    required this.landlordName,
    required this.tenantUserId,
    required this.tenantName,
    required this.monthlyRent,
    required this.deposit,
    required this.durationMonths,
    required this.startDate,
    required this.additionalTerms,
    required this.status,
    this.landlordSignature,
    this.tenantSignature,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String matchId;
  final String propertyId;
  final String propertyTitle;
  final String landlordUserId;
  final String landlordName;
  final String tenantUserId;
  final String tenantName;
  final int monthlyRent;
  final int deposit;
  final int durationMonths;
  final DateTime startDate;
  final String additionalTerms;
  final ContractStatus status;
  final ContractSignature? landlordSignature;
  final ContractSignature? tenantSignature;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DateTime get endDate =>
      DateTime(startDate.year, startDate.month + durationMonths, startDate.day);

  bool get isLandlordSigned => landlordSignature != null;
  bool get isTenantSigned => tenantSignature != null;
  bool get isFullySigned => isLandlordSigned && isTenantSigned;

  ContractSignature? signatureForRole(String role) =>
      role == 'landlord' ? landlordSignature : tenantSignature;

  /// Deterministic, human-readable representation of the binding terms. Both
  /// devices hash exactly this string, so signatures are reproducible and any
  /// later change to a term changes the hash (invalidating prior signatures).
  String get canonicalContent {
    final b = StringBuffer()
      ..writeln('RENTLY RENTAL AGREEMENT')
      ..writeln('contractId=$id')
      ..writeln('property=$propertyId|$propertyTitle')
      ..writeln('landlord=$landlordUserId|$landlordName')
      ..writeln('tenant=$tenantUserId|$tenantName')
      ..writeln('monthlyRent=$monthlyRent')
      ..writeln('deposit=$deposit')
      ..writeln('durationMonths=$durationMonths')
      ..writeln('startDate=${startDate.toIso8601String().split('T').first}')
      ..writeln('endDate=${endDate.toIso8601String().split('T').first}')
      ..writeln('terms=${additionalTerms.trim()}');
    return b.toString();
  }

  String get contentHash => SignatureService.contentHash(canonicalContent);

  RentalContract copyWith({
    ContractStatus? status,
    ContractSignature? landlordSignature,
    ContractSignature? tenantSignature,
    DateTime? updatedAt,
  }) {
    return RentalContract(
      id: id,
      matchId: matchId,
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      landlordUserId: landlordUserId,
      landlordName: landlordName,
      tenantUserId: tenantUserId,
      tenantName: tenantName,
      monthlyRent: monthlyRent,
      deposit: deposit,
      durationMonths: durationMonths,
      startDate: startDate,
      additionalTerms: additionalTerms,
      status: status ?? this.status,
      landlordSignature: landlordSignature ?? this.landlordSignature,
      tenantSignature: tenantSignature ?? this.tenantSignature,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory RentalContract.fromJson(Map<String, dynamic> json) {
    ContractSignature? sig(Object? v) {
      if (v is Map) return ContractSignature.fromJson(Map<String, dynamic>.from(v));
      return null;
    }

    return RentalContract(
      id: json['id']?.toString() ?? '',
      matchId: json['matchId']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? '',
      propertyTitle: json['propertyTitle']?.toString() ?? '',
      landlordUserId: json['landlordUserId']?.toString() ?? '',
      landlordName: json['landlordName']?.toString() ?? '',
      tenantUserId: json['tenantUserId']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? '',
      monthlyRent: (json['monthlyRent'] as num?)?.toInt() ?? 0,
      deposit: (json['deposit'] as num?)?.toInt() ?? 0,
      durationMonths: (json['durationMonths'] as num?)?.toInt() ?? 12,
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? '') ??
          DateTime.now(),
      additionalTerms: json['additionalTerms']?.toString() ?? '',
      status: contractStatusFromString(json['status']?.toString()),
      landlordSignature: sig(json['landlordSignature']),
      tenantSignature: sig(json['tenantSignature']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'matchId': matchId,
        'propertyId': propertyId,
        'propertyTitle': propertyTitle,
        'landlordUserId': landlordUserId,
        'landlordName': landlordName,
        'tenantUserId': tenantUserId,
        'tenantName': tenantName,
        'monthlyRent': monthlyRent,
        'deposit': deposit,
        'durationMonths': durationMonths,
        'startDate': startDate.toIso8601String(),
        'additionalTerms': additionalTerms,
        'status': status.name,
        if (landlordSignature != null)
          'landlordSignature': landlordSignature!.toJson(),
        if (tenantSignature != null)
          'tenantSignature': tenantSignature!.toJson(),
        'contentHash': contentHash,
        'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
        'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };
}
