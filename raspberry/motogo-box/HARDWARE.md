# MotoGo Box — hardware, zapojení a uvedení do provozu (šablona: 9zónový box Brno)

Platí pro každou samoobslužnou pobočku; konkrétní počet zón, adresy a mapování se zadávají
ve Velíně. Tabulky níže popisují výchozí šablonu (Brno, 9 zón).

Doplněk k `README.md`; zdrojem je `SPEC.md` (§2–§8, §13). Modbus adresy začínají nulou,
fyzické značení relé/vstupů jedničkou (coil 0 = R1, input 0 = DI1). Stejné mapování je
v `config/brno-9zone.yaml` a ve Velíně (Samoobsluha → Řídicí jednotka → hardware / hw per dveře).

## 1. Síť (SPEC §4)

| zařízení | IP | pozn. |
|---|---|---|
| Teltonika TSW202 (switch) | 192.168.50.2 | PoE se nepoužívá; napájení dle štítku kusu |
| Raspberry Pi 5 — eth0 | 192.168.50.10 | **bez výchozí brány**, profil `motogo-lan` |
| WAV645 | 192.168.50.20 | Modbus TCP 502, unit 1 |
| WAV617-A | 192.168.50.21 | Modbus TCP 502, unit 1 |
| WAV617-B | 192.168.50.22 | Modbus TCP 502, unit 1 |
| Shelly 1–4 | 192.168.50.31–34 | HTTP RPC, profil Lights ×5 |
| internet | LTE SIM7600E-H (USB) | profil `motogo-lte`, výchozí trasa jen tudy; PIN SIM do profilu (`MOTOGO_SIM_PIN` v install.sh) nebo PIN vypnout |

Waveshare: `TCP server`, `Modbus TCP`, port `502`, unit id `1`, gateway `multi-host non-storage`,
interní sériovka `115200-8-N-1`. Shelly: režim Lights ×5, cloud/BT vypnout, statická IP.

## 2. Mapa I/O (SPEC §5) a Modbus adresy (SPEC §6)

| zóna | zámek (WAV645) | kontakt (WAV617) | světlo (WAV617) | audio relé | červená (Shelly) | zelená (Shelly) |
|---|---|---|---|---|---|---|
| 1 | R1 / coil 0 | A DI1 / in 0 | A R1 / coil 0 | B R2 / coil 1 | 1 light 0 | 1 light 1 |
| 2 | R2 / coil 1 | A DI2 / in 1 | A R2 / coil 1 | B R3 / coil 2 | 1 light 2 | 1 light 3 |
| 3 | R3 / coil 2 | A DI3 / in 2 | A R3 / coil 2 | B R4 / coil 3 | 1 light 4 | 2 light 0 |
| 4 | R4 / coil 3 | A DI4 / in 3 | A R4 / coil 3 | B R5 / coil 4 | 2 light 1 | 2 light 2 |
| 5 | R5 / coil 4 | A DI5 / in 4 | A R5 / coil 4 | B R6 / coil 5 | 2 light 3 | 2 light 4 |
| 6 | R6 / coil 5 | A DI6 / in 5 | A R6 / coil 5 | B R7 / coil 6 | 3 light 0 | 3 light 1 |
| 7 | R7 / coil 6 | A DI7 / in 6 | A R7 / coil 6 | B R8 / coil 7 | 3 light 2 | 3 light 3 |
| 8 | R8 / coil 7 | A DI8 / in 7 | A R8 / coil 7 | WAV645 R10 / coil 9 | 3 light 4 | 4 light 0 |
| 9 | R9 / coil 8 | B DI1 / in 0 | B R1 / coil 0 | WAV645 R11 / coil 10 | 4 light 1 | 4 light 2 |
| rezerva | WAV645 R12–R16 (coil 11–15) | B DI2–DI8 | – | – | 4 light 3 | 4 light 4 |

**WAV645 (zámky + audio 8/9)**

