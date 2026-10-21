import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants/cloud_config.dart';

/// Phase E.20: Google Drive cloud sync via OAuth2 PKCE + Drive REST API.
///
/// This service implements the full cloud sync lifecycle:
/// 1. **Authenticate** via OAuth2 PKCE using `flutter_appauth` (opens
///    a Chrome Custom Tab on Android for the Google sign-in flow).
/// 2. **Store tokens** securely via `flutter_secure_storage` (backed
///    by Android Keystore — tokens survive app restarts).
/// 3. **Upload/download** `.epp` project files to/from Google Drive
///    using the Drive REST API v3.
/// 4. **List/delete** synced projects.
/// 5. **Auto-refresh** expired access tokens using the stored refresh
///    token.
///
/// ## Google Cloud Console setup
///
/// Before this service can be used, you must:
/// 1. Create a Google Cloud project (or use an existing one).
/// 2. Enable the Google Drive API.
/// 3. Create an OAuth2 client ID (Android type) with your app's
///    SHA-1 fingerprint.
/// 4. Add the redirect URI `com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect`
///    to the authorized redirect URIs.
/// 5. Fill in the client ID in `lib/core/constants/cloud_config.dart`.
///
/// See `docs/GOOGLE_DRIVE_SETUP.md` for the full walkthrough.
///
/// ## Security
///
/// - Access tokens are short-lived (~1 hour) and auto-refreshed.
/// - Refresh tokens are stored in Android Keystore via
///   `flutter_secure_storage` (never in SharedPreferences).
/// - The app requests the `drive.file` scope, which only grants
///   access to files created or opened by the app — not the user's
///   entire Drive.
class GoogleDriveSync {
  GoogleDriveSync._();
  static final GoogleDriveSync instance = GoogleDriveSync._();

  static const FlutterAppAuth _appAuth = FlutterAppAuth();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Google OAuth2 client ID (from Cloud Console).
  /// Loaded from `cloud_config.dart` — see E.20.3.
  String get _clientId => CloudConfig.googleDriveClientId;

  /// The redirect URI. For Android apps using AppAuth, this is
  /// `com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect`.
  String get _redirectUri =>
      'com.googleusercontent.apps.$_clientId:/oauth2redirect';

  /// OAuth2 scopes — `drive.file` only grants access to files created
  /// or opened by this app, not the user's entire Drive. This is the
  /// least-privilege scope for our use case.
  static const _scopes = [
    'https://www.googleapis.com/auth/drive.file',
    'openid',
    'email',
  ];

  /// The folder name where EDITORS-PRO projects are stored on Drive.
  /// Created on first upload if it doesn't exist.
  static const _driveFolderName = 'EDITORS-PRO';

  // ─── Secure storage keys ──────────────────────────────────────────
  static const _keyAccessToken = 'gdrive_access_token';
  static const _keyRefreshToken = 'gdrive_refresh_token';
  static const _keyTokenExpiry = 'gdrive_token_expiry';
  static const _keyAccountEmail = 'gdrive_account_email';
  static const _keyDriveFolderId = 'gdrive_folder_id';

  // ─── Current token state (in-memory cache) ────────────────────────
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _accountEmail;
  String? _driveFolderId;

  /// Whether the user is currently authenticated.
  ///
  /// Returns `true` if there's a stored access token or refresh token
  /// (the access token may be expired but can be refreshed).
  Future<bool> isAuthenticated() async {
    await _loadTokensFromStorage();
    if (_refreshToken != null) return true;
    if (_accessToken != null && _tokenExpiry != null) {
      return DateTime.now().isBefore(_tokenExpiry!);
    }
    return false;
  }

  /// Get the authenticated account email, or `null` if not authenticated.
  Future<String?> getAccountEmail() async {
    await _loadTokensFromStorage();
    return _accountEmail;
  }

