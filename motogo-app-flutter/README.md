# MotoGo24 Flutter App

Flutter migration of the MotoGo24 motorcycle rental app (originally Capacitor/Cordova).

## Architecture

```
lib/
├── main.dart                    # Entry point, Supabase init
├── core/
│   ├── supabase_client.dart     # Supabase URL, keys, client
│   ├── router.dart              # GoRouter, 36 routes, auth guard
│   ├── theme.dart               # MotoGoColors, MotoGoTheme (dark)
│   ├── app_shell.dart           # Bottom nav (4 tabs), header banner
│   ├── banner_provider.dart     # Realtime app_settings.header_banner
│   ├── offline_guard.dart       # Connectivity check, overlay
│   ├── widget_styles.dart       # Shared card/badge/button styles
│   ├── i18n/                    # Translations (cs/en/de + 4 more)
│   ├── data/                    # Legal texts (VOP, GDPR)
│   ├── push/                    # FCM push notifications
│   └── native/                  # GPS service
├── features/
│   ├── auth/                    # Login, register, biometric, session
│   ├── home/                    # Home screen
│   ├── catalog/                 # Motorcycle grid, detail, search calendar
│   ├── booking/                 # Booking form, price calc, extras, address
│   ├── payment/                 # Stripe Checkout, saved cards, confirmation
│   ├── reservations/            # List, detail, edit, cancel, rating
│   ├── sos/                     # SOS incidents, replacement, photos
│   ├── shop/                    # E-shop, cart, vouchers
│   ├── profile/                 # Profile, consents, settings
│   ├── documents/               # Documents, OCR scanner (Mindee)
│   └── messages/                # Threads, chat, AI agent
```

## Tech Stack

- **Flutter 3.x** (Dart 3.2+)
- **Supabase** — auth, DB, realtime, storage, edge functions
- **Riverpod** — state management
- **GoRouter** — declarative routing with auth guard
- **Stripe** — Checkout redirect (via process-payment edge function)
- **Firebase** — push notifications (FCM)
- **Geolocator** — GPS
- **local_auth** — biometric login (fingerprint/Face ID)
- **Mindee** — OCR via scan-document edge function

## Backend

Backend remains unchanged (Supabase). See `SUPABASE_BACKEND_STATE_*.md` files.

- 61 tables, 37 RPC functions, 49 triggers
- 26 edge functions
- Stripe LIVE payments
- Twilio SMS/WhatsApp
- Resend emails

## Build

```bash
# Install dependencies
flutter pub get

# Run on Android (debug)
flutter run

# Build release APK
flutter build apk --release

# Build iOS
flutter build ios --release
```

## Configuration

1. **Firebase**: Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
2. **Signing**: Configure `key.properties` for release builds
3. **Supabase**: Keys are in `lib/core/supabase_client.dart`

## Migration from Capacitor

| Feature | Capacitor | Flutter |
|---------|-----------|---------|
| UI Framework | Vanilla JS + HTML | Flutter widgets |
| State | Global JS vars | Riverpod providers |
| Routing | Custom router.js | GoRouter |
| Payments | Stripe.js inline | Stripe Checkout redirect |
| Camera | @capacitor/camera | image_picker |
| GPS | @capacitor/geolocation | geolocator |
| Biometric | BiometricAuth plugin | local_auth |
| Push | Cordova local notif | firebase_messaging |
| Storage | localStorage | shared_preferences + flutter_secure_storage |
| Build | VoltBuilder | flutter build |
