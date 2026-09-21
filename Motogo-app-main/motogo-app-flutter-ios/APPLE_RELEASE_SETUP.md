# MotoGo24 — iOS / App Store release (v 4.0.0)

Tato složka je **duplikát `motogo-app-flutter` připravený pro Apple App Store**.
Staví ji Codemagic workflow **`motogo-ios-release`** (kořenový `codemagic.yaml`).

## Firemní Apple účet (od 8/2026) — klíčové identifikátory

Aplikace přešla z původního individuálního Apple účtu na **firemní Apple
Developer účet Mnástrojárna s.r.o.** Apple nepustí staré identifikátory na
jiný účet, proto strategie „nový iOS Bundle ID" — Android/Google Play se nemění.

| Identifikátor | Hodnota | Poznámka |
|---|---|---|
| Apple Developer Team ID | `YP7TF3APAV` | Mnástrojárna s.r.o. |
| iOS Bundle ID | `com.motogo24.rental` | dříve `com.motogo24.app` (to zůstává jen Androidu) |
| Apple Pay Merchant ID | `merchant.cz.motogo24.rental` | dříve `merchant.cz.motogo24` |
| App Store Connect Apple ID | `6806045151` | SKU `motogo24-ios`, název „MotoGO24 - Půjčovna motorek" |

## Co se liší od Android verze

| Oblast | Android (`motogo-app-flutter`) | iOS (tato složka) |
|---|---|---|
| Platforma | `android/` | `ios/` (Xcode projekt Runner) |
| Peněženka | Google Pay | **Apple Pay** (nativní PKPaymentButton, merchant `merchant.cz.motogo24.rental`) |
| Push | FCM (Android kanál) | **FCM → APNs** (`aps-environment: production`, backend `send-push` už APNS payload posílá) |
| In-app update | Google Play in_app_update | neaktivní (guard `Platform.isAndroid`); force-update dialog vede do App Store |
| Bundle/App ID | `com.motogo24.app` | **`com.motogo24.rental`** (firemní účet — viz tabulka výše) |
| Verze | 4.0.0, build = $BUILD_NUMBER | **4.0.0**, build = $BUILD_NUMBER (Codemagic) |

Změněné soubory oproti Android kopii: `lib/features/payment/widgets/card_payment_sheet.dart`
(Apple Pay větev), `lib/core/update_check_provider.dart` (App Store URL), `pubspec.yaml` (komentáře).
Zbytek `lib/` + `assets/` je 1:1 kopie z 4.0.0.

## Jednorázové kroky před prvním buildem (ručně)

### 1. Apple Developer portál (developer.apple.com, Team `YP7TF3APAV`)
1. **Identifiers → App IDs** — registruj `com.motogo24.rental` a zapni capabilities:
   - **Push Notifications**
   - **Apple Pay Payment Processing**
   - **Associated Domains**
2. **Identifiers → Merchant IDs** — registruj **`merchant.cz.motogo24.rental`**
   (musí přesně odpovídat `Stripe.merchantIdentifier` v `lib/main.dart`)
   a přiřaď ho k App ID `com.motogo24.rental`.

### 2. Stripe Dashboard (LIVE)
Settings → Payments → **Apple Pay** → *iOS certificates* → Add new application:
1. stáhni CSR od Stripe,
2. v Apple portálu u merchant ID `merchant.cz.motogo24.rental` vytvoř
   **Apple Pay Payment Processing Certificate** z toho CSR,
3. vzniklý `.cer` nahraj zpět do Stripe.
Bez tohoto kroku Apple Pay platby selžou (karta v sheetu funguje i bez něj).

### 3. Firebase console (projekt `motogo24-518b4`)
1. Project settings → **Add app → iOS**, bundle ID **`com.motogo24.rental`**
   (nová iOS appka; původní registrace pro `com.motogo24.app` zůstává Androidu).
2. Stáhni nový `GoogleService-Info.plist` a přenastav jeho base64 do env var
   `GOOGLE_SERVICE_INFO_PLIST` v Codemagicu (env group `firebase_ios`).
3. Project settings → Cloud Messaging → **Apple app configuration** → nahraj
   **APNs Authentication Key (.p8)** (vytvoř v Apple portálu firemního účtu →
   Keys → APNs) + Key ID + Team ID `YP7TF3APAV`. Bez něj FCM nedoručí push na iOS.

### 4. Codemagic
1. **Teams → Integrations → Developer Portal** — přidej App Store Connect API
   klíč a pojmenuj ho **`motogo24_app_store_connect`** (název odkazovaný ve workflow).
   Po přechodu na firemní účet přepoj tuto integraci na API klíč NOVÉHO účtu
   (název integrace zůstává stejný, mění se jen klíč).
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
1. **My Apps → +** — appka „MotoGO24 - Půjčovna motorek" je založená na firemním
   účtu: bundle ID `com.motogo24.rental`, SKU `motogo24-ios`,
   **Apple ID `6806045151`**, primární jazyk čeština.
2. Apple ID aplikace je doplněné v `lib/core/update_check_provider.dart`
   (konstanta `_appStoreUrl` = `https://apps.apple.com/cz/app/id6806045151`).
3. Vyplň privacy (App Privacy: poloha, fotky, kontaktní údaje, platby),
   screenshoty iPhone (target je iPhone-only — iPad screenshoty nejsou potřeba).

### 6. Universal linky (volitelné, pro https://motogo24.cz/app deep linky)
Na web nasaď `https://motogo24.cz/.well-known/apple-app-site-association`
(Content-Type `application/json`, bez přípony):
```json
{ "applinks": { "apps": [], "details": [
  { "appID": "YP7TF3APAV.com.motogo24.rental", "paths": ["/app/*"] } ] } }
```
Bez něj funguje vše ostatní (Stripe návrat používá
custom scheme `motogo24://payment`, který je v Info.plist).