| operace | FC | adresa |
|---|---|---|
| čtení relé | 01 | 0x0000–0x000F |
| zapnutí/vypnutí | 05 | 0x0000–0x000F (0xFF00 / 0x0000) |
| vypnout všechna relé | 05 | 0x00FF, hodnota 0x0000 |
| **časovaný impulz zámku (flash-on)** | 05 | 0x0200 + coil, hodnota = čas/100 ms (800 ms → 8) |

**WAV617-A/B (kontakty + světla + audio 1–7)**

| operace | FC | adresa |
|---|---|---|
| čtení relé | 01 | 0x0000–0x0007 |
| čtení vstupů (kontakty) | 02 | 0x0000–0x0007 |
| ovládání relé | 05 | 0x0000–0x0007 |
| režim relé (musí být 0 = Normal) | 03/06 | 0x1000–0x1007 |

Polling: kontakty každých 100 ms, sw debounce 300 ms, Modbus timeout 500 ms, retry 100/250/500 ms,
modul offline po 3 neúspěších (→ zóna BOTH_BLINK, přístup zakázán).

## 3. Shelly signalizace (SPEC §7)

`POST http://192.168.50.3x/rpc` `{"id":1,"method":"Light.Set","params":{"id":<light>,"on":true,"brightness":100,"transition_duration":0.2}}`.
Z RGBW pásku je zapojeno jen **R = červená** a **G = zelená**; B a W nezapojeny. Společný +24 V.

| stav zóny | červená | zelená |
|---|---|---|
| zabezpečeno (SECURED) | 100 % | 0 |
| přístup povolen / dveře otevřené | 0 | 100 % |
| čekání na zavření (relace > 10 min) | 0 | pulzuje 15↔100 % |
| porucha kontaktu / násilné otevření | bliká 500 ms | 0 |
| I/O modul nedostupný | bliká | bliká |

## 4. Audio (SPEC §8)

Raspberry USB → AXAGON USB zvuková karta → oddělovací člen → TPA3116D2 (**jen jeden kanál, mono**)
→ SPK− všech reproduktorů spojen na výstup zesilovače, **SPK+ přes 9 samostatných NO relé** (tabulka
výše) → reproduktor kóje. Nikdy nesmí být sepnuté dva selektory (impedance ‖ → zničení zesilovače);
program to hlídá (vše off → 200 ms → jedno relé → 100 ms → hudba → fade-in; při ukončení fade-out
500 ms → stop → 200 ms → relé off). Hlasitost: `audio.volume` (0–100) ve Velíně, mixér karty `alsamixer`.
Výchozí ALSA zařízení RPi 5 je HDMI monitoru — `audio.device` MUSÍ mířit na USB kartu
(`alsa/plughw:CARD=<název z aplay -l>`); install.sh ji při založení `hardware.yaml` doplní sám, ve Velíně
ji zadej ručně (Velín má přednost).

## 5. Napájení (SPEC §3)

| větev | zdroj | napájí |
|---|---|---|
| 230 V AC (ze střídače FVE) | hlavní jistič, RCBO, přepěťovka | Mean Well 24 V, Mean Well 12 V, USB-C zdroj RPi 27 W, servisní zásuvka |
| 24 V DC | Mean Well NDR-480-24 (20 A) | WAV645, 2× WAV617, 4× Shelly, bílé + RGBW pásky, EDATEC, TSW202 (pokud štítek dovolí 24 V) |
| 12 V DC | Mean Well NDR-240-12 (20 A) | 9× zámek IBFM 9500 (každý vlastní pojistka + TVS 1.5KE18CA), TPA3116D2 |

Raspberry Pi 5 napájet **originálním 27W USB-C zdrojem** (5 V/5 A → plný proud pro USB modem,
dotyk a zvukovou kartu). Hlavní pojistka 12V větve zámků + pojistková svorka na každý zámek.

## 6. Komponenty (zkráceně, SPEC §2)

