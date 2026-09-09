# Implementační specifikace řídicího systému – 9zónový MotoGo box (Brno)

> Zadání uživatele (2026-09-09), doslovně. Program v tomto adresáři ji implementuje;
> logika/flow zůstává z tabletového kiosku (`Motogo-app-main/motogo-locker-kiosk`),
> mění se hardwarová vrstva + drobný upgrade (stavový automat s dveřními kontakty,
> bezpečnostní pravidla, LTE watchdog, PIN lockout).

## 1. Základní architektura

Raspberry Pi je jediný nadřazený řídicí počítač.

* zámky, světla a kontakty dveří nejsou připojené přímo na GPIO;
* průmyslové vstupy a relé komunikují přes Ethernet a Modbus TCP;
* signalizační LED ovládají Shelly přes lokální HTTP RPC;
* LTE modem, dotykový monitor a zvuková karta jsou připojené přes USB;
* systém musí fungovat lokálně i při výpadku internetu;
* internet slouží pro ověřování rezervací, synchronizaci, monitoring a vzdálenou správu;
* elektrické protiplechy pouze uvolní západku – dveře fyzicky neotevírají ani nezavírají.

## 2. Kompletní seznam komponent

### A. Již vlastněné komponenty

| Počet | Komponenta | Funkce |
|---|---|---|
| 1 | Raspberry Pi 5, 4 GB | Hlavní řídicí počítač |
| 1 | Waveshare SIM7600E-H 4G HAT | Mobilní internet, případně SMS/GPS/AT diagnostika |
| 1 | EDATEC ED-MONITOR-156CA | Dotykové zákaznické rozhraní |
| 9 | IBFM 9500 | Elektrické protiplechy jednotlivých dveří |
| 9 | Dveře/zóny | Samostatně ovládané kóje |

EDATEC má rozlišení 1920 × 1080, HDMI typu A, USB-C pro dotyk, napájení 12–24 V DC přes konektor 5,5 × 2,5 mm a nepotřebuje speciální dotykový ovladač.

IBFM 9500 je fail-secure protiplech s pamětí: elektrický impulz jej odblokuje, zůstane odblokovaný do otevření dveří a po následném zavření se mechanicky znovu zajistí. Má také mechanickou aretaci, která musí být při běžném provozu vypnutá.

### B. Komponenty vybrané na RPishopu

| Počet | Komponenta | Funkce |
|---|---|---|
| 1 | Waveshare WAV645 / Modbus POE ETH Relay 16CH | 9 zámků, 2 audio selektory, 5 rezervních relé |
| 2 | Waveshare WAV617 / Modbus POE ETH Relay (B) | Celkem 16 digitálních vstupů a 16 reléových výstupů |
| 4 | Shelly Pro RGBWW PM | 20 nezávislých PWM kanálů pro červenou/zelenou signalizaci |
| 1 | Teltonika TSW202 | Centrální řízený Ethernet switch |
| 1 | 52Pi DIN pouzdro pro Raspberry Pi 5 | Montáž Raspberry na DIN lištu |
| 1 | Originální Raspberry Pi 5 Active Cooler | Trvalé chlazení Raspberry |
| 1 | Raspberry Pi 64GB microSD A2 | Operační systém, databáze a hudba |
| 1 | Raspberry Pi 5 RTC baterie | Zachování času bez napájení a internetu |
| 2 | Originální Raspberry Pi 27W USB-C zdroj | Jeden provozní, jeden servisní náhradní |
| 1 | Micro-HDMI → HDMI kabel 1 m | Obraz Raspberry → EDATEC |
| 1 | USB-A → USB-C datový kabel | Dotyk EDATEC → Raspberry |
| 1 | USB-A → micro-USB datový kabel | SIM7600E-H → Raspberry |
| 1 | AXAGON USB zvuková karta | Audio výstup Raspberry |
| 1 | Audio oddělovací/odrušovací člen | Potlačení zemních smyček a rušení |
| 1 | 3,5mm audio kabel | Zvuková karta → zesilovač |
| 1 | TPA3116D2 Class-D zesilovač 2×50 W | Centrální audio zesilovač |
| 10 | Waveshare reproduktor 8 Ω / 5 W | 9 kójí + 1 náhradní |
| 5 | CAT6 patch kabel | Síťové propojení modulů |

