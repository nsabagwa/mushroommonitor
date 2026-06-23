import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:mushpi_hub/data/models/auth_models.dart';

/// Handles all auth operations via Firebase Authentication.
///
/// Firebase's SDK manages token storage, refresh, and session persistence
/// internally (using secure platform storage under the hood), so this
/// repository no longer needs flutter_secure_storage or manual token
/// handling — that complexity is gone.
class AuthRepository {
  AuthRepository({fb.FirebaseAuth? firebaseAuth})
      : _auth = firebaseAuth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  /// Sign up a new account with email/password.
  Future<AuthUser> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException.unknown('Signup succeeded but no user returned.');
      }
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }
      return AuthUser.fromFirebase(user);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (e) {
      throw AuthException.network();
    }
  }

  /// Log in with email/password.
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException.unknown('Login succeeded but no user returned.');
      }
      return AuthUser.fromFirebase(user);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (e) {
      throw AuthException.network();
    }
  }

  /// Returns the currently signed-in user, if any. Firebase persists the
  /// session automatically across app restarts, so this resolves instantly
  /// from local cache — no network call needed on the happy path.
  Future<AuthUser?> getCurrentUser() async {
    final user = _auth.currentUser;
    return user != null ? AuthUser.fromFirebase(user) : null;
  }

  /// Whether there's a persisted Firebase session to restore.
  Future<bool> hasStoredSession() async {
    return _auth.currentUser != null;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
