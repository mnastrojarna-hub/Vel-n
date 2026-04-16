# MotoGo24 Flutter – Kompletní analýza chybějících funkcí pro spuštění

**Datum:** 2026-04-15  
**Stav:** Analýza před finálním spuštěním  
**Flutter app:** `motogo-app-flutter/` (182 Dart souborů, 11 feature modulů)  
**Originál:** `motogo-app-frontend/` (34 screenů, 88 JS souborů)

---

## SHRNUTÍ

| Kategorie | Stav |
|-----------|------|
| **Screeny (UI)** | 34/36 implementováno (94%) |
| **Backend integrace** | 10/12 plně napojeno na Supabase (83%) |
| **i18n (překlady)** | ~883/1123 klíčů (78%) |
| **Nativní funkce** | 9/10 implementováno (90%) |
| **Build & deploy** | Android 75% ready, iOS 0% |

---

## 1. KRITICKÉ BLOKY (musí se vyřešit před spuštěním)

### 1.1 iOS build neexistuje
- **Závažnost: KRITICKÁ**
- Složka `ios/` ve Flutter projektu **vůbec neexistuje**
- Chybí: Podfile, Info.plist, .pbxproj, Runner.xcodeproj
- Chybí: GoogleService-Info.plist (Firebase pro iOS)
- Chybí: signing certificate + provisioning profiles
- Chybí: CI/CD workflow pro iOS v codemagic.yaml
- **Dopad:** Aplikaci nelze buildit ani nasadit na iPhone/iPad

### 1.2 Firebase konfigurace je placeholder
- **Závažnost: KRITICKÁ**
- `android/app/google-services.json` obsahuje **falešné hodnoty**:
  - `project_number`: "000000000000"
  - `project_id`: "motogo24-placeholder"
  - `api_key`: "placeholder"
- **Dopad:** Push notifikace nefungují na produkci
- **Fix:** Vytvořit reálný Firebase projekt a stáhnout google-services.json

### 1.3 Android release signing
- **Závažnost: KRITICKÁ**
- Chybí keystore soubor (*.jks) pro release podpis
- Chybí `local.properties` s versionCode/versionName
- build.gradle je připraven (čte CM_KEYSTORE_PATH), ale soubor neexistuje
- **Dopad:** Nelze vytvořit podepsaný APK/AAB pro Google Play

---

## 2. VYSOKÁ PRIORITA (funkční mezery)

### 2.1 Chybějící analytics a crash reporting
- **Závažnost: VYSOKÁ**
- Žádná integrace: Firebase Analytics, Crashlytics, ani Sentry
- V produkci bez crash reportingu = slepý let
- **Doporučení:** Přidat `firebase_crashlytics` + `firebase_analytics` (Firebase Core už je v projektu)

### 2.2 Chybějící překlady (~240 klíčů)
- **Závažnost: VYSOKÁ**
- Flutter: ~883 klíčů vs. Originál: ~1123 klíčů = **21% chybí**
- Hardcoded české stringy v UI souborech (obchází i18n):
  - `booking_form_screen.dart` – "Rezervace: ${moto.model}", "Motorka × $dayCount"
  - `payment_screen.dart` – "Platba se nezdařila", "Platba kartou zamítnuta", "Zaplaceno"
  - `reservation_edit_screen.dart` – "Rezervace byla zkrácena..."
  - `res_modification_history.dart` – "Motorka", "Rezervace ukončena SOS incidentem"
  - `payment_header_widgets.dart` – "Platba"
- **Dopad:** Aplikace funguje jen česky v některých částech, i když uživatel zvolí jiný jazyk

### 2.3 Voucher redemption screen chybí
- **Závažnost: VYSOKÁ**
- Nákup voucheru ✓ implementován (výběr částky, přidání do košíku)
- **Uplatnění/redeem voucheru ✗ chybí** – žádná obrazovka pro zadání kódu voucheru
- V originálu: s-voucher umožňuje i zadání existujícího voucher kódu
- **Fix:** Přidat vstupní pole pro voucher kód + validaci přes `validate_voucher_code()` RPC