WAV645 má 16 přepínacích relé 1NO/1NC, zatížitelnost maximálně 10 A při 30 V DC, napájení 7–36 V a podporuje Modbus TCP, Modbus RTU přes Ethernet, HTTP a MQTT.

WAV617 obsahuje osm relé a osm opticky oddělených digitálních vstupů. Vstupy podporují aktivní i pasivní kontakt, takže lze přímo použít beznapěťové NC dveřní kontakty.

Shelly Pro RGBWW PM má pět PWM výstupů, Ethernet, MQTT a lokální HTTP RPC. V režimu Lights × 5 lze každý z pěti výstupů ovládat samostatně. Limit je 5 A na kanál a 16 A celkem na zařízení.

### C. Komponenty nutné koupit jinde

**Napájení**

| Počet | Přesná specifikace | Účel |
|---|---|---|
| 1 | Mean Well NDR-480-24, 230 V AC → 24 V DC, 20 A, 480 W, DIN | Světla, Shelly, Waveshare, monitor a switch |
| 1 | Mean Well NDR-240-12, 230 V AC → 12 V DC, 20 A, 240 W, DIN | Zámky a audiozesilovač |
| 1 | Hlavní dvoupólový jistič/odpínač | Odpojení rozvaděče |
| 1 | Proudový chránič nebo RCBO podle zapojení měniče | Ochrana 230V části |
| 1 | Přepěťová ochrana pro 230V rozvod | Ochrana elektroniky |
| 1 | Servisní zásuvka 230 V uvnitř rozvaděče | Napájení Raspberry zdroje a servis |

Raspberry Pi napájet originálním 27W USB-C zdrojem ze 230 V. Raspberry Pi 5 pro plné napájení USB periferií používá 5 V / 5 A; při slabším zdroji omezuje dostupný proud USB.

**Dveřní kontakty a ochrany**

| Počet | Specifikace |
|---|---|
| 10 | Povrchový nebo zadlabací magnetický kontakt, NC, beznapěťový, průmyslový |
| 10 | TVS dioda 1.5KE18CA nebo ekvivalent pro 12V zámek |
| 9 | DIN pojistková svorka pro každý zámek |
| 9 | Provozní pojistka – hodnotu určit měřením odběru zámku |
| min. 9 | Náhradní pojistky |
| 1 | Samostatná hlavní pojistka 12V větve zámků |

U zámků zatím není doložený proud cívky. Proto se hodnota pojistky nesmí určit odhadem. Nejdříve změřit náběhový a ustálený proud jednoho zámku při 12 V DC.

**Osvětlení**

| Počet | Specifikace |
|---|---|
| 20 m | Bílý LED pásek 24 V, přibližně 8–10 W/m, IP65, 4000–5000 K |
| 20 m nebo kratší úseky podle konstrukce | RGB/RGBW pásek 24 V se společným kladným pólem |
| 9 | Samostatně jištěná větev bílého světla |
| 9 | Hliníkový profil s difuzorem pro hlavní světlo |
| 9 | Profil/kryt pro stavovou signalizaci |

Z RGBW pásku se v současném zapojení používá pouze: R = červená signalizace; G = zelená signalizace; B a W zůstanou nezapojené.

Plné nezávislé RGBW pro všech devět kójí by potřebovalo 36 PWM kanálů, tedy nejméně osm Shelly modulů. Současné čtyři moduly poskytují 20 kanálů, což stačí přesně na červenou a zelenou signalizaci devíti kójí plus dva rezervní kanály.

**Kabeláž**

| Množství | Kabel |
|---|---|
| 100 m | Cu 2×0,75 mm² pro zámky |
| 100 m | Cu 2×0,34 mm² stíněný nebo průmyslový signální kabel pro kontakty |
| 100 m | Cu 2×1,0 mm² pro bílé osvětlení |
| 100 m | Reproduktorový kabel 2×0,75 mm² |
| 100 m | Cu 5×0,5 až 0,75 mm² pro RGBW |
| 50 m | Instalační CAT6, plná měď, ne CCA |
| 20+ | RJ45 konektory odpovídající použitému kabelu |
| 1 | Krimpovací kleště RJ45 |

