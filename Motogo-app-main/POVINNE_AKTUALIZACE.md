# Povinné (vynucené) aktualizace appky — postup vydání

Cíl: žádný uživatel nesmí zůstat na staré verzi. Mechanismus má 3 vrstvy:

1. **Force-update gate** (`lib/core/update_check_provider.dart`, oba stromy) —
   appka čte `app_settings.min_app_version` (anon-čitelné, RLS „Public read
   non-secret"). Když `verze appky < min_app_version`, zobrazí NEZAVŘITELNÝ
   dialog s tlačítkem do storu. Kontrola běží po startu **a při každém návratu
   z pozadí** (throttle 15 min) — blokne i dlouho otevřenou appku.
2. **Google Play In-App Updates** (`lib/core/in_app_update_service.dart`,
   jen Android) — release s `inAppUpdatePriority >= 4` spustí blokující
   IMMEDIATE update přímo v appce (bez odchodu do Play); nižší priorita =
   flexible (stáhne na pozadí + nabídne restart). Rozjetý immediate update se
   po návratu z pozadí automaticky obnoví. iOS ekvivalent neexistuje —
   tam blokuje jen vrstva 1.
3. **Automatické aktualizace storu** — Play i App Store aktualizují na pozadí
   samy (pokud to uživatel nevypnul); vrstvy 1–2 dorazí zbytek.

## Checklist vydání povinné verze (např. 3.0.1)

1. **Bump verze v OBOU pubspec.yaml** (`motogo-app-flutter` = Android,
   `motogo-app-flutter-ios` = iOS). Pubspec je JEDINÝ zdroj versionName
   (x.y.z) — release workflows v `codemagic.yaml` už NESMÍ předávat
   `--build-name` (hardcoded 2.5.0 tam dřív přepisoval pubspec a buildy
   hlásily starou verzi). Build number (versionCode/CFBundleVersion)
   dodává Codemagic přes `--build-number=$BUILD_NUMBER` — číslo v pubspec
   za `+` je jen lokální fallback, storům je jedno.
2. **Build přes Codemagic** (oba stromy) → nahrát do Play Console
   a App Store Connect, projít review a **vydat na 100 % uživatelů**
   (žádný staged rollout — jinak část uživatelů uvidí blokaci bez
   možnosti aktualizovat).
3. **Android:** release nahrát s `inAppUpdatePriority: 5`. Priorita NEJDE
   nastavit v UI Play Console — jen přes Play Developer API / Codemagic
   (`google_play` publishing → `in_app_update_priority: 5`).
4. **Počkat, až je verze ŽIVÁ v obou storech** (Play propagace až ~24 h,
   App Store po schválení). Ověřit stažením na reálném zařízení.
5. **Teprve POTOM** nastavit minimální verzi v DB (SQL editor, ručně —
   NIKDY jako migrace do gitu, spustila by se hned po merge):

   ```sql
   INSERT INTO app_settings (key, value)
   VALUES ('min_app_version', '"3.0.1"'::jsonb)
   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
   ```

   POZOR: nastavení dřív, než je build ve storech, zablokuje VŠECHNY
   uživatele bez cesty ven.
6. Ověřit na zařízení se starou verzí: otevřít appku → musí naskočit
   dialog „Vyžadována aktualizace" a tlačítko musí otevřít správný store.

## Stav vydání 3.0.1 (záznam 23. 8. 2026)

- **Release 96 (2.5.0) v Play Console ZAHOZEN** — build běžel před opravou
  verzování (`b26340f`), nesl versionName 2.5.0. Nevydávat podobné buildy:
  s min 3.0.1 by DB gate zablokoval i aktualizované uživatele.
- **Publikování do Play jde přes API z Codemagicu** (jediná cesta, jak
  nastavit `inAppUpdatePriority`): GCP projekt `directed-galaxy-488222-c3`
  (účet mnastrojarna@gmail.com; Firebase projekt `motogo24-518b4` je pod
  jiným přístupem), zapnuté androidpublisher.googleapis.com, service account
  `codemagic-play-publisher@directed-galaxy-488222-c3.iam.gserviceaccount.com`
  (bez GCP rolí; v Play Console oprávnění „Vydávání v produkční verzi,
  vyloučení zařízení a Play App Signing"). JSON klíč je v Codemagicu jako
  secure var `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` v env group **`goole_play`**
  — ⚠️ PŘEKLEP v názvu skupiny je záměrně ponechán a codemagic.yaml na něj
  odkazuje; při přejmenování změnit OBOJE současně. Dluh: Codemagic hlásí
  deprecation názvu proměnné → časem přejmenovat na
  `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` (UI i yaml zároveň).
- **Commit `e5d30ec`:** workflow `motogo-android-release` publikuje sám:
  `track: production`, `in_app_update_priority: 5`, bez `rollout_fraction`
  (= 100 %). Každý build tohoto workflow jde rovnou do produkce.
- **Build 97 = 3.0.1 (97) nahrán do produkce** (23. 8. ~17:24 CEST, log:
  Version 3.0.1, code 97, track production, priority 5). Řízené publikování
  je VYPNUTÉ → po schválení Googlem se vydá samo na 100 %. Nic nemačkat.
- **Zbývá:** (1) počkat na „Dostupné na Google Play" (~24 h) a ověřit na
  zařízení; (2) TEPRVE POTOM spustit SQL `min_app_version = "3.0.1"` (viz
  checklist krok 5); (3) ověřit force-update dialog na staré verzi.
- **iOS vědomě neřešeno** (rozhodnutí Jiřího — iOS není v produkci, gate mu
  neublíží). ⚠️ iOS build #35 v App Store Connect nese 2.5.0 (běžel před
  `b26340f`) — NEVYDÁVAT. Před budoucím iOS vydáním: doplnit Apple ID
  (placeholdery níže), vydat iOS ≥ min_app_version dřív, než se min zvedne.

## Známé podmínky funkčnosti

- **iOS store URL:** v `motogo-app-flutter-ios/lib/core/update_check_provider.dart`
  je placeholder `idAPPLE_ID` — po publikování v App Store Connect DOPLNIT
  skutečné Apple ID (App Information → Apple ID), jinak tlačítko
  AKTUALIZOVAT na iPhonu otevře mrtvý odkaz. Stejný placeholder je
  v `motogo-web-php/manifest.webmanifest` (`id0000000000`).
- Překlady dialogu (`updateRequired/updateRequiredDesc/updateNow` +
  `updateDownloaded/updateRestart`) existují ve všech 8 jazycích v obou
  stromech.
- `min_app_version` smí být string `"3.0.1"` i objekt `{"version":"3.0.1"}` —
  checker umí obojí. Srovnává se jen `x.y.z` (build number se ignoruje).
