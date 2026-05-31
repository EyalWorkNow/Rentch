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
    defaultValue: false,
  );

  static const bool enableRemoteState = bool.fromEnvironment(
    'RENTCH_ENABLE_REMOTE_STATE',
    defaultValue: launchMode,
  );

  static const String appwriteEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://fra.cloud.appwrite.io/v1',
  );

  static const String appwriteProjectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: '6a11629d0022b837a38e',
  );

  static const String appwriteDatabaseId = String.fromEnvironment(
    'APPWRITE_DATABASE_ID',
    defaultValue: '6a1201ae0028f7ff2e77',
  );

  static const String appwriteAppStateTableId = String.fromEnvironment(
    'APPWRITE_APP_STATE_TABLE_ID',
    defaultValue: 'app_state',
  );

  static const String appwriteAppStateRowId = String.fromEnvironment(
    'APPWRITE_APP_STATE_ROW_ID',
    defaultValue: 'global_state',
  );

  static const String appwriteStorageBucketId = String.fromEnvironment(
    'APPWRITE_STORAGE_BUCKET_ID',
    defaultValue: '6a122da400013ecd35e0',
  );

  static const String appwriteMessagesTableId = String.fromEnvironment(
    'APPWRITE_MESSAGES_TABLE_ID',
    defaultValue: String.fromEnvironment(
      'APPWRITE_MESSAGES_COLLECTION_ID',
      defaultValue: 'messages',
    ),
  );

  static bool get isProduction => environment == 'production';

  static bool get hasAppwriteCoreConfig =>
      appwriteEndpoint.isNotEmpty && appwriteProjectId.isNotEmpty;

  static bool get canUseCloudStorage =>
      enableCloudStorage &&
      hasAppwriteCoreConfig &&
      appwriteStorageBucketId.isNotEmpty;

  static bool get canUseChat =>
      hasAppwriteCoreConfig &&
      appwriteDatabaseId.isNotEmpty &&
      appwriteMessagesTableId.isNotEmpty;

  static bool get canUseRemoteState =>
      enableRemoteState &&
      hasAppwriteCoreConfig &&
      appwriteDatabaseId.isNotEmpty &&
      appwriteAppStateTableId.isNotEmpty;

  static List<String> productionReadinessIssues() {
    if (!isProduction) return const [];

    final issues = <String>[];
    if (enableCloudStorage && !canUseCloudStorage) {
      issues.add(
          'Appwrite storage is enabled but bucket configuration is missing.');
    }
    if (!enableCloudStorage) {
      issues.add(
          'Cloud image storage is disabled; uploaded images remain local on this device.');
    }
    if (enableRemoteState && !canUseRemoteState) {
      issues.add(
          'Remote state is enabled but Appwrite database/table configuration is missing.');
    }
    if (!enableRemoteState) {
      issues.add(
          'Remote state is disabled; marketplace state remains device-local.');
    }
    if (launchMode) {
      issues.add(
          'Launch mode uses the current shared Appwrite state row; replace it with user-scoped tables before a public launch.');
    }
    return issues;
  }
}
