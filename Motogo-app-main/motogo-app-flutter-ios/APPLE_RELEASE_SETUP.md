# MotoGo24 — iOS / App Store release (v 1.1.0)

Tato složka je **duplikát `motogo-app-flutter` připravený pro Apple App Store**.
Staví ji Codemagic workflow **`motogo-ios-release`** (kořenový `codemagic.yaml`).

## Co se liší od Android verze

| Oblast | Android (`motogo-app-flutter`) | iOS (tato složka) |
|---|---|---|
| Platforma | `android/` | `ios/` (Xcode projekt Runner) |
| Peněženka | Google Pay | **Apple Pay** (nativní PKPaymentButton, merchant `merchant.cz.motogo24`) |
| Push | FCM (Android kanál) | **FCM → APNs** (`aps-environment: production`, backend `send-push` už APNS payload posílá) |
| In-app update | Google Play in_app_update | neaktivní (guard `Platform.isAndroid`); force-update dialog vede do App Store |
| Bundle/App ID | `com.motogo24.app` | `com.motogo24.app` (stejné — viz Firebase) |
| Verze | 1.1.0, build = $BUILD_NUMBER | **1.1.0**, build = $BUILD_NUMBER (Codemagic) |

Změněné soubory oproti Android kopii: `lib/features/payment/widgets/card_payment_sheet.dart`
(Apple Pay větev), `lib/core/update_check_provider.dart` (App Store URL), `pubspec.yaml` (komentáře).
Zbytek `lib/` + `assets/` je 1:1 kopie z 1.1.0.

## Jednorázové kroky před prvním buildem (ručně)

### 1. Apple Developer portál (developer.apple.com)
1. **Identifiers → App IDs** — registruj `com.motogo24.app` a zapni capabilities:
   - **Push Notifications**
   - **Apple Pay Payment Processing**
   - **Associated Domains**
2. **Identifiers → Merchant IDs** — registruj **`merchant.cz.motogo24`**
   (musí přesně odpovídat `Stripe.merchantIdentifier` v `lib/main.dart`)
   a přiřaď ho k App ID `com.motogo24.app`.

### 2. Stripe Dashboard (LIVE)
Settings → Payments → **Apple Pay** → *iOS certificates* → Add new application:
1. stáhni CSR od Stripe,
2. v Apple portálu u merchant ID `merchant.cz.motogo24` vytvoř
   **Apple Pay Payment Processing Certificate** z toho CSR,
3. vzniklý `.cer` nahraj zpět do Stripe.
Bez tohoto kroku Apple Pay platby selžou (karta v sheetu funguje i bez něj).

### 3. Firebase console (projekt `motogo24-518b4`)
1. Project settings → **Add app → iOS**, bundle ID **`com.motogo24.app`**.
2. Stáhni `GoogleService-Info.plist`.
3. Project settings → Cloud Messaging → **Apple app configuration** → nahraj
   **APNs Authentication Key (.p8)** (vytvoř v Apple portálu → Keys → APNs)
   + Key ID + Team ID. Bez něj FCM nedoručí push na iOS.

### 4. Codemagic
1. **Teams → Integrations → Developer Portal** — přidej App Store Connect API
   klíč a pojmenuj ho **`motogo24_app_store_connect`** (název odkazovaný ve workflow).
   Klíč vytvoř v App Store Connect → Users and Access → Integrations → API Keys
   s rolí **App Manager** + zaškrtnutým „Access to Certificates, Identifiers &
   Profiles" — slabší role (Developer) nestačí na automatické podepisování
   a nahrávání do TestFlightu.
2. **Env group `firebase_ios`** se secure proměnnou **`GOOGLE_SERVICE_INFO_PLIST`**:
   `base64 -i GoogleService-Info.plist | pbcopy` → vlož hodnotu.
   CI soubor vytvoří v `ios/Runner/` před buildem (do gitu se necommituje).
3. Spusť workflow **`motogo-ios-release`** → podepsaná IPA jde automaticky
   do **TestFlightu** (do App Store recenze se posílá ručně z ASC).

