# MotoGo Box — řídicí jednotka samoobslužné pobočky (Raspberry Pi 5)

Univerzální řídicí program pro VŠECHNY samoobslužné pobočky MotoGo24 (nástupce tabletového
kiosku). Každá pobočka má vlastní řídicí jednotku; počet kójí, zařízení a mapování I/O se
nastavují výhradně ve Velíně (první nasazení: box Brno — 8 zón (7 kójí + šatna) + venek; jeho mapa je výchozí šablona).
**Flow zákazníka, texty, servisní heslo i napojení na Velín zůstávají stejné** — mění se
hardwarová vrstva: místo Shelly relé volaných z tabletu řídí Raspberry Pi přes Modbus TCP
(Waveshare WAV645/WAV617) zámky, světla a dveřní kontakty, přes Shelly Pro RGBWW PM
červenou/zelenou signalizaci a hudbu v konkrétní kóji (mpv + reléový selektor, nebo v režimu `multi`
vlastní zvukový výstup každé místnosti — 7 kójí, šatna, venek; skladby z Velína, viz „Hudba“).
Zadání: `SPEC.md`; rozhraní modulů: `CONTRACT.md`; zapojení a tabulky I/O: `HARDWARE.md`.

## Co program dělá

1. Zákazník zadá **kód k oblečení** → otevře se kóje s oblečením (kind `accessories`).
2. Po zavření zadá **kód k motorce** → otevře se kóje konkrétní motorky (`box_number` → zóna).
3. Při otevření se v kóji **rozsvítí bílé světlo, signalizace přejde na zelenou a začne hrát hudba**
   (skladby přiřazené té kóji ve Velíně → „Hudba pobočky“; v režimu `multi` hraje zároveň i venek).
   Po zavření dveří hudba doběhne (10 s) a světlo zhasne (30 s), svítí červená.
4. **Servisní heslo** (Velín → Samoobsluha → Servisní hesla) otevře servisní panel: otevřít
   libovolné dveře, světlo/hudba per zóna, Vše vypnout, stav zařízení, přepárování, restart.

Kódy zákazníků jsou existující `branch_door_codes` (generují se při aktivaci rezervace).
Program je ověří přes RPC `kiosk_resolve_code`; při výpadku internetu proti **lokální cache**
(hashe HMAC z `kiosk_sync_config`) — otevírání funguje i bez LTE.

### Stavový automat zóny (SPEC §9)

`SECURED → (platný PIN) → WAITING_FOR_OPEN → (kontakt otevřen) → DOOR_OPEN → (zavřeno ≥ 1 s)
→ CLOSED_CONFIRMATION → (doběh světla/hudby) → SECURED`. Zámek dostane jen **hardwarový
800ms impulz** (WAV645 flash-on) — nikdy nezůstane pod napětím, ani při pádu programu.
Dveře neotevřené do 30 s → relace končí (OPEN_TIMEOUT, kód lze použít znovu). Dveře
otevřené > 10 min → zelená pulzuje, hudba stop, upozornění do Velína (10/20/30 min).
Více kójí smí být otevřených současně (rozhodnutí §13.7); v režimu `selector` hraje hudba jen v poslední
otevřené, v režimu `multi` v každé otevřené kóji (+ venek); pulzy zámků se nikdy nepřekrývají.

### Venek (zóna 9)

Zóna 9 v šabloně Brno je **venek** — prostor před displejem + venkovní osvětlení (rozhodnutí 2026-09-11). Není to řádek
`branch_doors`: bez zámku, dveřního kontaktu, signalizace, rezervací i dlaždice na displeji. Nastavuje se ve Velíně → Samoobsluha →
hardware → blok **„Venek (zóna bez dveří) — venkovní osvětlení + hudba venku“** (sekce `outdoor` HW mapy: číslo zóny, relé světla
Waveshare — v Brně WAV617-B R1, v režimu `multi` audio výstup + volitelné enable relé zesilovače, doběh světla; „Vymazat venek“ sekci
odstraní). **Světlo** se rozsvítí při zadání jakéhokoli kódu (první relace) a zhasne `light_after_close_s` po skončení poslední relace
(vlastní doběh venku má přednost před globálním); **hudba venku** hraje při jakémkoli kódu (jen režim `multi`, doběh
`music_after_close_s`). Z Velína (dlaždice „Venek“ v živém stavu zón) lze světlo ručně rozsvítit (drží do vypnutí) / zhasnout (do
další relace), hudbu spustit / zastavit a spustit test (světlo 1 s + tón 3 s; venek bez relé světla = jen tón; při běžící relaci
jednotka test odmítne). Ruční příkaz světla jednotka při chybě relé neopakuje — Velín dostane `ok:false`, příkaz zopakovat (jen
automatické přechody relace/doběh se po chybě zkoušejí znovu po 5 s). Stav:
`kiosk_devices.status.outdoor` (`api/state → outdoor`). Diagnostika pobočky venek kontroluje (skupina „Venek (zóna 9)“ v protokolu:
relé světla, hudba venku; světlo nikdy nespíná při relaci) a nepočítá ho mezi zóny. Starší zápis výstupu venku
`audio.channels.outdoor` jednotka dál čte (alias); Velín ho při uložení bloku Venek převede na `outdoor.audio`.

## Architektura procesů

| systemd unit | proces | obsah |
|---|---|---|
| `motogo-controller.service` | `python -m motogo_box controller` | Modbus I/O, Shelly, audio, stavové automaty zón, Supabase (heartbeat, sync, příkazy, status), lokální web+WS pro UI (`127.0.0.1:8080`), systemd watchdog |
| `motogo-health.service` | `python -m motogo_box health` | LTE watchdog (ModemManager/NetworkManager → reconnect → USB reset modemu → reboot), teplota/throttling/disk/RAM → `POST /api/health` |
| `motogo-ui.service` | `cage -- chromium --kiosk http://127.0.0.1:8080/` | Dotykové UI na EDATEC (responzivní 100vw×100vh, světlé téma MotoGo24 — viz „Displej“; Wayland kiosk na tty7, skript `scripts/kiosk-ui.sh`) |

Lokální data: SQLite `/var/lib/motogo/motogo.db` (cache kódů, fronta neodeslaných událostí,
PIN lockout, posledních 5000 událostí), stav health `/var/lib/motogo/health.json`.

## Displej (dotykové UI)

