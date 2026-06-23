import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Authenticated user profile, backed by Firebase Auth's [fb.User].
class AuthUser {
  final String id;
  final String email;
  final String? displayName;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  /// Build from a Firebase [fb.User] instance.
  factory AuthUser.fromFirebase(fb.User user) {
    return AuthUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
    );
  }
}

/// Thrown for any auth-related failure (bad credentials, network failure,
/// etc). [code] lets the UI branch on specific cases if needed.
class AuthException implements Exception {
  final String code;
  final String message;

  const AuthException(this.code, this.message);

  factory AuthException.network() => const AuthException(
      'NETWORK_ERROR', 'Could not reach the server. Check your connection.');

  factory AuthException.unknown([String? detail]) => AuthException(
      'UNKNOWN', detail ?? 'Something went wrong. Please try again.');

  /// Map a [fb.FirebaseAuthException] to our own [AuthException], with
  /// friendly messages for the cases users actually hit.
  factory AuthException.fromFirebase(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return const AuthException(
            'INVALID_EMAIL', 'Enter a valid email address.');
      case 'user-disabled':
        return const AuthException(
            'USER_DISABLED', 'This account has been disabled.');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return const AuthException(
            'INVALID_CREDENTIALS', 'Incorrect email or password.');
      case 'email-already-in-use':
        return const AuthException(
            'EMAIL_TAKEN', 'An account with this email already exists.');
      case 'weak-password':
        return const AuthException('WEAK_PASSWORD',
            'Password is too weak. Use at least 8 characters.');
      case 'network-request-failed':
        return AuthException.network();
      case 'too-many-requests':
        return const AuthException(
            'TOO_MANY_REQUESTS', 'Too many attempts. Please try again later.');
      default:
        return AuthException.unknown(e.message);
    }
  }

  @override
  String toString() => 'AuthException($code): $message';
}