**Rozvaděč:** IP65 minimálně 600 × 400 × 200 mm; DIN lišty; oddělený prostor 230 V a SELV 12/24 V; DIN svorkovnice +24 V, +12 V a 0 V; samostatné pojistkové svorky jednotlivých větví; ochranná PE svorkovnice; WAGO 221; dutinky 0,25–1,5 mm²; kabelové průchodky; kabelové žlaby; označení všech kabelů a svorek; ventilace nebo termostatické větrání rozvaděče; mechanické zakrytování audiozesilovače.

## 3. Napájecí rozdělení

**230 V AC** (ze střídače solární elektrárny): Mean Well 24 V; Mean Well 12 V; originální USB-C zdroj Raspberry Pi; případně servisní zásuvka.

**24 V DC** napájí: WAV645; oba WAV617; čtyři Shelly Pro RGBWW PM; bílé a stavové LED pásky; EDATEC monitor; Teltonika TSW202, pouze pokud rozsah napětí na štítku konkrétního kusu dovoluje 24 V.

U TSW202 se objevují dvě specifikace. Aktuální rychlý návod uvádí napájení switche 7–57 V, ale PoE výstup funguje pouze při 44–57 V. Některé starší datasheety uvádějí pouze 44–57 V. Rozhodující je štítek konkrétního kusu. PoE se v tomto systému nepoužívá.

**12 V DC** napájí: devět zámků IBFM; audiozesilovač. Všech devět zámků musí mít samostatnou pojistku a vlastní ochranu proti indukční špičce.

## 4. Síťová konfigurace

Použít samostatnou lokální síť:

| Zařízení | IP adresa |
|---|---|
| Teltonika switch | 192.168.50.2 |
| Raspberry Pi – eth0 | 192.168.50.10 |
| WAV645 | 192.168.50.20 |
| WAV617-A | 192.168.50.21 |
| WAV617-B | 192.168.50.22 |
| Shelly 1 | 192.168.50.31 |
| Shelly 2 | 192.168.50.32 |
| Shelly 3 | 192.168.50.33 |
| Shelly 4 | 192.168.50.34 |

```yaml
lan:
  subnet: 192.168.50.0/24
  raspberry_ip: 192.168.50.10
  default_gateway_on_eth0: null
  internet_interface: LTE
```

Na eth0 nenastavovat výchozí bránu. Výchozí internetová trasa musí vést přes SIM7600. I/O síť tak zůstane funkční i bez LTE.

Waveshare moduly nastavit:

```yaml
mode: TCP server
protocol: Modbus TCP
port: 502
unit_id: 1
gateway_type: multi-host non-storage
internal_serial: 115200-8-N-1
```

Waveshare výslovně doporučuje pro Modbus TCP port 502 a režim non-storage gateway.

## 5. Kompletní mapa vstupů a výstupů

Číslování Modbus adres začíná nulou, fyzické označení relé začíná jedničkou.

| Zóna | Zámek | Dveřní kontakt | Bílé světlo |
|---|---|---|---|
| 1 | WAV645 R1 / coil 0 | WAV617-A DI1 / input 0 | WAV617-A R1 / coil 0 |
| 2 | WAV645 R2 / coil 1 | WAV617-A DI2 / input 1 | WAV617-A R2 / coil 1 |
| 3 | WAV645 R3 / coil 2 | WAV617-A DI3 / input 2 | WAV617-A R3 / coil 2 |
| 4 | WAV645 R4 / coil 3 | WAV617-A DI4 / input 3 | WAV617-A R4 / coil 3 |
| 5 | WAV645 R5 / coil 4 | WAV617-A DI5 / input 4 | WAV617-A R5 / coil 4 |
| 6 | WAV645 R6 / coil 5 | WAV617-A DI6 / input 5 | WAV617-A R6 / coil 5 |
| 7 | WAV645 R7 / coil 6 | WAV617-A DI7 / input 6 | WAV617-A R7 / coil 6 |
| 8 | WAV645 R8 / coil 7 | WAV617-A DI8 / input 7 | WAV617-A R8 / coil 7 |
| 9 | WAV645 R9 / coil 8 | WAV617-B DI1 / input 0 | WAV617-B R1 / coil 0 |

