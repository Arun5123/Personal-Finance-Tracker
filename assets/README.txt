assets/app_logo.png
========================================
ACTION REQUIRED: save your SheetFin logo here
========================================
The image you shared in chat (circular SheetFin logo) should be saved to:

/Users/arun/Desktop/personal_finance_tracker/assets/app_logo.png

How to save it:
1. Right-click / long-press the SheetFin image in chat and Save/Download it.
2. Move/rename the downloaded file to:
   assets/app_logo.png  (inside personal_finance_tracker/)
3. Recommended: PNG, square, at least 512x512.
   Your shared image is already square-ish and works perfectly.

Why code already handles a missing file:
- pubspec.yaml already declares: assets/app_logo.png
- login_screen, home_screen AppBar, and splash all use Image.asset
  with errorBuilder fallbacks, so the app still runs before you add it.
  Once you add the PNG, the real SheetFin logo appears automatically.

After adding the file, run (when Flutter is available):
  flutter pub get
  flutter run

New packages used by this update (need `flutter pub get` once):
  path_provider (temp file for Excel/CSV export)
  share_plus (OS share sheet for "Download Excel")
