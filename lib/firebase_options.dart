import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase Web is not configured for this project.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'Firebase macOS is not configured for this project.',
        );
      default:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBCqvY0zKjBn0GatoeBJJRS2Z7ufD64DpM',
    appId: '1:116035400248:ios:9d7de1cc23d20e1ebdaccd',
    messagingSenderId: '116035400248',
    projectId: 'mydatingapp-4c043',
    storageBucket: 'mydatingapp-4c043.firebasestorage.app',
    iosClientId:
        '116035400248-8vr9h6b5nq73k8fihunjbes1kuufkr8p.apps.googleusercontent.com',
    iosBundleId: 'com.eyalatiyawork.rentch',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCDcwTR549WF4TG-Uezjrpa8oB9y7cO2-M',
    appId: '1:116035400248:android:6678941a7abcbc24bdaccd',
    messagingSenderId: '116035400248',
    projectId: 'mydatingapp-4c043',
    storageBucket: 'mydatingapp-4c043.firebasestorage.app',
    androidClientId:
        '116035400248-3mm52n5pe4r8f6oi35rmv80fqbqfehtu.apps.googleusercontent.com',
  );
}