**Audio selektory**

| Zóna | Audio relé |
|---|---|
| 1 | WAV617-B R2 |
| 2 | WAV617-B R3 |
| 3 | WAV617-B R4 |
| 4 | WAV617-B R5 |
| 5 | WAV617-B R6 |
| 6 | WAV617-B R7 |
| 7 | WAV617-B R8 |
| 8 | WAV645 R10 |
| 9 | WAV645 R11 |

WAV645 R12–R16 zůstávají rezervní.

Použít pouze jeden kanál zesilovače jako mono: všechny záporné vodiče reproduktorů na jeden výstup SPK−; kladný výstup SPK+ vést přes devět samostatných NO relé; současně smí být sepnutý maximálně jeden audio selektor.

**Stavová červená/zelená signalizace** — Shelly nastavit do režimu Lights x 5.

| Zóna | Červená | Zelená |
|---|---|---|
| 1 | Shelly 1, light:0 | Shelly 1, light:1 |
| 2 | Shelly 1, light:2 | Shelly 1, light:3 |
| 3 | Shelly 1, light:4 | Shelly 2, light:0 |
| 4 | Shelly 2, light:1 | Shelly 2, light:2 |
| 5 | Shelly 2, light:3 | Shelly 2, light:4 |
| 6 | Shelly 3, light:0 | Shelly 3, light:1 |
| 7 | Shelly 3, light:2 | Shelly 3, light:3 |
| 8 | Shelly 3, light:4 | Shelly 4, light:0 |
| 9 | Shelly 4, light:1 | Shelly 4, light:2 |
| rezerva | Shelly 4, light:3 | Shelly 4, light:4 |

## 6. Modbus rozhraní pro program

**WAV645 – zámky a audio**

| Operace | Funkce | Adresa |
|---|---|---|
| Čtení relé | FC01 | 0x0000–0x000F |
| Zapnutí/vypnutí relé | FC05 | 0x0000–0x000F |
| Vypnutí všech relé | FC05 | 0x00FF |
| Bezpečný časovaný impulz | FC05 | 0x0200–0x020F |

Nejbezpečnější způsob otevření zámku je funkce flash-on: `adresa = 0x0200 + číslo_zóny - 1`, `hodnota = 8`, `čas = 8 × 100 ms = 800 ms`. Modul sepne relé na 800 ms a potom jej sám vypne. Zámek tedy nezůstane pod proudem ani při pádu procesu Raspberry. Waveshare definuje adresy 0x0200–0x020F jako časované sepnutí s krokem 100 ms.

Pozor: jde o nestandardní použití FC05 s časovou hodnotou. Některé knihovny pymodbus dovolují u write_coil() pouze boolean. Programátor proto musí použít raw Modbus PDU nebo samostatnou implementaci příkazu.

**WAV617 – vstupy a světla**

| Operace | Funkce | Adresa |
|---|---|---|
| Čtení relé | FC01 | 0x0000–0x0007 |
| Čtení dveřních kontaktů | FC02 | 0x0000–0x0007 |
| Ovládání relé | FC05 | 0x0000–0x0007 |
| Režim relé | FC03/FC06 | 0x1000–0x1007 |

Všechna relé WAV617 nastavit na `0x1000–0x1007 = 0x0000`, tedy Normal mode. Nepoužívat hardware linkage, toggle ani edge trigger. Veškerou logiku musí řídit Raspberry.

**Polling**

```yaml
door_input_poll_ms: 100
software_debounce_ms: 300
modbus_timeout_ms: 500
retry_delays_ms: [100, 250, 500]
device_offline_after_failures: 3
```

NC kontakt musí být v programu konfigurovatelný: `door_closed = input_value == configured_closed_level`. Při přerušeném kabelu musí systém stav vyhodnotit stejně jako otevřené dveře nebo poruchu, nikdy jako bezpečně zavřené.

## 7. Shelly HTTP API

Primární ovládání přes lokální HTTP RPC, ne přes cloud.

