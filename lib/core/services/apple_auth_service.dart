import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppleAuthCanceledException implements Exception {
  const AppleAuthCanceledException();
  @override
  String toString() => 'AppleAuthCanceledException';
}

class AppleAuthUnsupportedException implements Exception {
  const AppleAuthUnsupportedException();
  @override
  String toString() => 'AppleAuthUnsupportedException';
}

class AppleAuthResult {
  const AppleAuthResult({
    required this.displayName,
    required this.email,
    required this.isNewUser,
  });

  final String displayName;
  final String email;
  final bool isNewUser;
}

class AppleAuthService {
  static Future<bool> get isAvailable => SignInWithApple.isAvailable();

  Future<AppleAuthResult> signIn() async {
    final available = await SignInWithApple.isAvailable();
    if (!available) {
      throw const AppleAuthUnsupportedException();
    }

    // Generate a nonce for Firebase verification.
    final rawNonce = _generateNonce();
    final nonce = _sha256(rawNonce);

    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppleAuthCanceledException();
      }
      debugPrint('[AppleAuth] authorization failed: ${e.code} — ${e.message}');
      rethrow;
    }

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw StateError('[AppleAuth] Apple returned no identity token.');
    }

    // Sign in to Firebase so the user has a real UID and JWT.
    // NOTE: passing authorizationCode as accessToken is REQUIRED here — this
    // matches the build-40 version that worked. Removing it (build 42) broke
    // Apple sign-in, so it is restored.
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: identityToken,
      rawNonce: rawNonce,
      accessToken: credential.authorizationCode,
    );

    UserCredential userCredential;
    try {
      userCredential =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);
    } on FirebaseAuthException catch (e) {
      debugPrint('[AppleAuth] Firebase error ${e.code}: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AppleAuth] Firebase signInWithCredential failed: $e');
      rethrow;
    }

    final user = userCredential.user;
    if (user == null) {
      throw StateError('[AppleAuth] Firebase returned no user after Apple sign-in.');
    }

    // Apple only provides givenName/familyName on the very first authorization.
    final fullName = [
      credential.givenName?.trim(),
      credential.familyName?.trim(),
    ].where((s) => s != null && s.isNotEmpty).join(' ');

    // Prefer Firebase display name for returning users.
    final displayName = fullName.isNotEmpty
        ? fullName
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'משתמש Apple');

    return AppleAuthResult(
      displayName: displayName,
      email: credential.email?.trim() ?? user.email?.trim() ?? '',
      isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false,
    );
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
