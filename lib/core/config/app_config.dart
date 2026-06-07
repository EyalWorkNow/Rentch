class AppConfig {
  const AppConfig._();

  static const String environment = String.fromEnvironment(
    'RENTCH_ENV',
    defaultValue: 'development',
  );

  static const bool launchMode = bool.fromEnvironment(
    'RENTCH_LAUNCH_MODE',
    defaultValue: false,
  );

  static const bool enableGoogleSignIn = bool.fromEnvironment(
    'RENTCH_ENABLE_GOOGLE_SIGN_IN',
    defaultValue: true,
  );

  static const bool enableCloudStorage = bool.fromEnvironment(
    'RENTCH_ENABLE_CLOUD_STORAGE',
    defaultValue: true,
  );

  static const bool enableRemoteState = bool.fromEnvironment(
    'RENTCH_ENABLE_REMOTE_STATE',
    defaultValue: true,
  );

  static const bool enable3dScanning = bool.fromEnvironment(
    'RENTCH_ENABLE_3D_SCANNING',
    defaultValue: false,
  );

  // ── AWS API Gateway ──────────────────────────────────────────────────────────
  // Live deployed backend (us-east-1). Override per-build with
  //   --dart-define=AWS_API_URL=https://<id>.execute-api.<region>.amazonaws.com/prod
  // The endpoint is protected by the Firebase JWT authorizer, so embedding it is
  // safe (no data is reachable without a valid Firebase ID token).
  static const String awsApiGatewayUrl = String.fromEnvironment(
    'AWS_API_URL',
    defaultValue: 'https://g7b9nx11sk.execute-api.us-east-1.amazonaws.com/prod',
  );

  // Live WebSocket endpoint for real-time chat (us-east-1). Firebase token is
  // passed as ?token=… on connect; gated by the WS authorizer Lambda.
  static const String awsWebSocketUrl = String.fromEnvironment(
    'AWS_WS_URL',
    defaultValue: 'wss://43ccfrrt44.execute-api.us-east-1.amazonaws.com/prod',
  );

  static bool get hasWebSocket => awsWebSocketUrl.trim().isNotEmpty;

  // Optional API Gateway Usage-Plan key (x-api-key). Not required — the backend
  // authorizes via Firebase JWT. Leave empty unless you add a usage plan.
  static const String awsApiKey = String.fromEnvironment(
    'AWS_API_KEY',
    defaultValue: '',
  );

  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'us-east-1',
  );

  // ── AWS DynamoDB table names ──────────────────────────────────────────────────
  static const String dynamoPropertiesTable = String.fromEnvironment(
    'DYNAMO_PROPERTIES_TABLE',
    defaultValue: 'rentch-properties',
  );

  static const String dynamoMessagesTable = String.fromEnvironment(
    'DYNAMO_MESSAGES_TABLE',
    defaultValue: 'rentch-messages',
  );

  static const String dynamoEventsTable = String.fromEnvironment(
    'DYNAMO_EVENTS_TABLE',
    defaultValue: 'rentch-events',
  );

  static const String dynamoUsersTable = String.fromEnvironment(
    'DYNAMO_USERS_TABLE',
    defaultValue: 'rentch-users',
  );

  static const String dynamoReportsTable = String.fromEnvironment(
    'DYNAMO_REPORTS_TABLE',
    defaultValue: 'rentch-reports',
  );

  static const String dynamoBlocksTable = String.fromEnvironment(
    'DYNAMO_BLOCKS_TABLE',
    defaultValue: 'rentch-blocks',
  );

  static const String dynamoPropertyViewsTable = String.fromEnvironment(
    'DYNAMO_PROPERTY_VIEWS_TABLE',
    defaultValue: '',
  );

  static const String dynamoPropertyLikesTable = String.fromEnvironment(
    'DYNAMO_PROPERTY_LIKES_TABLE',
    defaultValue: '',
  );

  // Per-device state document ID (Appwrite → DynamoDB migration kept same concept).
  // Empty default forces LocalStorageService to generate a per-device ID.
  static const String awsAppStateRowId = String.fromEnvironment(
    'AWS_APP_STATE_ROW_ID',
    defaultValue: '',
  );

  // ── AWS S3 ────────────────────────────────────────────────────────────────────
  static const String awsS3Bucket = String.fromEnvironment(
    'AWS_S3_BUCKET',
    defaultValue: 'rentch-media',
  );

  // ── Legal ─────────────────────────────────────────────────────────────────────
  static const String legalConsentVersion = String.fromEnvironment(
    'RENTCH_LEGAL_CONSENT_VERSION',
    defaultValue: 'v1.0',
  );

  // ── Pagination ────────────────────────────────────────────────────────────────
  static const int propertyPageSize = 150;

  // ── 3D Scanning (Scaniverse / NSDK) ──────────────────────────────────────────
  static const String scan3dProvider = String.fromEnvironment(
    'RENTCH_3D_SCAN_PROVIDER',
    defaultValue: 'scaniverse',
  );

  static const String spatialApiKey = String.fromEnvironment(
    'SPATIAL_API_KEY',
    defaultValue: '',
  );

  static const String spatialServiceAccountSecret = String.fromEnvironment(
    'SPATIAL_SERVICE_ACCOUNT_SECRET',
    defaultValue: '',
  );

  static bool get hasSpatialConfig => spatialApiKey.trim().isNotEmpty;

  static const String _scan3dProxyUrlOverride = String.fromEnvironment(
    'RENTCH_3D_SCAN_PROXY_URL',
    defaultValue: '',
  );

  static String get scan3dProxyUrl {
    final explicit = _scan3dProxyUrlOverride.trim();
    if (explicit.isNotEmpty) return explicit;
    return awsApiGatewayUrl.trim();
  }

  static const String scan3dDefaultPreset = String.fromEnvironment(
    'RENTCH_3D_SCAN_PRESET',
    defaultValue: 'standard',
  );

  static const String scan3dOutputFormat = String.fromEnvironment(
    'RENTCH_3D_SCAN_OUTPUT_FORMAT',
    defaultValue: 'sog',
  );

  // ── Derived capability flags ──────────────────────────────────────────────────

  static bool get isProduction => environment == 'production';

  static bool get hasAwsCoreConfig => awsApiGatewayUrl.trim().isNotEmpty;

  static bool get canUseCloudStorage => enableCloudStorage && hasAwsCoreConfig;

  static bool get canUseChat => hasAwsCoreConfig;

  static bool get canUseProperties => hasAwsCoreConfig;

  static bool get canUsePropertyAnalytics =>
      hasAwsCoreConfig &&
      dynamoPropertyViewsTable.isNotEmpty &&
      dynamoPropertyLikesTable.isNotEmpty;

  static bool get canUse3dScanBackend =>
      enable3dScanning && scan3dProxyUrl.trim().isNotEmpty;

  static bool get canUseRemoteState => enableRemoteState && hasAwsCoreConfig;

  // ── Legacy aliases (kept so existing callers compile unchanged) ───────────────
  // These map old Appwrite constant names → AWS equivalents.
  static String get appwriteEndpoint => awsApiGatewayUrl;
  static String get appwriteProjectId => '';
  static String get appwriteDatabaseId => '';
  static String get appwriteAppStateTableId => 'app_state';
  static String get appwriteAppStateRowId => awsAppStateRowId;
  static String get appwriteStorageBucketId => awsS3Bucket;
  static String get appwriteMessagesTableId => 'messages';
  static String get appwritePropertiesTableId => 'properties';
  static String get appwritePropertyViewSessionsTableId =>
      dynamoPropertyViewsTable.isEmpty ? '' : 'property_views';
  static String get appwritePropertyLikesTableId =>
      dynamoPropertyLikesTable.isEmpty ? '' : 'property_likes';
  static String get appwriteUsersTableId => 'users';
  static String get appwriteEventsTableId => 'events';
  static String get appwriteReportsTableId => 'reports';
  static String get appwriteBlocksTableId => 'blocks';
  static bool get hasAppwriteCoreConfig => hasAwsCoreConfig;

  static List<String> productionReadinessIssues() {
    if (!isProduction) return const [];
    final issues = <String>[];
    if (!hasAwsCoreConfig) {
      issues
          .add('AWS_API_URL is not set. Set via --dart-define=AWS_API_URL=...');
    }
    if (awsApiKey.isEmpty) {
      issues
          .add('AWS_API_KEY is not set. Set via --dart-define=AWS_API_KEY=...');
    }
    if (enableCloudStorage && !canUseCloudStorage) {
      issues.add('Cloud storage is enabled but AWS is not configured.');
    }
    if (!enableCloudStorage) {
      issues.add(
          'Cloud storage is disabled; uploaded images remain on-device only.');
    }
    if (enableRemoteState && !canUseRemoteState) {
      issues.add('Remote state is enabled but AWS_API_URL is missing.');
    }
    if (!enableRemoteState) {
      issues.add('Remote state is disabled; app state remains device-local.');
    }
    if (enable3dScanning && !canUse3dScanBackend) {
      issues.add(
          '3D scanning is enabled but RENTCH_3D_SCAN_PROXY_URL is missing.');
    }
    return issues;
  }
}
