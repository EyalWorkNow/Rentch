import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    await _googleSignIn.initialize();
    final account = await _googleSignIn.authenticate();
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
      throw StateError(
        'Firebase is not configured. Add FlutterFire options before using Google sign-in.',
      );
    }
    return FirebaseAuth.instance;
  }
}