### 2.4 Shop payment flow neúplný
- **Závažnost: VYSOKÁ**
- Platební metoda hardcoded na 'card'
- Chybí validace existence objednávky před platbou
- Chybí shop-specifický payment flow (e-shop objednávky mají jiný proces než booking)
- **Fix:** Přidat `confirm_shop_payment()` RPC volání a validaci

---

## 3. STŘEDNÍ PRIORITA (kvalita a robustnost)

### 3.1 Chybí error recovery a retry logika
- Většina providerů nemá retry při výpadku Supabase
- Výjimka: document_provider.dart – má retry s exponential backoff (vzor k následování)
- **Doporučení:** Přidat retry wrapper pro kritické operace (platba, booking, auth)

### 3.2 Chybí offline cache pro kritická data
- `offline_guard.dart` ✓ detekuje stav sítě a zobrazí overlay
- Ale: žádný offline cache pro seznam motorek, rezervací, zpráv
- Při krátkém výpadku uživatel vidí prázdnou obrazovku
- **Doporučení:** Přidat Hive/Isar cache pro katalog a rezervace

### 3.3 Haptic feedback chybí
- Originál používá `@capacitor/haptics` pro toast notifikace a akce
- Flutter app nemá žádnou haptic integraci
- **Fix:** Přidat `HapticFeedback.lightImpact()` na klíčové interakce (booking confirm, payment, SOS)

### 3.4 Hardware back button handling
- Originál má custom back button logiku pro Android (navigační stack)
- Flutter GoRouter to řeší částečně, ale speciální případy (exit app, booking form guard) nejsou ověřeny
- **Doporučení:** Otestovat a doplnit `WillPopScope`/`PopScope` na kritických screenech

---

## 4. NÍZKÁ PRIORITA (vylepšení)

### 4.1 Pluralizace v překladech
- Hardcoded plural logika v UI ("1 den" vs "2 dny" vs "5 dnů")
- Mělo by používat `intl` package s `Intl.plural()`
- Neblokuje spuštění, ale vypadá neprofesionálně v jiných jazycích

### 4.2 Status bar styling
- Originál dynamicky mění barvu status baru podle screenu
- Flutter app to dělá globálně, ne per-screen
- **Fix:** Přidat `SystemChrome.setSystemUIOverlayStyle()` na klíčových screenech

### 4.3 Animace přechodů mezi screeny
- CLAUDE.md definuje: slide zprava, 320ms, `CubicBezier(0.77, 0, 0.18, 1)`
- GoRouter má custom transitions, ale ne na všech routes
- **Doporučení:** Ověřit a sjednotit page transitions

### 4.4 App review/rating prompt
- Originál nemá explicitní review prompt
- Pro launch: zvážit přidání `in_app_review` po dokončení první rezervace

---

## 5. STAV SCREENŮ – DETAILNÍ POROVNÁNÍ

### Legenda: ✅ Hotovo | ⚠️ Částečně | ❌ Chybí

