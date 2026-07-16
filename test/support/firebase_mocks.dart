// Minimal Firebase Core + Auth platform mocks for widget tests.
//
// Several screens read `FirebaseAuth.instance` (e.g. _StartupGate's
// authStateChanges StreamBuilder, the dashboard header). Without a Firebase
// app that throws "No Firebase App '[DEFAULT]' has been created" during build.
// These mocks make `Firebase.app()` and `FirebaseAuth.instance` resolve to a
// signed-out state (currentUser == null, auth streams emit null) so tests can
// exercise the guest/onboarding flow. Call `setupFirebaseMocks()` in setUp.
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockFirebaseApp extends FirebaseAppPlatform {
  _MockFirebaseApp([String name = defaultFirebaseAppName])
      : super(
          name,
          const FirebaseOptions(
            apiKey: 'test',
            appId: 'test',
            messagingSenderId: 'test',
            projectId: 'test',
          ),
        );
}

class _MockFirebasePlatform extends FirebasePlatform
    with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _MockFirebaseApp(name);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _MockFirebaseApp(name ?? defaultFirebaseAppName);

  @override
  List<FirebaseAppPlatform> get apps => [_MockFirebaseApp()];
}

class _MockFirebaseAuth extends FirebaseAuthPlatform
    with MockPlatformInterfaceMixin {
  _MockFirebaseAuth({FirebaseApp? app}) : super(appInstance: app);

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) =>
      _MockFirebaseAuth(app: app);

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;

  @override
  UserPlatform? get currentUser => null;

  @override
  Stream<UserPlatform?> authStateChanges() => Stream<UserPlatform?>.value(null);

  @override
  Stream<UserPlatform?> idTokenChanges() => Stream<UserPlatform?>.value(null);

  @override
  Stream<UserPlatform?> userChanges() => Stream<UserPlatform?>.value(null);
}

bool _installed = false;

/// Installs signed-out Firebase Core + Auth mocks (idempotent).
void setupFirebaseMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_installed) return;
  _installed = true;
  FirebasePlatform.instance = _MockFirebasePlatform();
  FirebaseAuthPlatform.instance = _MockFirebaseAuth();
}
