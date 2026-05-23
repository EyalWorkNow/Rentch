import 'package:appwrite/appwrite.dart';

const String appwriteProjectId = '6a11629d0022b837a38e';
const String appwriteProjectName = 'mydatingapp';
const String appwritePublicEndpoint = 'https://fra.cloud.appwrite.io/v1';
const String appwriteDatabaseId = '6a1201ae0028f7ff2e77';
const String appwriteAppStateCollectionId = 'app_state';
const String appwriteAppStateDocumentId = 'global_state';
const String appwriteStorageBucketId = '6a122da400013ecd35e0';

final Client client = Client()
  ..setProject(appwriteProjectId)
  ..setEndpoint(appwritePublicEndpoint);

final TablesDB tables = TablesDB(client);
