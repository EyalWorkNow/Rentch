import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('EditProfileScreen tailors layout for landlord', (WidgetTester tester) async {
    final provider = DatingProvider(
      rentalDataService: _MockRentalDataService(),
      localStorageService: _MockLocalStorageService(),
    );
    try {
      await provider.initialize();
      await provider.setUserRole('landlord', explicit: true);

      const testProfile = TenantProfile(
        id: 'landlord-1',
        name: 'Owner Name',
        bio: 'Bio text',
        photoUrls: [],
        budgetMax: 7000,
        desiredRooms: 3.0,
        moveInWindow: 'גמיש',
        importantDetails: ['זוג', 'לא מעשנים'],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<DatingProvider>.value(
          value: provider,
          child: MaterialApp(
            locale: const Locale('he'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: EditProfileScreen(profile: testProfile),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify name field shows business/owner label
      expect(find.text('שם מלא / שם העסק'), findsOneWidget);
      // Verify bio field shows about me / properties label
      expect(find.text('עליי / על הנכסים'), findsOneWidget);

      // Seeker-specific labels/sections should not be visible
      expect(find.text('העדפות דירה'), findsNothing);
      expect(find.text('תגיות לבעלי דירות'), findsNothing);
      // Tags section for landlords should be visible with dynamic title
      expect(find.text('תגיות לשוכרים'), findsOneWidget);
    } finally {
      provider.dispose();
      await tester.pump(const Duration(seconds: 2));
    }
  });
}

class _MockRentalDataService extends RentalDataService {
  @override
  Future<PropertyPage> loadFirstPage({String areaId = 'all_israel'}) async {
    return PropertyPage(items: const [], hasMore: false);
  }
  @override
  TenantProfile createDefaultTenantProfile() {
    return const TenantProfile(
      id: 'test',
      name: 'Test',
      bio: '',
      photoUrls: [],
      budgetMax: 5000,
      desiredRooms: 2,
      moveInWindow: '',
      importantDetails: [],
    );
  }
}

class _MockLocalStorageService extends LocalStorageService {
  @override
  Future<Map<String, dynamic>?> loadAppState() async => null;
  @override
  Future<void> saveAppState(Map<String, dynamic> state, {bool syncRemote = true}) async {}
}
