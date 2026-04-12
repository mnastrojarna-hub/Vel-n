# Firebase Setup for MotoGo24 Flutter App

## Steps

### 1. Create Firebase Project
1. Go to https://console.firebase.google.com
2. Create project "MotoGo24" (or use existing)
3. Enable Cloud Messaging

### 2. Android Setup
1. Add Android app with package name `cz.motogo24.app`
2. Download `google-services.json`
3. Place at: `android/app/google-services.json`
4. Template file provided: `android/app/google-services.json.template`

### 3. iOS Setup (optional)
1. Add iOS app with bundle ID `cz.motogo24.app`
2. Download `GoogleService-Info.plist`
3. Place at: `ios/Runner/GoogleService-Info.plist`

### 4. Verify
```bash
flutter run
# Check logcat for: "FCM Token: ..."
```

### 5. Connect to Supabase
The FCM token is automatically saved to the `push_tokens` table in Supabase.
Push notifications are sent via Supabase Edge Functions (see `notification_log` table).

## Important
- `google-services.json` contains API keys — do NOT commit to public repos
- Add to `.gitignore`: `android/app/google-services.json`
- The `.template` file shows the required structure without real keys
