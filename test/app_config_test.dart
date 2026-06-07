import 'package:dating_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Appwrite aliases map to AWS REST resources', () {
    expect(AppConfig.appwriteAppStateTableId, 'app_state');
    expect(AppConfig.appwritePropertiesTableId, 'properties');
    expect(AppConfig.appwriteMessagesTableId, 'messages');
    expect(AppConfig.appwriteUsersTableId, 'users');
    expect(AppConfig.appwriteEventsTableId, 'events');
    expect(AppConfig.appwriteReportsTableId, 'reports');
    expect(AppConfig.appwriteBlocksTableId, 'blocks');
  });
}
