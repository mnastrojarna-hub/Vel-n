# MotoGo24 — Kiosk samoobslužné pobočky (AlzaBox na motorky)

Fullscreen Flutter appka pro **průmyslový Android tablet** na bezobslužné pobočce
(Brno, Pohořelice). Zákazník zadá kód → otevřou se správné dveře.

## Co appka dělá

1. Zákazník zadá **kód k oblečení** → otevřou se sdílené dveře skříně s oblečením.
2. Po zavření zadá **kód k motorce** → otevřou se dveře konkrétní garáže (dle `box_number` motorky).
3. Při otevření se na **celé pobočce spustí hudba** a v **konkrétní garáži rozsvítí světlo**.
4. **Servisní heslo** (nastavitelné ve Velíně, víc hesel/pobočka, měnitelná) otevírá
   všechny dveře — appka se zeptá, které dveře otevřít.

Kódy zákazníků jsou existující `branch_door_codes` (auto-generované při aktivaci
rezervace). Appka je jen ověří přes RPC a fyzicky otevře dveře.

## Architektura

- **Identita zařízení:** každý tablet = řádek v `kiosk_devices` s unikátním
  `id` + `device_token`. Pobočka má unikátní `branch_code`. Tablet je natrvalo
  spárovaný přes `device_id` + `device_token` (uloženo v secure storage).
- **Ověření kódu:** Supabase RPC `kiosk_resolve_code(device_id, device_token, code)`
  (SECURITY DEFINER) — vrátí, které dveře otevřít + URL relé/světla/hudby.
- **Fyzické ovládání:** appka volá HTTP přímo na **Shelly relé na LAN**
  (otevírání tak funguje i bez internetu; ověření kódu internet potřebuje).
- **Online stav:** appka posílá `kiosk_heartbeat` každých 30 s → Velín vidí online/offline.
- **Vzdálené ovládání (realtime):** appka poslouchá `kiosk_commands` přes Supabase
  Realtime; Velín pošle příkaz (otevři dveře / hudba / identifikuj) → tablet ho
  provede a nahlásí výsledek (`kiosk_complete_command`).
- **Audit:** každé otevření se loguje přes RPC `kiosk_log_open` → `branch_door_events`.

Údaje pro párování (ID + token) se generují ve Velíně → Pobočky → **Samoobsluha → Zařízení**.

## Konfigurace ve Velíně (per pobočka → záložka „Samoobsluha")

- **Zařízení (tablety)** — přidej tablet → dostaneš `ID` + `token` (zadej do appky).
  Vidíš online/offline stav, verzi appky a můžeš ho ovládat na dálku (otevřít
  dveře, hudba, identifikuj) nebo deaktivovat/smazat (revokace párování).
- **Hudba** — `music_on_url` (a volitelně `music_off_url`) = HTTP endpoint, který
  spustí hudbu na pobočce.
- **Dveře (relé + světlo):** pro každou kóji motorky (`box_number`) a pro sdílené
  dveře oblečení se nastaví `relay_url` (otevření zámku) a `light_url` (světlo).
- **Servisní hesla** — seznam aktivních hesel pro techniky.
- **Kamery** — náhled (snapshot/HLS/iframe) přímo ve Velíně; ovládací akce (PTZ/relé)
  se posílají přes tablet na LAN (`camera_control`). URL náhledu musí být dostupná
  z prostředí Velína (cloud/NVR), ovládací URL stačí na LAN.
- **Solární (ostrovní) elektrárna** — tablet stahuje stav z měniče na LAN
  (`power_status_url`, JSON) a posílá ho do Supabase (`kiosk_report_power`); Velín
  zobrazuje SoC baterie, FV výrobu, spotřebu, tok baterie a stav sítě/generátoru.

## Spuštění / build

Tento balík obsahuje jen `lib/`, `assets/` a `pubspec.yaml`. Nativní Android
projekt vygenerujte jednou:

```bash
cd Motogo-app-main/motogo-locker-kiosk
flutter create --platforms=android --project-name motogo_locker_kiosk .
flutter pub get
flutter run        # nebo: flutter build apk --release
```

### Doporučená nastavení tabletu (kiosk)

- Zapnout **Android kiosk / lock task mode** (pinned app) nebo MDM, ať appku nelze opustit.
- V `AndroidManifest.xml` přidat `<uses-permission android:name="android.permission.INTERNET"/>`
  (generuje `flutter create`) — appka volá Supabase i LAN relé.
- Tablet a relé Shelly musí být ve stejné LAN síti.

### Skrytý vstup do nastavení

Na hlavní obrazovce **5× klepnout na logo** (do 2 s) → otevře se párování pobočky.