- **Řízení:** Raspberry Pi 5 4 GB, Active Cooler, RTC baterie, 64 GB microSD A2, 52Pi DIN pouzdro, 2× 27W zdroj.
- **Konektivita:** Waveshare SIM7600E-H (USB, micro-USB kabel), Teltonika TSW202, 5× CAT6 patch, 50 m CAT6 (plná měď).
- **I/O:** 1× Waveshare WAV645 (16 relé), 2× WAV617 (8 relé + 8 DI), 4× Shelly Pro RGBWW PM.
- **Dveře:** 9× IBFM 9500 (fail-secure s pamětí, aretaci vypnout), 10× NC magnetický kontakt, 10× TVS, 9× pojistková svorka.
- **UI:** EDATEC ED-MONITOR-156CA (HDMI + USB-C dotyk, 24 V), micro-HDMI→HDMI, USB-A→USB-C.
- **Audio:** AXAGON USB zvuková karta, oddělovací člen, TPA3116D2 2×50 W, 10× reproduktor 8 Ω/5 W, repro kabel 2×0,75.
- **Osvětlení:** 20 m bílý LED pásek 24 V IP65, RGBW pásek 24 V společný +, hliníkové profily.
- **Rozvaděč:** IP65 ≥ 600×400×200, DIN lišty, oddělený 230 V / SELV, svorkovnice +24/+12/0 V, PE, WAGO 221, průchodky, větrání.

## 7. Ověření polarity dveřních kontaktů (`closed_level`, SPEC §13.5)

Program vyhodnocuje `door_closed = input_value == closed_level`. Přerušený kabel se MUSÍ jevit
jako otevřeno/porucha, nikdy jako zavřeno — proto NC kontakt a správná úroveň.

1. Zapoj kontakt zóny 1 na WAV617-A DI1, dveře **zavři**, spusť controller.
2. `curl -s http://127.0.0.1:8080/api/state | python3 -m json.tool | grep -A2 '"zone": 1'` →
   sleduj `door_closed`. Musí být `true` při zavřených dveřích a `false` při otevřených.
3. Je-li to obráceně: ve Velíně (hardware → `contacts.closed_level`) přepni `1` ↔ `0` (nebo lokálně v
   `/etc/motogo/hardware.yaml`), pošli `sync_config` / restartuj controller a zopakuj krok 2.
4. **Test přerušeného kabelu:** odpoj jeden vodič kontaktu při zavřených dveřích → `door_closed` musí
   spadnout na `false` (zóna přejde do `forced_open`/RED_BLINK). Pokud zůstane `true`, je polarita nebo
   zapojení (NO místo NC) špatně.
5. Zopakuj pro všech 9 zón (zóna 9 = WAV617-B DI1). Jednotlivou zónu lze přebít `closed_level` v `hw` dveří.

## 8. Měření odběru zámku a volba pojistky (SPEC §2/§13.1)

