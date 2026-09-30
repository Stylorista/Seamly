import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web client ID from Google Cloud Console (OAuth 2.0 Web application).
/// Passed with --dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com
class GoogleConfig {
  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isConfigured => webClientId.isNotEmpty;
}

/// Small wrapper around google_sign_in v7.
///
/// Web uses the GIS button (renderButton) + authenticationEvents stream;
/// mobile/desktop use initialize() + authenticate().
class GoogleSignInService {
  GoogleSignInService._();

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: GoogleConfig.isConfigured ? GoogleConfig.webClientId : null,
      serverClientId: GoogleConfig.isConfigured
          ? GoogleConfig.webClientId
          : null,
    );
    _initialized = true;
  }

  /// Mobile/desktop interactive sign-in. Returns the Google ID token.
  /// Throws a [GoogleSignInException] or [StateError] with a human message.
  static Future<String> signInWithGoogle() async {
    await ensureInitialized();
    if (kIsWeb) {
      throw StateError(
        'On web, use the Google button instead of direct sign-in.',
      );
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(
        'Google did not return a sign-in token. Please try again.',
      );
    }
    return idToken;
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best-effort: backend session logout is authoritative.
    }
  }
}