| # | Originál (screen ID) | Flutter screen | Stav | Poznámka |
|---|---------------------|----------------|------|----------|
| 1 | s-login | LoginScreen | ✅ | Plně funkční, Supabase auth |
| 2 | s-register | RegisterScreen | ✅ | 3-krokový flow |
| 3 | s-docs | DocumentsScreen | ✅ | Upload + OCR přes Mindee |
| 4 | s-doc-scan | DocumentScannerScreen | ✅ | 4-krokový scan (ID + DL) |
| 5 | s-home | HomeScreen | ✅ | Sticky header, filtry, grid |
| 6 | s-search | MotoSearchScreen | ✅ | Vyhledávání + filtry |
| 7 | s-detail | MotoDetailScreen | ✅ | Galerie, specs, kalendář |
| 8 | s-booking | BookingFormScreen | ✅ | Kompletní formulář |
| 9 | s-payment | PaymentScreen | ✅ | Stripe Payment Sheet |
| 10 | s-success | PaymentConfirmationScreen | ✅ | Animovaný checkmark |
| 11 | s-res | ReservationsScreen | ✅ | Seznam s filtry + realtime |
| 12 | s-res-detail | ReservationDetailScreen | ✅ | Unified (active+done+cancelled) |
| 13 | s-edit-res | ReservationEditScreen | ✅ | Editace dat, extras |
| 14 | s-done-detail | ReservationDetailScreen | ✅ | Sloučeno s res-detail |
| 15 | s-merch | ShopScreen | ✅ | Produkty ze Supabase |
| 16 | s-merch-detail | ProductDetailScreen | ✅ | Detail produktu |
| 17 | s-cart | CartScreen | ✅ | Košík s cenami |
| 18 | s-checkout | ShopCheckoutScreen | ⚠️ | Chybí plný payment flow |
| 19 | s-voucher | VoucherScreen | ⚠️ | Nákup ✓, redeem ✗ |
| 20 | s-sos | SosReportScreen | ✅ | Výběr typu incidentu |
| 21 | s-sos-nehoda | SosImmobileScreen | ✅ | Nehoda (zaviněná/nezaviněná) |
| 22 | s-sos-nepojizda | SosImmobileScreen | ✅ | Sloučeno s nehoda |
| 23 | s-sos-porucha | SosBreakdownImmobileScreen | ✅ | Porucha (minor/major) |
| 24 | s-sos-nepojizda-porucha | SosBreakdownImmobileScreen | ✅ | Combined breakdown |
| 25 | s-sos-servis | SosServiceScreen | ✅ | Self-repair + faktura |
| 26 | s-sos-kradez | SosTheftScreen | ✅ | Krádež (secured/unsecured) |
| 27 | s-sos-replacement | SosReplacementScreen | ✅ | Výběr náhradní motorky |
| 28 | s-sos-payment | PaymentScreen (reuse) | ✅ | Sdílený payment screen |
| 29 | s-sos-done | SosDetailScreen | ✅ | 8 kontextových variant |
| 30 | s-protocol | ProtocolScreen | ✅ | Smlouva / protokol |
| 31 | s-profile | ProfileScreen | ✅ | Profil + nastavení |
| 32 | s-messages | MessagesScreen | ✅ | Realtime vlákna |
| 33 | s-messages-thread | ThreadDetailScreen | ✅ | Chat s adminem |
| 34 | s-ai-agent | AiAgentScreen | ✅ | AI technik (edge function) |
| 35 | s-invoices | InvoicesScreen | ✅ | Faktury ze Supabase |
| 36 | s-contracts | ContractsScreen | ✅ | Smlouvy + VOP + GDPR |

---

## 6. STAV BACKEND INTEGRACE

| Služba | Provider | Supabase | Stav |
|--------|----------|----------|------|
| Auth (login/register) | auth_provider.dart | ✅ Real | Plně funkční |
| Katalog motorek | catalog_provider.dart | ✅ Real | S filtry a availability |
| Booking draft + cena | booking_provider.dart | ✅ Real | Promo kódy, extras, validace |
| Platba (Stripe) | stripe_service.dart | ✅ Real | Payment Sheet + polling |
| Platební metody | payment_provider.dart | ✅ Real | CRUD přes edge function |
| Rezervace | reservation_provider.dart | ✅ Real | Realtime + door codes |
| Zprávy | messages_provider.dart | ✅ Real | Realtime + unread count |
| Dokumenty + OCR | document_provider.dart | ✅ Real | Mindee v2 + retry |
| SOS incidenty | sos_provider.dart | ✅ Real | Foto, GPS, timeline |
| Profil | profile_screen.dart | ✅ Real | CRUD na profiles tabulku |
| Shop (produkty) | shop_provider.dart | ⚠️ Partial | Produkty OK, platba neúplná |
| Email service | email_service.dart | ⚠️ Partial | Potvrzovací emaily |