  /// Start the OAuth2 PKCE authentication flow.
  ///
  /// Opens a Chrome Custom Tab with the Google sign-in page. After the
  /// user signs in and grants permission, Google redirects back to the
  /// app with an authorization code, which is exchanged for access and
  /// refresh tokens.
  ///
  /// Returns the account email on success, or throws on failure.
  Future<String> authenticate() async {
    if (_clientId.isEmpty) {
      throw StateError(
        'Google Drive client ID not configured. '
        'See docs/GOOGLE_DRIVE_SETUP.md for setup instructions.',
      );
    }

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint:
                'https://accounts.google.com/o/oauth2/v2/auth',
            tokenEndpoint: 'https://oauth2.googleapis.com/token',
          ),
          scopes: _scopes,
          promptValues: ['select_account'],
        ),
      );

      if (result.accessToken == null) {
        throw StateError('OAuth2 flow returned no access token');
      }

      _accessToken = result.accessToken;
      _refreshToken = result.refreshToken;
      _tokenExpiry = result.accessTokenExpirationDateTime;
      _accountEmail = _extractEmailFromIdToken(result.idToken);

      await _persistTokens();

      developer.log(
        'Google Drive authentication successful. '
        'Account: $_accountEmail, '
        'Token expires: $_tokenExpiry',
        name: 'GoogleDriveSync',
      );

      return _accountEmail ?? 'unknown@gmail.com';
    } catch (e, st) {
      developer.log(
        'Google Drive authentication failed: $e',
        name: 'GoogleDriveSync',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Sign out and clear all stored tokens.
  Future<void> signOut() async {
    // Try to revoke the token on Google's side.
    if (_accessToken != null) {
      try {
        await http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          body: {'token': _accessToken},
        );
      } catch (e) {
        developer.log(
          'Token revocation failed (non-fatal): $e',
          name: 'GoogleDriveSync',
        );
      }
    }

    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _accountEmail = null;
    _driveFolderId = null;

    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyTokenExpiry);
    await _secureStorage.delete(key: _keyAccountEmail);
    await _secureStorage.delete(key: _keyDriveFolderId);

    developer.log('Signed out from Google Drive', name: 'GoogleDriveSync');
  }

  /// Upload a project `.epp` file to Google Drive.
  ///
  /// Uses `http.MultipartRequest` to build a multipart/related body
  /// with the JSON metadata part and the binary file content part.
  /// If a file with the same name already exists in the EDITORS-PRO
  /// folder, it's updated (not duplicated).
  ///
  /// Returns the Drive file ID on success.
  Future<String> uploadProject(String projectId, String filePath) async {
    final token = await _ensureValidToken();
    final folderId = await _ensureFolderExists(token);

    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Project file not found', filePath);
    }

    final bytes = await file.readAsBytes();
    final fileName = '$projectId.epp';

    // Check if a file with this name already exists in the folder.
    final existingFileId = await _findFileByName(token, folderId, fileName);

    // Build the multipart request. Google Drive's API expects a
    // multipart/related body with exactly two parts:
    // 1. application/json — the file metadata (name, parents)
    // 2. application/octet-stream — the raw file bytes
    //
    // We use http.MultipartRequest instead of manual string concatenation
    // because the latter corrupts binary data (String.fromCharCodes
    // mangles bytes > 127 into multi-byte UTF-8 sequences).
    final uri = existingFileId != null
        ? Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$existingFileId'
            '?uploadType=multipart&fields=id,name,modifiedTime,size',
          )
        : Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files'
            '?uploadType=multipart&fields=id,name,modifiedTime,size',
          );

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token';

    // Metadata part — set Content-Type via headers since MultipartFile
    // doesn't accept a string contentType directly.
    final metadata = {
      'name': fileName,
      if (existingFileId == null) 'parents': [folderId],
    };
    request.files.add(
      http.MultipartFile.fromString(
        'metadata',
        jsonEncode(metadata),
        contentType: MediaType('application', 'json', {'charset': 'UTF-8'}),
      ),
    );

    // File content part — pass raw bytes directly. MultipartFile.fromBytes
    // defaults to application/octet-stream which is correct for binary data.
    request.files.add(
      http.MultipartFile.fromBytes(
        'media',
        bytes,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Drive upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fileId = json['id'] as String;
    developer.log(
      'Uploaded $fileName to Drive (fileId=$fileId, ${bytes.length} bytes)',
      name: 'GoogleDriveSync',
    );
    return fileId;
  }

  /// Download a project `.epp` file from Google Drive.
  ///
  /// Saves the file to [destFilePath]. Returns the file size in bytes.
  Future<int> downloadProject(String projectId, String destFilePath) async {
    final token = await _ensureValidToken();
    final folderId = await _ensureFolderExists(token);
    final fileName = '$projectId.epp';

    final fileId = await _findFileByName(token, folderId, fileName);
    if (fileId == null) {
      throw Exception('Project "$fileName" not found on Google Drive');
    }

    final response = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Drive download failed (${response.statusCode}): ${response.body}',
      );
    }

    final file = File(destFilePath);
    await file.writeAsBytes(response.bodyBytes);

    developer.log(
      'Downloaded $fileName from Drive (${response.bodyBytes.length} bytes)',
      name: 'GoogleDriveSync',
    );
    return response.bodyBytes.length;
  }

  /// List all synced projects on Google Drive.
  ///
  /// Returns a list of [DriveProjectEntry] records with the project ID
  /// (extracted from the filename), modification time, and size.
  Future<List<DriveProjectEntry>> listProjects() async {
    final token = await _ensureValidToken();
    final folderId = await _ensureFolderExists(token);

    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        "?q='$folderId' in parents and trashed=false and name contains '.epp'"
        '&fields=files(id,name,modifiedTime,size,mimeType)'
        '&orderBy=modifiedTime desc',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Drive list failed (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final files = json['files'] as List? ?? [];

    return files
        .map<DriveProjectEntry>((f) {
          final name = f['name'] as String? ?? '';
          // Strip '.epp' extension to get the project ID.
          final projectId =
              name.endsWith('.epp') ? name.substring(0, name.length - 4) : name;
          return DriveProjectEntry(
            projectId: projectId,
            name: projectId,
            cloudFileId: f['id'] as String? ?? '',
            modifiedAt: DateTime.parse(f['modifiedTime'] as String? ?? '')
                .millisecondsSinceEpoch,
            sizeBytes: int.tryParse(f['size'] as String? ?? '0') ?? 0,
          );
        })
        .where((e) => e.projectId.isNotEmpty)
        .toList();
  }

  /// Delete a project from Google Drive.
  Future<void> deleteProject(String projectId) async {
    final token = await _ensureValidToken();
    final folderId = await _ensureFolderExists(token);
    final fileName = '$projectId.epp';

    final fileId = await _findFileByName(token, folderId, fileName);
    if (fileId == null) {
      developer.log(
        'deleteProject: $fileName not found on Drive (already deleted?)',
        name: 'GoogleDriveSync',
      );
      return;
    }

    final response = await http.delete(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'Drive delete failed (${response.statusCode}): ${response.body}',
      );
    }

    developer.log(
      'Deleted $fileName from Drive',
      name: 'GoogleDriveSync',
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────

  /// Ensure we have a valid (non-expired) access token, refreshing if needed.
  Future<String> _ensureValidToken() async {
    await _loadTokensFromStorage();

    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now()
            .isBefore(_tokenExpiry!.subtract(const Duration(minutes: 1)))) {
      return _accessToken!;
    }

    // Token is expired or missing — try to refresh.
    if (_refreshToken == null) {
      throw StateError(
        'Not authenticated. Call authenticate() first.',
      );
    }

    return _refreshAccessToken();
  }

  /// Refresh the access token using the stored refresh token.
  Future<String> _refreshAccessToken() async {
    try {
      final result = await _appAuth.token(
        TokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint:
                'https://accounts.google.com/o/oauth2/v2/auth',
            tokenEndpoint: 'https://oauth2.googleapis.com/token',
          ),
          refreshToken: _refreshToken,
          scopes: _scopes,
        ),
      );

      if (result.accessToken == null) {
        throw StateError('Token refresh returned no access token');
      }

      _accessToken = result.accessToken;
      if (result.refreshToken != null) {
        _refreshToken = result.refreshToken;
      }
      _tokenExpiry = result.accessTokenExpirationDateTime;

      await _persistTokens();

      developer.log(
        'Refreshed Google Drive access token (expires: $_tokenExpiry)',
        name: 'GoogleDriveSync',
      );
      return _accessToken!;
    } catch (e, st) {
      developer.log(
        'Token refresh failed: $e',
        name: 'GoogleDriveSync',
        error: e,
        stackTrace: st,
      );
      // If refresh fails, the refresh token may be revoked. Clear all
      // tokens so the user is prompted to re-authenticate.
      await signOut();
      rethrow;
    }
  }

  /// Ensure the EDITORS-PRO folder exists on Drive, creating it if needed.
  /// Returns the folder's file ID.
  Future<String> _ensureFolderExists(String token) async {
    if (_driveFolderId != null) return _driveFolderId!;

    // Search for an existing folder with our name.
    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        "?q=mimeType='application/vnd.google-apps.folder' and name='$_driveFolderName' and trashed=false"
        '&fields=files(id,name)',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final files = json['files'] as List? ?? [];
      if (files.isNotEmpty) {
        _driveFolderId = files[0]['id'] as String;
        await _secureStorage.write(
          key: _keyDriveFolderId,
          value: _driveFolderId,
        );
        return _driveFolderId!;
      }
    }

    // Folder doesn't exist — create it.
    final createResponse = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id,name'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': _driveFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    if (createResponse.statusCode != 200) {
      throw Exception(
        'Failed to create Drive folder (${createResponse.statusCode}): ${createResponse.body}',
      );
    }

    final createJson = jsonDecode(createResponse.body) as Map<String, dynamic>;
    _driveFolderId = createJson['id'] as String;
    await _secureStorage.write(key: _keyDriveFolderId, value: _driveFolderId);

    developer.log(
      'Created Drive folder "$_driveFolderName" (id=$_driveFolderId)',
      name: 'GoogleDriveSync',
    );
    return _driveFolderId!;
  }

  /// Find a file by name within a folder. Returns the file ID or `null`.
  Future<String?> _findFileByName(
    String token,
    String folderId,
    String fileName,
  ) async {
    final encodedName = Uri.encodeQueryComponent(fileName);
    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        "?q='$folderId' in parents and name='$encodedName' and trashed=false"
        '&fields=files(id,name)',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final files = json['files'] as List? ?? [];
    if (files.isEmpty) return null;
    return files[0]['id'] as String;
  }

  /// Load tokens from secure storage into the in-memory cache.
  Future<void> _loadTokensFromStorage() async {
    if (_accessToken != null) return; // Already loaded

    _accessToken = await _secureStorage.read(key: _keyAccessToken);
    _refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    _accountEmail = await _secureStorage.read(key: _keyAccountEmail);
    _driveFolderId = await _secureStorage.read(key: _keyDriveFolderId);

    final expiryStr = await _secureStorage.read(key: _keyTokenExpiry);
    if (expiryStr != null) {
      _tokenExpiry = DateTime.tryParse(expiryStr);
    }
  }

  /// Persist current tokens to secure storage.
  Future<void> _persistTokens() async {
    if (_accessToken != null) {
      await _secureStorage.write(key: _keyAccessToken, value: _accessToken);
    }
    if (_refreshToken != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: _refreshToken);
    }
    if (_tokenExpiry != null) {
      await _secureStorage.write(
        key: _keyTokenExpiry,
        value: _tokenExpiry!.toIso8601String(),
      );
    }
    if (_accountEmail != null) {
      await _secureStorage.write(key: _keyAccountEmail, value: _accountEmail);
    }
  }

  /// Extract the email from a Google ID token (JWT).
  ///
  /// The ID token is a JWT whose payload contains the user's email
  /// in the `email` claim. We decode it without verifying the signature
  /// (verification happens on Google's side during the OAuth2 exchange).
  String? _extractEmailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return null;
      // JWT payload is base64url-encoded (no padding).
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['email'] as String?;
    } catch (e) {
      developer.log(
        'Failed to extract email from ID token: $e',
        name: 'GoogleDriveSync',
      );
      return null;
    }
  }
}

/// A project entry returned by [GoogleDriveSync.listProjects].
class DriveProjectEntry {
  const DriveProjectEntry({
    required this.projectId,
    required this.name,
    required this.cloudFileId,
    required this.modifiedAt,
    required this.sizeBytes,
  });
  final String projectId;
  final String name;
  final String cloudFileId;
  final int modifiedAt;
  final int sizeBytes;
}
