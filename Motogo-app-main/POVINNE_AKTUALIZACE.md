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
   `motogo-app-flutter-ios` = iOS) — build number vždy +1.
   Android/iOS Gradle i Info.plist verzi přebírají z pubspec.
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
