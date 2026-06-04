import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/data/models/users/user_model.dart';
import 'package:flutter/foundation.dart';

// User-discovery service.
//
// Scalability design:
//   - Cursor-based pagination: [pageSize] users per fetch, never loads all at once.
//   - LRU cache: profile pages are cached for [_cacheTtl] to reduce Appwrite reads.
//   - Circuit breaker: trips after 5 consecutive failures; fast-fails until
//     Appwrite recovers, instead of hammering a degraded backend.
//   - Falls back to static demo profiles when Appwrite is not configured or
//     the circuit is open.
//
// Appwrite collection: APPWRITE_USERS_TABLE_ID
// Required attributes: userId, name, age, photoUrl, bio, interests (JSON array)
//
// To enable live profiles:
//   flutter run --dart-define=APPWRITE_USERS_TABLE_ID=your_collection_id

class MatchService {
  MatchService({int pageSize = 20}) : _pageSize = pageSize;

  final int _pageSize;
  final _breaker = CircuitBreaker(name: 'appwrite-users');

  bool get _isConfigured =>
      AppConfig.canUseProperties && // reuses core Appwrite connectivity check
      AppConfig.appwriteUsersTableId.isNotEmpty;

  static const List<String> availableInterests = [
    'Art', 'Travel', 'Music', 'Tech', 'Nature', 'Cooking',
    'Fitness', 'Reading', 'Photography', 'Movies', 'Running',
    'Design', 'Coffee', 'Wellness', 'Gaming', 'Dogs',
  ];

  // ── Discovery ────────────────────────────────────────────────────────────────

  // Returns the next page of discoverable users.
  // [cursor] = last seen document ID for cursor-based pagination (null = first page).
  Future<UserPage> getDiscoverableUsersPage({String? cursor}) async {
    if (!_isConfigured || _breaker.isOpen) {
      return _mockPage(cursor: cursor);
    }

    final cacheKey = 'users:${cursor ?? "start"}';
    final cached = AppCache.instance.profiles.get(cacheKey);
    if (cached != null) {
      return UserPage.fromCached(cached);
    }

    try {
      final result = await _breaker.call(() => RetryPolicy.transient.execute(
            () => tables.listRows(
              databaseId: appwriteDatabaseId,
              tableId: AppConfig.appwriteUsersTableId,
              queries: [
                Query.limit(_pageSize),
                if (cursor != null) Query.cursorAfter(cursor),
              ],
            ),
          ));

      final users = result.rows
          .map((row) => _rowToUser(row.data))
          .whereType<User>()
          .toList();

      final nextCursor =
          users.length == _pageSize ? users.last.id : null;
      final page = UserPage(users: users, nextCursor: nextCursor);

      AppCache.instance.profiles.put(cacheKey, page.toCacheMap());
      return page;
    } on CircuitOpenException {
      return _mockPage(cursor: cursor);
    } on AppwriteException catch (e) {
      if (kDebugMode) debugPrint('MatchService.getPage error: $e');
      return _mockPage(cursor: cursor);
    } catch (e) {
      if (kDebugMode) debugPrint('MatchService.getPage unexpected: $e');
      return _mockPage(cursor: cursor);
    }
  }

  // Convenience: returns just the first page (for simple use sites).
  Future<List<User>> getDiscoverableUsers() async {
    final page = await getDiscoverableUsersPage();
    return page.users;
  }

  User createCurrentUser() {
    return User(
      id: 'current-user',
      name: 'Luna',
      age: 27,
      photoUrl: _demoPhotos.first,
      bio: 'UX designer, coffee optimist, and always up for a rooftop sunset or a road trip.',
      distance: 12,
      interests: const ['Design', 'Travel', 'Coffee', 'Music'],
    );
  }

  bool shouldCreateMatch(User user, {bool isSuperLike = false}) {
    return isSuperLike || user.likesYou;
  }

  // Simulates a write acknowledgement for local swipe actions.
  // Real swipe persistence goes through DatingProvider → PropertyRepository.
  Future<void> simulateWrite() async {
    await Future.delayed(const Duration(milliseconds: 80));
  }

  // ── Row mapping ──────────────────────────────────────────────────────────────

