import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cloud backup + cross-device sync for the broker tools.
///
/// Every broker tool (clients, leads, deals, viewings, exclusivity, branding)
/// already persists its whole list as a single JSON blob under a local
/// SharedPreferences key. This mirrors that blob to `/broker_data/{key}`, which
/// the backend stores owner-scoped — the row id is ALWAYS `{callerUid}:{key}`,
/// derived server-side, so a broker can only ever read/write their own data.
///
/// Design: LOCAL-FIRST. The local write is the source of truth for instant,
/// offline-capable UX; the cloud push is fire-and-forget so a flaky network
/// never blocks the tool. On login/app-open the broker pulls each blob back so
/// their book survives a lost/replaced device and syncs across devices.
class BrokerCloudSync {
  BrokerCloudSync._();
  static final BrokerCloudSync instance = BrokerCloudSync._();

  /// Last cloud-push outcome so a tool can reassure the broker their data is
  /// backed up: null = not attempted yet, true = synced ✓, false = local-only
  /// (offline / backend unreachable). Reactive so a footer can listen.
  final ValueNotifier<bool?> lastPushOk = ValueNotifier<bool?>(null);
  DateTime? lastPushAt;

  /// Every broker-tool SharedPreferences key (MUST match each repository's
  /// `_key`), so we can pull them all on login.
  static const List<String> keys = [
    'broker_clients',
    'broker_leads',
    'broker_pipeline_deals',
    'broker_viewings',
    'broker_exclusivity_mandates',
  ];

  /// Pull every broker-tool blob from the cloud into the local store — call once
  /// when a broker signs in / opens the app, so their book is restored on a new
  /// device and kept in sync. Only overwrites a local key when the cloud has a
  /// non-empty blob, so a first-ever login with no cloud data leaves locals be.
  Future<void> pullAllToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in keys) {
      final raw = await pull(key);
      if (raw != null && raw.isNotEmpty) {
        await prefs.setString(key, raw);
      }
    }
  }

  /// Mirror a tool's raw JSON blob to the cloud. Fire-and-forget — the local
  /// write already succeeded, so any failure here is silently ignored.
  Future<void> push(String name, String rawJson) async {
    try {
      await AwsApiClient.instance.put('/broker_data/$name', {
        'data': rawJson,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      lastPushAt = DateTime.now();
      lastPushOk.value = true;
    } catch (e) {
      lastPushOk.value = false;
      if (kDebugMode) debugPrint('BrokerCloudSync.push($name) failed: $e');
    }
  }

  /// Fetch a tool's cloud blob — returns the raw JSON string, or null if there
  /// is none yet / on any failure.
  Future<String?> pull(String name) async {
    try {
      final res = await AwsApiClient.instance.get('/broker_data/$name');
      final data = res['data'];
      return (data is String && data.isNotEmpty) ? data : null;
    } catch (e) {
      if (kDebugMode) debugPrint('BrokerCloudSync.pull($name) failed: $e');
      return null;
    }
  }
}
