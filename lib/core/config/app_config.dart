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
    defaultValue: true,
  );

  /// אתי's LIVE speech-to-speech voice over Gemini Live (real-time, sub-second,
  /// bypasses the us-east-1 turn-based STT→LLM→TTS chain). OFF by default — the
  /// turn-based flow stays the default until this is validated on a real device;
  /// enable with --dart-define=ATI_LIVE_VOICE=true.
  static const bool atiLiveVoice = bool.fromEnvironment(
    'ATI_LIVE_VOICE',
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

  // PUBLIC (no-auth) base for shareable links. The API-GW /p/{id} route is served
  // by the PublicShareResource in aws/template.yaml (AuthorizationType: NONE) — a
  // dedicated resource on the SAME router Lambda as {proxy+}, but WITHOUT the
  // Firebase authorizer, so WhatsApp/social crawlers and anonymous browsers reach
  // the share page instead of getting a 401. The page opens the app at the
  // apartment (rently://) or falls back to the store. (Public Lambda Function URLs
  // are blocked by an org guardrail, so we use the API-GW path.)
  static const String publicShareBaseUrl = String.fromEnvironment(
    'PUBLIC_SHARE_URL',
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
    defaultValue: 'rently-properties',
  );

  static const String dynamoMessagesTable = String.fromEnvironment(
    'DYNAMO_MESSAGES_TABLE',
    defaultValue: 'rently-messages',
  );

  // Behavioral-event table. EventService routes through the AWS API gateway via
  // the `events` path segment (appwriteEventsTableId), so the backend's
  // TABLE_PREFIX (rentch-) resolves the real table — this constant is the
  // direct-DynamoDB name and is kept in sync with the live table so any direct
  // reader hits the right one. EventService is enabled whenever the AWS core
  // config + appwriteEventsTableId ('events') are present, which they are.
  static const String dynamoEventsTable = String.fromEnvironment(
    'DYNAMO_EVENTS_TABLE',
    defaultValue: 'rentch-events',
  );

  static const String dynamoUsersTable = String.fromEnvironment(
    'DYNAMO_USERS_TABLE',
    defaultValue: 'rently-users',
  );

  static const String dynamoReportsTable = String.fromEnvironment(
    'DYNAMO_REPORTS_TABLE',
    defaultValue: 'rently-reports',
  );

  static const String dynamoBlocksTable = String.fromEnvironment(
    'DYNAMO_BLOCKS_TABLE',
    defaultValue: 'rently-blocks',
  );

  static const String dynamoReviewsTable = String.fromEnvironment(
    'DYNAMO_REVIEWS_TABLE',
    defaultValue: 'rently-reviews',
  );

  // NOTE: these two constants act ONLY as an on/off gate for the dwell/session
  // analytics repo (see canUsePropertyAnalytics + appwritePropertyViewSessionsTableId
  // below). Their VALUE never reaches the backend — PropertyAnalyticsRepository
  // routes through the AWS API via the fixed logical paths 'property_views' /
  // 'property_likes' (aws.post('/property_views', …)), exactly like EventService
  // uses 'events'. The backend's TABLE_PREFIX resolves the real DynamoDB table.
  // They defaulted to '' which left dwell collection OFF in every prod build;
  // giving them the real table names (rently- convention, matching
  // dynamoPropertiesTable/dynamoUsersTable) turns collection ON while staying safe:
  // only non-emptiness is observed at runtime.
  static const String dynamoPropertyViewsTable = String.fromEnvironment(
    'DYNAMO_PROPERTY_VIEWS_TABLE',
    defaultValue: 'rently-property-views',
  );

  static const String dynamoPropertyLikesTable = String.fromEnvironment(
    'DYNAMO_PROPERTY_LIKES_TABLE',
    defaultValue: 'rently-property-likes',
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
    defaultValue: 'rently-media',
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
  static String get appwriteDatabaseId => 'rently-db';
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
  static String get appwriteReviewsTableId => 'reviews';
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
