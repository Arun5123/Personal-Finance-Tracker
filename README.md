# 📊 Personal Finance Tracker

A production-ready Flutter app for tracking rent collections & monthly payments using **your personal Google Drive & Google Sheets** as the backend — **100% free, no servers**.

## ✨ Features
- 🔐 Google Sign-In (OAuth 2.0)
- 📁 Auto-creates `Personal_Finance_Tracker` spreadsheet in your Drive
- 📑 Dynamic Sheet creation ("House Rent", "Monthly Collection")
- 🧩 Custom fields with types: `Date`, `Number`, `Text`
- 📝 Dynamic forms (DatePicker for dates, numeric keyboard for numbers)
- 📊 View all entries in a scrollable table

## 🚀 Setup

### 1. Google Cloud Console (CRITICAL)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. **Create Project** → e.g. `finance-tracker`
3. **Enable APIs** (APIs & Services → Library):
   - Google Drive API
   - Google Sheets API
4. **OAuth consent screen** (APIs & Services → OAuth consent screen):
   - User type: **External**
   - App name: `Personal Finance Tracker`
   - Add scopes: `https://www.googleapis.com/auth/drive.file` and `https://www.googleapis.com/auth/spreadsheets`
5. **Create OAuth Client ID** (APIs & Services → Credentials → + Create Credentials):
   - **Android**: Application type = Android
     - Get your SHA-1:
       ```bash
       cd android && ./gradlew signingReport
       ```
       (Look for SHA1 under `debug` → `debug.keystore`, e.g. `5E:8F:16:...` — remove colons)
     - Package name: `com.example.personal_finance_tracker`
   - **iOS** (optional): Application type = iOS, enter your bundle ID
6. **Add a test user** (required while the consent screen is in Testing):
   - Open OAuth consent screen → **Audience** → **Test users**
   - Add the Google account you will use in the app
   - Use the same Cloud project for the OAuth client and enabled APIs

### 2. Flutter Setup

Your Flutter SDK is located at: `/Users/arun/Downloads/flutter`

**Option A — Run the setup script** (recommended):
```bash
cd /Users/arun/Desktop/personal_finance_tracker
./setup.sh
```

**Option B — Manual setup**:
```bash
cd /Users/arun/Desktop/personal_finance_tracker
/Users/arun/Downloads/flutter/bin/flutter pub get
```

### 3. Android

- `android/app/src/main/AndroidManifest.xml` — already configured (INTERNET permission)
- Add your `google-services.json` (if using Firebase helper) OR ensure the OAuth client ID SHA-1 matches your debug keystore

### 4. iOS (Optional)

- Add `GoogleService-Info.plist` to `ios/Runner/`
- Add your `REVERSED_CLIENT_ID` to `Info.plist` → `CFBundleURLTypes`

### 5. Run

```bash
flutter run
```

## 🏗️ Architecture

```
lib/
├── main.dart                      # Entry, routing, Provider setup
├── models/
│   ├── field_definition.dart      # FieldType + FieldDefinition
│   └── sheet.dart                # Sheet (tab metadata)
├── services/
│   ├── google_auth_service.dart   # Sign-in + OAuth scopes
│   ├── google_sheets_service.dart # Drive/Sheets API ops
│   └── local_storage_service.dart # SharedPreferences cache
├── state/
│   └── app_state.dart             # Provider (ChangeNotifier)
└── screens/
    ├── login_screen.dart
    ├── home_screen.dart
    ├── create_sheet_screen.dart
    ├── data_entry_screen.dart
    └── data_view_screen.dart
```

## 📦 Dependencies
| Package | Purpose |
|---------|---------|
| `google_sign_in` | OAuth authentication |
| `googleapis` | Drive & Sheets API clients |
| `extension_google_sign_in_as_googleapis_auth` | Bridge between sign-in & APIs |
| `shared_preferences` | Local metadata storage |
| `provider` | State management |
| `intl` | Date formatting |
| `http` | HTTP client |
| `uuid` | Unique IDs |

## 🔒 Privacy
- 100% free — uses only your Google Drive/Sheets quota
- Data stays in your personal Google Drive
- Uses `drive.file` scope (only accesses files created by the app)

## 🛠️ Troubleshooting

| Issue | Fix |
|-------|-----|
| `DEVELOPER_ERROR` or error code `10` | Check that the installed app's signing SHA-1 and package name match the Android OAuth client. Uninstall/reinstall the app after changing credentials. |
| Error `12500`, `12501`, or `12502` | Check the OAuth consent screen, add your account as a test user, and make sure Google Play Services is available and updated. `12501` commonly means the account canceled the picker. |
| "Access blocked: app has not completed verification" | Add the account under OAuth consent screen → Audience → Test users, or complete Google verification before production use. |
| "Failed to init Sheets" | Ensure Drive & Sheets APIs are enabled |
| No spreadsheet found | App creates it automatically on first login |