## Audit oprávnění (proti reálnému použití v kódu)

| Oprávnění | Kód, který ho používá | Info.plist klíč | Podfile makro |
|---|---|---|---|
| Notifikace | PushService / PermissionService / FCM | `UIBackgroundModes: remote-notification` + entitlement `aps-environment` | `PERMISSION_NOTIFICATIONS=1` |
| Kamera | document_camera/scanner (`enableAudio: false`), image_picker (SOS) | `NSCameraUsageDescription` | `PERMISSION_CAMERA=1` |
| Fotky (galerie) | image_picker — nahrání dokladu/SOS fotky | `NSPhotoLibraryUsageDescription` (+ `...AddUsageDescription`) | `PERMISSION_PHOTOS=1` |
| Poloha (when-in-use) | GpsService (SOS, mapa, vzdálenost přistavení) | `NSLocationWhenInUseUsageDescription` | `PERMISSION_LOCATION=1` |
| Poloha na pozadí | **NEW 2026-09-21** RideRecorder — záznam projeté trasy během výpůjčky (`AppleSettings.allowBackgroundLocationUpdates`) | `UIBackgroundModes: location` (+ `showBackgroundLocationIndicator`) | `PERMISSION_LOCATION=1` (stále jen **when-in-use**, „Always" NEŽÁDÁME) |
| Dočasné zpřesnění polohy | **NEW 2026-09-21** RideRecorder — `requestTemporaryFullAccuracy(purposeKey: 'rideTracking')`, když má jezdec vypnutou „Přesnou polohu" | `NSLocationTemporaryUsageDescriptionDictionary` → klíč `rideTracking` | — |
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
- **Poloha na pozadí (2.5.4 / 5.1.1):** od 2026-09-21 appka zaznamenává projetou
  trasu i na pozadí. Vyžaduje `UIBackgroundModes: location`. Text pro App Review
  je níž — **zkopíruj ho do App Store Connect → Review Notes u každého buildu.**

## Text pro App Review — poloha na pozadí

> **Kam:** App Store Connect → verze → **App Review Information → Notes**.
> **Kdy:** u každého buildu, který obsahuje `UIBackgroundModes: location`.
> Bez tohoto vysvětlení Apple background-location běžně odmítá (guideline 2.5.4:
> poloha na pozadí musí mít přímý přínos pro uživatele a musí být zjevná).

### Anglicky (to vložit do Review Notes)

```
Background location — why this app needs it

MotoGo24 is a motorcycle rental service. During an active rental the app records
the route the customer rides, so they can see it afterwards as a trip diary
("My experiences" > recorded rides), share it, and add photo stops to it.

A motorcycle ride means the phone is in a pocket or a handlebar mount with the
screen off, so foreground-only location produces a useless track: we were getting
roughly 11 GPS points across a 33-hour rental, drawn as straight lines across the
map. Continuous background location is the only way to record the actual route.

How it works:
- The recording runs ONLY while the customer has an active rental AND has left the
  "Record my rides" switch on in My experiences. They can turn it off at any time
  in that same screen, and they can delete any recorded ride.
- We request WHEN-IN-USE authorization only. We do NOT request "Always".
- showBackgroundLocationIndicator is enabled, so the blue status-bar indicator is
  visible the whole time the app is recording.
- Recording stops when the rental ends. A server-side job closes any recording
  that has received no GPS fix for 3 hours, so tracking cannot silently continue.
- The route is private to the customer. It is visible to other users only if the
  customer publishes it themselves. During an active rental the rental operator
  can also see it, for the operation and safety of the rental; this is disclosed
  in the app's GDPR text and in the hint next to the recording switch.

How to reproduce in review:
1. Sign in with the demo account provided below.
2. The demo account has an active rental, so recording starts automatically.
   (Make sure location permission is granted and the "Record my rides" switch in
   My experiences is on.)
3. Lock the phone and move a few hundred metres; the blue location indicator
   stays visible.
4. Open My experiences > recorded rides: the ride is there with the route drawn
   on the map. Turning the switch off ends the recording immediately.

We also call requestTemporaryFullAccuracy (purpose key "rideTracking") when the
user has Precise Location turned off, because a reduced-accuracy track is not a
usable route. Declining it is fine — we keep recording at lower accuracy.
```

### Česky (pracovní překlad, do App Store Connect NEvkládat)

Appka je půjčovna motorek. Během aktivní výpůjčky zaznamenává projetou trasu jako
zážitkový deník zákazníka. Telefon je při jízdě v kapse nebo v držáku se zhasnutým
displejem, takže sběr polohy jen na popředí dává nepoužitelnou stopu (reálně 11
bodů za 33 hodin, na mapě rovné čáry). Žádáme jen **when-in-use**, „Always" ne;
modrý indikátor polohy svítí po celou dobu; záznam si zákazník kdykoli vypne
a jízdu smaže; server zavře nahrávku, do které 3 hodiny nic nepřišlo.

> **Ještě před odesláním:** v App Store Connect → App Privacy doplň, že se poloha
> sbírá i **na pozadí** a je **vázaná na identitu** (Precise Location → App
> Functionality; účel „Product Personalization" NEuvádět — nic personalizujeme).
> A do Review Notes připoj přihlašovací údaje demo účtu s aktivní výpůjčkou,
> jinak recenzent záznam nerozjede a build spadne na „nešlo ověřit".

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
