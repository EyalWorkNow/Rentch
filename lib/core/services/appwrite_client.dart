import 'package:appwrite/appwrite.dart';
import 'package:dating_app/core/config/app_config.dart';

const String appwriteProjectId = AppConfig.appwriteProjectId;
const String appwritePublicEndpoint = AppConfig.appwriteEndpoint;
const String appwriteDatabaseId = AppConfig.appwriteDatabaseId;
const String appwriteAppStateCollectionId = AppConfig.appwriteAppStateTableId;
const String appwriteStorageBucketId = AppConfig.appwriteStorageBucketId;

final Client client = Client()
  ..setEndpoint(appwritePublicEndpoint)
  ..setProject(appwriteProjectId);

final TablesDB tables = TablesDB(client);