### 5. App Store Connect
1. **My Apps → +** — založ aplikaci „MotoGo24", bundle ID `com.motogo24.app`,
   primární jazyk čeština, verze **1.1.0**.
2. Po založení zkopíruj **Apple ID** aplikace (App Information) a doplň ho do
   `lib/core/update_check_provider.dart` (konstanta `_appStoreUrl`, místo `APPLE_ID`).
3. Vyplň privacy (App Privacy: poloha, fotky, kontaktní údaje, platby),
   screenshoty iPhone (target je iPhone-only — iPad screenshoty nejsou potřeba).

### 6. Universal linky (volitelné, pro https://motogo24.cz/app deep linky)
Na web nasaď `https://motogo24.cz/.well-known/apple-app-site-association`
(Content-Type `application/json`, bez přípony):
```json
{ "applinks": { "apps": [], "details": [
  { "appID": "TEAMID.com.motogo24.app", "paths": ["/app/*"] } ] } }
```
`TEAMID` = Apple Team ID. Bez něj funguje vše ostatní (Stripe návrat používá
custom scheme `motogo24://payment`, který je v Info.plist).

## Audit oprávnění (proti reálnému použití v kódu)

| Oprávnění | Kód, který ho používá | Info.plist klíč | Podfile makro |
|---|---|---|---|
| Notifikace | PushService / PermissionService / FCM | `UIBackgroundModes: remote-notification` + entitlement `aps-environment` | `PERMISSION_NOTIFICATIONS=1` |
| Kamera | document_camera/scanner (`enableAudio: false`), image_picker (SOS) | `NSCameraUsageDescription` | `PERMISSION_CAMERA=1` |
| Fotky (galerie) | image_picker — nahrání dokladu/SOS fotky | `NSPhotoLibraryUsageDescription` (+ `...AddUsageDescription`) | `PERMISSION_PHOTOS=1` |
| Poloha (when-in-use) | GpsService (SOS, mapa, vzdálenost přistavení) | `NSLocationWhenInUseUsageDescription` | `PERMISSION_LOCATION=1` |
| Face ID | biometric_service (local_auth) | `NSFaceIDUsageDescription` | — (mimo permission_handler) |
| Mikrofon | **nepoužívá se** (kamera má enableAudio:false) | klíč přítomen jen pro statickou analýzu camera pluginu | `PERMISSION_MICROPHONE=0` |
| Apple Pay | card_payment_sheet (PlatformPayButton) | — | entitlement `com.apple.developer.in-app-payments` |
| Universal links | supabase app_links (`/app` deep linky) | `CFBundleURLTypes: motogo24://` | entitlement `associated-domains` |

Vše ostatní (kontakty, kalendář, Bluetooth, tracking…) je v Podfile explicitně
vypnuto (`=0`) → nedostane se do binárky a App Review se na to nemůže ptát.

**App Review požadavky — zkontrolováno:**
- **Smazání účtu v appce (5.1.1v):** ANO — Profil → „Smazat účet" volá RPC
  `delete_customer_account`.
- **Sign in with Apple (4.8):** NEVYŽADUJE SE — appka nemá žádný social login
  (jen e-mail/heslo + biometrika).
- **Privacy manifest (2024+):** `ios/Runner/PrivacyInfo.xcprivacy` přibalen
  (žádný tracking; required-reason API kryjí manifesty pluginů).
- **Šifrování:** `ITSAppUsesNonExemptEncryption=false` (jen standardní HTTPS).

## Backend — ověřeno, beze změn
- `push_tokens.platform` už podporuje `ios` (PushService ho posílá).
- Edge fn `send-push` posílá APNS payload vedle Android kanálu → iOS push
  funguje hned po nahrání APNs klíče do Firebase (žádná SQL změna).
- `process-payment` / `webhook-receiver` jsou na peněžence nezávislé
  (Apple Pay potvrzuje stejný PaymentIntent jako Google Pay/karta).

## Lokální build (vyžaduje macOS + Xcode)
```bash
cd Motogo-app-main/motogo-app-flutter-ios
# stáhni GoogleService-Info.plist do ios/Runner/ (krok 3)
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```
