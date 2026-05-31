import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// Thrown when the user actively dismisses the Apple sign-in sheet.
class AppleAuthCanceledException implements Exception {
  const AppleAuthCanceledException();
  @override
  String toString() => 'AppleAuthCanceledException';
}

// Thrown when the platform does not support Apple Sign-In
// (e.g., Android without a backend configured).
class AppleAuthUnsupportedException implements Exception {
  const AppleAuthUnsupportedException();
  @override
  String toString() => 'AppleAuthUnsupportedException';
}

class AppleAuthResult {
  const AppleAuthResult({
    required this.displayName,
    required this.email,
  });

  final String displayName;
  final String email;
}

class AppleAuthService {
  static Future<bool> get isAvailable => SignInWithApple.isAvailable();

  Future<AppleAuthResult> signIn() async {
    final available = await SignInWithApple.isAvailable();
    if (!available) {
      throw const AppleAuthUnsupportedException();
    }

    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppleAuthCanceledException();
      }
      debugPrint('[AppleAuth] authorization failed: ${e.code} — ${e.message}');
      rethrow;
    }

    final fullName = [
      credential.givenName?.trim(),
      credential.familyName?.trim(),
    ].where((s) => s != null && s.isNotEmpty).join(' ');

    return AppleAuthResult(
      displayName: fullName.isNotEmpty ? fullName : 'משתמש Apple',
      email: credential.email?.trim() ?? '',
    );
  }
}
