# MotoGo Box — řídicí jednotka samoobslužné pobočky (Raspberry Pi 5)

Univerzální řídicí program pro VŠECHNY samoobslužné pobočky MotoGo24 (nástupce tabletového
kiosku). Každá pobočka má vlastní řídicí jednotku; počet kójí, zařízení a mapování I/O se
nastavují výhradně ve Velíně (první nasazení: 9zónový box Brno — jeho mapa je výchozí šablona).
**Flow zákazníka, texty, servisní heslo i napojení na Velín zůstávají stejné** — mění se
hardwarová vrstva: místo Shelly relé volaných z tabletu řídí Raspberry Pi přes Modbus TCP
(Waveshare WAV645/WAV617) zámky, světla a dveřní kontakty, přes Shelly Pro RGBWW PM
červenou/zelenou signalizaci a přes mpv + reléový selektor hudbu v konkrétní kóji.
Zadání: `SPEC.md`; rozhraní modulů: `CONTRACT.md`; zapojení a tabulky I/O: `HARDWARE.md`.

## Co program dělá

1. Zákazník zadá **kód k oblečení** → otevře se kóje s oblečením (kind `accessories`).
2. Po zavření zadá **kód k motorce** → otevře se kóje konkrétní motorky (`box_number` → zóna).
3. Při otevření se v kóji **rozsvítí bílé světlo, signalizace přejde na zelenou a začne hrát hudba**
   (jen v té kóji). Po zavření dveří hudba doběhne (10 s) a světlo zhasne (30 s), svítí červená.
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
Více kójí smí být otevřených současně (rozhodnutí §13.7); hudba hraje vždy jen v poslední
otevřené, pulzy zámků se nikdy nepřekrývají.

## Architektura procesů

| systemd unit | proces | obsah |
|---|---|---|
| `motogo-controller.service` | `python -m motogo_box controller` | Modbus I/O, Shelly, audio, stavové automaty zón, Supabase (heartbeat, sync, příkazy, status), lokální web+WS pro UI (`127.0.0.1:8080`), systemd watchdog |
| `motogo-health.service` | `python -m motogo_box health` | LTE watchdog (ModemManager/NetworkManager → reconnect → USB reset modemu → reboot), teplota/throttling/disk/RAM → `POST /api/health` |
| `motogo-ui.service` | `cage -- chromium --kiosk http://127.0.0.1:8080/` | Dotykové UI na EDATEC 1920×1080 (Wayland kiosk na tty7, skript `scripts/kiosk-ui.sh`) |

Lokální data: SQLite `/var/lib/motogo/motogo.db` (cache kódů, fronta neodeslaných událostí,
PIN lockout, posledních 5000 událostí), stav health `/var/lib/motogo/health.json`.

## Co se nastavuje kde (Velín vs. Raspberry)

**Vše o hardwaru se nastavuje ve Velíně** → Pobočky → Samoobsluha → **„Řídicí jednotka (Raspberry)"**:
- `branch_kiosk_config.hardware` (jsonb) — zařízení (IP Waveshare/Shelly), časování, polling,
  polarita kontaktů (`contacts.closed_level`), bezpečnost (PIN lockout), audio, signalizace;
- `branch_doors.hw` (jsonb per dveře) — mapa zóny: zámek (coil), kontakt (input), světlo, audio relé,
  červená/zelená (Shelly light id). Tlačítko „Načíst výchozí mapu (šablona Brno, 9 zón)" předvyplní SPEC §5 — jiná pobočka
  si mapu upraví (jiný počet zón, jiné adresy);
- servisní hesla, zařízení (ID + token), kamery, měnič FV — beze změny oproti tabletu.
Program si konfiguraci stahuje každých 60 s (`kiosk_sync_config`) a při změně zařízení/zón
bezpečně přestaví I/O (vše vypnout → nové zóny).

