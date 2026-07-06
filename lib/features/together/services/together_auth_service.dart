import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class TogetherAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in anonymously so user can create/join sessions without full auth.
  /// Returns the User or null on failure.
  Future<User?> signInAnonymously({String? displayName}) async {
    try {
      if (_auth.currentUser != null) {
        // BUG-NAME FIX: always update displayName even if already signed in.
        // Previously this returned early without calling updateDisplayName(),
        // so the name typed by the user was silently discarded and the old
        // name (e.g. 'BeatFlow User' from social_screen auto-sign-in) stayed.
        if (displayName != null && displayName.isNotEmpty) {
          await _auth.currentUser!.updateDisplayName(displayName);
        }
        return _auth.currentUser;
      }
      final cred = await _auth.signInAnonymously();
      if (displayName != null && displayName.isNotEmpty) {
        await cred.user?.updateDisplayName(displayName);
      }
      return cred.user;
    } catch (e) {
      debugPrint('[Together] signInAnonymously error: $e');
      return null;
    }
  }

  /// Returns a display-friendly name for the current user.
  String get displayName {
    final user = _auth.currentUser;
    if (user == null) return 'Guest';
    return user.displayName?.isNotEmpty == true
        ? user.displayName!
        : 'User ${user.uid.substring(0, 4).toUpperCase()}';
  }

  /// Update display name in Firebase Auth.
  Future<void> setDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
