import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

/// Service responsible for handling Google Sign-In and providing
/// authenticated API clients for Google Drive and Google Sheets.
class GoogleAuthService {
  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope, // https://www.googleapis.com/auth/drive.file
    sheets.SheetsApi.spreadsheetsScope, // https://www.googleapis.com/auth/spreadsheets
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentAccount;
  String? _lastError;

  String? get lastError => _lastError;

  /// Returns true if a user is currently signed in.
  bool get isSignedIn => _currentAccount != null;

  /// Returns the signed-in user's email address (if any).
  String? get userEmail => _currentAccount?.email;

  /// Returns the signed-in user's display name (if any).
  String? get userDisplayName => _currentAccount?.displayName;

  /// Attempts to sign in silently (restore previous session) if possible.
  Future<bool> trySilentSignIn() async {
    try {
      _currentAccount = await _googleSignIn.signInSilently();
      _lastError = null;
      return _currentAccount != null;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Prompts the user to sign in with their Google account.
  Future<bool> signIn() async {
    try {
      _currentAccount = await _googleSignIn.signIn();
      if (_currentAccount == null) {
        _lastError = 'No Google account was selected. The sign-in flow was canceled.';
        return false;
      }
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Signs the user out and clears the cached account.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentAccount = null;
    _lastError = null;
  }

  /// Returns an authenticated [drive.DriveApi] client.
  /// Throws [StateError] if the user is not signed in.
  Future<drive.DriveApi> get driveApi async {
    final account = _currentAccount;
    if (account == null) {
      throw StateError('User is not signed in. Call signIn() first.');
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      throw StateError('Unable to authenticate with Google.');
    }
    return drive.DriveApi(client);
  }

  /// Returns an authenticated [sheets.SheetsApi] client.
  /// Throws [StateError] if the user is not signed in.
  Future<sheets.SheetsApi> get sheetsApi async {
    final account = _currentAccount;
    if (account == null) {
      throw StateError('User is not signed in. Call signIn() first.');
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      throw StateError('Unable to authenticate with Google.');
    }
    return sheets.SheetsApi(client);
  }
}