`motogo_box/ui/` (vanilla JS, offline). Od 2026-09-10 **responzivní rozložení 100vw × 100vh** pro široké a nízké
dotykové displeje (žádné pevné 1920×1080; ověřeno 1920×1080, 2560×1080, 1920×720, 3840×1080, 1280×400) a **světlý
design MotoGo24** (barvy webu/appky, logo `ui/logo-light.svg`). Hlavička: logo, lišta 8 jazyků (vždy viditelná, návrat
do češtiny po nečinnosti), **název pobočky** a tečka online. Tělo ve třech sloupcích: výzva + vysvětlivky („Kód najdete
v aplikaci MotoGo24 — v detailu rezervace a ve zprávách — nebo v potvrzovacím e‑mailu.“ / „Kód k výbavě otevře šatnu ·
kód k motorce otevře vaši garáž s vaší motorkou.“) + pole kódu (**zadávané znaky jsou viditelné** — žádné maskování tečkami,
rozhodnutí 2026-09-11; platí pro kód rezervace, servisní heslo i diagnostický kód) | klávesnice (numerická / „ABC“ pro servisní hesla,
velikost kláves podle místa, vždy ≥ 48 px, nic se nepřekrývá) | dlaždice zón („Šatna“, „Kóje N“; 1–2 sloupce).
Servisní panel, setup a diagnostika zůstávají tmavé overlaye (`ui/style-overlays.css`), použitelné i na nízkém displeji.
**Název pobočky se bere VÝHRADNĚ z Velína → Pobočky (`name`)** — není-li vyplněný, zůstává místo v hlavičce prázdné
(žádný náhradní text). Texty všech 8 jazyků: `ui/i18n.js`.

## Co se nastavuje kde (Velín vs. Raspberry)

**Vše o hardwaru se nastavuje ve Velíně** → Pobočky → Samoobsluha → **„Řídicí jednotka (Raspberry)"**:
- `branch_kiosk_config.hardware` (jsonb) — zařízení (IP Waveshare/Shelly), časování, polling,
  polarita kontaktů (`contacts.closed_level`), bezpečnost (PIN lockout), **audio** (sekce „Audio“: režim `audio.mode`
  `selector`/`multi`, `device` selektoru, `outputs` = pojmenované ALSA výstupy dle `aplay -L`), signalizace, **venek** (sekce
  `outdoor` — blok „Venek“: číslo zóny, relé světla, audio výstup (multi), doběh světla; viz „Venek (zóna 9)“);
- `branch_doors.hw` (jsonb per dveře) — mapa zóny: zámek (coil), kontakt (input), světlo, audio (relé selektoru, v režimu
  `multi` výstup `audio.out` + volitelné enable relé), červená/zelená (Shelly light id). Tlačítko „Načíst výchozí mapu
  (šablona Brno, 8 zón + venek)" předvyplní SPEC §5 — jiná pobočka si mapu upraví (jiný počet zón, jiné adresy);
- **hudba** — blok **„Hudba pobočky“**: nahrání skladeb přetažením a přiřazení kóji / šatně / venku / společné
  (`branch_music_tracks` + bucket `branch-music`); jednotka si soubory stáhne sama (viz „Hudba“);
- servisní hesla, zařízení (ID + token), kamery, měnič FV — beze změny oproti tabletu.
Program si konfiguraci stahuje každých 60 s (`kiosk_sync_config`) a při změně zařízení/zón
bezpečně přestaví I/O (vše vypnout → nové zóny).

**Na Raspberry se lokálně nastavuje jen:**
- `/etc/motogo/config.yaml` — Supabase URL/anon key, ID + token zařízení (nebo párování z UI),
  cesty, intervaly, sekce `health` (LTE watchdog) a `diagnostics` (kód pro diagnostiku pobočky
  z displeje, porty/podsítě scanu, limity běhu, `zone_test`); vzor `config/config.example.yaml`;
- `/etc/motogo/hardware.yaml` — **výchozí** HW mapa (kopie `config/brno-9zone.yaml`), použije se
  jen dokud Velín nepošle vlastní; Velín má vždy přednost.

## Instalace krok za krokem

1. **Image:** Raspberry Pi OS **Bookworm 64-bit Lite** (Raspberry Pi Imager: nastav hostname
   `motogo-<pobocka>`, uživatele pro SSH, lokalizaci `cs_CZ`, časovou zónu Europe/Prague). Nabootuj, `sudo apt update && sudo apt full-upgrade -y`.
2. **Rozbal program** (např. `git clone` repa nebo `scp` složky `raspberry/motogo-box`) a spusť:
   ```bash
   cd raspberry/motogo-box
   sudo MOTOGO_APN=internet.t-mobile.cz ./scripts/install.sh
   ```
   Instalátor je idempotentní (14 kroků): nainstaluje balíčky (python3-venv, mpv, cage, chromium,
   network-manager, modemmanager, alsa-utils, rsync, kbd, polkitd, unattended-upgrades), vytvoří uživatele `motogo`,
   zkopíruje program do `/opt/motogo` (venv + pip — bez internetu jen varuje a pokračuje) a root-owned kopie
   `motogo-update` / `motogo-usbreset` / `motogo-sysupdate` do `/usr/local/sbin` (krok 3; zdroj aktualizací
   `/etc/motogo/source_dir`), založí `/etc/motogo/config.yaml` a `hardware.yaml` (existující nepřepisuje),
   `/var/lib/motogo/music` + `music/tracks` + root-owned logy `/var/log/motogo-*.log` (krok 6), **Audio** (krok 7:
   šablona udev pravidel `systemd/70-motogo-audio.rules` → `/etc/udev/rules.d/` pro stálá jména USB zvukovek — živý
   soubor s aktivními pravidly se NEpřepisuje; reload udev; výpis karet `aplay -l` a zařízení pro `audio.outputs`
   `aplay -L`), udev pravidlo modemu (krok 8), `/etc/motogo/modem_vidpid`, NM profily (krok 9), sudoers (krok 10:
   reboot, restart motogo-*, motogo-update / -usbreset / -sysupdate BEZ argumentů, nmcli lte, mmcli signal-setup) +
   polkit pravidlo pro UI, **OS záplaty** (krok 11:
   `/etc/apt/apt.conf.d/52motogo-unattended` = jen Debian-Security, bez automatického restartu, + drop-in
   `apt-daily-upgrade.timer` 04:00 ± 20 min, `Persistent=false`; `MOTOGO_SKIP_APT=1` → jen varování, že balík chybí),
   systemd unity, dobíjení RTC baterie (`dtparam=rtc_bbat_vchg=3000000`), vypne `getty@tty7`, služby spustí.
   Zadává se interaktivně nebo přes env: `MOTOGO_DEVICE_ID`, `MOTOGO_DEVICE_TOKEN`, `MOTOGO_APN`,
   **`MOTOGO_SIM_PIN`** (PIN SIM je u všech poboček **1234** — výchozí hodnota install.sh; jiný PIN = `MOTOGO_SIM_PIN`; při
   opakované instalaci má přednost PIN už uložený v profilu `motogo-lte` (bez env se ponechá); explicitně prázdné `MOTOGO_SIM_PIN=`
   = SIM bez PINu a uložený PIN z profilu odstraní; zapíše se do `[gsm] pin=` profilu `motogo-lte`, jinak zůstane modem ve stavu
   `locked` a LTE nikdy nenaběhne), `MOTOGO_DIAG_CODE`
   (při založení `config.yaml` se jinak vygeneruje náhodný kód `diagNNNN` — žádný veřejný default z repa;
   existující kód se bez této proměnné nemění; kód se zadává na zákaznické klávesnici a chybné pokusy se
   počítají do lockoutu) a `MOTOGO_MODEM_VIDPID` (výchozí `1e0e:9001`).
   **USB zvuková karta:** instalátor ji najde přes `aplay -l` (název obsahuje `USB`/`AXAGON`) a při založení
   `hardware.yaml` nastaví `audio.device: alsa/plughw:CARD=<název>`; není-li karta připojená, varuje
   (bez toho hraje hudba z HDMI monitoru). Výsledný diagnostický kód, PIN, kartu i VID:PID vypíše shrnutí.
   **UI na tty7:** unit `motogo-ui` před startem přepne VT (`ExecStartPre=-+/usr/bin/chvt 7`) a instalátor
   nainstaluje `/etc/polkit-1/rules.d/50-motogo-kiosk.rules` (motogo smí `org.freedesktop.login1.chvt`);
   bez toho logind odmítne `Session.Activate` pro neaktivní session a cage se restartuje do nekonečna.
