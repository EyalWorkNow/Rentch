import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _appStateKey = 'dream_home_match_state_v1';
  static const String _payloadField = 'payload';
  static const String _schemaField = 'schema';
  static const String _updatedAtField = 'updatedAt';

  Future<Map<String, dynamic>?> loadAppState() async {
    final preferences = await SharedPreferences.getInstance();
    final rawLocalState = preferences.getString(_appStateKey);
    final localState = _decodeState(rawLocalState);

    final remoteState = await _loadRemoteState();
    if (remoteState != null) {
      await preferences.setString(_appStateKey, jsonEncode(remoteState));
      return remoteState;
    }

    if (localState != null && rawLocalState != null) {
      await _saveRemoteState(localState, rawLocalState);
    }

    return localState;
  }

  Future<void> saveAppState(Map<String, dynamic> state) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedState = jsonEncode(state);
    await preferences.setString(_appStateKey, encodedState);
    await _saveRemoteState(state, encodedState);
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

  Future<Map<String, dynamic>?> _loadRemoteState() async {
    try {
      final row = await tables.getRow(
        databaseId: appwriteDatabaseId,
        tableId: appwriteAppStateCollectionId,
        rowId: appwriteAppStateDocumentId,
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
    Map<String, dynamic> state,
    String encodedState,
  ) async {
    final data = {
      _payloadField: encodedState,
      _schemaField: state[_schemaField],
      _updatedAtField: DateTime.now().toUtc().toIso8601String(),
    };
    final permissions = [
      Permission.read(Role.any()),
      Permission.update(Role.any()),
      Permission.delete(Role.any()),
    ];

    try {
      await tables.upsertRow(
        databaseId: appwriteDatabaseId,
        tableId: appwriteAppStateCollectionId,
        rowId: appwriteAppStateDocumentId,
        data: data,
        permissions: permissions,
      );
    } on AppwriteException catch (error) {
      _logRemoteError('save', error);
      return;
    } catch (error) {
      _logRemoteError('save', error);
      return;
    }
  }

  void _logRemoteError(String action, Object error) {
    if (!kDebugMode) return;
    debugPrint('Appwrite state $action failed: $error');
  }
}
