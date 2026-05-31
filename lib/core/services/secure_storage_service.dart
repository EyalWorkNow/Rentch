import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Wraps flutter_secure_storage for sensitive data (matches, user profile, tokens).
//
// SEC-8: SharedPreferences on Android stores data as plain-text XML in
// /data/data/<app>/shared_prefs/ — readable on rooted devices.
// iOS Keychain (used by flutter_secure_storage) encrypts at rest with the
// Secure Enclave; Android uses AES-256 via EncryptedSharedPreferences.
//
// Use this service for anything that should not be readable if the device
// is compromised: auth tokens, match IDs, user contact data.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;

  // ── Generic read/write ────────────────────────────────────────────────────────

  Future<void> writeString(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage write error ($key): $e');
    }
  }

  Future<String?> readString(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage read error ($key): $e');
      return null;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage delete error ($key): $e');
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      if (kDebugMode) debugPrint('SecureStorage deleteAll error: $e');
    }
  }

  // ── JSON helpers ──────────────────────────────────────────────────────────────

  Future<void> writeJson(String key, Map<String, dynamic> data) async {
    await writeString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  // ── Named keys ────────────────────────────────────────────────────────────────

  // Device-scoped state document ID — used to scope this device's Appwrite doc.
  // Never share this ID between users or devices.
  Future<String?> readStateDocumentId() => readString(_Keys.stateDocId);
  Future<void> writeStateDocumentId(String id) => writeString(_Keys.stateDocId, id);

  // Auth session token (if using Appwrite account-based auth in the future)
  Future<String?> readSessionToken() => readString(_Keys.sessionToken);
  Future<void> writeSessionToken(String token) => writeString(_Keys.sessionToken, token);
  Future<void> clearSessionToken() => delete(_Keys.sessionToken);

  // Clear all security-sensitive data on logout
  Future<void> clearOnLogout() async {
    await delete(_Keys.sessionToken);
    // Keep _Keys.stateDocId so the user's doc persists across sessions
    // unless you want full data reset on logout (then deleteAll())
  }
}

class _Keys {
  static const String stateDocId = 'rentch_state_doc_id';
  static const String sessionToken = 'rentch_session_token';
}
