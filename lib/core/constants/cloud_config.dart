/// Phase E.20: Cloud sync configuration.
///
/// This file contains the OAuth2 client IDs for Google Drive sync.
/// The values come from the Google Cloud Console — see
/// `docs/GOOGLE_DRIVE_SETUP.md` for setup instructions.
///
/// ## Security note
///
/// OAuth2 client IDs for mobile apps are NOT secret — they're shipped
/// in the app binary and can be extracted. This is by design: the
/// security model relies on the OAuth2 PKCE flow + the redirect URI
/// being registered to your app's signing key, not on the client ID
/// being secret. Google's documentation explicitly states that
/// client IDs for installed/mobile apps don't need to be kept
/// confidential.
///
/// See: https://developers.google.com/identity/protocols/oauth2/native-app
class CloudConfig {
  CloudConfig._();

  /// Google OAuth2 client ID for the Android app.
  ///
  /// Format: `<numeric>-<random>.apps.googleusercontent.com`
  ///
  /// To get this:
  /// 1. Go to https://console.cloud.google.com/
  /// 2. Select your project → APIs & Services → Credentials
  /// 3. Create Credentials → OAuth client ID → Android
  /// 4. Enter your app's package name (`com.editorspro.editors_pro`)
  ///    and SHA-1 fingerprint (from your signing key)
  /// 5. Copy the client ID here
  ///
  /// Leave empty to disable Google Drive sync (the UI will show an
  /// error directing users to set up the integration).
  static const String googleDriveClientId = '';

  /// Whether Google Drive sync is configured (client ID is set).
  static bool get isGoogleDriveConfigured => googleDriveClientId.isNotEmpty;
}