---

## 7. STAV NATIVNÍCH FUNKCÍ

| Funkce | Soubor | Stav | Poznámka |
|--------|--------|------|----------|
| Push notifikace (FCM) | push_service.dart | ✅ | Token registrace + handling |
| Deep linking | notification_handler.dart | ✅ | 5 typů (booking, sos, message...) |
| GPS lokace | gps_service.dart | ✅ | High/low accuracy + fallback |
| Oprávnění | permission_service.dart | ✅ | Batch při onboardingu |
| Biometrie | biometric_service.dart | ✅ | Fingerprint + face |
| Offline guard | offline_guard.dart | ✅ | Ping + overlay |
| App update check | update_check_provider.dart | ✅ | Force-update dialog |
| Onboarding | onboarding_overlays.dart | ✅ | Jazyk + permissions |
| Cache cleanup | cache_cleanup_service.dart | ✅ | Lifecycle-aware |
| **Analytics/Crash** | **—** | **❌ CHYBÍ** | **Žádný crash reporting** |
| **Haptic feedback** | **—** | **❌ CHYBÍ** | **Žádná haptická odezva** |

---

## 8. AKČNÍ PLÁN PRO SPUŠTĚNÍ

### Fáze 1 – BLOKUJÍCÍ (odhadovaný rozsah: velký)
1. [ ] Vytvořit iOS projekt (`flutter create --platforms=ios .`)
2. [ ] Nastavit iOS signing (certifikát + provisioning)
3. [ ] Přidat GoogleService-Info.plist pro iOS
4. [ ] Nahradit placeholder google-services.json reálnými credentials
5. [ ] Vytvořit Android keystore pro release signing
6. [ ] Přidat iOS workflow do codemagic.yaml

### Fáze 2 – VYSOKÁ PRIORITA (střední rozsah)
7. [ ] Přidat Firebase Crashlytics + Analytics
8. [ ] Doplnit chybějící ~240 překladových klíčů
9. [ ] Nahradit hardcoded české stringy i18n voláními
10. [ ] Implementovat voucher redemption screen
11. [ ] Dokončit shop payment flow (confirm_shop_payment RPC)

### Fáze 3 – STŘEDNÍ PRIORITA (malý rozsah)
12. [ ] Přidat retry wrapper pro kritické Supabase operace
13. [ ] Přidat haptic feedback na klíčové interakce
14. [ ] Implementovat offline cache (Hive/Isar) pro katalog + rezervace
15. [ ] Otestovat hardware back button na všech screenech
16. [ ] Ověřit page transition animace dle designu

### Fáze 4 – POLISH (volitelné pro launch)
17. [ ] Pluralizace přes Intl.plural()
18. [ ] Per-screen status bar styling
19. [ ] In-app review prompt po první rezervaci
20. [ ] Production load testing Supabase

---

## 9. CO JE HOTOVO A FUNGUJE

Většina aplikace je **implementována a napojena na reálný Supabase backend**:

- **Kompletní booking flow:** Výběr motorky → detail → formulář → platba → potvrzení
- **Správa rezervací:** Seznam, detail, editace, cancel, door codes, realtime
- **SOS systém:** Všech 6 typů incidentů + replacement + AI agent
- **Messaging:** Realtime chat s adminem + push notifikace
- **Dokumenty:** OCR skenování (Mindee), upload, verifikace
- **Shop:** Produkty, košík, checkout (platba částečně)
- **Profil:** Editace, biometrie, jazyk, oprávnění
- **Auth:** Login, registrace, reset hesla, biometric login
- **7 jazyků:** CS, EN, DE, PL, FR, ES, NL (78% klíčů přeloženo)

**Celkové hodnocení: Aplikace je z ~85% připravena na produkční spuštění.** Hlavní bloky jsou infrastrukturní (iOS build, Firebase credentials, signing), ne funkční.