3. **Diagnostika pobočky hned po nahrání:** na displeji (setup obrazovka → „🔍 Diagnostika pobočky", nebo hlavní
   klávesnice) zadej diagnostický kód → kompletní běh: rozhraní/routy/DNS, LTE, internet, spojení s Velínem,
   dostupnost všech modulů z HW mapy, software a služby, konfigurace zón, HW test každé prázdné kóje (světlo,
   zelená, tón, dveřní kontakt, klidový stav zámku, Shelly), **scan celé LAN** (TCP porty 502/80/443/22/8080…,
   identifikace Waveshare přes Modbus a Shelly přes RPC, MAC z ARP) a **protokol „kde je problém a co s tím“ na
   displeji i ve Velíně** (blok „Kompletní diagnostika pobočky"; před spárováním se odešle po spárování, zóny se
   berou z lokální `hardware.yaml`). Viz níže.
4. **Párování:** ve Velíně → Samoobsluha → Řídicí jednotka → přidat zařízení → ID + token.
   Zadej do `config.yaml` (`device.id/token`) nebo na dotykovém UI (setup obrazovka / servisní panel → Přepárovat).
5. **Síť (SPEC §4):** `sudo /opt/motogo/scripts/set-static-lan.sh` — eth0 = `192.168.50.10/24`
   **bez výchozí brány**, internet výhradně přes LTE (`motogo-lte`, route-metric 100). Skript nejdřív
   aktivuje `motogo-lan` (NM nahradí DHCP profil atomicky), pak konkurenčním profilům vypne autoconnect
   a ověří, že `ip route` nemá `default via … dev eth0`. **Přes SSH na eth0 spojení spadne** (IP se
   mění) — skript se sám odpojí od terminálu, doběhne a výstup nechá v `/var/log/motogo-set-static-lan.log`;
   připoj se znovu na `192.168.50.10`. Kontrola LTE: `mmcli -m any`, `nmcli con show motogo-lte`
   (stav `locked` = chybí PIN → `sudo ./scripts/install.sh`; PIN SIM je u všech poboček **1234** — výchozí hodnota install.sh,
   jiný PIN = `MOTOGO_SIM_PIN`).
6. **Waveshare (SPEC §4/§6)** — ve webovém rozhraní modulu (výchozí IP viz manuál Waveshare):
   statická IP `192.168.50.20` (WAV645), `.21` (WAV617-A), `.22` (WAV617-B), maska `/24`, bez brány;
   `mode: TCP server`, `protocol: Modbus TCP`, `port 502`, `unit id 1`, `gateway type: multi-host
   non-storage`, interní sériovka `115200-8-N-1`. WAV617: všech 8 relé v režimu **Normal** (program
   si to při startu vynutí zápisem `0x1000–0x1007 = 0`).
7. **Shelly Pro RGBWW PM (SPEC §5/§7):** profil **Lights ×5**, statická IP `192.168.50.31–34`,
   cloud vypnout, Bluetooth vypnout, autentizaci RPC nezapínat (LAN je izolovaná). Ověření:
   `curl -s http://192.168.50.31/rpc/Shelly.GetStatus`.
8. **Zvuková karta:** instalátor USB kartu (AXAGON) najde sám a při založení `hardware.yaml` nastaví
   `audio.device` (viz krok 2); zkontroluj shrnutí instalace nebo `aplay -l` → název karty (např. `Device`)
   a do Velína zadej `audio.device` = `alsa/plughw:CARD=Device` (Velín má přednost před `hardware.yaml`).
   Hlasitost karty `alsamixer -c Device`. Test bez zón: `speaker-test -D plughw:CARD=Device -c 1 -t wav -l 1`.
   **Režim `multi` (9 nezávislých kanálů):** každá místnost vlastní kartu/výstup — kartám dej stálá jména podle USB
   portu (`/etc/udev/rules.d/70-motogo-audio.rules`, `HARDWARE.md` §4), pak ve Velíně → hardware → Audio: režim
   `multi`, výstupy `alsa/plughw:CARD=<jméno>` z `aplay -L`, u dveří role Audio = výstup, výstup venku v bloku Venek.
9. **Hudba:** ve Velíně → Samoobsluha → **„Hudba pobočky“** — přetáhnout soubory, zvolit cíl (společná / kóje /
   šatna / venek); jednotka si je stáhne sama do `/var/lib/motogo/music/tracks`. Ruční soubory přímo v
   `/var/lib/motogo/music` (vlastník `motogo`) = společná hudba. Náhodné míchání, smyčka, jen během relace (viz „Hudba“).
10. **Ověření na místě:** servisní heslo → servisní panel → u každé zóny „Otevřít" (světlo, zelená,
   hudba, zámek) a zkontrolovat, že po zavření dveří přejde stav na `CLOSED_CONFIRMATION → SECURED`.
   Checklist před provozem je v `HARDWARE.md`.

## Provoz