```http
POST http://192.168.50.31/rpc
Content-Type: application/json
{"id": 1, "method": "Light.Set", "params": {"id": 1, "on": true, "brightness": 100, "transition_duration": 0.2}}
```
Vypnutí: `{"id": 2, "method": "Light.Set", "params": {"id": 1, "on": false}}`

Doporučená signalizace:

| Stav | Červená | Zelená |
|---|---|---|
| Kóje zabezpečená | 100 % | 0 % |
| Přístup povolen | 0 % | 100 % |
| Dveře otevřené | 0 % | 100 % |
| Čekání na zavření | 0 % | pulzování |
| Porucha kontaktu | blikání | 0 % |
| I/O modul nedostupný | blikání | blikání |
| Raspberry nenaběhlo | stav podle posledního hardwarového stavu; při startu se resetuje | |

## 8. Připojení periferií Raspberry

**SIM7600E-H** — připojit přes micro-USB datový kabel, ne přes GPIO. Linux typicky vytvoří `/dev/ttyUSB0`–`/dev/ttyUSB3`. AT port bývá `/dev/ttyUSB2`, ale program jej nesmí natvrdo předpokládat. Použít udev pravidlo podle USB VID/PID a čísla rozhraní. Doporučení: NetworkManager + ModemManager; automatické obnovení LTE; kontrola internetu každých 30 sekund; po pěti neúspěšných reconnectech USB reset modemu; po dalších neúspěších restart Raspberry; logovat RSSI/RSRP/operátora a počet reconnectů.

**EDATEC** — Raspberry micro-HDMI → HDMI Type-A monitoru; Raspberry USB-A → USB-C USB TOUCH monitoru; 24 V DC → DC IN monitoru. Kiosk aplikace má běžet na 1920 × 1080, celoobrazovkově, bez systémových lišt.

**Audio** — Raspberry USB → AXAGON USB zvuková karta → oddělovací filtr → TPA3116D2 → reléový selektor → jeden z devíti reproduktorů.

Sekvence přepnutí reproduktoru: 1. ztlumit audio; 2. vypnout všechna audio relé; 3. čekat 200 ms; 4. zapnout relé požadované zóny; 5. čekat 100 ms; 6. spustit hudbu; 7. plynule zvýšit hlasitost.

Při ukončení: 1. fade-out 500 ms; 2. zastavit přehrávač; 3. čekat 200 ms; 4. vypnout selektor.

Současně smí hrát pouze jedna kóje. Zapnutí více reproduktorů paralelně by snížilo výslednou impedanci a mohlo poškodit zesilovač.

## 9. Stavový automat jedné zóny

```
SECURED
   ↓ platný PIN
ACCESS_GRANTED
   ↓ zámek 800 ms + světlo + zelená + hudba
WAITING_FOR_OPEN
   ↓ kontakt otevřen
DOOR_OPEN
   ↓ kontakt zavřen minimálně 1 s
CLOSED_CONFIRMATION
   ↓ doběhnutí světla/hudby
SECURED
```

Doporučená časování:

```yaml
lock_pulse_ms: 800
door_open_timeout_s: 30
door_close_debounce_ms: 1000
light_after_close_s: 30
music_after_close_s: 10
maximum_session_s: 600
forced_open_debounce_ms: 500
pin_entry_timeout_s: 20
```

**Platný PIN:** 1. Ověřit, že PIN má přesně šest číslic. 2. Ověřit rezervaci a časové okno. 3. Zjistit zone_id. 4. Ověřit dostupnost WAV645, příslušného WAV617 a Shelly. 5. Ověřit, že dveře nejsou už otevřené. 6. Zapnout bílé světlo. 7. Přepnout signalizaci červená → zelená. 8. Vybrat reproduktor. 9. Spustit hudbu. 10. Poslat zámku 800ms hardware impulz. 11. Zapsat událost ACCESS_GRANTED. 12. Čekat na otevření kontaktu.

**Dveře se do 30 sekund neotevřou:** zámek už nesmí být napájen; vypnout hudbu; po 30 sekundách vypnout bílé světlo; vrátit červenou signalizaci; ukončit relaci; stejný PIN může být podle rezervace znovu použit.