  User? _rowToUser(Map<String, dynamic> data) {
    try {
      final id = (data[r'$id'] ?? data['userId'] ?? '').toString();
      final name = (data['name'] ?? '').toString();
      final photoUrl = (data['photoUrl'] ?? _demoPhotos.first).toString();
      if (id.isEmpty || name.isEmpty) return null;

      final rawInterests = data['interests'];
      final interests = <String>[];
      if (rawInterests is List) {
        interests.addAll(rawInterests.whereType<String>());
      }

      return User(
        id: id,
        name: name,
        age: _asInt(data['age'], fallback: 25),
        photoUrl: photoUrl,
        bio: (data['bio'] ?? '').toString(),
        distance: _asDouble(data['distance'], fallback: 3.0),
        interests: interests,
        likesYou: data['likesYou'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  int _asInt(Object? v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  double _asDouble(Object? v, {double fallback = 0}) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  // ── Demo fallback ────────────────────────────────────────────────────────────

  UserPage _mockPage({String? cursor}) {
    // In demo mode, return a deterministic subset based on cursor position.
    final offset = cursor != null
        ? _demoUsers.indexWhere((u) => u.id == cursor) + 1
        : 0;
    final slice = offset >= _demoUsers.length
        ? <User>[]
        : _demoUsers.sublist(offset, (offset + _pageSize).clamp(0, _demoUsers.length));
    final nextCursor =
        slice.length == _pageSize && offset + _pageSize < _demoUsers.length
            ? slice.last.id
            : null;
    return UserPage(users: slice, nextCursor: nextCursor);
  }

  static const List<String> _demoPhotos = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1546961329-78bef0414d7c?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80',
  ];

  static final List<User> _demoUsers = [
    const User(
      id: 'emma',
      name: 'Emma',
      age: 26,
      photoUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
      bio: 'Brand designer, pilates regular, and always planning a weekend escape.',
      distance: 2.3,
      interests: ['Art', 'Travel', 'Coffee'],
      likesYou: true,
    ),
    const User(
      id: 'james',
      name: 'James',
      age: 29,
      photoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=900&q=80',
      bio: 'Product builder by day, trail runner by sunrise, pasta loyalist always.',
      distance: 4.1,
      interests: ['Tech', 'Running', 'Cooking'],
    ),
    const User(
      id: 'zoe',
      name: 'Zoe',
      age: 24,
      photoUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
      bio: 'Med student with a soft spot for bookstores, matcha, and long voice notes.',
      distance: 1.2,
      interests: ['Reading', 'Wellness', 'Music'],
      likesYou: true,
    ),
    const User(
      id: 'liam',
      name: 'Liam',
      age: 31,
      photoUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=900&q=80',
      bio: 'Architect, amateur chef, and the friend who always knows the next good spot.',
      distance: 5.7,
      interests: ['Design', 'Cooking', 'Travel'],
    ),
    const User(
      id: 'maya',
      name: 'Maya',
      age: 27,
      photoUrl: 'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=900&q=80',
      bio: 'Photographer chasing clean light, live gigs, and strong iced coffee.',
      distance: 3.4,
      interests: ['Photography', 'Music', 'Coffee'],
    ),
    const User(
      id: 'noah',
      name: 'Noah',
      age: 28,
      photoUrl: 'https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=900&q=80',
      bio: 'Startup operator, dog uncle, and big believer in last-minute road trips.',
      distance: 6.2,
      interests: ['Dogs', 'Tech', 'Nature'],
      likesYou: true,
    ),
    const User(
      id: 'ava',
      name: 'Ava',
      age: 25,
      photoUrl: 'https://images.unsplash.com/photo-1546961329-78bef0414d7c?auto=format&fit=crop&w=900&q=80',
      bio: 'Ceramics, film nights, and beach mornings. Looking for easy chemistry.',
      distance: 2.8,
      interests: ['Art', 'Movies', 'Nature'],
    ),
    const User(
      id: 'elijah',
      name: 'Elijah',
      age: 30,
      photoUrl: 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80',
      bio: 'Guitar player, designer, and loyal fan of quiet dinners over loud bars.',
      distance: 4.8,
      interests: ['Music', 'Design', 'Reading'],
    ),
  ];
}

/// A page of discoverable users with an optional cursor for the next page.
class UserPage {
  const UserPage({required this.users, this.nextCursor});

  final List<User> users;

  /// Cursor to pass to the next [MatchService.getDiscoverableUsersPage] call.
  /// Null means this is the last page.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  Map<String, dynamic> toCacheMap() => {
        'users': users.map(_userToMap).toList(),
        'nextCursor': nextCursor,
      };

  static UserPage fromCached(Map<String, dynamic> map) {
    final rawUsers = map['users'];
    final users = rawUsers is List
        ? rawUsers
            .whereType<Map<String, dynamic>>()
            .map(_mapToUser)
            .whereType<User>()
            .toList()
        : <User>[];
    return UserPage(
      users: users,
      nextCursor: map['nextCursor'] as String?,
    );
  }

  static Map<String, dynamic> _userToMap(User u) => {
        'id': u.id,
        'name': u.name,
        'age': u.age,
        'photoUrl': u.photoUrl,
        'bio': u.bio,
        'distance': u.distance,
        'interests': u.interests,
        'likesYou': u.likesYou,
      };

  static User? _mapToUser(Map<String, dynamic> m) {
    try {
      return User(
        id: m['id'] as String,
        name: m['name'] as String,
        age: m['age'] as int,
        photoUrl: m['photoUrl'] as String,
        bio: m['bio'] as String? ?? '',
        distance: (m['distance'] as num?)?.toDouble() ?? 0,
        interests: (m['interests'] as List?)?.cast<String>() ?? [],
        likesYou: m['likesYou'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
