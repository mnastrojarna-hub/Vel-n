# PLAY-FIXES — reakce na 3 doporučení ke buildu 60 (2.2.0)

Stav k 2026-07-04, větev `claude/motogo-photo-zoom-issue-hpgkgq`.
Týká se JEN Android stromu `Motogo-app-main/motogo-app-flutter/` (Play doporučení
se iOS netýkají; ios strom záměrně nezměněn, aby se neriskoval iOS build).

## 1. „Zobrazení bez okrajů nemusí fungovat" + „zastaralá API pro edge-to-edge"

Kód appky je čistý už od 30. 6. (enableEdgeToEdge v MainActivity, průhledné
lišty v main.dart, targetSdk 35 — viz PLAY-FIXES-EDGE-TO-EDGE.md) a build 60
tyto opravy UŽ obsahoval. Zbývající hlášky pocházejí z Android SDK starých
pluginů. Proto povýšeny (pubspec.yaml):

| Balíček | Z | Na |
|---|---|---|
| firebase_messaging | ^14.7.6 | ^16.4.1 |
| firebase_core | ^2.24.2 | ^4.11.0 |
| flutter_stripe | ^11.3.0 | ^13.0.0 |
| connectivity_plus | ^5.0.2 | ^7.2.0 |
| geolocator | ^10.0.0 | ^14.0.3 |
| permission_handler | ^11.3.0 | ^12.0.3 |
| in_app_update | ^4.2.3 | ^5.0.0 |
| camera | ^0.11.0+2 | ^0.12.0 |
| package_info_plus | ^8.0.0 | ^10.0.0 (vynuceno geolocatorem) |
| flutter_secure_storage | ^9.0.0 | ^10.3.1 (vynuceno řetězem závislostí) |

Navazující nutné úpravy:

- **lib/core/offline_guard.dart** — connectivity_plus 6+ vrací
  `List<ConnectivityResult>`; porovnání s enum hodnotou by jinak tiše rozbilo
  detekci offline stavu (vždy „online"). Přepsáno na `contains(...)`.
- **android/app/build.gradle** — `minSdk 21` → `minSdk flutter.minSdkVersion`
  (Flutter 3.44 → API 24). Firebase BOM a secure_storage 10 vyžadují ≥23,
  pevná 21 by rozbila manifest merge. DOPAD: zařízení s Androidem 5–6
  (podíl ~0,2 %) nedostanou aktualizace — Flutter 3.44 engine je už stejně
  nepodporuje.
- flutter_secure_storage 10 (biometrické přihlášení) migruje uložená data
  automaticky (`migrateOnAlgorithmChange: true` je default).
- Stripe: appka používá jen initPaymentSheet/presentPaymentSheet/applySettings
  — breaking changes v 12/13 (collectBankAccount, Sofort, FPX) se jí netýkají.

## 2. „Optimalizace rastrových obrázků"

- `assets/logo.png` (37 kB) → `assets/logo.webp` (17 kB, bezztrátově) + 11 referencí v lib/
- `assets/darkovy-poukaz.jpg` (103 kB) → `.webp` q82 (60 kB) + 2 reference
- `assets/app_icon.png` (63 kB) — ODSTRANĚN, nebyl nikde referencován
- `mipmap-*/ic_launcher.png` (24 kB) → bezztrátové `.webp` (12,5 kB); manifest
  odkazuje `@mipmap/ic_launcher` podle jména zdroje, beze změny

Celkem rastr v AAB: ~226 kB → ~90 kB (−60 %). Vizuálně beze změny (lossless,
u poukazu q82 nerozeznatelné).

## Validace (bez Android SDK v prostředí — proxy blokuje dl.google.com)

- ✅ `flutter pub get` (Flutter 3.44.4 stable = totéž co Codemagic)
- ✅ `flutter analyze` — žádná nová chyba (3 předchozí chyby v mrtvých,
  neimportovaných souborech safe_action.dart / booking_form_screen.dart
  existovaly už před změnami a do buildu nevstupují)
- ✅ plná kompilace Dart stromu přes `test/compile_smoke_test.dart`
  (importuje main.dart → zkompiluje celou dosažitelnou appku)
- ❌ gradle/nativní vrstva NEOVĚŘENA — nutný build na Codemagic

## Co zbývá na člověka

1. **Nejdřív debug workflow** na Codemagic (motogo-android) → ověřit, že se
   AAB/APK vůbec sestaví. Až pak release.
2. Na zařízení ověřit: **Stripe platba** (Payment Sheet end-to-end),
   **biometrické přihlášení** (migrace secure storage), **push notifikace**
   (FCM po upgradu firebase_messaging 16), kamera/sken dokladů, GPS v SOS,
   in-app update prompt, offline banner (letadlový režim).
3. Po nahrání do Play zkontrolovat, že doporučení zmizela (může trvat
   několik dní / další release).
