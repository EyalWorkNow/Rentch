import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/security/security_config.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _appStateKey = 'dream_home_match_state_v2';
  static const String _payloadField = 'payload';
  static const String _schemaField = 'schema';
  static const String _updatedAtField = 'updatedAt';
  static const String _remoteStateIdKey = 'rentch_remote_state_document_id_v2';

  Future<Map<String, dynamic>?> loadAppState() async {
    final preferences = await SharedPreferences.getInstance();
    final rawLocalState = preferences.getString(_appStateKey);
    final localState = _decodeState(rawLocalState);

    final remoteState = await _loadRemoteState(preferences);
    if (remoteState != null) {
      final mergedState = _mergeLocalMedia(remoteState, localState);
      await preferences.setString(_appStateKey, jsonEncode(mergedState));
      return mergedState;
    }

    if (localState != null && rawLocalState != null) {
      unawaited(_saveRemoteState(preferences, localState));
    }

    return localState;
  }

  Future<void> saveAppState(
    Map<String, dynamic> state, {
    bool syncRemote = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedState = jsonEncode(state);
    await preferences.setString(_appStateKey, encodedState);
    if (!syncRemote) return;
    await _saveRemoteState(preferences, state);
  }

  Future<void> syncRemoteAppState(Map<String, dynamic> state) async {
    final preferences = await SharedPreferences.getInstance();
    await _saveRemoteState(preferences, state);
  }

  Future<void> clearAppState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_appStateKey);
  }

  Map<String, dynamic>? _decodeState(String? rawState) {
    if (rawState == null || rawState.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawState);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<Map<String, dynamic>?> _loadRemoteState(
    SharedPreferences preferences,
  ) async {
    if (!AppConfig.canUseRemoteState) return null;

    try {
      final row = await tables.getRow(
        databaseId: appwriteDatabaseId,
        tableId: appwriteAppStateCollectionId,
        rowId: await _remoteStateDocumentId(preferences),
      );
      final payload = row.data[_payloadField];
      if (payload is String) {
        return _decodeState(payload);
      }
    } on AppwriteException catch (error) {
      _logRemoteError('load', error);
      return null;
    } catch (error) {
      _logRemoteError('load', error);
      return null;
    }

    return null;
  }

  Future<void> _saveRemoteState(
    SharedPreferences preferences,
    Map<String, dynamic> state,
  ) async {
    if (!AppConfig.canUseRemoteState) return;
    final remoteState = _stateForRemoteSync(state);

    final data = {
      _payloadField: jsonEncode(remoteState),
      _schemaField: remoteState[_schemaField],
      _updatedAtField: DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await tables.upsertRow(
        databaseId: appwriteDatabaseId,
        tableId: appwriteAppStateCollectionId,
        rowId: await _remoteStateDocumentId(preferences),
        data: data,
      );
    } on AppwriteException catch (error) {
      _logRemoteError('save', error);
      return;
    } catch (error) {
      _logRemoteError('save', error);
      return;
    }
  }

  Map<String, dynamic> _stateForRemoteSync(Map<String, dynamic> state) {
    final decoded = jsonDecode(jsonEncode(state));
    if (decoded is! Map<String, dynamic>) return state;

    final tenantProfile = decoded['tenantProfile'];
    if (tenantProfile is Map<String, dynamic>) {
      tenantProfile['photoUrls'] = _remoteUrls(tenantProfile['photoUrls']);
    }

    final customProperties = decoded['customProperties'];
    if (customProperties is List) {
      for (final item in customProperties) {
        if (item is Map<String, dynamic>) {
          item['media'] = _remoteMediaItems(item['media']);
          item['imageUrls'] = _remoteUrls(item['imageUrls']);
          item['videoUrls'] = _remoteUrls(item['videoUrls']);
          item['virtualTour'] = _remoteVirtualTour(item['virtualTour']);
          item['model3d'] = _remoteModel3d(item['model3d']);
        }
      }
    }

    return decoded;
  }

  Map<String, dynamic> _mergeLocalMedia(
    Map<String, dynamic> remoteState,
    Map<String, dynamic>? localState,
  ) {
    if (localState == null) return remoteState;

    final merged = jsonDecode(jsonEncode(remoteState));
    if (merged is! Map<String, dynamic>) return remoteState;

    final localTenant = localState['tenantProfile'];
    final mergedTenant = merged['tenantProfile'];
    if (localTenant is Map && mergedTenant is Map<String, dynamic>) {
      mergedTenant['photoUrls'] = _mergeUrls(
        mergedTenant['photoUrls'],
        localTenant['photoUrls'],
      );
    }

    final localProperties = <String, Map>{};
    final localCustomProperties = localState['customProperties'];
    if (localCustomProperties is List) {
      for (final item in localCustomProperties) {
        if (item is Map && item['id'] is String) {
          localProperties[item['id'] as String] = item;
        }
      }
    }

    final mergedCustomProperties = merged['customProperties'];
    if (mergedCustomProperties is List) {
      for (final item in mergedCustomProperties) {
        if (item is Map<String, dynamic> && item['id'] is String) {
          final localItem = localProperties[item['id']];
          if (localItem == null) continue;
          item['media'] = _mergeMediaItems(item['media'], localItem['media']);
          item['imageUrls'] = _mergeUrls(
            item['imageUrls'],
            localItem['imageUrls'],
          );
          item['videoUrls'] = _mergeUrls(
            item['videoUrls'],
            localItem['videoUrls'],
          );
          item['virtualTour'] = _mergeVirtualTour(
            item['virtualTour'],
            localItem['virtualTour'],
          );
          item['model3d'] = _mergeModel3d(
            item['model3d'],
            localItem['model3d'],
          );
        }
      }
    }

    return merged;
  }

  List<String> _remoteUrls(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((url) {
      final uri = Uri.tryParse(url.trim());
      if (uri == null) return false;
      return uri.scheme == 'https' || uri.scheme == 'http';
    }).toList();
  }

  List<String> _localUrls(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((url) {
      final trimmed = url.trim();
      return trimmed.startsWith('/') || trimmed.startsWith('file://');
    }).toList();
  }

  List<String> _mergeUrls(Object? remoteValue, Object? localValue) {
    final remote = _remoteUrls(remoteValue);
    final local = _localUrls(localValue);
    return [
      ...remote,
      ...local.where((url) => !remote.contains(url)),
    ];
  }

  List<Map<String, dynamic>> _remoteMediaItems(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final url = item['url'];
      if (url is! String) return false;
      final uri = Uri.tryParse(url.trim());
      if (uri == null) return false;
      return uri.scheme == 'https' || uri.scheme == 'http';
    }).toList();
  }

  List<Map<String, dynamic>> _localMediaItems(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final url = item['url'];
      if (url is! String) return false;
      final trimmed = url.trim();
      return trimmed.startsWith('/') || trimmed.startsWith('file://');
    }).toList();
  }

  List<Map<String, dynamic>> _mergeMediaItems(
    Object? remoteValue,
    Object? localValue,
  ) {
    final remote = _remoteMediaItems(remoteValue);
    final local = _localMediaItems(localValue);
    final existingUrls =
        remote.map((item) => item['url']).whereType<String>().toSet();
    return [
      ...remote,
      ...local.where((item) {
        final url = item['url'];
        return url is String && !existingUrls.contains(url);
      }),
    ];
  }

  Map<String, dynamic>? _remoteVirtualTour(Object? value) {
    if (value is! Map) return null;
    final tour = Map<String, dynamic>.from(value);
    for (final field in [
      'sourceVideoUrl',
      'viewerUrl',
      'downloadUrl',
      'previewImageUrl',
    ]) {
      final raw = tour[field];
      if (raw is! String) {
        tour[field] = '';
        continue;
      }
      final uri = Uri.tryParse(raw.trim());
      final isRemote =
          uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      tour[field] = isRemote ? raw.trim() : '';
    }
    return tour;
  }

  Map<String, dynamic>? _mergeVirtualTour(
    Object? remoteValue,
    Object? localValue,
  ) {
    final remote = remoteValue is Map
        ? Map<String, dynamic>.from(remoteValue)
        : <String, dynamic>{};
    if (localValue is! Map) return remote.isEmpty ? null : remote;

    final local = Map<String, dynamic>.from(localValue);
    final localSource = local['sourceVideoUrl'];
    if ((remote['sourceVideoUrl'] as String? ?? '').isEmpty &&
        localSource is String &&
        (localSource.startsWith('/') || localSource.startsWith('file://'))) {
      remote['sourceVideoUrl'] = localSource;
    }

    return remote.isEmpty ? null : remote;
  }

  Map<String, dynamic>? _remoteModel3d(Object? value) {
    if (value is! Map) return null;
    final model = Map<String, dynamic>.from(value);
    for (final field in [
      'viewerUrl',
      'glbUrl',
      'objUrl',
      'textureFolder',
      'floorPlanUrl',
    ]) {
      final raw = model[field];
      if (raw is! String) {
        model[field] = '';
        continue;
      }
      final uri = Uri.tryParse(raw.trim());
      final isRemote =
          uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      model[field] = isRemote ? raw.trim() : '';
    }
    return model;
  }

  Map<String, dynamic>? _mergeModel3d(
    Object? remoteValue,
    Object? localValue,
  ) {
    final remote = remoteValue is Map
        ? Map<String, dynamic>.from(remoteValue)
        : <String, dynamic>{};
    if (localValue is! Map) return remote.isEmpty ? null : remote;

    final local = Map<String, dynamic>.from(localValue);
    for (final field in [
      'viewerUrl',
      'glbUrl',
      'objUrl',
      'textureFolder',
      'floorPlanUrl',
    ]) {
      final remoteValue = remote[field] as String? ?? '';
      final localValue = local[field];
      if (remoteValue.isNotEmpty || localValue is! String) continue;
      if (localValue.startsWith('/') || localValue.startsWith('file://')) {
        remote[field] = localValue;
      }
    }

    return remote.isEmpty ? null : remote;
  }

  void _logRemoteError(String action, Object error) {
    if (!kDebugMode) return;
    debugPrint('Appwrite state $action failed: $error');
  }

  // Default production behavior isolates each device. Launch mode is the one
  // explicit exception, used for the current controlled Appwrite MVP.
  Future<String> _remoteStateDocumentId(SharedPreferences preferences) async {
    if (AppConfig.launchMode && AppConfig.appwriteAppStateRowId.isNotEmpty) {
      return AppConfig.appwriteAppStateRowId;
    }

    final existing = preferences.getString(_remoteStateIdKey);
    if (existing != null && existing.isNotEmpty) {
      if (existing == 'global_state' ||
          existing == AppConfig.appwriteAppStateRowId) {
        final migrated = _generateUniqueDocId();
        await preferences.setString(_remoteStateIdKey, migrated);
        if (kDebugMode) {
          debugPrint(
            'LocalStorageService: migrated from shared state ID "$existing" to "$migrated"',
          );
        }
        return migrated;
      }
      return existing;
    }

    final generated = _generateUniqueDocId();
    await preferences.setString(_remoteStateIdKey, generated);
    return generated;
  }

  // Generates a document ID that is unique per device and sufficiently random
  // to prevent enumeration attacks.
  String _generateUniqueDocId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = Random.secure().nextInt(0x7FFFFFFF);
    return '${SecurityConfig.stateDocumentPrefix}${timestamp}_$entropy';
  }
}
