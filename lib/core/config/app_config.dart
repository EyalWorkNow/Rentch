class AppConfig {
  const AppConfig._();

  static const String environment = String.fromEnvironment(
    'RENTCH_ENV',
    defaultValue: 'development',
  );

  static const bool enableGoogleSignIn = bool.fromEnvironment(
    'RENTCH_ENABLE_GOOGLE_SIGN_IN',
    defaultValue: false,
  );

  static const bool enableCloudStorage = bool.fromEnvironment(
    'RENTCH_ENABLE_CLOUD_STORAGE',
    defaultValue: false,
  );

  static const bool enableRemoteState = bool.fromEnvironment(
    'RENTCH_ENABLE_REMOTE_STATE',
    defaultValue: false,
  );

  static const String appwriteEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: '',
  );

  static const String appwriteProjectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: '',
  );

  static const String appwriteDatabaseId = String.fromEnvironment(
    'APPWRITE_DATABASE_ID',
    defaultValue: '',
  );

  static const String appwriteAppStateTableId = String.fromEnvironment(
    'APPWRITE_APP_STATE_TABLE_ID',
    defaultValue: '',
  );

  static const String appwriteStorageBucketId = String.fromEnvironment(
    'APPWRITE_STORAGE_BUCKET_ID',
    defaultValue: '',
  );

  static bool get isProduction => environment == 'production';

  static bool get hasAppwriteCoreConfig =>
      appwriteEndpoint.isNotEmpty && appwriteProjectId.isNotEmpty;

  static bool get canUseCloudStorage =>
      enableCloudStorage &&
      hasAppwriteCoreConfig &&
      appwriteStorageBucketId.isNotEmpty;

  static bool get canUseRemoteState =>
      enableRemoteState &&
      hasAppwriteCoreConfig &&
      appwriteDatabaseId.isNotEmpty &&
      appwriteAppStateTableId.isNotEmpty;

  static List<String> productionReadinessIssues() {
    if (!isProduction) return const [];

    final issues = <String>[];
    if (enableGoogleSignIn) {
      issues
          .add('Firebase platform options must be generated with FlutterFire.');
    }
    if (enableCloudStorage && !canUseCloudStorage) {
      issues.add(
          'Appwrite storage is enabled but bucket configuration is missing.');
    }
    if (enableRemoteState && !canUseRemoteState) {
      issues.add(
          'Remote state is enabled but Appwrite database/table configuration is missing.');
    }
    if (!enableRemoteState) {
      issues.add(
          'Remote state is disabled; marketplace state remains device-local.');
    }
    return issues;
  }
}