**Dveře se otevřou:** zapsat přesný čas; zámek musí být bez napětí; ponechat světlo; ponechat zelenou signalizaci; spustit maximální čas otevření.

**Dveře se zavřou:** vyžadovat stabilní NC stav alespoň 1 sekundu; IBFM se po zavření mechanicky znovu zajistí; zastavit hudbu po 10 sekundách; vypnout bílé světlo po 30 sekundách; rozsvítit červenou; zapsat SESSION_COMPLETED.

**Dveře zůstanou otevřené déle než 10 minut:** hudbu vypnout; bílé světlo lze ponechat; zelenou rozblikat; zobrazit chybu na displeji; odeslat vzdálené upozornění; opakovat upozornění například po 10, 20 a 30 minutách.

## 10. PIN a komunikace s rezervačním systémem

Minimální odpověď serveru:

```json
{"valid": true, "reservation_id": "uuid", "zone_id": 4, "valid_from": "2026-09-09T08:00:00+02:00", "valid_until": "2026-09-09T18:00:00+02:00", "customer_id": "uuid", "offline_allowed": true}
```

Raspberry musí mít lokální cache aktuálních rezervací, aby šlo dveře otevřít při výpadku LTE.

PIN neukládat v čistém textu. Protože šest číslic lze snadno projet hrubou silou, nestačí obyčejný hash. Použít například `HMAC-SHA256(secret_key, terminal_id + PIN)`.

```yaml
maximum_failed_attempts: 5
attempt_window_minutes: 5
lockout_minutes: 15
mask_pin_on_screen: true
store_plain_pin: false
```

## 11. Softwarové části Raspberry

| Služba | Funkce |
|---|---|
| motogo-ui.service | Dotykové zákaznické rozhraní |
| motogo-controller.service | Stavový automat všech devíti zón |
| motogo-modbus.service | WAV645/WAV617 komunikace |
| motogo-lighting.service | Shelly HTTP řízení |
| motogo-audio.service | Hudba a audio selektor |
| motogo-sync.service | Server, rezervace a odesílání událostí |
| motogo-health.service | Watchdog, teploty, disk, LTE a dostupnost modulů |

Doporučené technologie: Raspberry Pi OS 64-bit; Python; asyncio; pymodbus plus raw PDU pro hardware impulz; httpx pro Shelly; SQLite pro lokální frontu událostí; NetworkManager/ModemManager; mpv nebo GStreamer pro audio; systemd watchdog; read-only nebo overlay root filesystem, pokud to aplikace dovolí.

## 12. Povinné bezpečné chování

Po každém startu Raspberry: 1. WAV645 – vypnout všechna relé; 2. WAV617-A/B – vypnout všechna relé; 3. Shelly – vypnout všechny výstupy; 4. vypnout audio; 5. načíst dveřní kontakty; 6. zavřeným a funkčním zónám rozsvítit červenou; 7. otevřené zóny označit jako chybu; 8. teprve potom povolit zadávání PINů.

Další pravidla: nikdy nedržet zámek trvale pod napětím; nikdy neaktivovat více zámků současně; nikdy neaktivovat více audio selektorů současně; po ztrátě Modbus komunikace všechny zámky považovat za vypnuté a přístup zakázat; při restartu programu vždy provést hardwarový all relays off; příkaz na relé vždy následně ověřit čtením jeho stavu; hlavní relé zámků zapojit přes NO kontakt; při výpadku systému zůstávají dveře uzamčené; nepoužívat GPIO Raspberry pro výkonové nebo bezpečnostní funkce.

## 13. Parametry, které se musí fyzicky zjistit před konečným zapojením

1. Odběr jednoho IBFM 9500 při 12 V DC.
2. Skutečná polarita napájecího konektoru EDATEC.
3. Rozsah napájení uvedený na štítku konkrétního TSW202.
4. Skutečný příkon jednoho metru bílého a RGBW pásku.
5. Logická polarita vstupů WAV617 při připojeném NC kontaktu.
6. Zda jsou dveřní protiplechy mechanicky nastavené na paměťový režim a nemají zapnutou trvalou aretaci.
7. Zda má být povoleno současné otevření více kójí. Současný audio systém podporuje bezpečně jen jednu aktivní audiozónu.
