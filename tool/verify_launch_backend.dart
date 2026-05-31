import 'dart:convert';
import 'dart:io';

const _endpoint = String.fromEnvironment(
  'APPWRITE_ENDPOINT',
  defaultValue: 'https://fra.cloud.appwrite.io/v1',
);
const _projectId = String.fromEnvironment(
  'APPWRITE_PROJECT_ID',
  defaultValue: '6a11629d0022b837a38e',
);
const _databaseId = String.fromEnvironment(
  'APPWRITE_DATABASE_ID',
  defaultValue: '6a1201ae0028f7ff2e77',
);
const _tableId = String.fromEnvironment(
  'APPWRITE_APP_STATE_TABLE_ID',
  defaultValue: 'app_state',
);
const _rowId = String.fromEnvironment(
  'APPWRITE_APP_STATE_ROW_ID',
  defaultValue: 'global_state',
);

Future<void> main() async {
  final uri = Uri.parse(
    '$_endpoint/tablesdb/$_databaseId/tables/$_tableId/rows/$_rowId',
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set('X-Appwrite-Project', _projectId);
    request.headers.set('Accept', 'application/json');

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('Appwrite launch backend check failed.');
      stderr.writeln('HTTP ${response.statusCode}: $body');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final payload = decoded['payload'];
    final permissions = decoded[r'$permissions'];
    if (payload is! String || payload.isEmpty) {
      stderr.writeln('Appwrite row is reachable but has no payload field.');
      exitCode = 1;
      return;
    }

    final state = jsonDecode(payload) as Map<String, dynamic>;
    stdout.writeln('Appwrite launch backend is reachable.');
    stdout.writeln('schema: ${state['schema']}');
    stdout.writeln('row: $_databaseId/$_tableId/$_rowId');
    stdout.writeln('permissions: $permissions');
  } finally {
    client.close(force: true);
  }
}
