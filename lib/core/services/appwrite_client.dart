import 'package:appwrite/appwrite.dart';

const String appwriteProjectId = '6a11629d0022b837a38e';
const String appwriteProjectName = 'ranting app';
const String appwritePublicEndpoint = 'https://fra.cloud.appwrite.io/v1';

final Client client = Client()
  ..setProject(appwriteProjectId)
  ..setEndpoint(appwritePublicEndpoint);
