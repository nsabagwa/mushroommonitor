// File generated manually (flutterfire_cli had a Windows networking bug
// fetching the project list, so these values were copied directly from the
// Firebase console instead of running `flutterfire configure`).
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS was not configured. Re-run setup for iOS if/when you build for it.
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for ios - '
        'register an iOS app in the Firebase console and add its values here.',
      );
    }
    if (kIsWeb) {
      return web;
    }
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return web;
    }
    return web;
  }

  // Android app config (from android/app/google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDjyA_rOOhHOkj3hC7nRmz-UVyNqwzhS44',
    appId: '1:692396303316:android:181eeb5dad7846d4296c41',
    messagingSenderId: '692396303316',
    projectId: 'mushpi-hub',
    storageBucket: 'mushpi-hub.firebasestorage.app',
    databaseURL: 'https://mushpi-hub-default-rtdb.firebaseio.com',
  );

  // Web app config (from Firebase console "Your apps" -> web)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDeMt5d8Xy3Q0aVtZRVQhDzr2i2IFbyffY',
    appId: '1:692396303316:web:66fa4b4ddbf8e173296c41',
    messagingSenderId: '692396303316',
    projectId: 'mushpi-hub',
    authDomain: 'mushpi-hub.firebaseapp.com',
    storageBucket: 'mushpi-hub.firebasestorage.app',
    measurementId: 'G-L6MZBVBHXH',
    databaseURL: 'https://mushpi-hub-default-rtdb.firebaseio.com',
  );
}
