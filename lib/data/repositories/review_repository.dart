import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

enum ReviewTargetType { property, tenant }

class ReviewRecord {
  const ReviewRecord({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reviewerUserId,
    required this.reviewerRole,
    required this.authorName,
    required this.rating,
    required this.text,
    required this.createdAt,
    this.matchId = '',
    this.propertyId = '',
    this.revieweeUserId = '',
  });

  final String id;
  final ReviewTargetType targetType;
  final String targetId;
  final String reviewerUserId;
  final String reviewerRole;
  final String authorName;
  final int rating;
  final String text;
  final DateTime createdAt;
  final String matchId;
  final String propertyId;
  final String revieweeUserId;

  String get targetKey => ReviewRepository.targetKey(targetType, targetId);

  AppReview toAppReview() {
    return AppReview(
      id: id,
      authorName: authorName,
      rating: rating,
      text: text,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetType': targetType.name,
      'targetId': targetId,
      'targetKey': targetKey,
      'reviewerUserId': reviewerUserId,
      'reviewerRole': reviewerRole,
      'authorName': authorName,
      'rating': rating,
      'text': text,
      'matchId': matchId,
      'propertyId': propertyId,
      'revieweeUserId': revieweeUserId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    final rawTargetType = json['targetType']?.toString();
    final targetType = ReviewTargetType.values.firstWhere(
      (type) => type.name == rawTargetType,
      orElse: () => ReviewTargetType.property,
    );
    final rating = int.tryParse(json['rating']?.toString() ?? '') ??
        (json['rating'] is num ? (json['rating'] as num).round() : 0);
    return ReviewRecord(
      id: json['id']?.toString() ?? '',
      targetType: targetType,
      targetId: json['targetId']?.toString() ?? '',
      reviewerUserId: json['reviewerUserId']?.toString() ?? '',
      reviewerRole: json['reviewerRole']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'משתמש Rentch',
      rating: rating.clamp(1, 5),
      text: json['text']?.toString() ?? '',
      matchId: json['matchId']?.toString() ?? '',
      propertyId: json['propertyId']?.toString() ?? '',
      revieweeUserId: json['revieweeUserId']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class ReviewRepository {
  ReviewRepository({String? tableId})
      : _tableId = tableId ?? AppConfig.appwriteReviewsTableId;

  final String _tableId;

  bool get isConfigured =>
      AppConfig.hasAwsCoreConfig && _tableId.trim().isNotEmpty;

  static String targetKey(ReviewTargetType targetType, String targetId) {
    return '${targetType.name}#${targetId.trim()}';
  }

  Future<bool> saveReview(ReviewRecord review) async {
    if (!isConfigured) return false;
    try {
      await aws.post('/$_tableId', _sanitizeReview(review).toJson());
      return true;
    } on AwsApiException catch (error) {
      if (kDebugMode) {
        debugPrint('ReviewRepository.saveReview rejected: $error');
      }
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ReviewRepository.saveReview error: $error');
      }
      return false;
    }
  }

  Future<List<AppReview>> fetchReviews({
    required ReviewTargetType targetType,
    required String targetId,
    int limit = 50,
  }) async {
    if (!isConfigured || targetId.trim().isEmpty) return const [];
    try {
      final result = await aws.get(
        '/$_tableId',
        query: {
          'targetKey': targetKey(targetType, targetId),
          'order': 'desc',
          'limit': limit.clamp(1, 100).toString(),
        },
      );
      final rawItems = result['items'] as List? ?? const [];
      return rawItems
          .whereType<Map>()
          .map((item) => ReviewRecord.fromJson(Map<String, dynamic>.from(item)))
          .where((review) => review.id.isNotEmpty && review.text.isNotEmpty)
          .map((review) => review.toAppReview())
          .toList(growable: false);
    } on AwsApiException catch (error) {
      if (kDebugMode) {
        debugPrint('ReviewRepository.fetchReviews rejected: $error');
      }
      return const [];
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ReviewRepository.fetchReviews error: $error');
      }
      return const [];
    }
  }

  ReviewRecord _sanitizeReview(ReviewRecord review) {
    return ReviewRecord(
      id: InputSanitizer.sanitizeText(review.id, maxLength: 96),
      targetType: review.targetType,
      targetId: InputSanitizer.sanitizeText(review.targetId, maxLength: 96),
      reviewerUserId:
          InputSanitizer.sanitizeText(review.reviewerUserId, maxLength: 96),
      reviewerRole:
          InputSanitizer.sanitizeText(review.reviewerRole, maxLength: 32),
      authorName: InputSanitizer.sanitizeName(review.authorName),
      rating: review.rating.clamp(1, 5),
      text: InputSanitizer.sanitizeText(review.text, maxLength: 1000),
      createdAt: review.createdAt,
      matchId: InputSanitizer.sanitizeText(review.matchId, maxLength: 96),
      propertyId: InputSanitizer.sanitizeText(review.propertyId, maxLength: 96),
      revieweeUserId:
          InputSanitizer.sanitizeText(review.revieweeUserId, maxLength: 96),
    );
  }
}