```bash
systemctl status motogo-controller motogo-health motogo-ui
journalctl -u motogo-controller -f          # události zón, Modbus, Supabase
journalctl -u motogo-health -f              # LTE, teploty, reconnecty
curl -s http://127.0.0.1:8080/api/state | python3 -m json.tool   # živý stav (= kiosk_report_status)
curl -s 'http://127.0.0.1:8080/api/events?limit=50'              # posledních N událostí
sudo systemctl restart motogo-controller    # bezpečný restart (all relays off při startu i stopu)
sudo /usr/local/sbin/motogo-update          # aktualizace software ručně (viz Aktualizace; log /var/log/motogo-update.log)
sudo /usr/local/sbin/motogo-sysupdate       # apt full-upgrade ručně (nikdy nerestartuje; REBOOT_REQUIRED=/UPGRADED= na konci)
systemctl list-timers apt-daily-upgrade.timer   # záplaty OS: další běh 04:00 ± 20 min; log /var/log/unattended-upgrades/
ls /run/reboot-required* 2>/dev/null        # existuje = OS čeká na restart (Velín chip „Restart OS potřebný“)
```
Watchdog: controller posílá `WATCHDOG=1` jen pokud běží čtení kontaktů (jinak restart do 60 s,
`WatchdogSec=60`); health má `WatchdogSec=300` (jeden cyklus s nmcli/USB resetem trvá až ~100 s).
Při startu program VŽDY vypne všechna relé, Shelly a audio, načte kontakty, zavřeným zónám rozsvítí
červenou a teprve pak povolí zadávání kódů (SPEC §12).

Health sonduje internet na **třech nezávislých cílech** (`health.probe_url` = Supabase, `google.com/generate_204`,
TCP 1.1.1.1:443) a za výpadek považuje jen stav, kdy selžou všechny — výpadek Supabase nebo DNS operátora
tedy nespustí reconnect/USB reset/reboot. Hlásí-li modem `locked` (SIM PIN) nebo `failed` kvůli SIM, politika
obnovy stojí a v payloadu je `lte.error` (`sim_locked`/`sim_missing`/`sim_error`) — viz Řešení problémů.

**Souborový systém — rozhodnutí (SPEC §11):** root zůstává **read-write, overlay se nezapíná**. `/var/lib/motogo`
(SQLite cache kódů + fronta událostí, `health.json`, hudba), `/var/log` a NM profily musí přežít restart a oddělený
rw oddíl program nepodporuje. Ochrana dat: SQLite WAL, průmyslová microSD (pSLC/„High Endurance“, A2) a záložní
napájení RPi (UPS); overlay nikdy nezapínat před go-live ani bez přesunu dat na jiný oddíl.

**Simulátor pro vývoj (bez hardwaru):**
```bash
python3 -m venv venv && venv/bin/pip install -r requirements-dev.txt
venv/bin/python -m motogo_box simulate &                 # WAV645/WAV617 Modbus + 4× Shelly na localhostu
cat > /tmp/motogo-sim.yaml <<'Y'
paths: { data_dir: /tmp/motogo-sim, music_dir: /tmp/motogo-sim/music, hardware_file: config/sim-9zone.yaml, mpv_socket: /tmp/motogo-sim/mpv.sock }
Y
MOTOGO_CONFIG=/tmp/motogo-sim.yaml venv/bin/python -m motogo_box controller   # UI na http://127.0.0.1:8080/
curl -X POST http://127.0.0.1:18099/sim/input -d '{"dev":"wav617a","input":0,"value":false}'  # „otevři dveře" zóny 1
venv/bin/python -m pytest -q                                                 # testy (bez sítě)
venv/bin/python -m motogo_box check-config config/brno-9zone.yaml            # validace HW mapy
```

## Hudba

Hudba se nahrává **ve Velíně** → Pobočky → Samoobsluha → blok **„Hudba pobočky“**: přetažením souborů z PC do drop
zóny (nebo kliknutím vybrat víc souborů) a volbou cíle — **Všechny kóje (společná)**, **Kóje 1–N**, **Šatna**, **Venek**.
Formát libovolný, co přehraje mpv/ffmpeg (mp3, wav, flac, ogg/oga/opus, m4a/aac, wma, aiff, webm/mkv), max 200 MB na
soubor, nic se nepřekódovává. V seznamu lze měnit pořadí (▲▼), název, cíl, skladbu vypnout, přehrát v prohlížeči,
stáhnout nebo smazat (smaže i soubor v úložišti).

**Co hraje po zadání kódu:** kód kóje → skladby té kóje; kód šatny → skladby šatny; **venek hraje při jakémkoli kódu**
(dokud běží aspoň jedna relace, + doběh `timings.music_after_close_s` po poslední). Cíl bez vlastních skladeb hraje
**společnou** hudbu (Všechny kóje + ruční soubory přímo v `/var/lib/motogo/music`); nemá-li ani tu, nehraje nic
(Velín u cíle ukáže „0 — nehraje nic“). Náhodné míchání (`audio.shuffle`), smyčka, fade-in/out; po zavření dveří
doběh `music_after_close_s` (10 s).

**Režimy (Velín → hardware → sekce Audio, `audio.mode`):**
- `selector` (výchozí, dosavadní zapojení): 1 mono zesilovač + reléový přepínač reproduktorů — hraje vždy jen **jedna**
  kóje (poslední otevřená), ale už s vlastním playlistem; **venek v tomto režimu nefunguje** (jednotka to hlásí jako
  „Upozornění:“ v `config_problems`).
- `multi` (7 kójí + šatna + venek = 9 nezávislých kanálů): každá místnost má **vlastní zvukový výstup** (USB zvukovka
  nebo pár vícekanálové karty, `HARDWARE.md` §4) a vlastní proces mpv → hraje současně v libovolném počtu kójí, každá
  svůj playlist, venek při jakémkoli kódu. Ve Velíně: režim `multi`, seznam výstupů (název → ALSA zařízení dle
  `aplay -L`, např. `alsa/plughw:CARD=Box1`; tlačítko „Vzor 9 výstupů“), výstup venku v bloku **Venek** (sekce `outdoor`), u každých dveří role
  Audio = výstup (volitelně + „enable“ relé zesilovače). Změna režimu/výstupů = bezpečná přestavba jednotky (počká,
  až v žádné kóji nikdo není).

**Synchronizace na jednotce:** seznam skladeb přichází s konfigurací (`kiosk_sync_config.music`, á 60 s); jednotka si
soubory sama stáhne z bucketu `branch-music` do `/var/lib/motogo/music/tracks/<id>.<ext>` (max 3 najednou, index
v SQLite kv `music_index`), odebrané smaže, hrající kanál nikdy neutne (nový playlist až po zastavení). Nestažená
skladba se opakuje s rostoucím odstupem (2 min … 6 h); ve Velíně chip **„Jednotka: n/m staženo / stahuje k /
k selhalo“** a tlačítko **„Znovu synchronizovat“** (= `sync_config`, selhané zkusí hned). Stav: `api/state → audio`
(`mode`, `playing_zones`, `channels`, `players`, `library`), log `journalctl -u motogo-controller | grep motogo.music`.

## Vzdálené příkazy z Velína (`kiosk_commands`)