**Na Raspberry se lokálně nastavuje jen:**
- `/etc/motogo/config.yaml` — Supabase URL/anon key, ID + token zařízení (nebo párování z UI),
  cesty, intervaly, sekce `health` (LTE watchdog) a `diagnostics` (kód pro diagnostiku sítě
  z displeje, porty/podsítě scanu); vzor `config/config.example.yaml`;
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
   Instalátor je idempotentní: nainstaluje balíčky (python3-venv, mpv, cage, chromium,
   network-manager, modemmanager, alsa-utils, rsync, kbd, polkitd), vytvoří uživatele `motogo`, zkopíruje
   program do `/opt/motogo` (venv + pip — bez internetu jen varuje a pokračuje), založí
   `/etc/motogo/config.yaml` a `hardware.yaml` (existující nepřepisuje), `/var/lib/motogo/music`, udev
   pravidlo modemu, `/etc/motogo/modem_vidpid`, NM profily, sudoers, polkit pravidlo pro UI, systemd
   unity, dobíjení RTC baterie (`dtparam=rtc_bbat_vchg=3000000`), vypne `getty@tty7`, služby spustí.
   Zadává se interaktivně nebo přes env: `MOTOGO_DEVICE_ID`, `MOTOGO_DEVICE_TOKEN`, `MOTOGO_APN`,
   **`MOTOGO_SIM_PIN`** (PIN SIM karty — prázdné = SIM bez PINu; zapíše se do `[gsm] pin=` profilu
   `motogo-lte`, jinak zůstane modem ve stavu `locked` a LTE nikdy nenaběhne), `MOTOGO_DIAG_CODE`
   (při založení `config.yaml` se jinak vygeneruje náhodný kód `diagNNNN` — žádný veřejný default z repa;
   existující kód se bez této proměnné nemění; kód se zadává na zákaznické klávesnici a chybné pokusy se
   počítají do lockoutu) a `MOTOGO_MODEM_VIDPID` (výchozí `1e0e:9001`).
   **USB zvuková karta:** instalátor ji najde přes `aplay -l` (název obsahuje `USB`/`AXAGON`) a při založení
   `hardware.yaml` nastaví `audio.device: alsa/plughw:CARD=<název>`; není-li karta připojená, varuje
   (bez toho hraje hudba z HDMI monitoru). Výsledný diagnostický kód, PIN, kartu i VID:PID vypíše shrnutí.
   **UI na tty7:** unit `motogo-ui` před startem přepne VT (`ExecStartPre=-+/usr/bin/chvt 7`) a instalátor
   nainstaluje `/etc/polkit-1/rules.d/50-motogo-kiosk.rules` (motogo smí `org.freedesktop.login1.chvt`);
   bez toho logind odmítne `Session.Activate` pro neaktivní session a cage se restartuje do nekonečna.
