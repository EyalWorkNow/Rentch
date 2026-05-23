import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _appStateKey = 'dream_home_match_state_v1';

  Future<Map<String, dynamic>?> loadAppState() async {
    final preferences = await SharedPreferences.getInstance();
    final rawState = preferences.getString(_appStateKey);

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

  Future<void> saveAppState(Map<String, dynamic> state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_appStateKey, jsonEncode(state));
  }

  Future<void> clearAppState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_appStateKey);
  }
}