Odběr IBFM 9500 není doložený — hodnotu pojistky **neodhadovat**:
1. Jeden zámek napájet z 12 V DC laboratorního zdroje přes ampérmetr (rozsah ≥ 5 A) nebo klešťový DC ampérmetr.
2. Změř **náběhový** špičkový proud (první ~50 ms, ideálně osciloskop/„peak hold") a **ustálený** proud po 0,5 s.
3. Pojistka na zámek: pomalá (T) ≈ 1,5–2× ustálený proud; náběhová špička během 800ms impulzu ji nesmí
   vybavit (u pomalé pojistky krátká špička 3–5× In projde; typicky vychází T1A–T2A). Hlavní pojistka 12V větve: ≥ součet 2 současně aktivních zámků + zesilovač
   (zámky se nespínají zároveň — program pulzy serializuje) s rezervou, ale menší než jmenovitý proud zdroje.
4. Ke každému zámku TVS 1.5KE18CA přímo na svorky cívky (proti indukční špičce); kabel 2×0,75 mm².
5. Zapiš naměřené hodnoty do dokumentace pobočky a nastav stejné pojistky do všech 9 svorek + náhradní.

## 9. Checklist před uvedením do provozu (SPEC §12/§13)

- [ ] Změřen odběr IBFM 9500 (náběh/ustálený), zvoleny a osazeny pojistky všech 9 zámků + hlavní 12V pojistka
- [ ] Ověřena polarita napájecího konektoru EDATEC (5,5×2,5 mm, 12–24 V) před připojením
- [ ] Ověřen rozsah napájení na štítku TSW202 (24 V povoleno?) — jinak samostatný zdroj
- [ ] Změřen příkon 1 m bílého a RGBW pásku, dimenzován 24V zdroj a jištění větví
- [ ] Ověřena logická polarita vstupů WAV617 s NC kontaktem (`closed_level`, kap. 7) na všech 9 zónách
- [ ] Test přerušeného kabelu kontaktu → vyhodnoceno jako otevřeno/porucha
- [ ] Protiplechy IBFM v paměťovém režimu, trvalá aretace vypnutá (dveře po zavření samy zajištěné)
- [ ] Rozhodnutí o souběhu kójí zapsáno (ANO — SPEC §13.7); hudba jen v jedné kóji
- [ ] Waveshare: statické IP .20/.21/.22, TCP server, Modbus TCP 502, unit 1, non-storage; WAV617 relé Normal mode
- [ ] Shelly ×4: Lights ×5, statické IP .31–.34, cloud/BT vypnut; každý kanál rozsvítí správnou barvu ve správné kóji
- [ ] eth0 = 192.168.50.10/24 bez brány (`set-static-lan.sh` OK), internet přes LTE (`mmcli -m any` connected)
- [ ] PIN SIM vypnut, nebo zadán při instalaci (`MOTOGO_SIM_PIN` → `[gsm] pin=` v `motogo-lte`); `mmcli -m any` NENÍ `locked`, health nehlásí `lte.error`
- [ ] USB zvuková karta nalezena instalátorem (`aplay -l`, shrnutí install.sh) a `audio.device` = `alsa/plughw:CARD=<název>` i ve Velíně
- [ ] UI naběhlo na tty7 bez „Could not activate session“ (`journalctl -u motogo-ui`; `chvt 7` v unitě + polkit pravidlo `50-motogo-kiosk.rules`)
- [ ] microSD průmyslová (pSLC/„High Endurance“, A2), UPS/záložní napájení RPi — root je rw, overlay se nezapíná (rozhodnutí SPEC §11)
- [ ] Zámek každé zóny reaguje na servisní „Otevřít" (800ms impulz, nezůstává pod napětím — změřit napětí na cívce po impulzu = 0 V)
- [ ] Bílé světlo a červená/zelená každé zóny odpovídají číslu kóje (servisní panel / `zone_test`)
- [ ] Hudba hraje jen ve vybrané kóji (`audio_test` zóna po zóně); nikdy dvě relé současně
- [ ] Hlasitost karty (`alsamixer -c <název>`) a `audio.volume` přiměřené
- [ ] Zařízení spárováno, Velín ukazuje online, `kiosk_report_status` zobrazuje 9 zón SECURED/červená
- [ ] Aktualizace z Velína: Pobočky → „Aktualizace řídicích jednotek“ ukazuje jednotku s verzí („Aktuální“), OS a jádrem; `unattended-upgrade` nainstalován, `systemctl list-timers apt-daily-upgrade.timer` = 04:00 ± 20 min (záplaty OS bez restartu)
- [ ] Cache kódů stažena (odpojit LTE → zadat platný kód → dveře se otevřou offline)
- [ ] Po restartu RPi (výpadek 230 V) vše naběhne samo: all off → červená → UI; RTC drží čas (`timedatectl`)
- [ ] LTE watchdog vyzkoušen (vyjmout anténu → `journalctl -u motogo-health` ukáže reconnect)
- [ ] Rozvaděč: oddělené 230 V / SELV, PE, popisky všech kabelů a svorek, větrání, zakrytovaný zesilovač
- [ ] Hudba nahrána do `/var/lib/motogo/music`; servisní heslo nastaveno ve Velíně a vyzkoušeno na displeji
