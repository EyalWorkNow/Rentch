import 'dart:io';

import 'package:dating_app/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Thrown when the user actively dismisses the Google sign-in UI.
// The caller should treat this as a no-op (no error message to show).
class GoogleAuthCanceledException implements Exception {
  const GoogleAuthCanceledException();
  @override
  String toString() => 'GoogleAuthCanceledException';
}

// Thrown when the Google / Firebase configuration is incomplete.
class GoogleAuthConfigException implements Exception {
  const GoogleAuthConfigException(this.technicalMessage);
  final String technicalMessage;
  @override
  String toString() => 'GoogleAuthConfigException: $technicalMessage';
}

class GoogleAuthResult {
  const GoogleAuthResult({
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });

  final String displayName;
  final String email;
  final String? photoUrl;
}

class GoogleAuthService {
  GoogleAuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth? _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  Future<GoogleAuthResult> signIn() async {
    final firebaseAuth = _resolveFirebaseAuth();

    // On iOS, GIDClientID in Info.plist is the primary configuration source.
    // Passing it programmatically as well handles non-standard build setups
    // where Info.plist is not read (e.g., running tests with a mock runner).
    final clientId = !kIsWeb && Platform.isIOS
        ? DefaultFirebaseOptions.ios.iosClientId
        : null;

    try {
      await _googleSignIn.initialize(clientId: clientId);
    } on PlatformException catch (e) {
      debugPrint('[GoogleAuth] initialize failed: ${e.code} — ${e.message}');
      throw GoogleAuthConfigException('${e.code}: ${e.message}');
    }

    late final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const GoogleAuthCanceledException();
      }
      debugPrint(
          '[GoogleAuth] authenticate failed: ${e.code} — ${e.description}');
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' ||
          e.code == 'canceled' ||
          (e.message?.toLowerCase().contains('cancel') ?? false)) {
        throw const GoogleAuthCanceledException();
      }
      if (e.code == 'google_sign_in' &&
          (e.message?.contains('configuration') ?? false)) {
        debugPrint('[GoogleAuth] config error: ${e.message}');
        throw GoogleAuthConfigException('${e.code}: ${e.message}');
      }
      debugPrint(
          '[GoogleAuth] sign-in PlatformException: ${e.code} — ${e.message}');
      rethrow;
    }

    final auth = account.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
    );

    final userCredential = await firebaseAuth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Google sign-in completed without a Firebase user.');
    }

    return GoogleAuthResult(
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'משתמש Google',
      email: user.email?.trim() ?? '',
      photoUrl: user.photoURL,
    );
  }

  Future<void> signOut() async {
    if (Firebase.apps.isNotEmpty) {
      await (_firebaseAuth ?? FirebaseAuth.instance).signOut();
    }
    await _googleSignIn.signOut();
  }

  FirebaseAuth _resolveFirebaseAuth() {
    if (_firebaseAuth != null) return _firebaseAuth;
    if (Firebase.apps.isEmpty) {
      throw GoogleAuthConfigException(
        'Firebase is not initialized. Call Firebase.initializeApp() before using Google sign-in.',
      );
    }
    return FirebaseAuth.instance;
  }
}