| příkaz | parametry | akce |
|---|---|---|
| `open_door` | `door_id` / `zone` / `box_number` | plná přístupová sekvence zóny (servisní otevření) |
| `music_on` / `music_off` | `zone?` / `door_id?` / `box_number?` | hudba v zóně (bez zóny první) / stop — se zónou jen tato kóje (multi: ostatní hrají dál), bez zóny vše; `zone` = venek → hudba venku ručně (jen multi, jinak `outdoor_requires_multi`) |
| `light_on` / `light_off` | `zone` / `door_id` | bílé světlo; `zone` = číslo venku → venkovní světlo ručně (on drží, off zhasne do další relace) |
| `set_signal` | `zone`, `signal` (`red/green/off/green_pulse/red_blink/both_blink`) | ruční signalizace |
| `zone_test` | `zone` | test bez zámku: světlo → zelená 1 s → červená → světlo off; audio 3 s; `zone` = venek → světlo 1 s (jen s relé světla) + tón venku 3 s (jen multi), při relaci `busy` |
| `audio_test` | `zone`, `seconds?` | hudba v zóně na N s |
| `all_off` | – | vše vypnout (relé, Shelly, audio), zóny zabezpečit |
| `identify` | `label?` | „Tady jsem" na displeji + 3× bliknutí zelené |
| `reload` / `sync_config` | – | stáhnout konfiguraci, cache kódů a seznam hudby (sync knihovny na pozadí; selhané stahování zkusí hned — Velín „Znovu synchronizovat“) |
| `restart` | – | restart procesu controlleru |
| `reboot` | `wait_idle?`, `wait_idle_s?` | `systemctl reboot`; s `wait_idle:true` (Velín „Restart OS“ v bloku Aktualizace) až když je box volný — hned vrací `{scheduled}`, průběh v `status.update` |
| `update_software` | `ref?` (sha 7–40), `rollout_id?`, `wait_idle_s?` (výchozí 1800) | naplánuje `sudo /usr/local/sbin/motogo-update` (root-owned kopie `scripts/update.sh`: git fetch + ff-merge na `ref` / větev, pip, restart) — provede se, až je box volný; hned vrací `{scheduled}`; odmítne `invalid_ref` / `update_in_progress` |
| `update_system` | `rollout_id?`, `wait_idle_s?`, `auto_reboot?` | naplánuje `sudo /usr/local/sbin/motogo-sysupdate` (apt full-upgrade, bez restartu); `auto_reboot` = po novém jádru `systemctl reboot`, až je box volný |
| `http_get` / `camera_control` | `url` | HTTP GET na LAN (kamery, měnič) |
| `diagnostics` | `mode?` (`full` výchozí / `network` = jen síť), `cameras?` (seznam z Velína), `reason?` | kompletní diagnostika pobočky na pozadí (1–4 min; `network` 10–60 s); report + protokol → `kiosk_report_diagnostics` (Velín blok „Kompletní diagnostika pobočky") |

Příkazy chodí přes Supabase Realtime (broadcast) s pojistkou pollingu každých 10 s; výsledek
se hlásí přes `kiosk_complete_command`. Živý stav zón vidí Velín z `kiosk_report_status` (30 s).
Dokud běží aktualizační skript (git/pip/apt), jednotka odmítá `restart` i `reboot` s `update_in_progress`.

## Diagnostika pobočky

Jeden běh (`motogo_box/diagnostics.py` + `diag_steps.py` + `diag_protocol.py` + `diag_hints.py` + `net_scan.py`)
prověří celou pobočku a vydá **protokol „kde je problém a co s tím“**. Režim **kompletní** (`full`, výchozí,
1–4 min, limit 240 s) kontroluje:
- **Řídicí jednotka:** verze, uptime, teplota CPU, throttling/podpětí, disk, RAM, NTP, ready, chyby HW mapy.
- **Program a služby:** `motogo-controller/health/ui` (systemctl), selhané jednotky, stáří health hlášení, mpv + hudba
  (soubory/playlist), fronta neodeslaných RPC, cache kódů (stáří), PIN lockout, chyby za 24 h, poslední aktualizace,
  „restart OS potřebný“.
- **Síť:** rozhraní + IP/MAC, výchozí brána (chybí / vede přes eth0), DNS; **LTE** (mmcli/nmcli: stav, operátor,
  RSSI/RSRP/RSRQ/SNR); **internet** (DNS překlad, TCP 1.1.1.1:443, HTTP sondy); **Velín** (párování, heartbeat, realtime).
- **Moduly Waveshare/Shelly:** každé zařízení z HW mapy — TCP, ping, identifikace (WAV645/WAV617 přes Modbus FC01/FC02,
  Shelly přes `Shelly.GetDeviceInfo`), shoda typu s konfigurací, IP konflikt, online v programu.
- **Konfigurace pobočky:** zóny/dveře s HW mapou, chybějící role (zámek/kontakt = chyba, ostatní varování), dveře ve
  Velíně bez mapy, duplicitní kanály, časování mimo rozsah.
- **Zóny a periferie (každá kóje):** dveřní kontakt — hodnota z modulu vs. stav programu; zámek — modul online a relé
  v klidu ROZEPNUTÉ (**jen čtení, zámek se nikdy nespíná**); HW test světlo → zelená 1 s → obnova → tón 3 s a
  skutečný stav Shelly (`Light.GetStatus`) vs. požadovaná barva.
- **Venek (zóna 9, je-li nastaven):** modul relé venkovního světla online a stav relé (jen čtení), HW test světlo 1 s → obnova
  + tón venku 3 s (jen `multi`; nikdy při běžící relaci); v konfiguraci položka „Venek“. Do počtu zón se nepočítá.
- **Napájení (FV):** `power_status_url` pobočky (HTTP + JSON: SOC, napětí, výkony, síť) — nenastaveno = přeskočeno.
- **Kamery:** snapshot/stream URL předané Velínem (HTTP, tělo streamu se nečte); bez seznamu = přeskočeno.
- **Ostatní zařízení v LAN:** scan podsítí vlastních rozhraní + `diagnostics.scan_subnets` (porty `scan_ports`,
  identifikace Modbus/Shelly/HTTP, MAC z ARP) — cizí Modbus/Shelly mimo mapu = varování; tabulka ARP; průběh kroků.

Režim **jen síť** (`network`, 10–60 s, limit 120 s) = jen síťové kroky (systém, rozhraní, LTE, internet, Velín, moduly, LAN, ARP).

**Bezpečnost HW testu:** světlo/zelená/tón se spíná JEN v kóji bez relace, bez poruchy, s online I/O a připravenou
jednotkou; obsazená kóje se jen přečte (`session_active`). Zámek se **nikdy** nepulzuje. Test má rozpočet (nespustí
se, když by se do limitu nevešel; při přerušení se světlo a signalizace vždy obnoví a tón zastaví). Pobočka, kde technik
nechce blikat: `diagnostics.zone_test: false` v `config.yaml` (zóny se jen čtou).

**Spuštění:** (a) Velín → Samoobsluha → „Kompletní diagnostika pobočky (Raspberry)“ → **🔍 Kompletní diagnostika**
(příkaz `diagnostics {mode:'full', cameras}`) nebo malé **jen síť**; Velín ukazuje průběh „krok X (n/m)“ a čeká na
report až 5 min; (b) na displeji zadat `diagnostics.code` z `config.yaml` (hlavní klávesnice nebo setup obrazovka →
„🔍 Diagnostika pobočky“; funguje i před spárováním a při startu HW); (c) servisní heslo z Velína s účelem „diagnostika"
(jen diagnostika, nic neotevírá) nebo běžné servisní heslo → servisní panel → „🔍 Diagnostika pobočky". Displej i hesla
spouští vždy kompletní běh; jeden běh najednou (`already_running`).

**Protokol** (stejný na displeji i ve Velíně): hlavička (pobočka, jednotka, verze, datum, trvání, režim, výsledek
„Pobočka je v pořádku“ / „N problémů, M varování“, počty kontrol), blok **Kde je problém** (každá chyba: kontrola —
zjištění — „→ Co s tím“ = konkrétní rada s modulem/kanálem/IP), **Varování**, pak sekce Řídicí jednotka, Program a
služby, Síť, LTE, Internet, Spojení s Velínem, Moduly Waveshare / Shelly, Konfigurace pobočky, Zóny a periferie
(souhrn kóje + položka na každý nález), Napájení (FV), Kamery, Ostatní zařízení v LAN, Průběh diagnostiky (kontroly OK
sbalené). Velín: **Stáhnout protokol (.txt)** (`diagnostika-<pobocka>-<YYYYMMDD-HHMM>.txt` — hlavička, VÝSLEDEK, KDE JE
PROBLÉM, VAROVÁNÍ, [SEKCE] …) a **Kopírovat** (schránka); sbalený „Technický detail sítě“ (syrové tabulky, celý JSON).
Uložení: overlay na displeji + `GET /api/diagnostics` (localhost), Supabase `kiosk_diagnostics` (posledních 30 na
zařízení, přes `kiosk_report_diagnostics` z outboxu — před spárováním se odešle po spárování), souhrn do `kiosk_logs`
(zdroj `diagnostics`), SQLite kv `last_diagnostics`. Starší reporty bez protokolu se zobrazí jako dřív (jen síťový detail).

**Konfigurace (`config.yaml` → `diagnostics:`):** `code`, `scan_ports`, `scan_timeout_ms`, `scan_concurrency`,
`scan_subnets`, `max_hosts`, `internet_urls`, `timeout_s` (jen síť, 120), `full_timeout_s` (kompletní, 240),
`zone_test` (true), `camera_timeout_s` (6 — kamery i měnič FV).

## Aktualizace

**Verze a release.** Jednotka hlásí `<verze>+<git sha7>` (heartbeat); Velín porovnává sha s nejnovějším releasem. Release =
commit v `main`, který změnil `raspberry/motogo-box/**` — po merge ho workflow `.github/workflows/release-motogo-box.yml`
zapíše do `kiosk_releases` (verze, sha, zpráva, autor, datum). **Push do main NIKDY jednotky neaktualizuje sám.** Ruční běh
workflow (Actions → Run workflow, vstup `commit` = plný sha z main) slouží jen k doplnění chybějícího NOVĚJŠÍHO commitu (např.
tabulka při prvním nasazení ještě neexistovala — workflow na ni čeká ~5 min a pak skončí varováním); starší commit workflow
odmítne; červený běh = chyba psql (issue se nezakládá).

- **Jedna jednotka:** Velín → Samoobsluha → Řídicí jednotka → „Aktualizovat software“ (`update_software`). Příkaz se jen
  NAPLÁNUJE a provede se, až v boxu nikdo není (žádná relace, neběží diagnostika — nejdéle „čekání na klid“ `wait_idle_s`,
  výchozí 30 min, pak i tak). Výsledek poznáte z hlášené verze a řádku „Aktualizace: čeká na klid / probíhá / selhalo“
  (`status.update`). Během běhu skriptu se `restart`/`reboot` odmítají (`update_in_progress`).
- **Všechny pobočky:** Velín → Pobočky → „Aktualizace řídicích jednotek (všechny pobočky)“: seznam releasů, tabulka jednotek
  (verze, Aktuální/Zastaralá, stav aktualizace, OS + jádro + datum záplat, chip „Restart OS potřebný“, tlačítka „Restart OS“
  a „Aktualizovat OS“ pro jednu jednotku), „Aktualizovat všechny pobočky“ → dialog (kanárek, sledování min, čekání na klid s)
  → **kanárek → sledování (soak: bez chyb v `kiosk_logs`, online) → zbytek poboček**; průběh po jednotkách, „Zrušit“,
  „Zkontrolovat teď“ (jinak vyhodnocení každých 5 min přes pg_cron); nastavení automatiky; historie posledních 10. Chyba,
  výpadek nebo timeout kanárka rollout zastaví — ostatní jednotky se netknou. Offline jednotky se zkouší až 24 h.
- **Noční automatika:** v nastavenou hodinu (výchozí 03:00 Prahy) se sama spustí aktualizace na nejnovější release, pokud
  nějaká jednotka viděná za posledních 24 h zaostává — stejný postup přes kanárka, nejvýš jednou za noc.
- **OS (Debian):** bezpečnostní záplaty instaluje `unattended-upgrades` sám v noci ve **04:00 ± 20 min** (jen Debian-Security,
  bez restartu, zmeškaná noc se nedohání v provozní době). Úplný `apt full-upgrade` = „Aktualizovat OS“ (jedna jednotka, bez
  restartu), „Aktualizovat OS na všech pobočkách“ (kanárek → soak → zbytek, volba „automatický restart po novém jádru“) nebo
  automaticky každých N dní (nastavení; stejná noční hodina, software má přednost). Restart OS: tlačítko „Restart OS“
  (`reboot` s `wait_idle` — provede se, až je box volný), nebo automaticky po jádru, když je box volný. Chip „Restart OS
  potřebný“ = `/run/reboot-required` (na Debianu ho zakládá až motogo-sysupdate / hook po unattended-upgrades).
- **Rollback:** revert commit v `main` + nový rollout. Jednotka se posouvá jen dopředu (`git merge --ff-only` na cílový
  commit; starší commit / jiná větev = kód 3).
- **Jak to běží na jednotce:** `sudo /usr/local/sbin/motogo-update` (root-owned kopie `scripts/update.sh`, sudoers jen bez
  argumentů; změna v `/opt/motogo/scripts/update.sh` se projeví až dalším během): cíl z `/var/lib/motogo/update_ref` (zapíše
  controller z `ref`, jinak větev; soubor se vždy smaže), `git fetch origin` + `git merge --ff-only` **jako vlastník checkoutu**
  (`/etc/motogo/source_dir`; credential helper / deploy key bez hesla — root žádné nemá), rsync do `/opt/motogo`, pip jen v
  mezích `requirements.txt` (`MOTOGO_PIP_UPGRADE=1` povýší v rámci rozsahů), obnova změněných unit/sudoers/polkit/apt
  konfigurace, doinstalování `unattended-upgrades`, restart controller + health (za 2 s přes systemd-run). Skript drží flock
  (souběh = „už běží“, kód 2) a běží ve vlastním systemd scope, takže restart/pád controlleru ho nezabije. Ručně jako root:
  `sudo /usr/local/sbin/motogo-update` (nebo `sudo /opt/motogo/scripts/update.sh /cesta/k/nove/verzi` — argument jen při
  ručním spuštění rootem, ne přes sudo od `motogo`). OS: `sudo /usr/local/sbin/motogo-sysupdate` (žádné argumenty; apt update
  → full-upgrade → autoremove → clean; nikdy nerestartuje; na konci vypíše `REBOOT_REQUIRED=0|1` a `UPGRADED=<n>`). Logy
  `/var/log/motogo-update.log`, `/var/log/motogo-sysupdate.log` (root-owned). Venv patří uživateli `motogo`, root ho nespouští.
- **První rollout na stávajících jednotkách:** provede ho ještě starý controller a starý `motogo-update` (hned, bez čekání na
  klid, na větev; starý controller čeká na skript max 120 s — trvá-li pip déle, ohlásí příkaz timeout, což rollout
  ignoruje: čeká dál na hlášenou novou verzi). `motogo-sysupdate` a
  `unattended-upgrades` se nainstalují až dalším během — „Aktualizovat OS“ do té doby hlásí `sysupdate_missing` → spusťte
  znovu „Aktualizovat software“.

## Řešení problémů

| projev | příčina | co dělat |
|---|---|---|
| zóna bliká **červená i zelená** (BOTH_BLINK), UI hlásí `io_offline`, kódy pro zónu odmítá | Modbus modul zóny (WAV645/WAV617) nebo Shelly nedostupné | `ping 192.168.50.20/21/22`, `curl http://192.168.50.31/rpc/Shelly.GetStatus`, kabel/switch/napájení 24 V; po návratu modulu se zóna sama obnoví (`IO_ONLINE`) |
| **červená bliká** (RED_BLINK), `forced_open` / `open_at_startup` | dveře otevřené bez přístupu, přerušený kabel kontaktu, špatná polarita (`closed_level`) | zkontrolovat dveře a kontakt; ověřit polaritu podle `HARDWARE.md`; po zavření se zóna vrátí do SECURED |
| kód odmítnut „Chyba spojení" | není internet ani cache | `journalctl -u motogo-health`, `mmcli -m any`; cache se plní po prvním úspěšném `kiosk_sync_config` |
| „Příliš mnoho neplatných pokusů" | PIN lockout (5 pokusů / 5 min → 15 min) | počkat nebo restart controlleru (lockout je v SQLite — přežije restart) |
| LTE offline dlouhodobě | slabý signál / modem zamrzl | health sám: 5× výpadek (všechny 3 sondy) → `nmcli con up`, 5× reconnect → USB reset modemu, 3× reset → reboot (jen při uptime ≥ 30 min). Ručně: `sudo /usr/local/sbin/motogo-usbreset` (VID:PID z `/etc/motogo/modem_vidpid`; jako root přímo lze `usbreset-modem.sh 1e0e:9001`); `mmcli -m any --signal-get` |
| `mmcli -m any` = `locked`, health hlásí `lte.error=sim_locked` (nebo `sim_missing`) | SIM má PIN a profil ho nezná / SIM chybí | `sudo ./scripts/install.sh` — PIN SIM je u všech poboček **1234** (výchozí hodnota install.sh; jiný PIN = `MOTOGO_SIM_PIN`; zapíše `[gsm] pin=` do `motogo-lte`); health v tomto stavu záměrně nedělá reconnect/USB reset/reboot |
| Velín: `update_software` selhal (kód 3) | `git fetch` / `git merge --ff-only` ve zdrojovém checkoutu selhal: síť, přihlášení, větev bez upstreamu, nebo cíl z Velína (`/var/lib/motogo/update_ref`) není dopředný potomek HEAD — starší commit, jiná větev, neznámý sha | `sudo cat /var/log/motogo-update.log`; jako vlastník checkoutu ověř `git fetch origin` (credential helper / deploy key); rollback = revert commit v main a nový rollout (checkout se nikdy necouvá); ručně `sudo /usr/local/sbin/motogo-update` (kód 2 = „už běží“ / chybný zdroj) |
| Velín: `update_software` / `update_system` / `restart` / `reboot` → `update_in_progress` | běží jiná aktualizace, nebo předchozí běh vypršel a root skript možná ještě běží (`reason: timeout_orphan`, `retry_after_s`) | počkat (řádek „Aktualizace“ / `status.update`), `sudo cat /var/log/motogo-update.log /var/log/motogo-sysupdate.log`; lhůta = délka timeoutu skriptu (15 / 45 min), restart controlleru ji zruší |
| Velín: „Aktualizovat OS“ selhalo `sysupdate_missing` | starší instalace bez `/usr/local/sbin/motogo-sysupdate` (nainstaluje ho až nový `motogo-update`) | spustit „Aktualizovat software“, pak OS aktualizaci znovu |
| Velín: rollout `Selhalo` | `canary_failed: update_failed …` (kanárek nahlásil chybu — `status.update.last.error`, např. `rc=3`) / `command_failed` / `command_expired` (příkaz selhal nebo nebyl vyzvednut do 10 min); `canary_timeout` (kanárek se do čekání na klid + 45 min neaktualizoval — offline, dlouhá relace, pomalý git/pip); `canary_errors: N` (během sledování chyby error/crash v `kiosk_logs` — `result.errors`); `canary_offline` (kanárek > 10 min neviděn); `devices_failed: N` (po rozeslání selhaly jednotky — detail u řádků) | historie v bloku Aktualizace + logy kanárka (Samoobsluha → Logy), na jednotce `journalctl -u motogo-controller`, `/var/log/motogo-update.log`; opravit a spustit nový rollout (jednotky už na cíli přeskočí rovnou do soak / `updated`) |
| OS záplaty se neinstalují / chip „Restart OS potřebný“ nezmizí | timer nebo balík `unattended-upgrades` chybí; nové jádro čeká na restart | `systemctl list-timers apt-daily-upgrade.timer` (04:00 ± 20 min), `unattended-upgrade --dry-run -d`, `/var/log/unattended-upgrades/unattended-upgrades.log`, `cat /run/reboot-required.pkgs`; restart z Velína („Restart OS“ — provede se, až je box volný) |
| UI černé / „Řídicí jednotka nedostupná" | controller neběží nebo startuje | `systemctl status motogo-controller`; UI se samo připojí po startu |
| UI černé, `journalctl -u motogo-ui` opakuje „Could not activate session“ | session motogo na tty7 není aktivní (VT nepřepnuto / chybí polkit pravidlo) | `chvt 7` ručně, ověř `/etc/polkit-1/rules.d/50-motogo-kiosk.rules` a balík `kbd` (unit dělá `chvt 7` v `ExecStartPre`); `loginctl session-status` |
| bez zvuku (režim selector) | špatný `audio.device`, hlasitost karty, sepnuté relé jiné zóny | `aplay -l`, `alsamixer`, servisní panel → Hudba v zóně; `api/state` → `audio.playing_zone`, `audio.players.mpv.alive` |
| kanál (kóje / šatna / venek) mlčí v režimu multi | zóna nemá výstup, špatné ALSA zařízení výstupu, mpv výstupu neběží, prázdný playlist | `api/state → audio.players[out]` (`alive`, `device`, `playlist_count`, `playing`); `aplay -L` → jméno karty musí odpovídat `audio.outputs[out].device` (`alsa/plughw:CARD=…`), stálá jména podle USB portu viz `HARDWARE.md` §4; `speaker-test -D plughw:CARD=<jméno> -c2 -t wav -l1`; `config_problems` („Zóna N: nemá audio výstup“) |
| skladba z Velína se na jednotce nestáhla (chip „k selhalo“ / dlouho „stahuje“) | výpadek LTE, timeout, chyba velikosti, neplatný záznam — opakuje se s odstupem 2 min … 6 h | `api/state → audio.library` (`failed`, `reason`, `last_sync_at`); Velín → Hudba pobočky → „Znovu synchronizovat“ (zruší odstup); `journalctl -u motogo-controller \| grep motogo.music`; volné místo v `/var/lib/motogo/music/tracks` |
| venek nehraje | jednotka běží v režimu `selector` (hudba venku jen v `multi`), venek nemá audio výstup, nebo nemá vlastní ani společnou hudbu | Velín → hardware → Audio: režim `multi`; blok **Venek** → Audio výstup (`outdoor.audio.out`); `config_problems` „Upozornění: kanál outdoor (venek) nelze v režimu selector“, příkaz z Velína `outdoor_requires_multi`; u cíle Venek nesmí být „0 — nehraje nic“ |
| venkovní světlo nesvítí / nezhasne | relé venku (WAV617-B R1) neodpovídá nebo modul offline, ruční režim z Velína, chybí sekce `outdoor` | dlaždice „Venek“ ve Velíně (světlo „(ručně)“ → Světlo ⏹ vrátí automatiku po další relaci), `api/state → outdoor` (`light`, `manual`, `off_in_s`), diagnostika → „Venek (zóna 9) — venkovní světlo“; `journalctl -u motogo-controller \| grep motogo.outdoor` |
| Velín hlásí zařízení offline | LTE / token | `nmcli con show motogo-lte`; přepárovat v servisním panelu |
| nevím, co na pobočce nefunguje | — | Velín → Samoobsluha → „Kompletní diagnostika pobočky“ → 🔍 (nebo diagnostický kód na displeji); protokol má blok „Kde je problém“ s radou „Co s tím“ u každé chyby, .txt ke stažení pro technika; rychlý přehled sítě = „jen síť“ |
| protokol: „dveřní kontakt: program hlásí zavřeno, modul wav617a DI3 čte otevřeno“ (Kóje N — dveřní kontakt) | NC kontakt, vodič do DI vstupu WAV617 nebo obrácená polarita `closed_level` | podle rady v protokolu: kontakt / vodič / `closed_level` v HW mapě (Velín → Samoobsluha → Zóny); polarita viz `HARDWARE.md` |
| protokol: „světlo: relé wav617a R2 nepotvrdilo sepnutí“ (Kóje N — světlo) | vodič ke světlu / svorky relé daného kanálu, modul není v režimu Normal | zkontrolovat vodič a svorky relé R<N>; Normal mode si program vynucuje při startu → restart controlleru |
| protokol: „červená signalizace má svítit, Shelly shelly1 světlo 0 je vypnuté“ / „… neodpovídá na Light.GetStatus“ (Kóje N — Shelly signalizace) | LED pásek bez napájení, špatný `light id` kanálu v HW mapě, Shelly offline | napájení pásku, kanál (light id) v HW mapě, `curl http://<ip>/rpc/Shelly.GetStatus`; offline Shelly viz první řádek |
| protokol: „zámek: relé wav645 R3 je SEPNUTÉ v klidu — NEBEZPEČÍ, odpojte modul“ (Kóje N — zámek) | relé zámku drží v klidu sepnuto = zámek pod proudem (program relé zámku nikdy nedrží) | **ihned odpojit modul / napájení zámku**, zkontrolovat konfiguraci relé (flash-on 800 ms) a zapojení; do opravy kóji nepoužívat |
| protokol: „Kamera X (snapshot) neodpovídá: …“ | kamera bez napájení / LAN, špatná URL ve Velíně | napájení, LAN, URL kamery (Velín → Samoobsluha → Kamery); z RPi `curl -I <url>` |
| protokol: „Stav napájení nelze stáhnout z <url> (…)“ | měnič/monitor FV nedostupný nebo URL nevrací JSON | `power_status_url` pobočky musí vracet JSON v LAN jednotky; z RPi `curl <url>` |
| protokol: „Test přeskočen: …“ u kóje | relace v kóji, porucha, I/O offline, `zone_test: false`, došel limit běhu | spustit diagnostiku znovu, až bude kóje volná / porucha odezní; u limitu zkontrolovat odezvu modulů a Shelly (ping) |

## Bezpečnostní chování (SPEC §12)

Po každém startu: WAV645 all off → WAV617-A/B all off → Shelly all off → audio off → načíst kontakty →
zavřené+funkční zóny červená, otevřené = porucha → teprve pak PINy. Nikdy nedržet zámek pod napětím
(jen HW flash-on 800 ms), nikdy dva zámky ani dva audio selektory současně, každý příkaz relé se
ověřuje zpětným čtením, při ztrátě Modbus komunikace je přístup do zóny zakázán, při zastavení
programu se vše vypne (dveře zůstávají mechanicky zamčené — fail-secure IBFM 9500). GPIO Raspberry
se pro výkonové/bezpečnostní funkce nepoužívá.
