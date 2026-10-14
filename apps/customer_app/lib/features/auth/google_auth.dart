import 'package:google_sign_in/google_sign_in.dart';

/// The Web client ID from Google Cloud, given at build time with
/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. The server accepts tokens for
/// the same ID (GOOGLE_CLIENT_IDS). Empty means Google sign-in is not set up.
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Google sign-in. Google shows its own account picker; the app only gets an
/// ID token, which the server verifies. No password ever passes through us.
abstract final class GoogleAuth {
  static bool get configured => _serverClientId.isNotEmpty;
  static bool _ready = false;

  /// Returns an ID token, or null if the person closed the picker.
  static Future<String?> idToken() async {
    final g = GoogleSignIn.instance;
    if (!_ready) {
      await g.initialize(serverClientId: _serverClientId);
      _ready = true;
    }
    try {
      final account = await g.authenticate(scopeHint: const ['email', 'profile']);
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Forgets the chosen Google account on this phone (on sign out).
  static Future<void> signOut() async {
    if (!_ready) return;
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Nothing to do if Google is not reachable.
    }
  }
}
