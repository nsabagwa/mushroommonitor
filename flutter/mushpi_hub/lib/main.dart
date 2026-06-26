import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Android, the Google Services Gradle plugin (triggered by
  // google-services.json) auto-initializes the default Firebase app
  // natively before Dart code runs. Checking Firebase.apps.isEmpty isn't
  // reliable here because the Dart-side app list can lag behind what's
  // already registered natively, so we catch the specific duplicate-app
  // error instead.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
    // Already initialized natively — fine, continue.
  }

  await FirebaseAuth.instance.signOut();

  runApp(
    const ProviderScope(
      child: MushPiApp(),
    ),
  );
}