3. **Diagnostika sítě hned po nahrání:** na displeji (setup obrazovka → „Diagnostika sítě", nebo hlavní
   klávesnice) zadej diagnostický kód → program prověří rozhraní/routy/DNS, LTE, internet, spojení
   s Velínem, dostupnost všech modulů z HW mapy, **oskenuje celou LAN** (TCP porty 502/80/443/22/8080…,
   identifikace Waveshare přes Modbus a Shelly přes RPC, MAC z ARP) a výsledek **zobrazí na displeji
   a odešle do Velína** (blok „Diagnostika sítě"; před spárováním se odešle po spárování). Viz níže.
4. **Párování:** ve Velíně → Samoobsluha → Řídicí jednotka → přidat zařízení → ID + token.
   Zadej do `config.yaml` (`device.id/token`) nebo na dotykovém UI (setup obrazovka / servisní panel → Přepárovat).
5. **Síť (SPEC §4):** `sudo /opt/motogo/scripts/set-static-lan.sh` — eth0 = `192.168.50.10/24`
   **bez výchozí brány**, internet výhradně přes LTE (`motogo-lte`, route-metric 100). Skript nejdřív
   aktivuje `motogo-lan` (NM nahradí DHCP profil atomicky), pak konkurenčním profilům vypne autoconnect
   a ověří, že `ip route` nemá `default via … dev eth0`. **Přes SSH na eth0 spojení spadne** (IP se
   mění) — skript se sám odpojí od terminálu, doběhne a výstup nechá v `/var/log/motogo-set-static-lan.log`;
   připoj se znovu na `192.168.50.10`. Kontrola LTE: `mmcli -m any`, `nmcli con show motogo-lte`
   (stav `locked` = chybí PIN → `sudo MOTOGO_SIM_PIN=1234 ./scripts/install.sh`).
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
9. **Hudba:** mp3/ogg/flac/wav do `/var/lib/motogo/music` (vlastník `motogo`); playlist se náhodně
   míchá, přehrává se ve smyčce jen během relace v kóji.
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

## Vzdálené příkazy z Velína (`kiosk_commands`)

| příkaz | parametry | akce |
|---|---|---|
| `open_door` | `door_id` / `zone` / `box_number` | plná přístupová sekvence zóny (servisní otevření) |
| `music_on` / `music_off` | `zone?` | hudba v zóně / stop |
| `light_on` / `light_off` | `zone` / `door_id` | bílé světlo |
| `set_signal` | `zone`, `signal` (`red/green/off/green_pulse/red_blink/both_blink`) | ruční signalizace |
| `zone_test` | `zone` | test bez zámku: světlo → zelená 1 s → červená → světlo off; audio 3 s |
| `audio_test` | `zone`, `seconds?` | hudba v zóně na N s |
| `all_off` | – | vše vypnout (relé, Shelly, audio), zóny zabezpečit |
| `identify` | `label?` | „Tady jsem" na displeji + 3× bliknutí zelené |
| `reload` / `sync_config` | – | stáhnout konfiguraci a cache kódů |
| `restart` | – | restart procesu controlleru |
| `reboot` | – | `systemctl reboot` |
| `update_software` | – | `sudo /usr/local/sbin/motogo-update` (root-owned kopie `scripts/update.sh`: git pull / pip / restart) |
| `http_get` / `camera_control` | `url` | HTTP GET na LAN (kamery, měnič) |
| `diagnostics` | `reason?` | kompletní diagnostika sítě na pozadí; report → `kiosk_report_diagnostics` (Velín blok „Diagnostika sítě") |

Příkazy chodí přes Supabase Realtime (broadcast) s pojistkou pollingu každých 10 s; výsledek
se hlásí přes `kiosk_complete_command`. Živý stav zón vidí Velín z `kiosk_report_status` (30 s).

## Diagnostika sítě

Jeden běh (10–60 s, `motogo_box/diagnostics.py` + `net_scan.py`) zjistí: systém (hostname, verze,
teplota, throttling, disk, NTP), rozhraní + IP/MAC + výchozí brány + DNS, LTE modem (mmcli/nmcli:
stav, operátor, RSSI/RSRP/RSRQ/SNR), internet (DNS překlad, TCP 1.1.1.1:443, HTTP sondy), spojení
s Velínem (heartbeat, outbox), **každé zařízení z HW mapy** (TCP, ping, identifikace: WAV645/WAV617
přes Modbus FC01/FC02, Shelly přes `Shelly.GetDeviceInfo`, shoda typu s konfigurací), **scan celé LAN**
(všechny podsítě vlastních rozhraní + `diagnostics.scan_subnets`, porty `scan_ports`, identifikace
Modbus/Shelly/HTTP, MAC z ARP, přiřazení ke konfiguraci) a tabulku ARP. Vyhodnocení = seznam problémů
(bez brány, brána přes eth0, LTE odpojeno, bez internetu, modul nedostupný / jiný typ, IP konflikt,
cizí Modbus/Shelly v LAN, teplota, throttling, disk, NTP, chyby konfigurace).

**Spuštění:** (a) na displeji zadat `diagnostics.code` z `config.yaml` (funguje i před spárováním a
při startu HW), (b) servisní heslo z Velína s účelem „diagnostika" (jen diagnostika, nic neotevírá)
nebo běžné servisní heslo → servisní panel → „Diagnostika sítě", (c) Velín → Samoobsluha →
„Diagnostika sítě" → Spustit (příkaz `diagnostics`). **Výsledek:** overlay na displeji (souhrn,
tabulky, průběh), `GET /api/diagnostics` (localhost), Supabase `kiosk_diagnostics` (posledních 30
na zařízení) přes `kiosk_report_diagnostics` (frontuje se v outboxu), souhrn i v `kiosk_logs`
(zdroj `diagnostics`) a poslední report v SQLite kv `last_diagnostics`.

## Aktualizace

- Z Velína: příkaz `update_software` → `sudo /usr/local/sbin/motogo-update` — **root-owned kopie**
  `scripts/update.sh`, kterou install/update instaluje do `/usr/local/sbin` (sudoers ji povoluje jen bez
  argumentů). Změna v `/opt/motogo/scripts/update.sh` se projeví až po dalším install/update.
- Zdroj = `/etc/motogo/source_dir` (git checkout uložený instalátorem). `git pull --ff-only` běží **jako
  vlastník checkoutu** (jeho credential helper / deploy key bez hesla — root žádné nemá); když pull selže,
  skript končí kódem 3, nic neinstaluje a Velín vidí selhání příkazu.
- Ručně jako root: `sudo /usr/local/sbin/motogo-update` (nebo `sudo /opt/motogo/scripts/update.sh /cesta/k/nove/verzi`
  — argument se přijímá jen při ručním spuštění rootem, ne přes sudo od uživatele `motogo`).
  Log `/var/log/motogo-update.log` (root-owned). pip instaluje jen v mezích `requirements.txt` (žádné slepé
  `--upgrade`; `MOTOGO_PIP_UPGRADE=1` povýší v rámci rozsahů), aktualizuje změněné unity/sudoers/polkit
  a restartuje controller + health. Venv patří uživateli `motogo` a root ho nikdy nespouští.

## Řešení problémů

| projev | příčina | co dělat |
|---|---|---|
| zóna bliká **červená i zelená** (BOTH_BLINK), UI hlásí `io_offline`, kódy pro zónu odmítá | Modbus modul zóny (WAV645/WAV617) nebo Shelly nedostupné | `ping 192.168.50.20/21/22`, `curl http://192.168.50.31/rpc/Shelly.GetStatus`, kabel/switch/napájení 24 V; po návratu modulu se zóna sama obnoví (`IO_ONLINE`) |
| **červená bliká** (RED_BLINK), `forced_open` / `open_at_startup` | dveře otevřené bez přístupu, přerušený kabel kontaktu, špatná polarita (`closed_level`) | zkontrolovat dveře a kontakt; ověřit polaritu podle `HARDWARE.md`; po zavření se zóna vrátí do SECURED |
| kód odmítnut „Chyba spojení" | není internet ani cache | `journalctl -u motogo-health`, `mmcli -m any`; cache se plní po prvním úspěšném `kiosk_sync_config` |
| „Příliš mnoho neplatných pokusů" | PIN lockout (5 pokusů / 5 min → 15 min) | počkat nebo restart controlleru (lockout je v SQLite — přežije restart) |
| LTE offline dlouhodobě | slabý signál / modem zamrzl | health sám: 5× výpadek (všechny 3 sondy) → `nmcli con up`, 5× reconnect → USB reset modemu, 3× reset → reboot (jen při uptime ≥ 30 min). Ručně: `sudo /usr/local/sbin/motogo-usbreset` (VID:PID z `/etc/motogo/modem_vidpid`; jako root přímo lze `usbreset-modem.sh 1e0e:9001`); `mmcli -m any --signal-get` |
| `mmcli -m any` = `locked`, health hlásí `lte.error=sim_locked` (nebo `sim_missing`) | SIM má PIN a profil ho nezná / SIM chybí | `sudo MOTOGO_SIM_PIN=1234 ./scripts/install.sh` (zapíše `[gsm] pin=` do `motogo-lte`) nebo PIN na SIM vypnout; health v tomto stavu záměrně nedělá reconnect/USB reset/reboot |
| Velín: `update_software` selhal (kód 3) | `git pull` ve zdrojovém checkoutu selhal (síť, přihlášení, větev bez upstreamu) | `sudo cat /var/log/motogo-update.log`; jako vlastník checkoutu ověř `git pull --ff-only` (credential helper / deploy key), nebo ručně `sudo /usr/local/sbin/motogo-update` |
| UI černé / „Řídicí jednotka nedostupná" | controller neběží nebo startuje | `systemctl status motogo-controller`; UI se samo připojí po startu |
| UI černé, `journalctl -u motogo-ui` opakuje „Could not activate session“ | session motogo na tty7 není aktivní (VT nepřepnuto / chybí polkit pravidlo) | `chvt 7` ručně, ověř `/etc/polkit-1/rules.d/50-motogo-kiosk.rules` a balík `kbd` (unit dělá `chvt 7` v `ExecStartPre`); `loginctl session-status` |
| bez zvuku | špatný `audio.device`, hlasitost karty, sepnuté relé jiné zóny | `aplay -l`, `alsamixer`, servisní panel → Hudba v zóně; `api/state` → `audio.playing_zone` |
| Velín hlásí zařízení offline | LTE / token | `nmcli con show motogo-lte`; přepárovat v servisním panelu |
| nevím, co v síti nefunguje | — | na displeji zadat diagnostický kód (`diagnostics.code`) nebo Velín → Diagnostika sítě → Spustit; report ukáže rozhraní, LTE, internet, moduly, celou LAN a seznam problémů |

## Bezpečnostní chování (SPEC §12)

Po každém startu: WAV645 all off → WAV617-A/B all off → Shelly all off → audio off → načíst kontakty →
zavřené+funkční zóny červená, otevřené = porucha → teprve pak PINy. Nikdy nedržet zámek pod napětím
(jen HW flash-on 800 ms), nikdy dva zámky ani dva audio selektory současně, každý příkaz relé se
ověřuje zpětným čtením, při ztrátě Modbus komunikace je přístup do zóny zakázán, při zastavení
programu se vše vypne (dveře zůstávají mechanicky zamčené — fail-secure IBFM 9500). GPIO Raspberry
se pro výkonové/bezpečnostní funkce nepoužívá.
