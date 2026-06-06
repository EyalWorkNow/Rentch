// Compatibility shim — all Appwrite calls now route through AwsApiClient.
//
// This file keeps existing imports working without updating every caller.
// The real implementation is in aws_client.dart.
//
// Old pattern:  tables.createRow(databaseId: x, tableId: y, rowId: z, data: d)
// New pattern:  aws.post('/y', {'id': z, ...d})

export 'package:dating_app/core/services/aws_client.dart'
    show AwsApiClient, AwsApiException;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/aws_client.dart';

// These constants are kept so callers that reference them by name still compile.
const String appwriteDatabaseId = ''; // unused — AWS uses table-name routing
const String appwriteProjectId = ''; // unused
const String appwritePublicEndpoint = ''; // unused
const String appwriteStorageBucketId = AppConfig.awsS3Bucket;

// Shared singleton — all services use this.
final AwsApiClient aws = AwsApiClient.instance;

// ─── TablesDB compatibility layer ─────────────────────────────────────────────
//
// Provides the same method signatures as Appwrite's TablesDB so that callers
// need only change their import and optionally replace `tables.` with `aws.`.
// Internal services have been updated to call aws.* directly; this class is
// retained for any remaining callers that haven't been migrated yet.

// ignore: non_constant_identifier_names
TablesDB get tables => TablesDB._instance;

class TablesDB {
  TablesDB._();
  static final TablesDB _instance = TablesDB._();

  Future<RowDocument> createRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    final body = {'id': rowId, ...data};
    final result = await aws.post('/$tableId', body);
    return RowDocument(result);
  }

  Future<RowDocument> upsertRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    final body = {'id': rowId, ...data};
    final result = await aws.put('/$tableId/$rowId', body);
    return RowDocument(result);
  }

  Future<RowDocument> getRow({
    required String databaseId,
    required String tableId,
    required String rowId,
  }) async {
    final result = await aws.get('/$tableId/$rowId');
    return RowDocument(result);
  }

  Future<RowList> listRows({
    required String databaseId,
    required String tableId,
    List<String> queries = const [],
  }) async {
    final qMap = _parseQueries(queries);
    final result = await aws.get('/$tableId', query: qMap);
    final rawRows = result['items'] as List? ?? result['rows'] as List? ?? [];
    return RowList(rawRows
        .whereType<Map>()
        .map((r) => RowDocument(Map<String, dynamic>.from(r)))
        .toList());
  }

  Future<void> deleteRow({
    required String databaseId,
    required String tableId,
    required String rowId,
  }) =>
      aws.delete('/$tableId/$rowId');

  // Minimal query-string encoder for the most common Appwrite query patterns.
  Map<String, String> _parseQueries(List<String> queries) {
    final map = <String, String>{};
    for (final q in queries) {
      if (q.startsWith('equal(')) {
        // equal("field","value") → field=value
        final inner = q.substring(6, q.length - 1);
        final parts = inner.split('","');
        if (parts.length == 2) {
          final field = parts[0].replaceAll('"', '');
          final value = parts[1].replaceAll('"', '');
          map[field] = value;
        }
      } else if (q.startsWith('limit(')) {
        map['limit'] = q.substring(6, q.length - 1);
      } else if (q.startsWith('orderAsc(')) {
        map['orderBy'] = q.substring(9, q.length - 1);
        map['order'] = 'asc';
      } else if (q.startsWith('orderDesc(')) {
        map['orderBy'] = q.substring(10, q.length - 1);
        map['order'] = 'desc';
      } else if (q.startsWith('cursorAfter(')) {
        map['after'] = q.substring(12, q.length - 1).replaceAll('"', '');
      }
    }
    return map;
  }
}

/// Minimal stand-in for Appwrite's Document / Row type.
class RowDocument {
  RowDocument(this.data);
  final Map<String, dynamic> data;

  // Appwrite-style accessor: $id → data['id']
  // ignore: non_constant_identifier_names
  String get $id => (data['id'] ?? data[r'$id'] ?? '').toString();
}

/// Minimal stand-in for Appwrite's DocumentList / RowList.
class RowList {
  RowList(this.rows);
  final List<RowDocument> rows;
  int get total => rows.length;
}

// ── Query builder (Appwrite-compatible statics) ────────────────────────────────

class Query {
  static String equal(String field, Object value) =>
      'equal("$field","$value")';
  static String limit(int n) => 'limit($n)';
  static String orderAsc(String field) => 'orderAsc($field)';
  static String orderDesc(String field) => 'orderDesc($field)';
  static String cursorAfter(String id) => 'cursorAfter("$id")';
  static String isNotNull(String field) => 'isNotNull($field)';
  static String greaterThan(String field, Object value) =>
      'greaterThan("$field","$value")';
}

// ── ID generator (replaces Appwrite's ID.unique()) ────────────────────────────

class ID {
  static String unique() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = (DateTime.now().millisecondsSinceEpoch % 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0');
    return 'rentch_${ts}_$rand';
  }
}
